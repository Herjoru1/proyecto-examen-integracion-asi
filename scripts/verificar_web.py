import socket
from cliente import Cliente, DOMINIO, accesos


def verificar():
    direccion = socket.gethostbyname(DOMINIO)
    cliente = Cliente()
    credenciales = accesos()
    try:
        estado, _, texto = cliente.peticion("GET", "/")
        assert estado == 200 and "Iniciar sesión" in texto
        print(f"Dominio resuelve a {direccion}; TLS valida CA y nombre; formulario HTTP 200")

        estado, cabeceras, _ = cliente.peticion("GET", "/articulos")
        assert estado == 302 and cabeceras["Location"] == "/"
        assert cliente.inicio("consulta", "contraseña-incorrecta")[0] == 401
        assert cliente.peticion("POST", "/sesion", origen="https://otro.example")[0] == 403
        print("Listado protegido; credenciales incorrectas 401; formulario de otro origen 403")

        estado, cabeceras, _ = cliente.inicio("consulta", credenciales["consulta"])
        assert estado == 303 and cabeceras["Location"] == "/articulos"
        cookie = cabeceras["Set-Cookie"]
        assert all(valor in cookie for valor in ("__Host-asi_sesion=", "HttpOnly", "Secure", "SameSite=Strict", "Path=/"))
        estado, _, texto = cliente.peticion("GET", "/articulos")
        assert estado == 200 and "Elementos existentes" in texto and 'href="/existencias"' not in texto
        for articulo in ("Laptop Empresarial", "Monitor 27", "Teclado Mecánico", "Adaptador HDMI"):
            assert articulo in texto
        assert cliente.peticion("GET", "/existencias")[0] == 403
        print("Consulta: inicia sesión, ve los cuatro artículos y recibe 403 en Existencias")

        cookie_anterior = cliente.cookie
        assert cliente.peticion("POST", "/salir")[0] == 303
        cliente.cookie = cookie_anterior
        assert cliente.peticion("GET", "/articulos")[0] == 302
        print("Cerrar sesión invalida la cookie anterior")

        assert cliente.inicio("admin", credenciales["admin"])[0] == 303
        estado, _, texto = cliente.peticion("GET", "/articulos")
        assert estado == 200 and 'href="/existencias"' in texto
        estado, _, texto = cliente.peticion("GET", "/existencias")
        assert estado == 200 and "Unidades en inventario" in texto
        assert cliente.peticion("POST", "/salir")[0] == 303
        assert cliente.peticion("GET", "/estilos.css")[0] == 200
        print("Administrador: inicia sesión, ve Artículos y abre Existencias")
    finally:
        cliente.cerrar()


if __name__ == "__main__":
    verificar()
