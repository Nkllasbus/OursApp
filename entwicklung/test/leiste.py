"""Test der Navigationsleiste unten (Tabs, Bögen, Chat-Zähler, Pausen-Timer)."""
import json, pathlib, re, subprocess, sys, time
from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parents[2]
STUB = (ROOT / "entwicklung/test/firebase-attrappe.js").read_text(encoding="utf-8")
T = ["dates", "recipes", "chores", "budget", "gym", "calendar", "trips"]
SEED = {".info": {"connected": True}, "users": {"u1": {"profile": {"name": "Niklas"}, "spaces": {t: "s-" + t for t in T}, "friendCode": "ABC123"}},
        "pub": {"u1": {"name": "Niklas"}}, "chatIndex": {"u1": {"c1": {"unread": 3}}},
        "spaces": {"s-" + t: {"meta": {"type": t, "by": "u1"}, "access": {"u1": True}} for t in T}}
PORT = 8773
srv = subprocess.Popen([sys.executable, "-m", "http.server", str(PORT)], cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(0.8)
ok = []; bad = []
def check(name, cond): (ok if cond else bad).append(name)
try:
    with sync_playwright() as p:
        b = p.chromium.launch(**({"executable_path": "/opt/pw-browsers/chromium"} if pathlib.Path("/opt/pw-browsers/chromium").exists() else {}))
        for dev in ["iPhone 13", None]:
            ctx = b.new_context(**(p.devices[dev] if dev else {"viewport": {"width": 1280, "height": 800}}), service_workers="block")
            ctx.add_init_script(f"window.__SEED={json.dumps(SEED)}")
            ctx.route(re.compile(r"gstatic\.com/firebasejs/"), lambda r: r.fulfill(status=200, content_type="text/javascript", body=STUB if "app-compat" in r.request.url else ""))
            ctx.route("**/version.json*", lambda r: r.fulfill(status=404, body=""))
            pg = ctx.new_page(); errs = []; pg.on("pageerror", lambda e: None if "ViewTransition" in str(e) else errs.append(str(e)))
            tag = dev or "PC"
            pg.goto(f"http://localhost:{PORT}/gym.html"); pg.wait_for_timeout(1500)
            bar = pg.locator("#oursTabs").bounding_box(); vh = pg.viewport_size["height"]
            check(f"{tag}: Leiste schwebt unten", bar and 0 <= vh - (bar["y"] + bar["height"]) <= 40)
            pad = pg.evaluate("parseFloat(getComputedStyle(document.querySelector('.wrap .scroll')).paddingBottom)")
            check(f"{tag}: Inhalt läuft unter der Leiste und endet darüber", pad >= vh - bar["y"])
            check(f"{tag}: Seiten-Tab aktiv auf Gym", pg.get_attribute("#pgBtn", "aria-current") == "page")
            check(f"{tag}: Chat-Zähler 3", pg.inner_text("#oursChatN") == "3" and pg.is_visible("#oursChatN"))
            pg.click("#pgBtn"); pg.wait_for_timeout(300)
            check(f"{tag}: Seiten-Bogen offen", pg.is_visible("#pgMenu"))
            sb = pg.locator("#pgMenu").bounding_box()
            check(f"{tag}: Bogen über der Leiste", sb["y"] + sb["height"] <= bar["y"])
            pg.mouse.click(10, 10); pg.wait_for_timeout(200)
            check(f"{tag}: Tipp daneben schließt", not pg.is_visible("#pgMenu"))
            pg.click("#tabMe"); pg.wait_for_timeout(300)
            check(f"{tag}: Du-Bogen offen", pg.is_visible("#pfMenu"))
            pg.click("#pfMenu [data-pf=settings]"); pg.wait_for_timeout(400)
            check(f"{tag}: Einstellungen öffnen (ohne Dunkelmodus)", pg.is_visible("#psNote") and pg.locator(".auth-theme").count() == 0)
            pg.click("#stDone"); pg.wait_for_timeout(200)
            # Pausen-Timer sichtbar über der Leiste
            pg.evaluate("restSec=60; startRest();"); pg.wait_for_timeout(300)
            rb = pg.locator("#restBar").bounding_box()
            check(f"{tag}: Pausen-Timer über der Leiste", rb and rb["y"] + rb["height"] <= bar["y"])
            pg.evaluate("stopRest()")
            pg.click("#pgBtn"); pg.click("#pgMenu [data-page=budget]"); pg.wait_for_url("**/budget.html"); pg.wait_for_timeout(800)
            check(f"{tag}: Raster öffnet Budget", pg.is_visible("text=Übersicht"))
            pg.click("#oursTabs [data-tab=feed]"); pg.wait_for_url("**/feed.html"); pg.wait_for_timeout(800)
            check(f"{tag}: Feed-Tab aktiv", pg.get_attribute("#oursTabs [data-tab=feed]", "aria-current") == "page")
            pg.click("#oursTabs [data-tab=home]"); pg.wait_for_url("**/home.html"); pg.wait_for_timeout(800)
            check(f"{tag}: Home-Tab", pg.get_attribute("#oursTabs [data-tab=home]", "aria-current") == "page")
            if dev is None: pg.screenshot(path=str(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp") / "pc.png"))
            check(f"{tag}: keine JS-Fehler", not errs)
            if errs: print(errs[:3])
            ctx.close()
        b.close()
finally:
    srv.terminate()
print("OK:", len(ok)); print("FEHLER:", bad or "keine")
