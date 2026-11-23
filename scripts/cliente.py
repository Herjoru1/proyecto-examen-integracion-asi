from http.client import HTTPSConnection
from pathlib import Path
import ssl
from urllib.parse import urlencode

RAIZ = Path(__file__).resolve().parent.parent
DOMINIO = "proyecto.final.asi"
ORIGEN = f"https://{DOMINIO}"
CONTEXTO_TLS = ssl.create_default_context(cafile=RAIZ / ".asilab/tls/ca.crt")


def accesos():
    return dict(linea.split("=", 1) for linea in (RAIZ / ".asilab/accesos").read_text().splitlines())


class Cliente:
    def __init__(self, perfil=False):
        self.conexion = HTTPSConnection(DOMINIO, timeout=20, context=CONTEXTO_TLS)
        self.cookie = None
        self.perfil = perfil

    def peticion(self, metodo, ruta, datos=None, origen=ORIGEN):
        cabeceras = {"X-ASI-Perfil": "1"} if self.perfil else {}
        cuerpo = None
        if self.cookie:
            cabeceras["Cookie"] = self.cookie
        if metodo == "POST":
            cabeceras["Origin"] = origen
        if datos is not None:
            cuerpo = urlencode(datos)
            cabeceras["Content-Type"] = "application/x-www-form-urlencoded"
        self.conexion.request(metodo, ruta, cuerpo, cabeceras)
        respuesta = self.conexion.getresponse()
        texto = respuesta.read().decode("utf-8")
        return respuesta.status, respuesta.headers, texto

    def inicio(self, usuario, password):
        estado, cabeceras, texto = self.peticion(
            "POST", "/sesion", {"usuario": usuario, "password": password}
        )
        cookie = cabeceras.get("Set-Cookie")
        if estado == 303 and cookie:
            self.cookie = cookie.split(";", 1)[0]
        return estado, cabeceras, texto

    def cerrar(self):
        self.conexion.close()
