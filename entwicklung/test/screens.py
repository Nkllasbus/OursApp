"""Screenshots aller Seiten im iPhone-Format (angemeldet über die Firebase-Attrappe).
Aufruf: python3 entwicklung/test/screens.py [ausgabeordner] [seite ...] [--dark]
"""
import json, pathlib, re, subprocess, sys, time
from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parents[2]
args = [a for a in sys.argv[1:] if not a.startswith("--")]
OUT = pathlib.Path(args[0] if args else "/tmp/ours-screens"); OUT.mkdir(parents=True, exist_ok=True)
PAGES = args[1:] or ["home", "kalender", "gym", "budget", "haushalt", "rezepte", "index", "reise", "chat", "mail", "raum"]
DARK = "--dark" in sys.argv
STUB = (ROOT / "entwicklung/test/firebase-attrappe.js").read_text(encoding="utf-8")
SEED = {".info": {"connected": True}, "users": {"u1": {"profile": {"name": "Niklas"}, "spaces": {t: "s-" + t for t in ["dates", "recipes", "chores", "budget", "gym", "calendar", "trips"]},
                         "friendCode": "ABC123"}},
        "pub": {"u1": {"name": "Niklas"}},
        "spaces": {"s-" + t: {"meta": {"type": t, "by": "u1"}, "access": {"u1": True}} for t in ["dates", "recipes", "chores", "budget", "gym", "calendar", "trips"]}}

PORT = 8771
srv = subprocess.Popen([sys.executable, "-m", "http.server", str(PORT)], cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(0.8)
errors = {}
try:
    with sync_playwright() as p:
        b = p.chromium.launch()
        ctx = b.new_context(**p.devices["iPhone 13"], service_workers="block", color_scheme="dark" if DARK else "light")
        ctx.add_init_script(f"window.__SEED={json.dumps(SEED)};try{{localStorage.setItem('ours.theme','{'dark' if DARK else 'light'}')}}catch(e){{}}")
        ctx.route(re.compile(r"gstatic\.com/firebasejs/"), lambda r: r.fulfill(status=200, content_type="text/javascript", body=STUB if "app-compat" in r.request.url else ""))
        ctx.route("**/version.json*", lambda r: r.fulfill(status=404, body=""))
        for name in PAGES:
            pg = ctx.new_page(); errs = []
            pg.on("pageerror", lambda e, errs=errs: errs.append(str(e)))
            pg.goto(f"http://localhost:{PORT}/{name}.html"); pg.wait_for_timeout(1500)
            sfx = "-dark" if DARK else ""
            pg.screenshot(path=str(OUT / f"{name}{sfx}.png"))
            if name == "gym":   # Bögen der Leiste unten
                pg.click("#pgBtn"); pg.wait_for_timeout(600); pg.screenshot(path=str(OUT / f"bogen-seiten{sfx}.png")); pg.click("#pgBtn")
                pg.click("#tabMe"); pg.wait_for_timeout(600); pg.screenshot(path=str(OUT / f"bogen-du{sfx}.png")); pg.mouse.click(5, 300)
            if errs: errors[name] = errs[:3]
            pg.close()
        b.close()
finally:
    srv.terminate()
print("Screenshots in", OUT)
print("Fehler:", json.dumps(errors, ensure_ascii=False, indent=1) if errors else "keine")
