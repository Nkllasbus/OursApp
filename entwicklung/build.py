"""Baut auth.js in alle Seiten ein und setzt eine neue Versionsnummer.

Die HTML-Dateien im Hauptordner sind die Quelle. Jede Seite enthält auth.js direkt
(in einem <script>, das mit "/* Anmeldung, Profil und Bereiche" beginnt).
Aufruf:  python3 entwicklung/build.py
"""
import re, json, time, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
PAGES = ["home", "index", "rezepte", "haushalt", "budget", "gym", "kalender", "reise", "mail", "chat", "raum"]
MARK = "/* Anmeldung, Profil und Bereiche"

version = time.strftime("%Y-%m-%d-%H%M%S")
auth = (ROOT / "entwicklung" / "auth.js").read_text(encoding="utf-8")
auth = re.sub(r'const APP_VERSION="[^"]*"', f'const APP_VERSION="{version}"', auth).rstrip("\n") + "\n"
(ROOT / "entwicklung" / "auth.js").write_text(auth, encoding="utf-8")

for name in PAGES:
    f = ROOT / f"{name}.html"
    s = f.read_text(encoding="utf-8")
    i = s.find(MARK)
    assert i > 0 and s.count(MARK) == 1, f"{name}: auth.js-Block nicht eindeutig gefunden"
    j = s.find("</script>", i)
    f.write_text(s[:i] + auth + s[j:], encoding="utf-8")
    print("✓", f.name)

(ROOT / "version.json").write_text(json.dumps({"v": version}), encoding="utf-8")
print("Version", version)
