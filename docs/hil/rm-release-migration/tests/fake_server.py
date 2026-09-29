#!/usr/bin/env python3
"""Test stand-in for the releases server (C7) and the local status endpoints of rc/home/kiosk.

Serves ROOT as static files (GET /releases/workstation/<v>/<file>, /releases/workstation/latest.json,
/rc/status, /home/status, /home/ui-heartbeat-state) and answers any POST with 200 {} (update-status).
Counts GETs of *.tgz in ROOT/downloads.log.   Usage: fake_server.py ROOT PORT
"""
import http.server
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()


class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(ROOT), **kw)

    def do_GET(self):  # noqa: N802
        if self.path.endswith(".tgz"):
            with open(ROOT / "downloads.log", "a") as f:
                f.write(self.path + "\n")
        super().do_GET()

    def do_POST(self):  # noqa: N802
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n)
        with open(ROOT / "posts.log", "ab") as f:
            f.write(self.path.encode() + b" " + body + b"\n")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b"{}")

    def log_message(self, *a):
        pass


http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[2])), H).serve_forever()
