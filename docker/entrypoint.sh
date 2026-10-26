#!/bin/sh
set -eu

CONFIG_PATH="/etc/claude/gateway.yaml"
S3_CONFIG_PATH="/gateway-config/gateway.yaml"

if [ ! -s "$S3_CONFIG_PATH" ]; then
  echo "ERROR: No se encontro configuracion valida en $S3_CONFIG_PATH." >&2
  exit 1
fi

# La copia conserva el archivo fuente del volumen S3 y permite modificar el puerto
# en el directorio escribible por el usuario del Gateway (UID 65532).
cp "$S3_CONFIG_PATH" "$CONFIG_PATH"

# Reasignamos el puerto interno de claude gateway a 8081 para que gateway_proxy_loki.py
# escuche en 0.0.0.0:8080, capture los prompts (POST /v1/messages) hacia Loki y reenvie el trafico.
sed -i 's/port: 8080/port: 8081/' "$CONFIG_PATH"

exec python3 /usr/local/bin/gateway_proxy_loki.py "$CONFIG_PATH" "$@"
