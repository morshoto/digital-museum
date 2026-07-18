#!/usr/bin/env python3
"""Offline visual-generation seam for Evolving Impressionist.

The HTTP contract is intentionally compatible with a future Diffusers Img2Img
worker. The default renderer is dependency-free, so the exhibition can be
developed and tested without downloading a model.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hashlib
import json
import math
import random
from urllib.parse import urlparse


def clamp(value):
    return max(0.0, min(1.0, float(value)))


def prompt_for(s):
    light = "soft moonlit" if s["brightness"] < .35 else "luminous golden" if s["brightness"] > .65 else "diffused daylight"
    temperature = "cool blue-green" if s["warmth"] < .4 else "amber and rose" if s["warmth"] > .65 else "pearl and lavender"
    gesture = "restless sweeping" if s["motion"] > .65 else "slow visible" if s["motion"] > .35 else "quiet delicate"
    mood = "unsettled" if s["tension"] > .65 else "serene" if s["tension"] < .35 else "expectant"
    return f"{light} {temperature} impressionist painting, {gesture} brush strokes, {mood} atmosphere, abstraction {s['abstraction']:.2f}, no hard scene cut"


def render_svg(state, previous):
    s = {k: clamp(state.get(k, .5)) for k in ("brightness", "warmth", "abstraction", "motion", "tension")}
    seed_material = json.dumps(s, sort_keys=True) + (previous or "")[-512:]
    rng = random.Random(int(hashlib.sha256(seed_material.encode()).hexdigest()[:12], 16))
    width, height = 1600, 1000
    light = int(40 + 52 * s["brightness"])
    warmth = int(150 * s["warmth"])
    blue = int(180 - 110 * s["warmth"])
    contrast = 0.55 + s["tension"] * .5
    circles = []
    count = int(55 + s["abstraction"] * 100)
    for _ in range(count):
        x = rng.uniform(-.05, 1.05) * width
        y = rng.uniform(-.08, 1.08) * height
        radius = rng.uniform(25, 130) * (.75 + s["motion"])
        alpha = rng.uniform(.08, .25) * contrast
        hue_shift = rng.randint(-20, 20)
        color = f"rgb({max(0,min(255, light + warmth//2 + hue_shift))},{max(0,min(255, light + warmth//3 + hue_shift))},{max(0,min(255, blue + light//3))})"
        circles.append(f'<ellipse cx="{x:.1f}" cy="{y:.1f}" rx="{radius:.1f}" ry="{radius*rng.uniform(.35,.9):.1f}" fill="{color}" opacity="{alpha:.3f}" transform="rotate({rng.uniform(-35,35):.1f} {x:.1f} {y:.1f})"/>')
    prompt = prompt_for(s)
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
<defs><linearGradient id="sky" x1="0" y1="0" x2="1" y2="1"><stop stop-color="rgb({light+warmth//2},{light+warmth//3},{blue})"/><stop offset="1" stop-color="rgb({max(10,light//3)},{max(15,light//4)},{max(30,blue//2)})"/></linearGradient><filter id="blur"><feGaussianBlur stdDeviation="{3+s['abstraction']*8:.1f}"/></filter></defs>
<rect width="100%" height="100%" fill="url(#sky)"/><g filter="url(#blur)">{''.join(circles)}</g>
<path d="M0 {height*.72:.0f} Q{width*.25:.0f} {height*.58:.0f} {width*.5:.0f} {height*.72:.0f} T{width} {height*.65:.0f} V{height} H0Z" fill="rgb({30+warmth//3},{40+warmth//4},{80+blue//3})" opacity=".48"/>
<text x="38" y="{height-35}" fill="white" opacity=".42" font-family="sans-serif" font-size="16">EVOLVING IMPRESSIONIST · {s['brightness']:.2f} / {s['warmth']:.2f} / {s['abstraction']:.2f} / {s['motion']:.2f} / {s['tension']:.2f}</text>
</svg>'''
    return svg, prompt


class Handler(BaseHTTPRequestHandler):
    def _send(self, status, body):
        encoded = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(encoded)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        if urlparse(self.path).path == "/health":
            self._send(200, {"ok": True, "renderer": "offline-painterly-fallback"})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        if urlparse(self.path).path != "/generate":
            self._send(404, {"error": "not found"})
            return
        try:
            payload = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
            svg, prompt = render_svg(payload.get("state", {}), payload.get("previousSVG"))
            self._send(200, {"svg": svg, "prompt": prompt})
        except (ValueError, TypeError, KeyError) as error:
            self._send(400, {"error": str(error)})

    def log_message(self, format, *args):
        print(f"[visual-service] {format % args}", flush=True)


if __name__ == "__main__":
    print("Evolving Impressionist visual service listening on http://127.0.0.1:8000", flush=True)
    ThreadingHTTPServer(("127.0.0.1", 8000), Handler).serve_forever()
