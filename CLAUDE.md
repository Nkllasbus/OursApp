# Ours – Projektwissen für Claude

Ours ist eine private Web-App für ein Paar bzw. eine WG (Niklas, GitHub `Nkllasbus`).
**Alle Texte in der App und alle Antworten an Niklas auf Deutsch.**

## Arbeitsregeln (von Niklas festgelegt)
- **Nach jeder fertigen, getesteten Änderung sofort hochladen** (push auf `main` in `Nkllasbus/OursApp`). Niklas will nicht jedes Mal darum bitten.
- Das alte Repo `Nkllas/Dateideen` **nicht anfassen**.
- Firebase-Regeln und Cloudflare-Worker kann Claude nicht selbst ändern: Datei an Niklas geben, er fügt sie ein.
- **Niemals** API-Schlüssel, den Enable-Banking-Schlüssel (.pem), `FIN_SECRET` oder Client-Secrets im Chat oder auf GitHub. Sie gehören nur in die Cloudflare-Secrets. Bank-PINs/Passwörter werden nirgends gespeichert.
- Niklas möchte Schritt-für-Schritt-Anleitungen: immer nur den nächsten Schritt geben, wenn er „gib mir den nächsten Schritt“ sagt.
- Design: konsequent Apple-Stil (iOS 26: helle Systemfarben, große Titel, Kapsel-Knöpfe, Segmented Controls, schwebende Glas-Leiste, Sheets von unten, Haptik). **Vorerst nur ein heller Modus** – den Dunkelmodus machen wir später wieder.

## Adressen
- Webseite (GitHub Pages): https://nkllasbus.github.io/OursApp/ (Start: `home.html`)
- Firebase Realtime Database, Projekt `oursapp-ff4cf` (europe-west1). Die Firebase-Konfiguration in den Seiten ist öffentlich und kein Geheimnis.
- Cloudflare Worker („Helfer“): https://oursapp.niklasbergnerbus.workers.dev
- iPhone-App (unsigniert, Installation mit Sideloadly): https://github.com/Nkllasbus/OursApp/releases/download/app-neueste/Ours.ipa

## Aufbau
- Jede Seite ist eine einzelne HTML-Datei im Hauptordner: `home` (Start), `index` (Dateideen), `rezepte`, `haushalt`, `budget`, `gym`, `kalender`, `reise`, `mail`, `chat`, `feed`, `datenschutz`. (Räume und Smart Home sind vorerst entfernt und kommen später.)
- **`entwicklung/auth.js`** ist der gemeinsame Kern und steckt eingebettet in jeder Seite: Anmeldung, Bereiche (`spaces/<id>`), Seitenmenü, Einstellungen, Hell/Dunkel (`OursTheme`), Apple-Design-Schicht (Schrift, Farben, Drück-Gefühl, Haptik `OursHaptic`, Bögen, Seitenübergänge), Offline-Schicht (Zwischenspeicher `ofl:c:` + Warteschlange `ofl:outbox`, Daten sofort aus dem Speicher), Mitteilungen (`OursPush`), Kurzbefehle-Links, Freunde/Chat.
  - Nach Änderungen an `auth.js`: `python3 entwicklung/build.py` (baut es in alle Seiten ein und setzt eine neue Version in `version.json`).
  - **Navigation (seit 12.11.2026, Stil wie Instagram/YouTube):** Leiste unten `#oursTabs` mit Home · Feed · Seiten (Raster `#pgMenu`, Liste `GRID`) · Chats (Zähler `#oursChatN`) · Du (Profilbild `#pfBtn`, Menü `#pfMenu` als Bogen). Kopfzeile schlicht (Hintergrund `--bg`, Titel links). `.wrap` endet über der Leiste (`--tab-h`). Kein Logo und kein schwebender Chat-Knopf mehr.
- `sw.js`: Service Worker. Seiten zuerst aus dem Speicher, im Hintergrund aktualisieren. Bei Bild-/Dateiänderungen `CACHE` (z. B. `ours-v7`) hochzählen und denselben Namen in `auth.js` (Versionsprüfung, `caches.open(...)`) anpassen.
- `entwicklung/cloudflare-worker.js`: aktueller Worker-Code (Rezept-Import, Nährwerte, Raumdesign mit Gemini, Bank über Enable Banking `fin-*`, Mitteilungen `push-*`, Cron für Erinnerungen und neue Umsätze).
- `entwicklung/firebase/regeln.json`: aktuelle Firebase-Regeln (Bereiche generisch über `spaces/$sid/access`).
- `app/` + `.github/workflows/ios-app.yml`: iPhone-App mit Capacitor 7. Lädt live `home.html` (server.url), Plugins: Haptics, LocalNotifications, Keyboard. GitHub Actions baut bei Änderungen in `app/` eine unsignierte IPA und legt sie als Release `app-neueste` ab. (macOS-Runner werden manchmal nach 15 Min. Wartezeit abgebrochen – dann einfach erneut anstoßen.)

## Daten (Firebase)
- `spaces/<sid>/…` gemeinsame Bereiche je Seite (`users/<uid>/spaces/<typ>` zeigt auf den Bereich). Typen: dates, recipes, chores, budget, gym, calendar, trips.
  - Kalender: `events/<id>` mit `rep` ({f:day|week|month|year, n, days, until}), `skip`, `al` (Hinweise je Nutzer: Minuten vorher), `kind:"rem"` (Erinnerung, abhaken über `doneOn[datum]`), `inv` (Eingeladene), `url`.
  - Reisen: `trips/<id>` mit pack, todo, plan, costs, info.
  - Gym: `workouts/<id>` mit `al` (Hinweise).
- `users/<uid>/fin/…` privates Budget (Konten, Umsätze `tx`, Regeln, Verträge, Enable-Banking-Sitzungen `eb`).
  - Reiter „Budgets“ (Gehalt einteilen): `fin.budgets` (Kategorie → Cent je Gehaltszeitraum), `fin.meta.salaryAmt` (eigener Gehaltsbetrag), `fin.meta.extraInc` (weitere Einnahmen {n,a,m: jeden Monat, p: Zeitraum-Start}), `fin.meta.countOtherInc`. Zeitraum = letztes Gehalt bis Tag vor dem nächsten. Korrekturen je Kategorie: `fin.adj/<id>` = {cat, a (Cent; >0 Geld zurück, <0 Ausgabe dazu), n, d, tx (verknüpfter Eingang)} – fließen in `periodSpend` ein. PayPal-Doppelungen: `ppPairs()` gleicht Girokonto-Abbuchungen „PayPal“ mit dem PayPal-Konto ab (Umbuchung), Ausnahme `fin.meta.ppKeep`. Warnungen bei 80 %/100 % schickt der Worker (`push-budget`, auch für Abbuchungen aus dem Cron).
- `users/<uid>/home/{budget,gym}` Kurzinfos für Startseite und Kalender.
- Feed (`feed.html`, Tab in der Leiste): zeigt nur Freunde-Aktivität – Rezepte (`posts/<uid>`), abgeschlossene Trainings (`shelf/<uid>/gym` → `sessions`) und neue Termine anderer im geteilten Kalender (nur wenn `access` > 1 Person). Budget, Mail, Haushalt und der Rest erscheinen bewusst nicht. Kommentare wie bei Instagram: Rezepte `posts/<uid>/<pid>/comments`, Trainings `posts/<uid>/g_<sessionId>/comments` (ohne `at`, erscheint daher nicht als Beitrag), Termine `spaces/<kal>/events/<id>/comments`; Kommentar = {by,name,text,at}.
- Freundesprofil (`friendProfile(uid,back)` in `auth.js`, auch `Auth.openFriend(uid)`; geöffnet aus Einstellungen → Freunde, Feed und „Mein Profil“ → „So sehen dich deine Freunde“): zeigt `pub/<uid>`, geteilte Rezepte (`shelf/<uid>/recipes`), Training (`shelf/<uid>/gym`: Monat, Minuten, Wochen in Folge, 8-Wochen-Balken), Beiträge, „Gemeinsam“ (eigene Bereiche, in deren `access` der Freund steht) und „Einladen“ zu eigenen Seiten. Budget und Mail nie. Rezepte öffnen über `rezepte.html#frr~uid~sid~rid` bzw. `#prof~uid`.
- `users/<uid>/settings` (kcal-Schalter, theme, push-Kategorien).

## Cloudflare-Einstellungen (macht Niklas)
- Secrets: `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `EB_PRIVATE_KEY`, `FIN_SECRET`; Text: `ALLOWED_ORIGIN`, `EB_APP_ID`.
- KV-Bindung **`PUSH`** (Mitteilungen; VAPID-Schlüssel erzeugt der Worker selbst) und Cron-Trigger `*/15 * * * *`.
- Apple-Kalender-Abo: Worker liefert `GET /cal/<schlüssel>/<kalender>.ics` (KV: `calu:<uid>`→Schlüssel, `calt:<schlüssel>`→{uid,sid}, `cals:<sid>` gemeinsame Termine je Farbe, `calp:<uid>` private Arten Gym/Dates/Verträge/Reisen). Die Kalender-Seite schickt den Stand mit `cal-publish`, sobald `spaces/<kal>/meta/calFeed` an ist. Je Terminart ein Abo, weil Apple bei Abos nur eine Farbe pro Kalender kennt.

## Testen
Seiten lokal mit `python3 -m http.server` ausliefern und mit Playwright (Chromium ist vorinstalliert) testen. Vor jedem Push die betroffenen Abläufe durchklicken.
- `entwicklung/test/firebase-attrappe.js`: Firebase-Attrappe mit angemeldetem Nutzer „Niklas“ (uid `u1`), Startdaten über `window.__SEED`.
- `python3 entwicklung/test/screens.py <ordner> [seiten…] [--dark]`: Screenshots aller Seiten im iPhone-Format.
- `python3 entwicklung/test/leiste.py`: Ablauftest der Navigationsleiste (Handy und PC).
- Wichtig: im Kontext `service_workers="block"` setzen und die Route als Regex `gstatic\.com/firebasejs/` angeben (ein Glob `**/gstatic.com/…` trifft `www.gstatic.com` nicht).

## Offene Punkte (Stand 12.11.2026)
- Apple-Gestaltung (Stylesheet `ours-apple` in `auth.js`, je Seite eine Tint-Farbe über `data-hig-page`) – Niklas gibt weitere Anweisungen, danach Dunkelmodus.
- Budget: Umsätze vom selben Tag kommen bei der Sparkasse teils nicht an. Diagnose eingebaut (Meldung nach „Aktualisieren“ zeigt Anzahl und Datum des neuesten Umsatzes). Auf der Webseite geht es, in der App noch prüfen (neue App-Version installieren).
- iPhone-App: nächster Schritt für Niklas = automatische Verlängerung alle 7 Tage (kostenlose Apple-ID; Sideloadly „Auto Refresh“ o. Ä.).
- Mail: Gmail-OAuth-Client-ID fehlt noch (`GMAIL_CLIENT_ID` in `mail.html`).
- Smart Home und Räume: später (Seiten entfernt; Smart-Home-Fragen offen: IKEA-Hub, TV-Marke, Home Assistant).
