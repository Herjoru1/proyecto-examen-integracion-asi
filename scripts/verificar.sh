#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/verificar_web.py

llave=${LLAVE_PRIVADA_WEB:-.asilab/web}
puerto=${PUERTO_EVALUACION:-$(sed -n 's/^PUERTO_SFTP=//p' .env)}
destino=web@proyecto.final.asi
temporal=$(mktemp -d)
trap 'rm -rf "$temporal"' EXIT
printf '[proyecto.final.asi]:%s %s\n' "$puerto" \
    "$(docker compose exec -T sftp cat /etc/ssh/host/ssh_host_ed25519_key.pub)" > "$temporal/known_hosts"
opciones=(-o "UserKnownHostsFile=$temporal/known_hosts" -o StrictHostKeyChecking=yes
    -o BatchMode=yes -o ConnectTimeout=5 -o IdentitiesOnly=yes -i "$llave")

printf 'ASI prueba de transferencia\n' > "$temporal/entrada"
archivo="prueba-$(date +%s)-$$.txt"
sftp "${opciones[@]}" -P "$puerto" -b - "$destino" <<BATCH
pwd
cd /
ls
cd /entrega
put $temporal/entrada $archivo
get $archivo $temporal/salida
rm $archivo
BATCH
cmp "$temporal/entrada" "$temporal/salida"
printf 'SFTP: llave válida y contenido de subida y descarga idéntico\n'

if sftp "${opciones[@]}" -P "$puerto" -b - "$destino" >"$temporal/jaula" 2>&1 <<BATCH
get /etc/passwd $temporal/fuera
BATCH
then
    printf 'Falló la prueba de aislamiento\n' >&2
    exit 1
fi
[[ ! -e "$temporal/fuera" ]]
printf 'Jaula: /etc/passwd del servidor no está disponible para web\n'

if ssh "${opciones[@]}" -p "$puerto" "$destino" id >"$temporal/terminal" 2>&1; then
    printf 'Falló la restricción de ejecución remota\n' >&2
    exit 1
fi
grep -F 'This service allows sftp connections only.' "$temporal/terminal"
if ssh "${opciones[@]}" -p "$puerto" -tt "$destino" id >"$temporal/pty" 2>&1; then
    printf 'Falló la restricción de terminal\n' >&2
    exit 1
fi
grep -F 'PTY allocation request failed' "$temporal/pty"
if ssh "${opciones[@]}" -o PubkeyAuthentication=no \
        -o PreferredAuthentications=password -p "$puerto" "$destino" true >"$temporal/password" 2>&1; then
    printf 'SSH aceptó una conexión sin llave\n' >&2
    exit 1
fi
grep -F 'Permission denied (publickey)' "$temporal/password"
printf 'SSH: terminal, comandos y autenticación sin llave rechazados\n'

docker compose exec -T db psql -U postgres -d asi -At -c \
    'SELECT version(); SELECT codigo FROM roles ORDER BY codigo; SELECT count(*) FROM articulos;'
docker compose exec -T sftp /usr/sbin/sshd -T -C user=web,host=proyecto.final.asi,addr=127.0.0.1 |
    awk '$1 ~ /^(authenticationmethods|passwordauthentication|kbdinteractiveauthentication|chrootdirectory|forcecommand|permittty)$/'
