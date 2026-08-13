#!/usr/bin/env python3
"""Serve one Nix archive over HTTP, with controllable failure modes.

Used by tests/prefetch-nix-archive.test.sh to reproduce the truncated download
that scripts/prefetch-nix-archive.sh must survive.

Usage: fake-release-server.py MODE ARCHIVE COUNT_FILE PORT_FILE

MODE is one of:
  good              every request returns the whole archive
  silent-first      request 1 returns half the archive with a matching
                    Content-Length, so the client sees a clean short body;
                    later requests return the whole archive
  closed-always     every request declares the full Content-Length and then
                    sends half the body and closes the connection
  missing           every request returns 404
  server-error      every request returns 503

COUNT_FILE receives one line per request. PORT_FILE receives the bound port.
"""

import http.server
import sys
import threading

MODE, ARCHIVE, COUNT_FILE, PORT_FILE = sys.argv[1:5]

with open(ARCHIVE, "rb") as fh:
    BODY = fh.read()
HALF = BODY[: len(BODY) // 2]

lock = threading.Lock()
requests = 0


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def do_GET(self):
        global requests
        with lock:
            requests += 1
            n = requests
            with open(COUNT_FILE, "a") as fh:
                fh.write(f"{self.path}\n")

        if MODE in ("missing", "server-error"):
            self.send_response(404 if MODE == "missing" else 503)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        truncate = MODE == "closed-always" or (MODE == "silent-first" and n == 1)
        body = HALF if truncate else BODY

        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        # closed-always advertises the full size and then hangs up mid-body, the
        # shape curl reports as "transfer closed with N bytes remaining".
        # silent-first advertises the short size, which curl accepts, so only the
        # integrity check can reject it.
        self.send_header(
            "Content-Length", str(len(BODY) if MODE == "closed-always" else len(body))
        )
        self.end_headers()
        self.wfile.write(body)
        if truncate and MODE == "closed-always":
            self.close_connection = True


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(PORT_FILE, "w") as fh:
    fh.write(str(server.server_address[1]))
server.serve_forever()
