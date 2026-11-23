#!/usr/bin/env bash
set -euo pipefail

psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --set ON_ERROR_STOP=1 \
  --set app_password="$APP_DB_PASSWORD" \
  --set admin_hash="$ADMIN_WEB_HASH" --set consulta_hash="$CONSULTA_WEB_HASH" <<'SQL'
BEGIN;
CREATE ROLE asi_web LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'app_password';
REVOKE ALL ON DATABASE asi FROM PUBLIC;
GRANT CONNECT ON DATABASE asi TO asi_web;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO asi_web;

CREATE TABLE roles (
  codigo text PRIMARY KEY,
  etiqueta text NOT NULL
);

CREATE TABLE usuarios (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  usuario text NOT NULL UNIQUE,
  password_hash text NOT NULL,
  rol text NOT NULL REFERENCES roles(codigo)
);

CREATE TABLE articulos (
  id_articulo integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre text NOT NULL,
  precio numeric(12,2) NOT NULL CHECK (precio >= 0),
  elementos_existentes integer NOT NULL CHECK (elementos_existentes >= 0)
);

CREATE TABLE sesiones (
  token_hash text PRIMARY KEY,
  usuario_id bigint NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  vence timestamptz NOT NULL
);
CREATE INDEX sesiones_vence_idx ON sesiones (vence);

INSERT INTO roles (codigo, etiqueta)
VALUES ('administrador', 'Administrador'), ('consulta', 'Consulta');

INSERT INTO usuarios (usuario, password_hash, rol)
VALUES ('admin', :'admin_hash', 'administrador'), ('consulta', :'consulta_hash', 'consulta');

INSERT INTO articulos (nombre, precio, elementos_existentes) VALUES
  ('Laptop Empresarial 15"', 18500.00, 12),
  ('Monitor 27" IPS 4K', 6490.00, 8),
  ('Teclado Mecánico Inalámbrico', 1450.00, 25),
  ('Adaptador HDMI a USB-C', 350.00, 0);

GRANT SELECT ON roles, usuarios, articulos TO asi_web;
GRANT SELECT, INSERT, DELETE ON sesiones TO asi_web;
COMMIT;
SQL
