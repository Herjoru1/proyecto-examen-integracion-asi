import argparse
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
import math
from pathlib import Path
from statistics import median
import subprocess
from threading import Barrier
from time import perf_counter

from cliente import Cliente, RAIZ, accesos

MIB = 1024 ** 2
RUTAS = {
    "inicio": "GET /",
    "iniciar_sesion": "POST /sesion",
    "listar_articulos": "GET /articulos",
    "resumen_existencias": "GET /existencias",
    "cerrar_sesion": "POST /salir",
    "comprobar_salud": "GET /salud",
}


def verificar(respuesta, esperado, contenido=None):
    estado, _, texto = respuesta
    if estado != esperado or (contenido and contenido not in texto):
        raise RuntimeError(f"HTTP {estado}, se esperaba {esperado}")


def perfilar(repeticiones, credencial):
    desde = datetime.now(timezone.utc).isoformat()
    cliente = Cliente(perfil=True)
    try:
        for _ in range(repeticiones):
            cliente.cookie = None
            verificar(cliente.peticion("GET", "/"), 200)
            verificar(cliente.inicio("admin", credencial), 303)
            verificar(cliente.peticion("GET", "/articulos"), 200, "Elementos existentes")
            verificar(cliente.peticion("GET", "/existencias"), 200)
            verificar(cliente.peticion("POST", "/salir"), 303)
            verificar(cliente.peticion("GET", "/salud"), 200, "ok")
    finally:
        cliente.cerrar()

    salida = subprocess.check_output(
        ["docker", "compose", "logs", "--no-color", "--no-log-prefix", "--since", desde, "app"],
        cwd=RAIZ, text=True,
    )
    muestras = defaultdict(list)
    for linea in salida.splitlines():
        if linea.startswith('{"tipo":"perfil",'):
            entrada = json.loads(linea)
            muestras[entrada["script"]].append(entrada)

    resumen = []
    for script, ruta in RUTAS.items():
        registros = muestras[script]
        if len(registros) != repeticiones:
            raise RuntimeError(f"{ruta} produjo {len(registros)} métricas; esperadas {repeticiones}")
        resumen.append({
            "script": script,
            "ruta": ruta,
            "muestras": len(registros),
            "tiempo_mediana_ms": round(median(r["tiempo_ms"] for r in registros), 2),
            "cpu_mediana_ms": round(median(r["cpu_ms"] for r in registros), 2),
            "ram_rss_max_mib": round(max(r["rss_max_bytes"] for r in registros) / MIB, 2),
            "ram_aumento_max_mib": round(max(
                r["rss_max_bytes"] - r["rss_inicial_bytes"] for r in registros
            ) / MIB, 2),
        })
    return resumen


def usuario_simulado(barrera, password):
    barrera.wait(timeout=25)
    inicio = perf_counter()
    cliente = Cliente()
    try:
        verificar(cliente.inicio("consulta", password), 303)
        verificar(cliente.peticion("GET", "/articulos"), 200, "Elementos existentes")
        verificar(cliente.peticion("POST", "/salir"), 303)
        return (perf_counter() - inicio) * 1000, None
    except (OSError, RuntimeError) as error:
        return None, str(error)
    finally:
        cliente.cerrar()


def fase(concurrentes, oleadas, password, objetivo_ms):
    latencias = []
    errores = defaultdict(int)
    inicio = perf_counter()
    with ThreadPoolExecutor(max_workers=concurrentes) as grupo:
        for _ in range(oleadas):
            barrera = Barrier(concurrentes)
            tareas = [grupo.submit(usuario_simulado, barrera, password) for _ in range(concurrentes)]
            for tarea in tareas:
                duracion, error = tarea.result()
                if error is None:
                    latencias.append(duracion)
                else:
                    errores[error] += 1
    latencias.sort()
    p95 = latencias[math.ceil(len(latencias) * .95) - 1] if latencias else None
    return {
        "usuarios_simultaneos": concurrentes,
        "oleadas": oleadas,
        "sesiones_correctas": len(latencias),
        "errores": dict(errores),
        "p95_ms": round(p95, 2) if p95 is not None else None,
        "sesiones_por_segundo": round(len(latencias) / (perf_counter() - inicio), 2),
        "cumple": not errores and p95 is not None and p95 <= objetivo_ms,
    }


def main():
    parser = argparse.ArgumentParser(description="Perfila rutas y mide sesiones concurrentes sobre HTTPS.")
    parser.add_argument("--niveles", default="1,5,10,15,20,22,24,26,28,30,35,40")
    parser.add_argument("--oleadas", type=int, default=5)
    parser.add_argument("--muestras", type=int, default=12)
    parser.add_argument("--objetivo-ms", type=int, default=1500)
    parser.add_argument("--salida", type=Path, default=Path("evidencia/mediciones.json"))
    args = parser.parse_args()
    try:
        niveles = sorted({int(nivel) for nivel in args.niveles.split(",")})
        if niveles[0] < 1 or min(args.oleadas, args.muestras, args.objetivo_ms) < 1:
            raise ValueError
    except ValueError:
        parser.error("Especifica números positivos en los niveles, oleadas, muestras y objetivo.")

    credenciales = accesos()
    perfiles = perfilar(args.muestras, credenciales["admin"])
    for perfil in perfiles:
        print(json.dumps(perfil, ensure_ascii=False), flush=True)
    fases = []
    for nivel in niveles:
        resultado = fase(nivel, args.oleadas, credenciales["consulta"], args.objetivo_ms)
        fases.append(resultado)
        print(json.dumps(resultado, ensure_ascii=False), flush=True)

    capacidad = max((r["usuarios_simultaneos"] for r in fases if r["cumple"]), default=0)
    args.salida.write_text(json.dumps({
        "fecha_utc": datetime.now(timezone.utc).isoformat(),
        "objetivo_p95_ms": args.objetivo_ms,
        "flujo_carga": ["POST /sesion", "GET /articulos", "POST /salir"],
        "perfil": perfiles,
        "carga": fases,
        "maximo_nivel_validado": capacidad,
    }, ensure_ascii=False, indent=2) + "\n")
    print(f"Máximo nivel probado que cumple el criterio: {capacidad} usuarios simultáneos")


if __name__ == "__main__":
    main()
