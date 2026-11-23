#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -f .asilab/accesos ]]; then
    printf 'Ejecuta primero ./scripts/preparar.sh.\n' >&2
    exit 1
fi
printf 'Credenciales web de esta instalación\n'
cat .asilab/accesos
