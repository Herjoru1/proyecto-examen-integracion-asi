#!/bin/sh
set -eu
umask 077

printf 'admin:%s\nweb:%s\n' "$ADMIN_CONSOLA" "$WEB_CONSOLA" | chpasswd
unset ADMIN_CONSOLA WEB_CONSOLA
install -d -o root -g root -m 0755 /etc/ssh/keys
install -o root -g root -m 0644 /entrada/web.pub /etc/ssh/keys/web
install -d -o root -g root -m 0755 /run/sshd
chown web:desarrolladores /srv/sftp/web/entrega
chmod 0750 /srv/sftp/web/entrega
if [ ! -f /etc/ssh/host/ssh_host_ed25519_key ]; then
    ssh-keygen -q -t ed25519 -N '' -f /etc/ssh/host/ssh_host_ed25519_key
fi
/usr/sbin/sshd -t
exec /usr/sbin/sshd -D -e
