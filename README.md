# Proyecto final de Integración de Servicios Web

Servidor A para el examen de integración de conocimientos. Apache HTTP Server recibe HTTPS en `proyecto.final.asi`, la aplicación de inventario usa Express y PostgreSQL, y OpenSSH presta SFTP en una jaula para la cuenta `web`. Apache sirve los archivos estáticos y funciona como proxy inverso de Express mediante `mod_proxy_http`. Los cuatro servicios se ejecutan con Docker Compose en la misma VM Ubuntu.

- **443/TCP** · HTTPS mediante Apache HTTP Server. Node y PostgreSQL solo tienen acceso en la red de Compose.
- **2222/TCP** · SFTP como `web`, con llave Ed25519, en `/entrega` y sin terminal.
- **Usuarios web** · `admin` ve Artículos y Existencias. `consulta` ve Artículos. El servidor comprueba el rol al abrir Existencias y devuelve HTTP 403 a Consulta.
- **PostgreSQL** · guarda roles, usuarios, sesiones y la tabla `articulos` con `id_articulo`, `nombre`, `precio` y `elementos_existentes`. Los datos iniciales vienen del parcial.

## Instalar en Ubuntu

Se necesita Docker Engine con Compose v2, Python 3, OpenSSL, OpenSSH cliente y acceso a Internet para la primera construcción. Ejecuta los comandos desde la raíz del ZIP descomprimido o del repositorio.

```bash
./scripts/preparar.sh --modo-examen
docker compose up -d --build --wait --remove-orphans
docker compose ps
./scripts/accesos.sh
```

`preparar.sh` genera la CA y el certificado, crea las credenciales web y, si no se proporciona una, genera la pareja de llaves de práctica para SFTP. Conserva `.env` y `.asilab/` mientras uses esta instalación. En la VM que ya está configurada, usa la carpeta existente para no generar credenciales diferentes frente a los mismos volúmenes. Para autorizar tu propia llave, inicia una instalación nueva con `LLAVE_PUBLICA_WEB=/ruta/a/tu_llave.pub ./scripts/preparar.sh --modo-examen`.

El modo examen aplica las contraseñas de la hoja a las cuentas de sistema del servicio Ubuntu. La contraseña de `admin` se usa en la consola local. El servicio SSH ofrece exclusivamente autenticación por llave a `web`. La cuenta de administración de consola se llama `admin`, es distinta de la cuenta web y pertenece al grupo `sudo`. En una instalación nueva, omitir `--modo-examen` genera también contraseñas aleatorias de sistema en `.env`.

### Abrir en la VM

1. Agrega `127.0.0.1 proyecto.final.asi` al archivo `/etc/hosts` si la entrada aún no existe.
2. Importa `.asilab/tls/ca.crt` en las autoridades de confianza del navegador. En Chrome, abre `chrome://settings/certificates`. La CA es local para el laboratorio. Puedes confirmar nombre y confianza desde terminal sin cambiar su almacén con el comando de abajo.
3. Abre [https://proyecto.final.asi](https://proyecto.final.asi) e ingresa las credenciales de `./scripts/accesos.sh`.

```bash
curl --cacert .asilab/tls/ca.crt -I https://proyecto.final.asi/
openssl s_client -connect proyecto.final.asi:443 -servername proyecto.final.asi \
  -verify_hostname proyecto.final.asi -CAfile .asilab/tls/ca.crt \
  -verify_return_error -brief </dev/null
```

### Abrir desde el equipo anfitrión

1. Encuentra la IP privada de la interfaz Ubuntu que es alcanzable desde el anfitrión con `ip -4 -br addr`.
2. Cambia `IP_ESCUCHA` en `.env` a esa IP y ejecuta `docker compose up -d --wait`. Los puertos quedarán publicados en esa interfaz.
3. Configura `proyecto.final.asi` con la IP de la VM en el archivo `hosts` de los equipos que van a abrir el sitio. En Windows se encuentra en `C:\Windows\System32\drivers\etc\hosts`. En Linux y macOS, en `/etc/hosts`. Actualiza también la entrada dentro de Ubuntu si seguirás usando el sitio allí.
4. Copia el certificado público `.asilab/tls/ca.crt` al anfitrión e impórtalo en su tienda de autoridades de confianza. Desde ahí abre la misma URL. Para SFTP desde el anfitrión, autoriza preferiblemente la llave pública de ese equipo al preparar la instalación y usa su llave privada en el cliente.

Para mover toda la aplicación a otra máquina con Docker, usa el ZIP o clona este repositorio y repite la instalación. Una instalación nueva genera sus propias credenciales y certificados. Compose conserva los datos y archivos subidos entre reinicios mediante los volúmenes `datos` y `entregas`.

## Demostración de los 10 puntos

| Puntos | Demostración |
| --- | --- |
| 1, 2 y 3 | Ejecuta `docker compose exec apache httpd -S`, abre el dominio en el navegador y muestra la comprobación TLS. |
| 4 | Ejecuta la consulta de PostgreSQL que aparece abajo para mostrar el motor, los roles y el esquema. |
| 5 y 6 | Entra como `consulta` y muestra el listado y su menú. Entra como `admin` y abre Existencias. |
| 7 y 8 | Entra por SFTP, muestra `pwd` y `ls`, y sube un archivo a `/entrega`. Ejecuta `./scripts/verificar.sh` para demostrar además que no hay terminal, comandos remotos ni autenticación SSH por contraseña. |
| 9 y 10 | Presenta [las mediciones registradas](evidencia/mediciones.json) y, si hace falta repetirlas, ejecuta `python3 scripts/medir.py`. |

```bash
docker compose exec db psql -U postgres -d asi -c 'SELECT version();' \
  -c 'SELECT * FROM roles;' -c '\d articulos' -c 'TABLE articulos;'
sftp -P 2222 -i .asilab/web web@proyecto.final.asi
./scripts/verificar.sh
python3 scripts/medir.py
```

Antes de aceptar por primera vez la huella SSH en el cliente, puedes verificarla con:

```bash
docker compose exec sftp ssh-keygen -lf /etc/ssh/host/ssh_host_ed25519_key.pub
```

Para demostrar el acceso administrativo en consola, ejecuta `docker compose exec --user web sftp su - admin` y usa la contraseña de la hoja. SFTP recibe archivos de trabajo en `/entrega`. La versión publicada de la aplicación se despliega desde el repositorio.

### Método de medición

El perfil ejecuta cada ruta en secuencia. Obtiene la mediana del tiempo de ejecución y del tiempo de CPU del proceso Node, el pico observado de memoria residente (RSS) y el mayor aumento sobre la memoria al comenzar la ruta. La RSS se muestrea cada 5 ms y se lee al entrar y salir. Puede incluir asignaciones de otras solicitudes previas o del runtime y no contabiliza la memoria de PostgreSQL o Apache HTTP Server. Por eso se muestran el pico del proceso y el aumento observado por separado.

La prueba de carga activa sesiones simultáneas en oleadas. Cada usuario completa por HTTPS el inicio de sesión, consulta el listado y cierra sesión. La capacidad observada es el nivel de concurrencia más alto probado con **cero errores** y un **p95 de hasta 1.500 ms** para el flujo completo. Ese umbral se fijó para la demostración porque la hoja no especifica una latencia objetivo. El resultado corresponde a esta VM y a esta carga. La aplicación tiene un límite de 2 vCPU y 384 MiB, y PostgreSQL de 1 vCPU y 320 MiB.

**Resultado en la VM.** 24 usuarios simultáneos cumplieron el criterio con un p95 de 1.376,82 ms y cero errores. A 26 usuarios el p95 fue de 1.694,69 ms. El inicio de sesión concentró el mayor tiempo de CPU y el mayor aumento de RSS.

## Evidencias y procedencia

- [Verificación funcional](evidencia/verificacion.txt)
- [Resultados por ruta y nivel de carga](evidencia/mediciones.json)
- [Portal del administrador](evidencia/administrador.png) y [portal de consulta](evidencia/consulta.png) y [resumen de existencias](evidencia/existencias.png)
- El proyecto adapta el inventario y la base visual del [portal administrativo del parcial](https://github.com/nathanbeltran232/Proyecto-Parcial-Integracion-de-Servicios-Web/tree/df6c9a7b4a502fcc4415f17371b7a25b6f0d75cc). Los artículos de ejemplo provienen de su [esquema de inventario](https://github.com/nathanbeltran232/Proyecto-Parcial-Integracion-de-Servicios-Web/blob/f9080ec920d07cc8afc143fe2d416fc67af5b39b/database/schema.sql).
- Referencias de configuración. [Proxy inverso de Apache](https://httpd.apache.org/docs/2.4/howto/reverse_proxy.html), [TLS de Apache](https://httpd.apache.org/docs/2.4/mod/mod_ssl.html), [OpenSSH](https://man.openbsd.org/sshd_config), [Docker Compose](https://docs.docker.com/compose/how-tos/startup-order) y [certificados de Chrome en Linux](https://chromium.googlesource.com/chromium/src/+/7cab636ebce4a3d375cf7df2dddb59ce6035f474/docs/linux/cert_management.md).
