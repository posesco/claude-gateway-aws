#!/bin/sh
set -eu

CONFIG_PATH="/etc/claude/gateway.yaml"

# Si ECS Fargate inyecta GATEWAY_CONFIG_YAML desde AWS SSM Parameter Store,
# materializamos el archivo declarativo en /etc/claude/gateway.yaml antes de arrancar.
if [ -n "${GATEWAY_CONFIG_YAML:-}" ]; then
  printf '%s\n' "$GATEWAY_CONFIG_YAML" > "$CONFIG_PATH"
fi

if [ ! -s "$CONFIG_PATH" ]; then
  echo "ERROR: No se encontro configuracion valida en $CONFIG_PATH ni en la variable GATEWAY_CONFIG_YAML." >&2
  exit 1
fi

# Reasignamos el puerto interno de claude gateway a 8081 para que gateway_proxy_loki.py
# escuche en 0.0.0.0:8080, capture los prompts (POST /v1/messages) hacia Loki y reenvie el trafico.
sed -i 's/port: 8080/port: 8081/' "$CONFIG_PATH"

exec python3 /usr/local/bin/gateway_proxy_loki.py "$CONFIG_PATH" "$@"
