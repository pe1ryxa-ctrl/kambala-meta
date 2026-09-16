#!/usr/bin/env python3
"""Minimal-header HTTP proxy to FlyByIP-B for a browser that sends too-long headers.
Write-enabled variant: all GET requests pass (including Save), POST/PUT/DELETE blocked.
Listens on 127.0.0.1:8011 only (reach via SSH tunnel). Logs to /tmp/fbproxy.log. Auto-stops after 30 min."""
import http.client, http.server, threading, time, os, signal

TARGET = ("192.168.13.11", 80)
LOG = open("/tmp/fbproxy.log", "a", buffering=1)


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def deny(self, why):
        LOG.write(f"{time.strftime('%H:%M:%S')} DENY {self.command} {self.path} ({why})\n")
        body = f"Blocked by proxy: {why}".encode()
        self.send_response(403)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        c = http.client.HTTPConnection(*TARGET, timeout=8)
        c.request("GET", self.path, headers={"Host": TARGET[0]})
        r = c.getresponse()
        data = r.read()
        LOG.write(f"{time.strftime('%H:%M:%S')} OK   GET {self.path[:160]} -> {r.status} {len(data)}b\n")
        self.send_response(r.status)
        self.send_header("Content-Type", r.getheader("Content-Type", "text/html"))
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        self.deny("method POST")

    def do_PUT(self):
        self.deny("method PUT")

    def do_DELETE(self):
        self.deny("method DELETE")


srv = http.server.ThreadingHTTPServer(("127.0.0.1", 8011), H)
threading.Timer(1800, lambda: os.kill(os.getpid(), signal.SIGTERM)).start()
LOG.write(f"{time.strftime('%H:%M:%S')} START write-enabled proxy 127.0.0.1:8011 -> 192.168.13.11:80, auto-stop 30 min\n")
print("proxy listening on 127.0.0.1:8011 (30 min)")
srv.serve_forever()
