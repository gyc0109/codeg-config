#!/usr/bin/env python3
"""
Dual-upstream gateway for codeg on this Mac: OpenCode Go + Command Code GOAT.

Model names carry a prefix that selects the upstream (stripped before sending):

    ocg/<id>  ->  https://opencode.ai/zen/go          (OpenCode Go)
    ccg/<id>  ->  https://api.commandcode.ai/provider/v1   (Command Code GOAT)
    <id>      ->  OpenCode Go (legacy behaviour, no prefix)

Point any OpenAI/Anthropic compatible agent at http://127.0.0.1:15825/v1
(Anthropic clients at http://127.0.0.1:15825).

OpenCode Go refuses any request that does not carry a session header
(x-opencode-session / session_id / x-session-id). Most coding agents cannot
send one, so for ocg/ requests this proxy:

  * injects Authorization: Bearer <OPENCODE_API_KEY>
  * injects a session id (reuses the client's if it sent one, else a uuid)

Command Code's Anthropic endpoint (/provider/v1/messages) is stricter than
Anthropic's own: it rejects any message whose role is `system` with
`400 Invalid input at messages.N.role`. Claude Code routinely injects
environment/context blocks as `system` turns inside the messages array, so for
ccg/ requests to */messages this proxy hoists those turns into the top-level
`system` field, injects the real Bearer key, and makes sure `messages` still
starts with a `user` turn.

Upstream responses are forwarded head-verbatim and streamed byte-for-byte, so
chunked SSE and plain JSON both reach the client intact.

'OPENCODE_API_KEY' is read from the environment or ~/.codeg/opencode-go-key;
'COMMANDCODE_API_KEY' from the environment or ~/.codeg/commandcode-goat-key.
"""
import http.client
import http.server
import json
import os
import sys
import uuid

LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = int(os.environ.get("OPENCODE_GO_PROXY_PORT", "15825"))

OCG_HOST = "opencode.ai"
OCG_BASE = "/zen/go"
OCG_KEY = os.environ.get("OPENCODE_API_KEY", "")
OCG_KEY_FILE = os.path.expanduser("~/.codeg/opencode-go-key")
if not OCG_KEY and os.path.exists(OCG_KEY_FILE):
    with open(OCG_KEY_FILE) as fh:
        OCG_KEY = fh.read().strip()

CC_HOST = "api.commandcode.ai"
CC_BASE = "/provider/v1"
CC_KEY = os.environ.get("COMMANDCODE_API_KEY", "")
CC_KEY_FILE = os.path.expanduser("~/.codeg/commandcode-goat-key")
if not CC_KEY and os.path.exists(CC_KEY_FILE):
    with open(CC_KEY_FILE) as fh:
        CC_KEY = fh.read().strip()

SESSION_HEADERS = ("x-opencode-session", "session_id", "x-session-id")

_HOP = (
    "host",
    "connection",
    "content-length",
    "transfer-encoding",
    "authorization",
    "x-api-key",
    "accept-encoding",
    "accept",
    "anthropic-version",
)


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "codeg-dual-proxy/1.0"

    def log_message(self, fmt, *args):  # keep the log quiet-ish
        sys.stderr.write("[codeg-dual-proxy] %s\n" % (fmt % args))
        sys.stderr.flush()

    def _session_id(self):
        for name in SESSION_HEADERS:
            value = self.headers.get(name)
            if value and value.strip():
                return value.strip()
        return str(uuid.uuid4())

    def _read_body(self):
        tee = (self.headers.get("Transfer-Encoding") or "").lower()
        if "chunked" in tee:
            chunks = []
            while True:
                line = self.rfile.readline()
                if not line:
                    break
                line = line.strip()
                if not line:
                    continue
                size = int(line.split(b";")[0], 16)
                if size == 0:
                    self.rfile.readline()
                    break
                chunks.append(self.rfile.read(size))
                self.rfile.readline()
            return b"".join(chunks)
        length = self.headers.get("Content-Length")
        if not length:
            return b""
        try:
            n = int(length)
        except ValueError:
            return b""
        return self.rfile.read(n) if n > 0 else b""

    def _error(self, status, message):
        payload = json.dumps(
            {"error": {"type": "proxy_error", "message": message}}
        ).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    @staticmethod
    def _split_model(model):
        """('ocg'|'ccg', wire_id); unprefixed models stay on OpenCode Go."""
        if isinstance(model, str):
            if model.startswith("ocg/"):
                return "ocg", model[4:]
            if model.startswith("ccg/"):
                return "ccg", model[4:]
        return "ocg", model

    @staticmethod
    def _text_of(content):
        if isinstance(content, str):
            return content
        out = []
        if isinstance(content, list):
            for blk in content:
                if isinstance(blk, dict) and blk.get("type") == "text":
                    out.append(blk.get("text", ""))
        return "\n".join(out)

    @classmethod
    def _normalize_cc_messages(cls, body):
        """Hoist `system` turns out of `messages` into top-level `system`."""
        try:
            doc = json.loads(body)
        except (ValueError, TypeError):
            return body, False
        if not isinstance(doc, dict):
            return body, False
        msgs = doc.get("messages")
        if not isinstance(msgs, list):
            return body, False

        kept, extra = [], []
        for msg in msgs:
            if isinstance(msg, dict) and msg.get("role") == "system":
                extra.append(cls._text_of(msg.get("content")))
            else:
                kept.append(msg)
        if not extra:
            return body, False

        parts = []
        cur = doc.get("system")
        if isinstance(cur, str):
            parts.append(cur)
        elif isinstance(cur, list):
            parts.extend(cls._text_of(cur).split("\n"))
        parts.extend(extra)
        doc["system"] = "\n\n".join(p for p in parts if p)

        while kept and isinstance(kept[0], dict) and kept[0].get("role") == "assistant":
            kept.pop(0)
        doc["messages"] = kept
        return json.dumps(doc).encode(), True

    def _route(self, path, body):
        """Decide (host, target_path, key, kind, body)."""
        model = None
        if body:
            try:
                doc = json.loads(body)
                if isinstance(doc, dict):
                    model = doc.get("model")
            except (ValueError, TypeError):
                pass
        prefix, wire = self._split_model(model)

        # Normalize "/v1/..." and bare "/..." (Anthropic clients) the same way.
        suffix = path[3:] if path.startswith("/v1") else path

        if prefix == "ccg":
            if not CC_KEY:
                return None
            out = body
            changed = False
            if wire is not None and wire != model:
                try:
                    doc = json.loads(out)
                    if isinstance(doc, dict):
                        doc["model"] = wire
                        out = json.dumps(doc).encode()
                        changed = True
                except (ValueError, TypeError):
                    pass
            if "/messages" in suffix:
                out, fixed = self._normalize_cc_messages(out)
                changed = changed or fixed
            return (CC_HOST, CC_BASE + suffix, CC_KEY, "cc", out)

        if not OCG_KEY:
            return None
        out = body
        if wire is not None and wire != model:
            try:
                doc = json.loads(out)
                if isinstance(doc, dict):
                    doc["model"] = wire
                    out = json.dumps(doc).encode()
            except (ValueError, TypeError):
                pass
        return (OCG_HOST, OCG_BASE + path, OCG_KEY, "ocg", out)

    def _proxy(self):
        body = self._read_body()
        routed = self._route(self.path, body)
        if routed is None:
            missing = "COMMANDCODE_API_KEY" if body and b'"model"' in body and b"ccg/" in body else "OPENCODE_API_KEY"
            self._error(500, "%s is not configured" % missing)
            return
        host, target, key, kind, body = routed

        headers = {}
        for hkey, value in self.headers.items():
            if hkey.lower() in _HOP:
                continue
            headers[hkey] = value
        headers["Authorization"] = "Bearer " + key
        if kind == "ocg":
            headers["x-api-key"] = key
            headers["x-opencode-session"] = self._session_id()
        headers["Accept"] = "application/json, text/event-stream"
        if "/messages" in target:
            headers["anthropic-version"] = "2023-06-01"
        if body:
            headers["Content-Length"] = str(len(body))

        conn = http.client.HTTPSConnection(host, timeout=600)
        try:
            conn.request(self.command, target, body=body or None, headers=headers)
            resp = conn.getresponse()
        except Exception as exc:  # noqa: BLE001
            conn.close()
            self._error(502, "upstream request failed: %s" % exc)
            return

        transfer_encoding = (resp.getheader("Transfer-Encoding") or "").lower()
        content_length = resp.getheader("Content-Length")

        self.send_response(resp.status)
        for key, value in resp.getheaders():
            if key.lower() in ("transfer-encoding", "content-length", "connection"):
                continue
            self.send_header(key, value)

        try:
            if content_length is not None and "chunked" not in transfer_encoding:
                self.send_header("Content-Length", content_length)
                self.end_headers()
                remaining = int(content_length)
                while remaining > 0:
                    chunk = resp.read(min(65536, remaining))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    remaining -= len(chunk)
            else:
                self.send_header("Transfer-Encoding", "chunked")
                self.end_headers()
                while True:
                    chunk = resp.read(65536)
                    if not chunk:
                        break
                    self.wfile.write(("%X\r\n" % len(chunk)).encode() + chunk + b"\r\n")
                    self.wfile.flush()
                self.wfile.write(b"0\r\n\r\n")
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            conn.close()

    def do_GET(self):
        self._proxy()

    def do_POST(self):
        self._proxy()

    def do_PUT(self):
        self._proxy()

    def do_PATCH(self):
        self._proxy()

    def do_DELETE(self):
        self._proxy()


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    if not OCG_KEY:
        sys.stderr.write("[codeg-dual-proxy] no OpenCode Go API key\n")
    if not CC_KEY:
        sys.stderr.write("[codeg-dual-proxy] no Command Code API key\n")
    httpd = Server((LISTEN_HOST, LISTEN_PORT), Handler)
    sys.stderr.write(
        "[codeg-dual-proxy] listening on http://%s:%d\n"
        "  ocg/* -> https://%s%s\n"
        "  ccg/* -> https://%s%s\n"
        % (LISTEN_HOST, LISTEN_PORT, OCG_HOST, OCG_BASE, CC_HOST, CC_BASE)
    )
    sys.stderr.flush()
    httpd.serve_forever()
