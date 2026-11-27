"""A tiny dependency-free web app for the ECS Fargate demo."""
import json, os, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = os.environ.get("APP_VERSION", "1")
COLOR = {"1": "#ff9900", "2": "#2ea44f"}.get(VERSION, "#ff9900")


def task_id():
    """Short ECS task ID from the task metadata endpoint (falls back to 'local')."""
    uri = os.environ.get("ECS_CONTAINER_METADATA_URI_V4")
    if not uri:
        return "local"
    try:
        with urllib.request.urlopen(f"{uri}/task", timeout=1) as r:
            return json.load(r)["TaskARN"].split("/")[-1][:8]
    except Exception:
        return "unknown"


TASK = task_id()

PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Fargate demo</title>
<style>body{{margin:0;min-height:100vh;display:grid;place-items:center;font-family:system-ui,sans-serif;
background:#0f1b2d;color:#e8eef7}}main{{padding:40px;background:#16263d;border-radius:16px;max-width:520px}}
.v{{display:inline-block;padding:4px 12px;border-radius:999px;background:{color};color:#0f1b2d;font-weight:700}}
code{{color:{color}}}</style></head><body><main>
<p class="v">Version {version}</p>
<h1>Hello from AWS Fargate 🐳</h1>
<p>This container runs on <strong>Amazon ECS Fargate</strong> behind an <strong>Application Load Balancer</strong>.</p>
<p>Served by task <code>{task}</code>. Refresh to see the load balancer pick a task.</p>
</main></body></html>"""


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            body, ctype = b'{"status":"ok"}', "application/json"
        elif self.path == "/api/info":
            body = json.dumps({"version": VERSION, "task": TASK}).encode()
            ctype = "application/json"
        else:
            body = PAGE.format(version=VERSION, task=TASK, color=COLOR).encode()
            ctype = "text/html; charset=utf-8"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        print(json.dumps({"task": TASK, "path": self.path, "status": args[1] if len(args) > 1 else ""}), flush=True)


if __name__ == "__main__":
    print(json.dumps({"msg": "starting", "version": VERSION, "task": TASK}), flush=True)
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
