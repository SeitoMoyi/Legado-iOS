# -*- coding: utf-8 -*-
"""Loopback-only fixtures for the isolated iOS verification app. No user sources."""
import base64
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys
import threading
from urllib.parse import urlsplit

pixel = base64.b64decode('R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==')
events = []
lock = threading.Lock()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlsplit(self.path).path
        authenticated = 'probe=1' in self.headers.get('Cookie', '')
        with lock:
            events.append({'path': path, 'cookie': authenticated})
        status, mime = 200, 'application/json'
        if path == '/feed':
            status = 200 if self.headers.get('X-Probe') == 'native' else 403
            data = json.dumps([{'title': 'Native', 'link': '/article'}]).encode()
        elif path == '/gate':
            status, data = 403, b'login'
        elif path == '/replacement':
            data = b'replacement'
        elif path == '/pixel.gif':
            status, data, mime = (200 if authenticated else 403), pixel, 'image/gif'
        elif path == '/download':
            data, mime = '第一章 原生下载\n正文内容。\n'.encode(), 'application/octet-stream'
        elif path == '/rules':
            data = json.dumps([{'bookSourceUrl': 'https://native-fixture.test', 'bookSourceName': 'Fixture'}]).encode()
        elif path == '/events':
            with lock:
                data = json.dumps(events).encode()
        else:
            status, data = 404, b'missing'
        self.send_response(status)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        if path == '/download':
            self.send_header('Content-Disposition', 'attachment; filename="probe.txt"')
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *args):
        pass

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
Path(sys.argv[1]).write_text('http://127.0.0.1:' + str(server.server_port))
print('Native fixture server ready', flush=True)
server.serve_forever()
