#!/usr/bin/env python3
"""
Transparent async TCP/HTTP proxy and Loki log/prompt shipper for Claude Apps Gateway.

- Listens on 0.0.0.0:8080 (ALB target port) and forwards all traffic transparently
  (including SSE streaming responses and HTTP/1.1 Keep-Alive connections) to
  `claude gateway` listening on 127.0.0.1:8081.
- Captures `POST /v1/messages` requests (up to 4 MB, supporting Content-Length,
  Transfer-Encoding: chunked, and Content-Encoding: gzip) to extract user email,
  target model, and sanitized prompt text (stripping `<system-reminder>` blocks and
  unwrapping `<session>` auto-title wrappers, with 30s deduplication), emitting
  structured `evt="user.prompt"` JSON logs to stdout (CloudWatch) and shipping them
  to Grafana Loki.
- Resolves all Cloud Map A-record IPs for `loki.claude-gateway-lab.internal` and
  maintains an in-memory ring buffer (`loki_history`, last 500 events) that is
  automatically replayed to any newly discovered Loki IP within <=15 seconds so
  ECS rolling updates or Loki container restarts never lose prompt/audit logs.
"""

import asyncio
import base64
import collections
import datetime
import gzip
import json
import os
import queue
import re
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

LISTEN_HOST = os.environ.get("PROXY_LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("PROXY_LISTEN_PORT", "8080"))
UPSTREAM_HOST = os.environ.get("UPSTREAM_HOST", "127.0.0.1")
UPSTREAM_PORT = int(os.environ.get("UPSTREAM_PORT", "8081"))
LOKI_PUSH_URL = os.environ.get(
    "LOKI_PUSH_URL",
    "http://loki.claude-gateway-lab.internal:3100/loki/api/v1/push",
)
MAX_CAPTURE_BYTES = 4 * 1024 * 1024  # 4 MB for full Claude Code CLI payloads
MAX_PROMPT_CHARS = 4000
DEDUP_WINDOW_SECONDS = 30.0

LokiItem = tuple[dict[str, str], int, str]

loki_queue: "queue.Queue[LokiItem]" = queue.Queue(maxsize=5000)
history_lock = threading.Lock()
loki_history: "collections.deque[LokiItem]" = collections.deque(maxlen=500)
synced_loki_ips: set[str] = set()

identity_lock = threading.Lock()
sub_to_email: dict[str, str] = {}
last_known_email: list[str] = ["unknown"]
recent_prompts: dict[tuple[str, str], float] = {}


def record_known_identity(sub: str, email: str) -> None:
    with identity_lock:
        if email and email not in ("unknown", "system", "none"):
            last_known_email[0] = email
            if sub and sub != "unknown":
                sub_to_email[sub] = email


def resolve_known_email(sub: str, email: str) -> str:
    with identity_lock:
        if email and email != "unknown":
            if sub and sub != "unknown":
                sub_to_email[sub] = email
            last_known_email[0] = email
            return email
        if sub and sub in sub_to_email:
            return sub_to_email[sub]
        return last_known_email[0]


def is_duplicate_prompt(email: str, prompt: str) -> bool:
    now = time.monotonic()
    key = (email, prompt)
    with identity_lock:
        expired = [k for k, ts in recent_prompts.items() if now - ts > DEDUP_WINDOW_SECONDS]
        for k in expired:
            recent_prompts.pop(k, None)
        last_ts = recent_prompts.get(key)
        if last_ts is not None and (now - last_ts) <= DEDUP_WINDOW_SECONDS:
            return True
        recent_prompts[key] = now
        return False


def clean_prompt_text(raw: str) -> str:
    if not raw:
        return ""
    text = re.sub(r"<system-reminder>.*?</system-reminder>", "", raw, flags=re.DOTALL).strip()
    session_match = re.search(r"<session>\s*(.*?)\s*</session>", text, flags=re.DOTALL)
    if session_match:
        text = session_match.group(1).strip()
    text = re.sub(
        r"\s*Write the title in the predominant language.*$",
        "",
        text,
        flags=re.DOTALL,
    ).strip()
    return text


def enqueue_loki(labels: dict[str, str], line: str) -> None:
    if not LOKI_PUSH_URL:
        return
    ts_ns = time.time_ns()
    clean_labels = {
        k: (str(v) if v else "unknown")
        for k, v in labels.items()
    }
    item: LokiItem = (clean_labels, ts_ns, line)
    with history_lock:
        loki_history.append(item)
    try:
        loki_queue.put_nowait(item)
    except queue.Full:
        pass


def resolve_loki_targets() -> list[tuple[str, str, str]]:
    """
    Returns a list of (ip_or_host, target_push_url, host_header) for all currently
    registered A-records of the Loki service discovery hostname.
    """
    parsed = urllib.parse.urlsplit(LOKI_PUSH_URL)
    host = parsed.hostname or "loki.claude-gateway-lab.internal"
    port = parsed.port or (443 if parsed.scheme == "https" else 3100)
    path = parsed.path or "/loki/api/v1/push"

    ips: list[str] = []
    try:
        infos = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM)
        for info in infos:
            ip = info[4][0]
            if ip and ip not in ips:
                ips.append(ip)
    except Exception:
        pass

    if not ips:
        return [(host, LOKI_PUSH_URL, host)]

    targets: list[tuple[str, str, str]] = []
    for ip in ips:
        url = f"{parsed.scheme}://{ip}:{port}{path}"
        targets.append((ip, url, host))
    return targets


def build_loki_payload(items: list[LokiItem]) -> bytes:
    streams_map: dict[tuple[tuple[str, str], ...], list[list[str]]] = {}
    seen: set[tuple[int, str]] = set()
    for labels, ts_ns, line in items:
        dedup_key = (ts_ns, line)
        if dedup_key in seen:
            continue
        seen.add(dedup_key)
        key = tuple(sorted(labels.items()))
        streams_map.setdefault(key, []).append([str(ts_ns), line])

    payload = {
        "streams": [
            {"stream": dict(key), "values": values}
            for key, values in streams_map.items()
        ]
    }
    return json.dumps(payload, ensure_ascii=False).encode("utf-8")


def push_items_to_target(ip_key: str, target_url: str, host_header: str, items: list[LokiItem]) -> bool:
    if not items:
        return True
    body = build_loki_payload(items)
    last_err = None
    for attempt in range(3):
        try:
            req = urllib.request.Request(
                target_url,
                data=body,
                headers={
                    "Content-Type": "application/json",
                    "Host": host_header,
                },
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=2.5) as resp:
                resp.read()
            return True
        except Exception as exc:
            last_err = exc
            if attempt < 2:
                time.sleep(1.5)

    print(
        f"[gateway-proxy-loki] warn: failed to push {len(items)} logs to {target_url} ({ip_key}): {last_err}",
        file=sys.stderr,
        flush=True,
    )
    return False


def flush_batch_and_sync_targets(batch: list[LokiItem]) -> None:
    targets = resolve_loki_targets()
    active_ips = {ip_key for ip_key, _, _ in targets}

    with history_lock:
        # Prune stale IPs that are no longer in DNS so if an IP is reused later it resyncs
        synced_loki_ips.intersection_update(active_ips)
        history_snapshot = list(loki_history)

    for ip_key, target_url, host_header in targets:
        with history_lock:
            needs_replay = ip_key not in synced_loki_ips

        items_to_send = history_snapshot if needs_replay else batch
        if not items_to_send:
            continue

        if push_items_to_target(ip_key, target_url, host_header, items_to_send):
            with history_lock:
                synced_loki_ips.add(ip_key)


def loki_shipper_worker() -> None:
    while True:
        batch: list[LokiItem] = []
        try:
            first_item = loki_queue.get(timeout=15.0)
            batch.append(first_item)
            deadline = time.monotonic() + 1.0
            while len(batch) < 50 and time.monotonic() < deadline:
                try:
                    batch.append(loki_queue.get(timeout=0.1))
                except queue.Empty:
                    break
        except queue.Empty:
            # Periodic 15s check: if a new Loki task IP appeared in Cloud Map while idle,
            # replay `loki_history` to it immediately.
            pass
        except Exception:
            continue

        try:
            flush_batch_and_sync_targets(batch)
        except Exception:
            pass


def decode_jwt_identity(headers_raw: str) -> tuple[str, str]:
    token = ""
    for line in headers_raw.split("\r\n")[1:]:
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        k_lower = k.strip().lower()
        v_clean = v.strip()
        if k_lower == "authorization" and v_clean.lower().startswith("bearer "):
            token = v_clean[7:].strip()
            break
        if k_lower == "x-api-key" and v_clean:
            token = v_clean
            break

    email = "unknown"
    sub = "unknown"
    if token and "." in token:
        parts = token.split(".")
        if len(parts) >= 2:
            try:
                payload_b64 = parts[1]
                padding = "=" * (-len(payload_b64) % 4)
                decoded = base64.urlsafe_b64decode(payload_b64 + padding).decode(
                    "utf-8", errors="replace"
                )
                claims = json.loads(decoded)
                if isinstance(claims, dict):
                    email = str(
                        claims.get("email")
                        or claims.get("upn")
                        or claims.get("preferred_username")
                        or "unknown"
                    )
                    sub = str(claims.get("sub") or claims.get("principal") or "unknown")
            except Exception:
                pass

    resolved_email = resolve_known_email(sub, email)
    return resolved_email, sub


def extract_text_from_content(content: object) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            if isinstance(item, str):
                parts.append(item)
            elif isinstance(item, dict):
                if item.get("type") == "text" and isinstance(item.get("text"), str):
                    parts.append(item["text"])
                elif "content" in item:
                    sub = extract_text_from_content(item.get("content"))
                    if sub:
                        parts.append(sub)
        return "\n".join(parts)
    return ""


def decode_chunked_body(raw: bytes) -> bytes:
    out = bytearray()
    pos = 0
    n = len(raw)
    while pos < n:
        line_end = raw.find(b"\r\n", pos)
        if line_end == -1:
            break
        size_str = raw[pos:line_end].split(b";", 1)[0].strip()
        try:
            chunk_size = int(size_str, 16)
        except ValueError:
            break
        if chunk_size == 0:
            break
        chunk_start = line_end + 2
        chunk_end = chunk_start + chunk_size
        if chunk_end > n:
            break
        out.extend(raw[chunk_start:chunk_end])
        pos = chunk_end + 2
    return bytes(out)


def inspect_and_log_prompt(captured: bytes) -> bool:
    """
    Returns True once inspection of this HTTP request is complete (logged or skipped),
    or False if still waiting for more request body bytes.
    """
    if not captured.startswith(b"POST /v1/messages"):
        return True

    sep_idx = captured.find(b"\r\n\r\n")
    if sep_idx == -1:
        return len(captured) >= MAX_CAPTURE_BYTES

    headers_bytes = captured[:sep_idx]
    body_bytes = captured[sep_idx + 4:]
    headers_str = headers_bytes.decode("latin-1", errors="replace")

    content_length = 0
    is_chunked = False
    is_gzip = False

    for line in headers_str.split("\r\n")[1:]:
        lower_line = line.lower()
        if lower_line.startswith("content-length:"):
            try:
                content_length = int(line.split(":", 1)[1].strip())
            except ValueError:
                content_length = 0
        elif lower_line.startswith("transfer-encoding:") and "chunked" in lower_line:
            is_chunked = True
        elif lower_line.startswith("content-encoding:") and "gzip" in lower_line:
            is_gzip = True

    if is_chunked:
        if b"0\r\n\r\n" not in body_bytes:
            return len(captured) >= MAX_CAPTURE_BYTES
        raw_payload_bytes = decode_chunked_body(body_bytes)
    else:
        if content_length > MAX_CAPTURE_BYTES:
            return True
        if content_length > 0 and len(body_bytes) < content_length:
            return len(captured) >= MAX_CAPTURE_BYTES
        raw_payload_bytes = body_bytes[:content_length] if content_length > 0 else body_bytes

    if is_gzip:
        try:
            raw_payload_bytes = gzip.decompress(raw_payload_bytes)
        except Exception:
            return True

    email, sub = decode_jwt_identity(headers_str)
    try:
        payload = json.loads(raw_payload_bytes.decode("utf-8", errors="replace"))
    except Exception:
        return True

    if not isinstance(payload, dict):
        return True

    model = str(payload.get("model") or "unknown")
    messages = payload.get("messages")
    last_user_prompt = ""
    messages_count = 0

    if isinstance(messages, list):
        messages_count = len(messages)
        for msg in reversed(messages):
            if isinstance(msg, dict) and msg.get("role") == "user":
                raw_text = extract_text_from_content(msg.get("content")).strip()
                cleaned_text = clean_prompt_text(raw_text)
                if cleaned_text:
                    last_user_prompt = cleaned_text
                    break

    if not last_user_prompt:
        return True

    if len(last_user_prompt) > MAX_PROMPT_CHARS:
        last_user_prompt = last_user_prompt[:MAX_PROMPT_CHARS] + "... [truncated]"

    if is_duplicate_prompt(email, last_user_prompt):
        return True

    now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
    log_entry = {
        "ts": now_iso,
        "evt": "user.prompt",
        "email": email,
        "sub": sub,
        "model": model,
        "prompt": last_user_prompt,
        "messages_count": messages_count,
    }
    log_line = json.dumps(log_entry, ensure_ascii=False)
    print(log_line, flush=True)
    enqueue_loki(
        {
            "app": "claude-gateway",
            "evt": "user.prompt",
            "email": email,
            "model": model,
        },
        log_line,
    )
    return True


async def pipe_client_to_upstream(
    reader: asyncio.StreamReader, writer: asyncio.StreamWriter
) -> None:
    captured = bytearray()
    capturing = False
    try:
        while True:
            chunk = await reader.read(65536)
            if not chunk:
                break
            writer.write(chunk)
            await writer.drain()

            try:
                if not capturing:
                    marker_idx = chunk.find(b"POST /v1/messages")
                    if marker_idx != -1:
                        capturing = True
                        captured.clear()
                        captured.extend(chunk[marker_idx:marker_idx + MAX_CAPTURE_BYTES])
                        if inspect_and_log_prompt(bytes(captured)):
                            capturing = False
                            captured.clear()
                else:
                    if len(captured) < MAX_CAPTURE_BYTES:
                        remaining = MAX_CAPTURE_BYTES - len(captured)
                        captured.extend(chunk[:remaining])
                    if inspect_and_log_prompt(bytes(captured)):
                        capturing = False
                        captured.clear()
            except Exception:
                capturing = False
                captured.clear()
    except Exception:
        pass
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass


async def pipe_upstream_to_client(
    reader: asyncio.StreamReader, writer: asyncio.StreamWriter
) -> None:
    try:
        while True:
            chunk = await reader.read(65536)
            if not chunk:
                break
            writer.write(chunk)
            await writer.drain()
    except Exception:
        pass
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass


async def handle_client(
    client_reader: asyncio.StreamReader, client_writer: asyncio.StreamWriter
) -> None:
    upstream_reader = None
    upstream_writer = None
    for attempt in range(10):
        try:
            upstream_reader, upstream_writer = await asyncio.open_connection(
                UPSTREAM_HOST, UPSTREAM_PORT
            )
            break
        except Exception:
            if attempt == 9:
                try:
                    client_writer.close()
                    await client_writer.wait_closed()
                except Exception:
                    pass
                return
            await asyncio.sleep(0.15)

    await asyncio.gather(
        pipe_client_to_upstream(client_reader, upstream_writer),
        pipe_upstream_to_client(upstream_reader, client_writer),
    )


def stream_subprocess_output(pipe, target_stream, parse_for_loki: bool) -> None:
    try:
        for raw_line in iter(pipe.readline, b""):
            line_str = raw_line.decode("utf-8", errors="replace").rstrip("\r\n")
            print(line_str, file=target_stream, flush=True)
            if not parse_for_loki or not line_str:
                continue

            if line_str.startswith("{"):
                try:
                    obj = json.loads(line_str)
                    if isinstance(obj, dict) and "evt" in obj:
                        evt = str(obj.get("evt") or "log")
                        sub = str(obj.get("sub") or obj.get("principal") or "unknown")
                        raw_email = str(obj.get("email") or "")
                        if raw_email:
                            record_known_identity(sub, raw_email)
                        email = (
                            raw_email
                            or resolve_known_email(sub, "unknown")
                            or "system"
                        )
                        model = str(obj.get("model") or "none")
                        enqueue_loki(
                            {
                                "app": "claude-gateway",
                                "evt": evt,
                                "email": email,
                                "model": model,
                            },
                            line_str,
                        )
                except Exception:
                    pass
            elif line_str.startswith("[gateway]"):
                enqueue_loki(
                    {
                        "app": "claude-gateway",
                        "evt": "gateway.info",
                        "email": "system",
                        "model": "none",
                    },
                    line_str,
                )
    except Exception:
        pass


async def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: gateway_proxy_loki.py <config_path> [extra_args...]", file=sys.stderr)
        sys.exit(1)

    config_path = sys.argv[1]
    extra_args = sys.argv[2:]

    shipper = threading.Thread(target=loki_shipper_worker, daemon=True)
    shipper.start()

    cmd = ["/usr/local/bin/claude", "gateway", "--config", config_path] + extra_args
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    t_out = threading.Thread(
        target=stream_subprocess_output,
        args=(proc.stdout, sys.stdout, True),
        daemon=True,
    )
    t_err = threading.Thread(
        target=stream_subprocess_output,
        args=(proc.stderr, sys.stderr, True),
        daemon=True,
    )
    t_out.start()
    t_err.start()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        try:
            loop.add_signal_handler(sig, lambda s=sig: proc.send_signal(s))
        except NotImplementedError:
            pass

    server = await asyncio.start_server(handle_client, LISTEN_HOST, LISTEN_PORT)

    async with server:
        while True:
            ret = proc.poll()
            if ret is not None:
                sys.exit(ret)
            await asyncio.sleep(0.5)


if __name__ == "__main__":
    asyncio.run(main())
