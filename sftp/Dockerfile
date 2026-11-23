FROM ubuntu:24.04
RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-server sudo \
    && rm -rf /var/lib/apt/lists/* /etc/ssh/ssh_host_* \
    && groupadd --system desarrolladores \
    && useradd --no-create-home --home-dir /entrega --shell /usr/sbin/nologin -g desarrolladores web \
    && useradd --create-home --shell /bin/bash -G sudo admin \
    && install -d -o root -g root -m 0755 /srv/sftp/web /run/sshd \
    && install -d -o web -g desarrolladores -m 0750 /srv/sftp/web/entrega
COPY sshd_config /etc/ssh/sshd_config
COPY iniciar.sh /usr/local/sbin/iniciar-sftp
ENTRYPOINT ["/usr/local/sbin/iniciar-sftp"]
