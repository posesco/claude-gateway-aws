#!/bin/sh
set -eu

# 1. Parse GATEWAY_POSTGRES_URL into PG_HOSTPORT, PG_USER, PG_PASS, PG_DB
# Format: postgres://user:pass@host:5432/db?sslmode=require
if [ -n "${GATEWAY_POSTGRES_URL:-}" ]; then
  PG_NO_PROTO="${GATEWAY_POSTGRES_URL#*://}"
  PG_CREDS="${PG_NO_PROTO%%@*}"
  PG_REST="${PG_NO_PROTO#*@}"
  export PG_USER="${PG_CREDS%%:*}"
  export PG_PASS="${PG_CREDS#*:}"
  export PG_HOSTPORT="${PG_REST%%/*}"
  PG_DB_QUERY="${PG_REST#*/}"
  export PG_DB="${PG_DB_QUERY%%\?*}"
fi

# 2. Copy provisioning configs from /etc/observability/grafana/provisioning/ to /etc/grafana/provisioning/
if [ -d "/etc/observability/grafana/provisioning" ]; then
  mkdir -p /etc/grafana/provisioning
  cp -r /etc/observability/grafana/provisioning/* /etc/grafana/provisioning/

  # Safely replace environment placeholders in datasource configs using literal awk replacement
  if [ -d "/etc/grafana/provisioning/datasources" ]; then
    for f in /etc/grafana/provisioning/datasources/*.yaml /etc/grafana/provisioning/datasources/*.yml; do
      [ -f "$f" ] || continue
      awk '
      function replace_all(str, pat, rep,    pos, res) {
        res = ""
        while ((pos = index(str, pat)) > 0) {
          res = res substr(str, 1, pos - 1) rep
          str = substr(str, pos + length(pat))
        }
        return res str
      }
      {
        line = $0
        line = replace_all(line, "$${PG_HOSTPORT}", ENVIRON["PG_HOSTPORT"])
        line = replace_all(line, "${PG_HOSTPORT}", ENVIRON["PG_HOSTPORT"])
        line = replace_all(line, "$${PG_USER}", ENVIRON["PG_USER"])
        line = replace_all(line, "${PG_USER}", ENVIRON["PG_USER"])
        line = replace_all(line, "$${PG_DB}", ENVIRON["PG_DB"])
        line = replace_all(line, "${PG_DB}", ENVIRON["PG_DB"])
        line = replace_all(line, "$${PG_PASS}", ENVIRON["PG_PASS"])
        line = replace_all(line, "${PG_PASS}", ENVIRON["PG_PASS"])
        print line
      }
      ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    done
  fi
fi

# 3. Execute official Grafana entrypoint
exec /run.sh "$@"
