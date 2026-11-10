# Ours – Projektwissen für Claude

Ours ist eine private Web-App für ein Paar bzw. eine WG (Niklas, GitHub `Nkllasbus`).
**Alle Texte in der App und alle Antworten an Niklas auf Deutsch.**

## Arbeitsregeln (von Niklas festgelegt)
- **Nach jeder fertigen, getesteten Änderung sofort hochladen** (push auf `main` in `Nkllasbus/OursApp`). Niklas will nicht jedes Mal darum bitten.
- Das alte Repo `Nkllas/Dateideen` **nicht anfassen**.
- Firebase-Regeln und Cloudflare-Worker kann Claude nicht selbst ändern: Datei an Niklas geben, er fügt sie ein.
- **Niemals** API-Schlüssel, den Enable-Banking-Schlüssel (.pem), `FIN_SECRET` oder Client-Secrets im Chat oder auf GitHub. Sie gehören nur in die Cloudflare-Secrets. Bank-PINs/Passwörter werden nirgends gespeichert.
- Niklas möchte Schritt-für-Schritt-Anleitungen: immer nur den nächsten Schritt geben, wenn er „gib mir den nächsten Schritt“ sagt.
- Design: Apple-Stil (HIG), siehe unten.

## Adressen
- Webseite (GitHub Pages): https://nkllasbus.github.io/OursApp/ (Start: `home.html`)
- Firebase Realtime Database, Projekt `oursapp-ff4cf` (europe-west1). Die Firebase-Konfiguration in den Seiten ist öffentlich und kein Geheimnis.
- Cloudflare Worker („Helfer“): https://oursapp.niklasbergnerbus.workers.dev
- iPhone-App (unsigniert, Installation mit Sideloadly): https://github.com/Nkllasbus/OursApp/releases/download/app-neueste/Ours.ipa

## Aufbau
- Jede Seite ist eine einzelne HTML-Datei im Hauptordner: `home` (Start), `index` (Dateideen), `rezepte`, `haushalt`, `budget`, `gym`, `kalender`, `reise`, `mail`, `chat`, `raum` (Raumdesign), `smarthome` (bald), `datenschutz`.
- **`entwicklung/auth.js`** ist der gemeinsame Kern und steckt eingebettet in jeder Seite: Anmeldung, Bereiche (`spaces/<id>`), Seitenmenü, Einstellungen, Hell/Dunkel (`OursTheme`), Apple-Design-Schicht (Schrift, Farben, Drück-Gefühl, Haptik `OursHaptic`, Bögen, Seitenübergänge), Offline-Schicht (Zwischenspeicher `ofl:c:` + Warteschlange `ofl:outbox`, Daten sofort aus dem Speicher), Mitteilungen (`OursPush`), Kurzbefehle-Links, Freunde/Chat.
  - Nach Änderungen an `auth.js`: `python3 entwicklung/build.py` (baut es in alle Seiten ein und setzt eine neue Version in `version.json`).
- `sw.js`: Service Worker. Seiten zuerst aus dem Speicher, im Hintergrund aktualisieren. Bei Bild-/Dateiänderungen `CACHE` (z. B. `ours-v7`) hochzählen und denselben Namen in `auth.js` (Versionsprüfung, `caches.open(...)`) anpassen.
- `entwicklung/cloudflare-worker.js`: aktueller Worker-Code (Rezept-Import, Nährwerte, Raumdesign mit Gemini, Bank über Enable Banking `fin-*`, Mitteilungen `push-*`, Cron für Erinnerungen und neue Umsätze).
- `entwicklung/firebase/regeln.json`: aktuelle Firebase-Regeln (Bereiche generisch über `spaces/$sid/access`).
- `app/` + `.github/workflows/ios-app.yml`: iPhone-App mit Capacitor 7. Lädt live `home.html` (server.url), Plugins: Haptics, LocalNotifications, Keyboard. GitHub Actions baut bei Änderungen in `app/` eine unsignierte IPA und legt sie als Release `app-neueste` ab. (macOS-Runner werden manchmal nach 15 Min. Wartezeit abgebrochen – dann einfach erneut anstoßen.)

## Daten (Firebase)
- `spaces/<sid>/…` gemeinsame Bereiche je Seite (`users/<uid>/spaces/<typ>` zeigt auf den Bereich). Typen: dates, recipes, chores, budget, gym, calendar, trips.
  - Kalender: `events/<id>` mit `rep` ({f:day|week|month|year, n, days, until}), `skip`, `al` (Hinweise je Nutzer: Minuten vorher).
  - Reisen: `trips/<id>` mit pack, todo, plan, costs, info.
  - Gym: `workouts/<id>` mit `al` (Hinweise).
- `users/<uid>/fin/…` privates Budget (Konten, Umsätze `tx`, Regeln, Verträge, Enable-Banking-Sitzungen `eb`).
- `users/<uid>/home/{budget,gym}` Kurzinfos für Startseite und Kalender.
- `users/<uid>/settings` (kcal-Schalter, theme, push-Kategorien).

## Cloudflare-Einstellungen (macht Niklas)
- Secrets: `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `EB_PRIVATE_KEY`, `FIN_SECRET`; Text: `ALLOWED_ORIGIN`, `EB_APP_ID`.
- KV-Bindung **`PUSH`** (Mitteilungen; VAPID-Schlüssel erzeugt der Worker selbst) und Cron-Trigger `*/15 * * * *`.

## Testen
Seiten lokal mit `python3 -m http.server` ausliefern und mit Playwright (Chromium ist vorinstalliert) testen; Firebase dabei durch eine Attrappe ersetzen (Route auf `gstatic.com/firebasejs/*app-compat*`). Vor jedem Push die betroffenen Abläufe durchklicken.

## Offene Punkte (Stand 10.11.2026)
- Budget: Umsätze vom selben Tag kommen bei der Sparkasse teils nicht an. Diagnose eingebaut (Meldung nach „Aktualisieren“ zeigt Anzahl und Datum des neuesten Umsatzes). Auf der Webseite geht es, in der App noch prüfen (neue App-Version installieren).
- iPhone-App: nächster Schritt für Niklas = automatische Verlängerung alle 7 Tage (kostenlose Apple-ID; Sideloadly „Auto Refresh“ o. Ä.).
- Mail: Gmail-OAuth-Client-ID fehlt noch (`GMAIL_CLIENT_ID` in `mail.html`).
- Smart Home: Antworten offen (IKEA-Hub DIRIGERA/TRÅDFRI?, TV-Marke, Home Assistant ja/nein).
