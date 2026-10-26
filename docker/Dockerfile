# syntax=docker/dockerfile:1
FROM python:3.14-slim-bookworm AS downloader

ARG CLAUDE_VERSION=latest
ARG TARGETARCH=amd64

RUN python3 - <<'PY'
import hashlib, json, os, pathlib, urllib.request

arch_map = {"amd64": "linux-x64", "arm64": "linux-arm64"}
platform = arch_map[os.environ.get("TARGETARCH", "amd64")]
base = "https://downloads.claude.ai/claude-code-releases"
version = os.environ.get("CLAUDE_VERSION", "latest")
if version == "latest":
    version = urllib.request.urlopen(f"{base}/latest", timeout=30).read().decode().strip()

manifest = json.loads(urllib.request.urlopen(f"{base}/{version}/manifest.json", timeout=30).read())
expected = manifest["platforms"][platform]["checksum"]
binary = urllib.request.urlopen(f"{base}/{version}/{platform}/claude", timeout=120).read()
actual = hashlib.sha256(binary).hexdigest()
if actual != expected:
    raise SystemExit(f"SHA-256 mismatch: {actual} != {expected}")

claude_path = pathlib.Path("/usr/local/bin/claude")
claude_path.write_bytes(binary)
claude_path.chmod(0o755)

rds_ca = urllib.request.urlopen(
    "https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem", timeout=30
).read()
ca_path = pathlib.Path("/rds-global-bundle.pem")
ca_path.write_bytes(rds_ca)
ca_path.chmod(0o644)
PY

FROM python:3.14-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    CLAUDE_CONFIG_DIR=/tmp/.claude \
    NODE_EXTRA_CA_CERTS=/etc/claude/rds-global-bundle.pem

RUN install -d -m 0755 -o 65532 -g 65532 /etc/claude /tmp/.claude

COPY --from=downloader --chmod=0755 /usr/local/bin/claude /usr/local/bin/claude
COPY --from=downloader --chmod=0644 /rds-global-bundle.pem /etc/claude/rds-global-bundle.pem
COPY --chmod=0755 gateway_proxy_loki.py entrypoint.sh /usr/local/bin/

EXPOSE 8080
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
