#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
modo=${1:-}
if [[ -n "$modo" && "$modo" != --modo-examen ]]; then
    printf 'Uso: %s [--modo-examen]\n' "$0" >&2
    exit 2
fi

mkdir -p .asilab/tls .asilab/ssh-host
if [[ ! -s .env ]]; then
    if [[ -e .asilab/accesos ]]; then
        printf 'Falta .env. Recupera el archivo de esta instalación antes de continuar.\n' >&2
        exit 1
    fi
    python3 - "$modo" <<'PY'
import hashlib
from pathlib import Path
import secrets
import sys

def password_hash(password):
    salt = secrets.token_bytes(16)
    hashed = hashlib.scrypt(password.encode(), salt=salt, n=16384, r=8, p=1, dklen=64)
    return f"{salt.hex()}:{hashed.hex()}"

admin = secrets.token_urlsafe(16)
consulta = secrets.token_urlsafe(16)
modo_examen = sys.argv[1] == "--modo-examen"
config = {
    "IP_ESCUCHA": "127.0.0.1",
    "PUERTO_SFTP": "2222",
    "POSTGRES_PASSWORD": secrets.token_urlsafe(32),
    "APP_DB_PASSWORD": secrets.token_urlsafe(32),
    "ADMIN_WEB_HASH": password_hash(admin),
    "CONSULTA_WEB_HASH": password_hash(consulta),
    "ADMIN_CONSOLA": "123456" if modo_examen else secrets.token_urlsafe(16),
    "WEB_CONSOLA": "12345678" if modo_examen else secrets.token_urlsafe(16),
}
Path(".env").write_text("".join(f"{name}={value}\n" for name, value in config.items()))
Path(".asilab/accesos").write_text(f"admin={admin}\nconsulta={consulta}\n")
PY
fi

if [[ ! -s .asilab/web.pub ]]; then
    if [[ -n "${LLAVE_PUBLICA_WEB:-}" ]]; then
        ssh-keygen -l -f "$LLAVE_PUBLICA_WEB" >/dev/null
        cp "$LLAVE_PUBLICA_WEB" .asilab/web.pub
    else
        if [[ ! -s .asilab/web ]]; then
            ssh-keygen -q -t ed25519 -N '' -C 'web@proyecto.final.asi' -f .asilab/web
        else
            ssh-keygen -y -f .asilab/web > .asilab/web.pub
        fi
    fi
fi

tls=.asilab/tls
if [[ ! -s "$tls/ca.crt" && ! -s "$tls/ca.key" ]]; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -sha256 \
        -days 365 -subj '/CN=ASI CA de laboratorio' \
        -addext 'basicConstraints=critical,CA:TRUE,pathlen:0' \
        -addext 'keyUsage=critical,keyCertSign,cRLSign' \
        -keyout "$tls/ca.key" -out "$tls/ca.crt"
fi

if [[ ! -s "$tls/servidor.crt" || ! -s "$tls/servidor.key" ]] ||
        ! openssl x509 -in "$tls/servidor.crt" -checkend 604800 -noout >/dev/null; then
    openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
        -subj '/CN=proyecto.final.asi' -keyout "$tls/servidor.key" -out "$tls/servidor.csr"
    openssl x509 -req -sha256 -days 120 -in "$tls/servidor.csr" \
        -CA "$tls/ca.crt" -CAkey "$tls/ca.key" -CAcreateserial -out "$tls/servidor.crt" \
        -extfile apache/cert-ext.cnf
    rm "$tls/servidor.csr"
fi
openssl verify -CAfile "$tls/ca.crt" -verify_hostname proyecto.final.asi "$tls/servidor.crt"
printf 'Configuración preparada. Inicia con docker compose up -d --build --wait --remove-orphans\n'
