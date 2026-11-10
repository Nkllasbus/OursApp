// Rezept-Helfer für "Unsere Rezepte"
// - Link zu TikTok, Instagram oder YouTube: holt Beschreibung und Vorschaubild, Claude macht daraus ein Rezept
// - mode "nutrition": schätzt Menge und Nährwerte pro 100 g für Zutatenzeilen
// - mode "label": liest die Nährwerttabelle von einem Foto ab
// - mode "photo": macht aus Fotos (Screenshot, Kochbuch, handgeschriebener Zettel) ein Rezept
// - mode "price": sucht aktuelle Discounterpreise im Netz und rechnet sie auf die Rezeptmengen um
// - mode "stores": schätzt, welche Zutaten es bei welchen Supermarktketten normalerweise gibt
// - mode "room-empty": räumt ein Raumfoto leer (Google Gemini)
// - mode "room-style": richtet den leeren Raum in einem Einrichtungsstil ein (Google Gemini)
//
// Einstellungen in Cloudflare (Settings → Variables and Secrets):
//   ANTHROPIC_API_KEY  (Typ "Secret")  dein Claude-API-Schlüssel
//   ALLOWED_ORIGIN     (Typ "Text")    z.B. https://nkllas.github.io
//   GEMINI_API_KEY     (Typ "Secret")  Schlüssel aus Google AI Studio, nur für Raumdesign
//   GEMINI_MODEL       (Typ "Text", optional) anderes Bildmodell von Google
//
// Finanzen (Budget-Seite, Bankkonten über Enable Banking / PSD2):
// - mode "fin-banks": Liste der Banken eines Landes
// - mode "fin-start": Anmeldung bei der Bank starten (Login passiert auf der Seite der Bank)
// - mode "fin-finish": nach der Rückkehr von der Bank die Sitzung anlegen
// - mode "fin-sync": Kontostände und Umsätze abrufen (nur lesen)
// - mode "fin-end": Verbindung zur Bank wieder trennen
// - mode "fin-cat": Umsätze automatisch Kategorien zuordnen (Claude)
// Jede fin-Anfrage braucht ein gültiges Firebase-Login (ID-Token), sonst wird sie abgelehnt.
//   EB_APP_ID          (Typ "Text")    Application ID aus dem Enable-Banking-Control-Panel
//   EB_PRIVATE_KEY     (Typ "Secret")  privater Schlüssel der Anwendung (kompletter Inhalt der .pem-Datei)
//   FIN_SECRET         (Typ "Secret")  beliebiger langer Zufallstext, verknüpft Bank-Sitzungen mit deinem Konto
//
// Mitteilungen aufs Handy (Web Push):
// - mode "push-key": öffentlicher Schlüssel für die Anmeldung beim Browser (wird beim ersten Mal selbst erzeugt)
// - mode "push-sub": Gerät an- oder abmelden, Arten von Mitteilungen speichern
// - mode "push-plan": Erinnerungen der nächsten Tage hinterlegen (die Seite rechnet sie aus)
// - mode "push-notify": Personen eines gemeinsamen Bereichs benachrichtigen (z. B. neuer Termin)
// - mode "push-test": Test-Mitteilung an die eigenen Geräte
// Braucht einen KV-Speicher mit der Bindung PUSH und einen Cron-Trigger (z. B. alle 15 Minuten).
// Die Schlüssel für Web Push erzeugt der Helfer selbst und legt sie nur im KV-Speicher ab.

const MODEL = "claude-opus-5-5";

const RECIPE_SCHEMA = {
  type: "object",
  properties: {
    title: { type: "string" },
    ingredients: { type: "array", items: { type: "string" } },
    steps: { type: "array", items: { type: "string" } },
    category: { type: "string", enum: ["Frühstück", "Hauptgericht", "Vorspeise", "Süßes", "Backen", "Snack"] },
    servings: { type: "integer" },
  },
  required: ["title", "ingredients", "steps", "category", "servings"],
  additionalProperties: false,
};

const SYSTEM = `Du bekommst Titel und Beschreibung eines Koch-Videos von TikTok, Instagram oder YouTube.
Mach daraus ein Rezept auf Deutsch.
- title: kurzer, appetitlicher Rezeptname ohne Hashtags und Emojis.
- ingredients: eine Zutat pro Eintrag, Menge zuerst, z.B. "200 g rote Linsen". Übersetze ins Deutsche, rechne Cups und Unzen grob in g/ml um.
- steps: kurze, klare Arbeitsschritte in der richtigen Reihenfolge, ohne Nummerierung.
- category: "Frühstück" für typisches Frühstück (Porridge, Müsli, Overnight Oats, Pancakes, Rührei, Frühstücksbowls, Smoothies), "Hauptgericht" für sättigende Mahlzeiten (Pasta, Currys, Bowls, Burger), "Vorspeise" für Suppen, Salate und kleine Teller vorab, "Süßes" für Desserts ohne Ofen wie Pudding, Mousse und Eis, "Backen" für alles, was gebacken wird, wie Kuchen, Brot, Brötchen, Kekse, Muffins und Brownies, "Snack" für Kleinigkeiten zwischendurch, Dips, Riegel und Fingerfood.
- servings: für wie viele Portionen die Mengen gedacht sind. Steht es im Text, nimm das. Sonst schätze es anhand der Mengen (meist 2 bis 4). Bei Kuchen oder Blechen die übliche Stückzahl (z.B. 12).
Erfinde keine Zutaten oder Schritte, die nicht im Text stehen oder sich nicht eindeutig daraus ergeben.
Steht im Text kein Rezept, gib nur einen passenden Titel zurück und lass ingredients und steps leer.`;

export default {
  async scheduled(event, env, ctx) { ctx.waitUntil(pushCron(env)); },
  async fetch(request, env) {
    const origin = request.headers.get("Origin") || "";
    const allowed = (env.ALLOWED_ORIGIN || "").split(",").map(s => s.trim()).filter(Boolean);
    const cors = {
      "Access-Control-Allow-Origin": allowed.includes(origin) ? origin : (allowed[0] || ""),
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
      "Vary": "Origin",
    };
    const reply = (status, data) =>
      new Response(JSON.stringify(data), { status, headers: { ...cors, "Content-Type": "application/json" } });

    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
    if (request.method !== "POST") return reply(405, { error: "Nur POST erlaubt." });
    // nur Anfragen von deiner eigenen Seite, damit niemand sonst dein Guthaben verbraucht
    if (!allowed.includes(origin)) return reply(403, { error: "Diese Seite darf den Helfer nicht benutzen." });
    let body;
    try { body = await request.json(); } catch { return reply(400, { error: "Die Anfrage war leer." }); }

    if (body.mode === "room-empty" || body.mode === "room-style") {
      if (!env.GEMINI_API_KEY) return reply(500, { error: "Der Gemini-Schlüssel fehlt in Cloudflare (GEMINI_API_KEY)." });
      const m = String(body.image || "").match(/^data:(image\/(?:jpeg|png|webp));base64,([A-Za-z0-9+/=]+)$/);
      if (!m || m[2].length > 6_000_000) return reply(400, { error: "Das Foto ist zu groß oder kein Bild." });
      let prompt;
      if (body.mode === "room-empty") prompt = EMPTY_PROMPT;
      else {
        const style = STYLES[body.style];
        if (!style) return reply(400, { error: "Diesen Einrichtungsstil kenne ich nicht." });
        const room = ROOMS[body.room] || "room";
        const wish = String(body.wish || "").replace(/\s+/g, " ").trim().slice(0, 300);
        prompt = `Furnish this ${room} in ${style} interior design style.` +
          (wish ? ` The owner's wishes (may be in German): "${wish}".` : "") +
          ` Keep the room's architecture exactly as in the photo: walls, windows, doors, floor, ceiling, radiators, built-in fixtures, camera angle, perspective and daylight.` +
          ` Furniture must have realistic scale and fit the space. Photorealistic interior photograph, no text, no people.`;
      }
      try { return reply(200, await geminiImage(env, prompt, m[1], m[2])); }
      catch (e) { return reply(502, { error: e.message || "Google hat nicht geantwortet." }); }
    }

    if (String(body.mode || "").startsWith("push-")) {
      try { return reply(200, await pushApi(env, body)); }
      catch (e) { return reply(e.status || 502, { error: e.message || "Mitteilungen haben nicht geklappt." }); }
    }

    if (String(body.mode || "").startsWith("fin-")) {
      try { return reply(200, await finance(env, body, request)); }
      catch (e) { return reply(e.status || 502, { error: e.message || "Die Bankverbindung hat nicht geklappt." }); }
    }

    if (!env.ANTHROPIC_API_KEY) return reply(500, { error: "Der API-Schlüssel fehlt in Cloudflare." });

    if (body.mode === "nutrition") {
      const items = Array.isArray(body.items) ? body.items.map(String).filter(Boolean).slice(0, 60) : [];
      if (!items.length) return reply(400, { error: "Keine Zutaten übergeben." });
      try { return reply(200, { items: await estimateNutrition(env.ANTHROPIC_API_KEY, items) }); }
      catch (e) { return reply(502, { error: e.message || "Claude hat nicht geantwortet." }); }
    }
    if (body.mode === "price") {
      const items = Array.isArray(body.items) ? body.items.map(x => String(x).slice(0, 120)).filter(Boolean).slice(0, 60) : [];
      if (!items.length) return reply(400, { error: "Keine Zutaten übergeben." });
      try { return reply(200, await estimatePrice(env.ANTHROPIC_API_KEY, items)); }
      catch (e) { return reply(502, { error: e.message || "Claude hat nicht geantwortet." }); }
    }
    if (body.mode === "stores") {
      const stores = Array.isArray(body.stores) ? body.stores.map(x => String(x).slice(0, 60)).filter(Boolean).slice(0, 10) : [];
      const items = Array.isArray(body.items) ? body.items.map(x => String(x).slice(0, 120)).filter(Boolean).slice(0, 60) : [];
      if (!stores.length || !items.length) return reply(400, { error: "Keine Läden oder Zutaten übergeben." });
      try { return reply(200, { stores: await checkStores(env.ANTHROPIC_API_KEY, stores, items) }); }
      catch (e) { return reply(502, { error: e.message || "Claude hat nicht geantwortet." }); }
    }
    if (body.mode === "label") {
      const m = String(body.image || "").match(/^data:(image\/(?:jpeg|png|webp));base64,([A-Za-z0-9+/=]+)$/);
      if (!m || m[2].length > 4_000_000) return reply(400, { error: "Das Foto ist zu groß oder kein Bild." });
      try { return reply(200, await readLabel(env.ANTHROPIC_API_KEY, m[1], m[2], String(body.name || ""))); }
      catch (e) { return reply(502, { error: e.message || "Claude hat nicht geantwortet." }); }
    }

    if (body.mode === "photo") {
      const imgs = (Array.isArray(body.images) ? body.images : []).slice(0, 4).map(x => String(x || "").match(/^data:(image\/(?:jpeg|png|webp));base64,([A-Za-z0-9+/=]+)$/));
      if (!imgs.length || imgs.some(m => !m || m[2].length > 4_000_000)) return reply(400, { error: "Ein Foto ist zu groß oder kein Bild." });
      try { return reply(200, await readRecipePhotos(env.ANTHROPIC_API_KEY, imgs.map(m => ({ type: m[1], data: m[2] })))); }
      catch (e) { return reply(502, { error: e.message || "Claude hat nicht geantwortet." }); }
    }

    let link;
    try { link = new URL(body.url); }
    catch { return reply(400, { error: "Das ist kein gültiger Link." }); }

    let video;
    try { video = await loadVideo(link); }
    catch (e) { return reply(422, { error: e.message || "Das Video konnte nicht gelesen werden." }); }

    let recipe;
    try { recipe = await askClaude(env.ANTHROPIC_API_KEY, video); }
    catch (e) { return reply(502, { error: e.message || "Claude hat nicht geantwortet." }); }

    const cover = video.thumbnail ? await toDataUrl(video.thumbnail).catch(() => null) : null;
    return reply(200, { ...recipe, cover, source: video.url });
  },
};

/* ---------- Video-Infos holen ---------- */
async function loadVideo(link) {
  const host = link.hostname.replace(/^www\.|^m\./, "");
  if (host.endsWith("tiktok.com")) return loadTikTok(link);
  if (host === "youtube.com" || host === "youtu.be" || host.endsWith(".youtube.com")) return loadYouTube(link);
  if (host === "instagram.com" || host.endsWith(".instagram.com") || host === "instagr.am") return loadInstagram(link);
  throw new Error("Bitte einen TikTok-, Instagram- oder YouTube-Link einfügen.");
}

// TikTok antwortet ohne Browser-Kennung oft leer
const BROWSER = {
  "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36",
  "Accept-Language": "de-DE,de;q=0.9,en;q=0.8",
};

async function loadTikTok(link) {
  // Kurzlinks (vm.tiktok.com) erst auflösen, Zusätze wie ?q=…&t=… entfernen
  let page = link;
  if (/^(vm|vt)\./.test(link.hostname)) {
    const r = await fetch(link.href, { redirect: "follow", headers: BROWSER });
    page = new URL(r.url);
  }
  const url = "https://www.tiktok.com" + page.pathname.replace(/\/$/, "");
  if (!/\/video\/\d+/.test(url)) throw new Error("Das ist kein Link zu einem TikTok-Video.");

  let description = "", author = "", thumbnail = null;
  try {
    const r = await fetch("https://www.tiktok.com/oembed?url=" + encodeURIComponent(url), { headers: BROWSER });
    if (r.ok) {
      const o = await r.json();
      description = o.title || "";
      author = o.author_name || "";
      thumbnail = o.thumbnail_url || null;
    }
  } catch {}

  // Zweiter Versuch: Beschreibung und Bild direkt aus der Videoseite lesen
  if (!description || !thumbnail) {
    try {
      const html = await fetch(url, { headers: BROWSER }).then(r => r.text());
      const desc = html.match(/"desc":"((?:[^"\\]|\\.)*)"/);
      if (!description && desc) description = JSON.parse('"' + desc[1] + '"');
      const og = html.match(/<meta[^>]+property="og:image"[^>]+content="([^"]+)"/);
      const cover = html.match(/"(?:originCover|cover)":"((?:[^"\\]|\\.)*)"/);
      if (!thumbnail && og) thumbnail = og[1].replace(/&amp;/g, "&");
      if (!thumbnail && cover) thumbnail = JSON.parse('"' + cover[1] + '"');
    } catch {}
  }

  if (!description) {
    throw new Error("TikTok hat die Beschreibung nicht herausgegeben. Versuch es in ein paar Minuten noch einmal.");
  }
  return { url, title: "", description, author, thumbnail };
}

async function loadInstagram(link) {
  const m = link.pathname.match(/\/(?:p|reel|reels|tv)\/([A-Za-z0-9_-]{5,})/);
  if (!m) throw new Error("Das ist kein Link zu einem Instagram-Beitrag oder Reel.");
  const code = m[1], url = `https://www.instagram.com/p/${code}/`;
  const clean = t => t.replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]+>/g, "").replace(/&amp;/g, "&").replace(/&quot;/g, '"')
    .replace(/&#39;|&#x27;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(+n)).trim();
  let description = "", author = "", thumbnail = null;
  // Weg 1: die Einbettungsseite mit Beschreibung
  try {
    const html = await fetch(`https://www.instagram.com/p/${code}/embed/captioned/`, { headers: BROWSER }).then(r => r.text());
    const cap = html.match(/<div class="Caption">([\s\S]*?)<div class="CaptionComments">/);
    if (cap) {
      const user = cap[1].match(/class="CaptionUsername"[^>]*>([^<]+)</);
      if (user) author = clean(user[1]);
      description = clean(cap[1].replace(/<a class="CaptionUsername"[\s\S]*?<\/a>/, ""));
    }
    const img = html.match(/class="EmbeddedMediaImage"[^>]*src="([^"]+)"/) || html.match(/<img[^>]+src="(https:\/\/[^"]*(?:cdninstagram|fbcdn)[^"]+)"/);
    if (img) thumbnail = img[1].replace(/&amp;/g, "&");
  } catch {}
  // Weg 2: Vorschau-Angaben der normalen Seite
  if (!description || !thumbnail) {
    try {
      const html = await fetch(url, { headers: BROWSER }).then(r => r.text());
      const og = n => (html.match(new RegExp(`<meta[^>]+property="og:${n}"[^>]+content="([^"]*)"`)) || [])[1];
      if (!description && og("description")) description = clean(og("description")).replace(/^[\d.,KkMm]+ likes?, [\d.,KkMm]+ comments? - [^:]+:\s*/i, "");
      if (!thumbnail && og("image")) thumbnail = og("image").replace(/&amp;/g, "&");
    } catch {}
  }
  if (!description) throw new Error("Instagram hat die Beschreibung nicht herausgegeben. Ist der Beitrag öffentlich? Sonst versuch es später noch einmal.");
  return { url, title: "", description, author, thumbnail };
}

async function loadYouTube(link) {
  const id = link.hostname.endsWith("youtu.be")
    ? link.pathname.slice(1)
    : (link.searchParams.get("v") || (link.pathname.match(/\/(shorts|embed|live)\/([\w-]{6,})/) || [])[2]);
  if (!id) throw new Error("In dem YouTube-Link steckt keine Video-ID.");
  const url = "https://www.youtube.com/watch?v=" + id;
  const o = await fetch("https://www.youtube.com/oembed?format=json&url=" + encodeURIComponent(url))
    .then(r => (r.ok ? r.json() : {}));
  // Die Beschreibung steht nur auf der Videoseite selbst
  let description = "";
  try {
    const html = await fetch(url, { headers: { "Accept-Language": "de-DE,de;q=0.9,en;q=0.8" } }).then(r => r.text());
    const m = html.match(/"shortDescription":"((?:[^"\\]|\\.)*)"/);
    if (m) description = JSON.parse('"' + m[1] + '"');
  } catch {}
  if (!o.title && !description) throw new Error("YouTube hat das Video nicht herausgegeben. Ist es öffentlich?");
  return { url, title: o.title || "", description, author: o.author_name || "",
           thumbnail: `https://i.ytimg.com/vi/${id}/hqdefault.jpg` };
}

/* ---------- Claude fragen ---------- */
async function askClaude(key, video) {
  const text = [
    video.title && "Titel: " + video.title,
    video.author && "Von: " + video.author,
    "Beschreibung:\n" + (video.description || "(keine)"),
  ].filter(Boolean).join("\n\n").slice(0, 20000);

  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": key,
      "anthropic-version": "2026-10-21",
      "anthropic-beta": "server-side-fallback-2026-07-01",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 8000,
      fallbacks: "default",
      output_config: { effort: "low", format: { type: "json_schema", schema: RECIPE_SCHEMA } },
      system: SYSTEM,
      messages: [{ role: "user", content: text }],
    }),
  });
  const data = await r.json();
  if (!r.ok) {
    const msg = data?.error?.message || "";
    if (r.status === 401) throw new Error("Der API-Schlüssel stimmt nicht.");
    if (/credit|balance/i.test(msg)) throw new Error("Dein Claude-Guthaben ist aufgebraucht.");
    throw new Error("Claude-Fehler: " + (msg || r.status));
  }
  if (data.stop_reason === "refusal") throw new Error("Claude wollte zu diesem Video kein Rezept schreiben.");
  const block = (data.content || []).find(b => b.type === "text");
  if (!block) throw new Error("Claude hat kein Rezept zurückgegeben.");
  const out = JSON.parse(block.text);
  return {
    title: String(out.title || video.title || "Neues Rezept").slice(0, 120),
    ingredients: (out.ingredients || []).map(String).filter(Boolean).slice(0, 80),
    steps: (out.steps || []).map(String).filter(Boolean).slice(0, 60),
    category: ["Frühstück", "Hauptgericht", "Vorspeise", "Süßes", "Backen", "Snack"].includes(out.category) ? out.category : null,
    servings: Number.isInteger(out.servings) && out.servings >= 1 && out.servings <= 50 ? out.servings : null,
  };
}

/* ---------- Nährwerte ---------- */
async function callClaude(key, system, content, schema) {
  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-api-key": key, "anthropic-version": "2026-10-21", "anthropic-beta": "server-side-fallback-2026-07-01" },
    body: JSON.stringify({ model: MODEL, max_tokens: 8000, fallbacks: "default",
      output_config: { effort: "low", format: { type: "json_schema", schema } }, system, messages: [{ role: "user", content }] }),
  });
  const data = await r.json();
  if (!r.ok) {
    const msg = data?.error?.message || "";
    if (r.status === 401) throw new Error("Der API-Schlüssel stimmt nicht.");
    if (/credit|balance/i.test(msg)) throw new Error("Dein Claude-Guthaben ist aufgebraucht.");
    throw new Error("Claude-Fehler: " + (msg || r.status));
  }
  if (data.stop_reason === "refusal") throw new Error("Claude wollte das nicht beantworten.");
  const block = (data.content || []).find(b => b.type === "text");
  if (!block) throw new Error("Claude hat nichts zurückgegeben.");
  return JSON.parse(block.text);
}
const NUM = { type: "number" };
async function estimateNutrition(key, items) {
  const schema = { type: "object", additionalProperties: false, required: ["items"], properties: { items: { type: "array",
    items: { type: "object", additionalProperties: false, required: ["grams", "kcal", "protein", "carbs", "fat", "sugar", "fiber", "salt", "satfat"],
      properties: { grams: NUM, kcal: NUM, protein: NUM, carbs: NUM, fat: NUM, sugar: NUM, fiber: NUM, salt: NUM, satfat: NUM } } } } };
  const system = `Du schätzt Nährwerte für Zutaten aus Rezepten.
Für jede Zeile in derselben Reihenfolge:
- grams: Gewicht der angegebenen Menge in Gramm (Flüssigkeiten: ml ≈ g). "1 Dose Kokosmilch" ≈ 400, "1 EL Öl" ≈ 10, "1 TL" ≈ 5, "1 Prise" ≈ 1, "etwas" ≈ 5. Ohne Mengenangabe eine übliche Menge für ein Rezept mit 2 bis 4 Portionen.
- kcal, protein, carbs, fat: typische Werte pro 100 g, so wie die Zutat ins Rezept kommt (trocken/roh, wenn nicht anders angegeben).
- sugar (Zucker, Teil der Kohlenhydrate), fiber (Ballaststoffe), salt (Salz), satfat (gesättigte Fettsäuren): ebenfalls pro 100 g.
Gib genau so viele Einträge zurück wie Zeilen. Nur Zahlen, keine Erklärungen.`;
  const out = await callClaude(key, system, items.map((t, i) => `${i + 1}. ${t}`).join("\n"), schema);
  const list = Array.isArray(out.items) ? out.items : [];
  return items.map((_, i) => { const x = list[i] || {}; const n = v => Math.max(0, Math.round((+v || 0) * 10) / 10);
    return { grams: n(x.grams), kcal: n(x.kcal), protein: n(x.protein), carbs: n(x.carbs), fat: n(x.fat), sugar: n(x.sugar), fiber: n(x.fiber), salt: n(x.salt), satfat: n(x.satfat) }; });
}
async function readLabel(key, mediaType, data, name) {
  const schema = { type: "object", additionalProperties: false, required: ["found", "kcal", "protein", "carbs", "fat", "sugar", "salt", "fiber", "satfat"],
    properties: { found: { type: "boolean" }, kcal: NUM, protein: NUM, carbs: NUM, fat: NUM, sugar: NUM, salt: NUM, fiber: NUM, satfat: NUM } };
  const system = `Du liest Nährwerttabellen von Lebensmittelverpackungen ab.
Gib die Werte pro 100 g bzw. 100 ml zurück. Steht nur ein Wert pro Portion da und die Portionsgröße ist angegeben, rechne auf 100 g um.
Wenn steht kJ und kcal, nimm kcal. Ist keine Nährwerttabelle zu erkennen, setz found auf false und alle Zahlen auf 0.`;
  const out = await callClaude(key, system, [
    { type: "image", source: { type: "base64", media_type: mediaType, data } },
    { type: "text", text: name ? `Das Produkt ist für die Zutat: ${name}` : "Lies die Nährwerte ab." },
  ], schema);
  const n = v => Math.max(0, Math.round((+v || 0) * 10) / 10);
  return { found: !!out.found, kcal: n(out.kcal), protein: n(out.protein), carbs: n(out.carbs), fat: n(out.fat), sugar: n(out.sugar), salt: n(out.salt), fiber: n(out.fiber), satfat: n(out.satfat) };
}

/* ---------- Preis: Discounterpreise aus dem Netz, auf die Menge umgerechnet ---------- */
async function estimatePrice(key, items) {
  const system = `Du ermittelst, was die Zutaten eines Rezepts beim Discounter in Deutschland ungefähr kosten.
Nutze die Websuche, um aktuelle Preise bei Aldi oder Lidl zu finden (z.B. aldi-sued.de, aldi-nord.de, lidl.de oder Preisvergleiche). Such gezielt nur nach Zutaten, deren Preis du nicht sicher kennst, höchstens ein paar Suchen.
Rechne den Packungspreis auf die Menge im Rezept herunter (anteilig, nicht die ganze Packung). Ohne Mengenangabe nimm eine übliche Menge für 2 bis 4 Portionen.
Gewürze, Salz, Öl in kleinen Mengen kosten nur wenige Cent.
Antworte am Ende ausschließlich mit JSON in <json></json>-Tags, ohne weiteren Text danach:
<json>{"items":[{"eur":0.45,"pack":"Tofu 400 g für 1,79 €"}],"sources":[{"title":"...","url":"https://..."}]}</json>
items in genau der Reihenfolge und Anzahl der Zutaten. eur = Kosten der Rezeptmenge in Euro. pack = kurz, worauf der Preis beruht (höchstens 8 Wörter).
sources: höchstens 4 Seiten, die du wirklich benutzt hast.`;
  const messages = [{ role: "user", content: "Zutaten:\n" + items.map((x, i) => `${i + 1}. ${x}`).join("\n") }];
  let data;
  for (let round = 0; round < 4; round++) {
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-api-key": key, "anthropic-version": "2026-10-21", "anthropic-beta": "server-side-fallback-2026-07-01" },
      body: JSON.stringify({ model: MODEL, max_tokens: 16000, fallbacks: "default", output_config: { effort: "low" }, system, messages,
        tools: [{ type: "web_search_20260209", name: "web_search", max_uses: 6, user_location: { type: "approximate", country: "DE" } }] }),
    });
    data = await r.json();
    if (!r.ok) {
      const msg = data?.error?.message || "";
      if (r.status === 401) throw new Error("Der API-Schlüssel stimmt nicht.");
      if (/credit|balance/i.test(msg)) throw new Error("Dein Claude-Guthaben ist aufgebraucht.");
      if (/web.?search/i.test(msg)) throw new Error("Die Websuche ist in deinem Claude-Konto nicht freigeschaltet (Console → Settings → Privacy).");
      throw new Error("Claude-Fehler: " + (msg || r.status));
    }
    if (data.stop_reason !== "pause_turn") break;
    messages.push({ role: "assistant", content: data.content });   // lange Suche: weitermachen lassen
  }
  if (data.stop_reason === "refusal") throw new Error("Claude wollte das nicht beantworten.");
  const text = (data.content || []).filter(b => b.type === "text").map(b => b.text).join("");
  const m = text.match(/<json>([\s\S]*?)<\/json>/) || text.match(/(\{[\s\S]*\})/);
  let out; try { out = JSON.parse(m[1]); } catch { throw new Error("Claude hat keine Preise zurückgegeben."); }
  const list = Array.isArray(out.items) ? out.items : [];
  const res = items.map((_, i) => { const x = list[i] || {}; return { eur: Math.max(0, Math.round((+x.eur || 0) * 100) / 100), pack: String(x.pack || "").slice(0, 80) }; });
  const sources = (Array.isArray(out.sources) ? out.sources : []).filter(x => x && /^https:\/\//.test(x.url || "")).slice(0, 4).map(x => ({ title: String(x.title || x.url).slice(0, 80), url: String(x.url).slice(0, 300) }));
  return { items: res, total: Math.round(res.reduce((a, x) => a + x.eur, 0) * 100) / 100, sources };
}

/* ---------- Supermärkte: was gibt es wo? ---------- */
async function checkStores(key, stores, items) {
  const schema = { type: "object", additionalProperties: false, required: ["stores"], properties: { stores: { type: "array", items: {
    type: "object", additionalProperties: false, required: ["items"], properties: { items: { type: "array", items: {
      type: "object", additionalProperties: false, required: ["s", "hint"],
      properties: { s: { type: "string", enum: ["ja", "vielleicht", "nein"] }, hint: { type: "string" } } } } } } } } };
  const system = `Du kennst das übliche Sortiment von Supermärkten, Discountern, Bioläden und Drogerien in Deutschland, Österreich und der Schweiz.
Du bekommst eine Liste von Läden (Kette oder Name aus OpenStreetMap) und eine Liste von Zutaten aus einem Rezept.
Schätze für jeden Laden und jede Zutat, ob man sie dort normalerweise kaufen kann:
- "ja": gehört zum Standardsortiment dieser Art von Laden.
- "vielleicht": nur in größeren Filialen, saisonal, als Aktionsware oder in einer ähnlichen Variante.
- "nein": gibt es dort normalerweise nicht.
Mengenangaben ignorierst du. Kennst du einen Laden nicht, schätz anhand des Namens, was für ein Laden es ist.
hint: höchstens 6 Wörter, nur wenn hilfreich, z.B. "im Kühlregal", "als Eigenmarke", "eher im Asia-Laden". Sonst leer.
Gib die Läden und Zutaten in genau der Reihenfolge und Anzahl zurück, in der du sie bekommst.`;
  const text = "Läden:\n" + stores.map((x, i) => `${i + 1}. ${x}`).join("\n") + "\n\nZutaten:\n" + items.map((x, i) => `${i + 1}. ${x}`).join("\n");
  const out = await callClaude(key, system, text, schema);
  const list = Array.isArray(out.stores) ? out.stores : [];
  return stores.map((_, si) => { const it = (list[si] && Array.isArray(list[si].items)) ? list[si].items : [];
    return { items: items.map((_, ii) => { const x = it[ii] || {}; return { s: ["ja", "vielleicht", "nein"].includes(x.s) ? x.s : "vielleicht", hint: String(x.hint || "").slice(0, 60) }; }) }; });
}

/* ---------- Rezept von Fotos ---------- */
async function readRecipePhotos(key, images) {
  const schema = { ...RECIPE_SCHEMA,
    properties: { ...RECIPE_SCHEMA.properties, found: { type: "boolean" }, dishImage: { type: "integer" } },
    required: [...RECIPE_SCHEMA.required, "found", "dishImage"] };
  const system = `Du bekommst ein oder mehrere Fotos eines Rezepts: zum Beispiel einen Screenshot der Beschreibung eines Koch-Videos, eine Seite aus einem Kochbuch oder einen handgeschriebenen Zettel.
Gehören mehrere Fotos zusammen (z.B. zwei Buchseiten), mach daraus ein einziges Rezept.
Lies den Text sorgfältig ab, auch Handschrift. Mach daraus ein Rezept auf Deutsch.
- title: kurzer, appetitlicher Rezeptname ohne Hashtags und Emojis. Steht keiner da, nenn das Gericht passend.
- ingredients: eine Zutat pro Eintrag, Menge zuerst, z.B. "200 g Mehl". Übersetze ins Deutsche, rechne Cups und Unzen grob in g/ml um. Alte Angaben wie "1 Pfund" darfst du in g umrechnen.
- steps: kurze, klare Arbeitsschritte in der richtigen Reihenfolge, ohne Nummerierung.
- category: "Frühstück" für typisches Frühstück (Porridge, Müsli, Overnight Oats, Pancakes, Rührei, Frühstücksbowls, Smoothies), "Hauptgericht" für sättigende Mahlzeiten, "Vorspeise" für Suppen, Salate und kleine Teller vorab, "Süßes" für Desserts ohne Ofen und süßes Frühstück, "Backen" für alles, was gebacken wird, "Snack" für Kleinigkeiten, Dips und Fingerfood.
- servings: für wie viele Portionen die Mengen gedacht sind. Steht es da, nimm das, sonst schätze es anhand der Mengen (meist 2 bis 4; Kuchen: übliche Stückzahl).
- found: false, wenn auf den Fotos kein Rezept zu erkennen ist.
- dishImage: Nummer des Fotos (ab 0), das das fertige Gericht schön zeigt und als Titelbild taugt. -1, wenn keins das Gericht zeigt (z.B. nur Text oder Screenshot).
Erfinde keine Zutaten oder Schritte, die nicht auf den Fotos stehen oder sich nicht eindeutig daraus ergeben. Unleserliches lässt du weg.`;
  const content = images.flatMap((im, i) => [
    { type: "text", text: `Foto ${i}:` },
    { type: "image", source: { type: "base64", media_type: im.type, data: im.data } },
  ]);
  content.push({ type: "text", text: "Schreib das Rezept von diesen Fotos ab." });
  const out = await callClaude(key, system, content, schema);
  const di = Number.isInteger(out.dishImage) && out.dishImage >= 0 && out.dishImage < images.length ? out.dishImage : -1;
  return {
    found: !!out.found,
    title: String(out.title || "Neues Rezept").slice(0, 120),
    ingredients: (out.ingredients || []).map(String).filter(Boolean).slice(0, 80),
    steps: (out.steps || []).map(String).filter(Boolean).slice(0, 60),
    category: ["Frühstück", "Hauptgericht", "Vorspeise", "Süßes", "Backen", "Snack"].includes(out.category) ? out.category : null,
    servings: Number.isInteger(out.servings) && out.servings >= 1 && out.servings <= 50 ? out.servings : null,
    dishImage: di,
  };
}

/* ---------- Raumdesign mit Google Gemini ---------- */
const EMPTY_PROMPT = "Edit this photo of a room: remove ALL furniture, decorations, rugs, curtains, lamps that stand or hang, plants, pictures, " +
  "objects, clutter and people, so that the room is completely empty. Keep the architecture exactly the same: walls, floor, ceiling, windows, " +
  "window frames, doors, radiators, sockets, built-in fixtures, camera angle, perspective and lighting. Fill the removed areas realistically " +
  "with the matching floor and wall surfaces. Photorealistic, same resolution and framing.";
const STYLES = {
  skandi: "Scandinavian (light oak wood, white and soft neutral tones, cosy wool and linen textiles, simple functional furniture, a few green plants)",
  modern: "modern contemporary (clean lines, neutral palette with one bold accent colour, sleek low furniture, glass and matte metal)",
  minimal: "minimalist (very few essential pieces, completely uncluttered, calm monochrome palette, hidden storage)",
  industrial: "industrial loft (black steel, cognac leather, reclaimed wood, concrete look, exposed bulbs and metal lamps)",
  boho: "bohemian (layered patterned rugs and textiles, rattan and wicker, macrame, many plants, warm earthy colours)",
  landhaus: "country house (rustic wood, cream and sage green tones, checked and floral fabrics, cosy traditional furniture)",
  midcentury: "mid-century modern (walnut wood, tapered legs, organic shapes, mustard, teal and burnt orange accents)",
  japandi: "Japandi (Japanese-Scandinavian blend, low natural wood furniture, linen, paper lamps, muted earthy tones, very calm)",
  klassisch: "classic elegant (wall mouldings, symmetry, tufted upholstered furniture, chandelier, rich fabrics, marble)",
  artdeco: "Art Deco (geometric patterns, velvet, brass and gold accents, curved furniture, emerald and navy jewel tones)",
  mediterran: "Mediterranean (terracotta, whitewashed plaster look, olive wood, linen, blue accents, wrought iron, natural textures)",
};
const ROOMS = { wohnen: "living room", schlafen: "bedroom", kueche: "kitchen", essen: "dining room", bad: "bathroom",
  arbeiten: "home office", kind: "children's room", flur: "hallway", balkon: "balcony" };
async function geminiImage(env, prompt, mime, data) {
  const models = [env.GEMINI_MODEL, "gemini-nano-banana-2.1", "gemini-3.1-flash-image-preview", "gemini-2.5-flash-image"].filter(Boolean);
  let last = "Google hat kein Bild zurückgegeben.";
  for (const model of [...new Set(models)]) {
    const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }, { inline_data: { mime_type: mime, data } }] }],
        generationConfig: { responseModalities: ["IMAGE"] },
      }),
    });
    const out = await r.json().catch(() => ({}));
    if (r.status === 404) { last = "Das Bildmodell von Google wurde nicht gefunden."; continue; }   // nächstes Modell probieren
    if (!r.ok) {
      const msg = out?.error?.message || "";
      if (r.status === 400 && /api key/i.test(msg)) throw new Error("Der Gemini-Schlüssel stimmt nicht.");
      if (r.status === 403) throw new Error("Der Gemini-Schlüssel darf dieses Modell nicht benutzen.");
      if (r.status === 429) throw new Error("Das Kontingent bei Google ist gerade aufgebraucht. Versuch es später nochmal.");
      throw new Error("Google-Fehler: " + (msg || r.status));
    }
    const cand = (out.candidates || [])[0] || {};
    const part = (cand.content?.parts || []).find(p => p.inlineData || p.inline_data);
    const img = part && (part.inlineData || part.inline_data);
    if (img && img.data) return { image: `data:${img.mimeType || img.mime_type || "image/png"};base64,${img.data}` };
    if (/SAFETY|PROHIBITED/.test(cand.finishReason || "") || out.promptFeedback?.blockReason)
      throw new Error("Google hat das Bild abgelehnt. Probier ein anderes Foto, am besten ohne Personen.");
    throw new Error(last);
  }
  throw new Error(last);
}

/* ---------- Vorschaubild als Daten-URL mitschicken ---------- */
async function toDataUrl(src) {
  const ref = /cdninstagram|fbcdn/.test(src) ? "https://www.instagram.com/" : "https://www.tiktok.com/";
  const r = await fetch(src, { headers: { ...BROWSER, Referer: ref } });
  if (!r.ok) return null;
  const type = (r.headers.get("Content-Type") || "image/jpeg").split(";")[0];
  if (!type.startsWith("image/")) return null;
  const bytes = new Uint8Array(await r.arrayBuffer());
  if (bytes.length > 1_500_000) return null;
  let bin = "";
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return `data:${type};base64,${btoa(bin)}`;
}

/* ===================== Finanzen: Enable Banking (PSD2, nur Lesezugriff) ===================== */
const FIREBASE_PROJECT = "oursapp-ff4cf";
const EB_API = "https://api.enablebanking.com";
const fail = (status, message) => Object.assign(new Error(message), { status });
const b64u = buf => btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const b64uText = t => b64u(new TextEncoder().encode(t));
const fromB64u = s => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4)), c => c.charCodeAt(0));

// Firebase-Login prüfen: Signatur mit den öffentlichen Google-Schlüsseln, Projekt, Ablauf
let jwkCache = { at: 0, keys: [] };
async function verifyFirebase(token) {
  const parts = String(token || "").split(".");
  if (parts.length !== 3) throw fail(401, "Bitte melde dich neu an.");
  const head = JSON.parse(new TextDecoder().decode(fromB64u(parts[0])));
  const pay = JSON.parse(new TextDecoder().decode(fromB64u(parts[1])));
  const now = Math.floor(Date.now() / 1000);
  if (head.alg !== "RS256" || pay.aud !== FIREBASE_PROJECT || pay.iss !== "https://securetoken.google.com/" + FIREBASE_PROJECT || !pay.sub || pay.exp < now - 30 || pay.iat > now + 300)
    throw fail(401, "Deine Anmeldung ist abgelaufen. Lade die Seite neu.");
  if (Date.now() - jwkCache.at > 3600e3 || !jwkCache.keys.some(k => k.kid === head.kid)) {
    const r = await fetch("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com");
    jwkCache = { at: Date.now(), keys: (await r.json()).keys || [] };
  }
  const jwk = jwkCache.keys.find(k => k.kid === head.kid);
  if (!jwk) throw fail(401, "Bitte melde dich neu an.");
  const key = await crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
  const ok = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, fromB64u(parts[2]), new TextEncoder().encode(parts[0] + "." + parts[1]));
  if (!ok) throw fail(401, "Bitte melde dich neu an.");
  return pay.sub;
}
// Bank-Sitzung an das eigene Konto binden: ticket = HMAC(FIN_SECRET, uid|session)
async function ticketFor(env, uid, session) {
  if (!env.FIN_SECRET || env.FIN_SECRET.length < 16) throw fail(500, "FIN_SECRET fehlt in Cloudflare (mindestens 16 Zeichen).");
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(env.FIN_SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return b64u(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(uid + "|" + session)));
}
// privater Schlüssel: PKCS#8 ("BEGIN PRIVATE KEY") oder PKCS#1 ("BEGIN RSA PRIVATE KEY")
function derLen(n) { if (n < 128) return [n]; const b = []; while (n) { b.unshift(n & 255); n >>= 8; } return [0x80 | b.length, ...b]; }
function pkcs1to8(der) {
  const alg = [0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00];
  const oct = [0x04, ...derLen(der.length), ...der], body = [0x02, 0x01, 0x00, ...alg, ...oct];
  return new Uint8Array([0x30, ...derLen(body.length), ...body]);
}
let ebKey = null;
async function ebToken(env) {
  if (!env.EB_APP_ID || !env.EB_PRIVATE_KEY) throw fail(500, "Enable Banking ist in Cloudflare noch nicht eingerichtet (EB_APP_ID, EB_PRIVATE_KEY).");
  if (!ebKey) {
    const pem = String(env.EB_PRIVATE_KEY), rsa = /BEGIN RSA PRIVATE KEY/.test(pem);
    let der = Uint8Array.from(atob(pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "")), c => c.charCodeAt(0));
    if (rsa) der = pkcs1to8(der);
    ebKey = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  }
  const now = Math.floor(Date.now() / 1000);
  const data = b64uText(JSON.stringify({ typ: "JWT", alg: "RS256", kid: env.EB_APP_ID })) + "." +
    b64uText(JSON.stringify({ iss: "enablebanking.com", aud: "api.enablebanking.com", iat: now, exp: now + 3600 }));
  return data + "." + b64u(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", ebKey, new TextEncoder().encode(data)));
}
async function eb(env, method, path, body, extra) {
  const r = await fetch(EB_API + path, { method, headers: { Authorization: "Bearer " + await ebToken(env), "Content-Type": "application/json", ...(extra || {}) }, body: body ? JSON.stringify(body) : undefined });
  const t = await r.text(); let d = null; try { d = t ? JSON.parse(t) : null; } catch {}
  if (!r.ok) {
    const msg = (d && (d.message || d.error || d.detail)) || t || r.status;
    if (r.status === 401 || r.status === 403) throw fail(502, "Enable Banking lehnt den Zugriff ab. Prüf EB_APP_ID und EB_PRIVATE_KEY. (" + String(msg).slice(0, 120) + ")");
    if (r.status === 429) throw fail(429, "Die Bank erlaubt gerade keine weiteren Abrufe. Versuch es später nochmal.");
    throw fail(502, "Bank-Fehler: " + String(typeof msg === "object" ? JSON.stringify(msg) : msg).slice(0, 200));
  }
  return d;
}
const allowedRedirect = (env, url) => {
  try { const u = new URL(url); const allowed = (env.ALLOWED_ORIGIN || "").split(",").map(s => s.trim()).filter(Boolean);
    return allowed.includes(u.origin) && /\/budget\.html$/.test(u.pathname); } catch { return false; }
};
const cents = v => Math.round(parseFloat(v) * 100);
function normTx(t) {
  const amt = cents(t.transaction_amount && t.transaction_amount.amount), out = t.credit_debit_indicator === "DBIT" ? -Math.abs(amt) : Math.abs(amt);
  const name = (out < 0 ? t.creditor && t.creditor.name : t.debtor && t.debtor.name) || (t.creditor && t.creditor.name) || (t.debtor && t.debtor.name) || "";
  const text = (Array.isArray(t.remittance_information) ? t.remittance_information.join(" ") : t.remittance_information || "") || t.note || "";
  return { id: t.entry_reference || t.transaction_id || null, date: t.booking_date || t.value_date || t.transaction_date || null, amount: out,
    cur: (t.transaction_amount && t.transaction_amount.currency) || "EUR", name: String(name).slice(0, 120), text: String(text).replace(/\s+/g, " ").slice(0, 300),
    pending: t.status === "PDNG" };
}
async function finance(env, body, request) {
  const uid = await verifyFirebase(body.token);
  const mode = body.mode;
  if (mode === "fin-banks") {
    const country = /^[A-Z]{2}$/.test(body.country || "") ? body.country : "DE";
    const d = await eb(env, "GET", "/aspsps?country=" + country + "&psu_type=personal");
    return { banks: (d.aspsps || []).map(a => ({ name: a.name, country: a.country, logo: a.logo || null, maxDays: a.maximum_consent_validity ? Math.floor(a.maximum_consent_validity / 86400) : 90 })) };
  }
  if (mode === "fin-start") {
    if (!allowedRedirect(env, body.redirect)) throw fail(400, "Diese Rücksprung-Adresse ist nicht erlaubt.");
    const name = String(body.bank && body.bank.name || "").slice(0, 120), country = /^[A-Z]{2}$/.test(body.bank && body.bank.country || "") ? body.bank.country : "DE";
    const days = Math.max(1, Math.min(180, +body.days || 90)), state = b64u(crypto.getRandomValues(new Uint8Array(16)));
    const d = await eb(env, "POST", "/auth", { access: { valid_until: new Date(Date.now() + days * 864e5).toISOString() }, aspsp: { name, country }, state, redirect_url: body.redirect, psu_type: "personal" });
    return { url: d.url, state };
  }
  if (mode === "fin-finish") {
    const code = String(body.code || ""); if (!code || code.length > 2000) throw fail(400, "Der Rücksprung von der Bank war unvollständig.");
    const d = await eb(env, "POST", "/sessions", { code });
    return { session: d.session_id, ticket: await ticketFor(env, uid, d.session_id), bank: d.aspsp && d.aspsp.name, validUntil: d.access && d.access.valid_until,
      accounts: (d.accounts || []).map(a => ({ uid: a.uid, iban: a.account_id && a.account_id.iban || null, name: a.name || a.product || a.details || "", currency: a.currency || "EUR", product: a.product || "" })) };
  }
  if (mode === "fin-sync" || mode === "fin-end") {
    const session = String(body.session || "");
    if (!session || body.ticket !== await ticketFor(env, uid, session)) throw fail(403, "Diese Bankverbindung gehört nicht zu deinem Konto.");
    if (mode === "fin-end") { await eb(env, "DELETE", "/sessions/" + encodeURIComponent(session)).catch(() => {}); return { ok: true }; }
    const s = await eb(env, "GET", "/sessions/" + encodeURIComponent(session));
    const mine = new Set(s.accounts || []), want = (Array.isArray(body.accounts) ? body.accounts : []).filter(a => mine.has(a)).slice(0, 10);
    const from = /^\d{4}-\d{2}-\d{2}$/.test(body.from || "") ? body.from : new Date(Date.now() - 90 * 864e5).toISOString().slice(0, 10);
    // Abruf mit dir als Nutzer (zählt nicht zu den 4 Hintergrund-Abrufen pro Tag)
    const psu = request ? Object.fromEntries([["Psu-Ip-Address", request.headers.get("CF-Connecting-IP")], ["Psu-User-Agent", request.headers.get("User-Agent")]].filter(x => x[1])) : {};
    const out = [];
    for (const acc of want) {
      const r = { uid: acc, balance: null, tx: [], error: null };
      try {
        const b = await eb(env, "GET", `/accounts/${encodeURIComponent(acc)}/balances`, null, psu);
        const pick = (b.balances || []).sort((x, y) => ["CLAV", "ITAV", "XPCD", "CLBD", "ITBD"].indexOf(x.balance_type) - ["CLAV", "ITAV", "XPCD", "CLBD", "ITBD"].indexOf(y.balance_type))[0];
        if (pick) r.balance = cents(pick.balance_amount.amount);
        let key = null, pages = 0;
        do {
          const q = `/accounts/${encodeURIComponent(acc)}/transactions?date_from=${from}` + (key ? "&continuation_key=" + encodeURIComponent(key) : "");
          const t = await eb(env, "GET", q, null, psu); (t.transactions || []).forEach(x => r.tx.push(normTx(x))); key = t.continuation_key; pages++;
        } while (key && pages < 20);
        // vorgemerkte Umsätze (z. B. Kartenzahlungen von heute) – nicht jede Bank liefert sie
        // manche Banken liefern Umsätze von heute nur mit eigenem Status (vorgemerkt, gehalten, sonstige)
        const recent = new Date(Date.now() - 10 * 864e5).toISOString().slice(0, 10), from2 = from > recent ? from : recent;
        for (const st of ["PDNG", "HOLD", "OTHR"]) {
          try {
            const tp = await eb(env, "GET", `/accounts/${encodeURIComponent(acc)}/transactions?date_from=${from2}&transaction_status=${st}`, null, psu);
            const have = new Set(r.tx.map(x => x.id || `${x.date}|${x.amount}|${x.name}`));
            (tp.transactions || []).forEach(x => { const n = normTx(x); if (st !== "OTHR") n.pending = true; if (!have.has(n.id || `${n.date}|${n.amount}|${n.name}`)) r.tx.push(n); });
            if (st === "PDNG") r.pend = true;
          } catch {}
        }
      } catch (e) { r.error = e.message; }
      out.push(r);
    }
    await rememberBank(env, uid, session, want, out).catch(() => {});
    return { status: s.status, validUntil: s.access && s.access.valid_until, accounts: out };
  }
  if (mode === "fin-cat") {
    if (!env.ANTHROPIC_API_KEY) throw fail(500, "Der Claude-Schlüssel fehlt in Cloudflare.");
    const cats = (Array.isArray(body.cats) ? body.cats : []).map(c => String(c).slice(0, 30)).slice(0, 40);
    const items = (Array.isArray(body.items) ? body.items : []).slice(0, 80).map(x => ({ n: String(x.name || "").slice(0, 80), o: String(x.orig || "").slice(0, 80), t: String(x.text || "").slice(0, 140), a: +x.amount || 0 }));
    if (!cats.length || !items.length) return { cats: [], sure: [] };
    const schema = { type: "object", additionalProperties: false, required: ["items"], properties: { items: { type: "array",
      items: { type: "object", additionalProperties: false, required: ["cat", "sure"], properties: { cat: { type: "string", enum: cats }, sure: { type: "boolean" } } } } } };
    const system = `Du ordnest Bankumsätze aus Deutschland Kategorien zu. Für jeden Umsatz in derselben Reihenfolge genau eine Kategorie aus der Liste und ob du dir sicher bist.
Jeder Umsatz: Händlername | Original-Empfänger | Verwendungszweck | Betrag. Negative Beträge sind Ausgaben.
Sei vorsichtig: sure = true nur, wenn der Händler eindeutig bekannt ist oder der Text klar sagt, worum es geht (z.B. Supermarkt, Tankstelle, Apotheke, Restaurant, Versicherung, Streamingdienst).
Bei Privatpersonen, unbekannten Firmen, Zahlungsdiensten ohne erkennbaren Händler oder wenn mehrere Kategorien passen könnten: cat = "Sonstiges" und sure = false.
Lieber "Sonstiges" als eine falsche Kategorie.`;
    const out = await callClaude(env.ANTHROPIC_API_KEY, system, items.map((x, i) => `${i + 1}. ${x.n} | ${x.o} | ${x.t} | ${(x.a / 100).toFixed(2)} €`).join("\n"), schema);
    const list = Array.isArray(out.items) ? out.items : [];
    return { cats: items.map((_, i) => (list[i] && list[i].cat) || "Sonstiges"), sure: items.map((_, i) => !!(list[i] && list[i].sure)) };
  }
  throw fail(400, "Unbekannte Anfrage.");
}

/* ---------- Mitteilungen (Web Push, RFC 8291 + VAPID RFC 8292) ---------- */
const DB_URL = "https://oursapp-ff4cf-default-rtdb.europe-west1.firebasedatabase.app";
const cat = (...a) => { const n = a.reduce((x, y) => x + y.length, 0), o = new Uint8Array(n); let i = 0; for (const x of a) { o.set(x, i); i += x.length; } return o; };
const te = t => new TextEncoder().encode(t);
async function hmac(key, data) { const k = await crypto.subtle.importKey("raw", key, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]); return new Uint8Array(await crypto.subtle.sign("HMAC", k, data)); }
function needKV(env) { if (!env.PUSH) throw fail(500, "Für Mitteilungen fehlt in Cloudflare der KV-Speicher mit der Bindung PUSH."); return env.PUSH; }
async function vapid(env) {
  const kv = needKV(env); let v = await kv.get("vapid", "json");
  if (!v) {
    const kp = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
    const jwk = await crypto.subtle.exportKey("jwk", kp.privateKey), raw = new Uint8Array(await crypto.subtle.exportKey("raw", kp.publicKey));
    v = { pub: b64u(raw), jwk }; await kv.put("vapid", JSON.stringify(v));
  }
  return v;
}
async function vapidAuth(env, endpoint) {
  const v = await vapid(env), aud = new URL(endpoint).origin, now = Math.floor(Date.now() / 1000);
  const data = b64uText(JSON.stringify({ typ: "JWT", alg: "ES256" })) + "." + b64uText(JSON.stringify({ aud, exp: now + 12 * 3600, sub: env.PUSH_CONTACT || "https://nkllasbus.github.io/OursApp/" }));
  const key = await crypto.subtle.importKey("jwk", { ...v.jwk, key_ops: ["sign"] }, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, te(data));
  return "vapid t=" + data + "." + b64u(sig) + ", k=" + v.pub;
}
async function encryptPush(sub, text) {
  const ua = fromB64u(sub.keys.p256dh), auth = fromB64u(sub.keys.auth);
  const eph = await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]);
  const as = new Uint8Array(await crypto.subtle.exportKey("raw", eph.publicKey));
  const uaKey = await crypto.subtle.importKey("raw", ua, { name: "ECDH", namedCurve: "P-256" }, false, []);
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: "ECDH", public: uaKey }, eph.privateKey, 256));
  const ikm = (await hmac(await hmac(auth, shared), cat(te("WebPush: info\0"), ua, as, new Uint8Array([1])))).slice(0, 32);
  const salt = crypto.getRandomValues(new Uint8Array(16)), prk = await hmac(salt, ikm);
  const cek = (await hmac(prk, cat(te("Content-Encoding: aes128gcm\0"), new Uint8Array([1])))).slice(0, 16);
  const nonce = (await hmac(prk, cat(te("Content-Encoding: nonce\0"), new Uint8Array([1])))).slice(0, 12);
  const k = await crypto.subtle.importKey("raw", cek, "AES-GCM", false, ["encrypt"]);
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, k, cat(te(text), new Uint8Array([2]))));
  return cat(salt, new Uint8Array([0, 0, 16, 0]), new Uint8Array([as.length]), as, ct);
}
// schickt an alle Geräte einer Person; gibt zurück, ob Geräte entfernt werden müssen
async function sendTo(env, rec, msg) {
  let gone = false, sent = 0; const info = [];
  for (const sub of rec.subs || []) {
    let host = "?"; try { host = new URL(sub.endpoint).hostname; } catch {}
    try {
      const r = await fetch(sub.endpoint, { method: "POST", headers: { Authorization: await vapidAuth(env, sub.endpoint), "Content-Encoding": "aes128gcm", "Content-Type": "application/octet-stream", TTL: "86400", Urgency: "high" }, body: await encryptPush(sub, JSON.stringify(msg)) });
      const text = r.ok ? "" : (await r.text().catch(() => "")).slice(0, 160);
      info.push({ host, status: r.status, text });
      if (r.status === 404 || r.status === 410) { sub.gone = true; gone = true; } else if (r.ok) sent++;
    } catch (e) { info.push({ host, status: 0, text: String(e && e.message || e).slice(0, 160) }); }
  }
  if (gone) rec.subs = rec.subs.filter(x => !x.gone);
  return { gone, sent, info };
}
const okSub = s => s && typeof s.endpoint === "string" && /^https:\/\//.test(s.endpoint) && s.endpoint.length < 1000 && s.keys && typeof s.keys.p256dh === "string" && typeof s.keys.auth === "string";
const clip = (t, n) => String(t || "").slice(0, n);
async function pushApi(env, body) {
  const mode = body.mode;
  if (mode === "push-key") return { key: (await vapid(env)).pub, version: "push-2" };
  const uid = await verifyFirebase(body.token), kv = needKV(env), key = "u:" + uid;
  const rec = (await kv.get(key, "json")) || { subs: [], rem: {}, cats: {} };
  if (mode === "push-sub") {
    if (body.off) rec.subs = rec.subs.filter(x => x.endpoint !== (body.sub && body.sub.endpoint));
    else if (okSub(body.sub)) { rec.subs = rec.subs.filter(x => x.endpoint !== body.sub.endpoint); rec.subs.push({ endpoint: body.sub.endpoint, keys: { p256dh: body.sub.keys.p256dh, auth: body.sub.keys.auth } }); rec.subs = rec.subs.slice(-6); }
    if (body.cats && typeof body.cats === "object") rec.cats = Object.fromEntries(Object.entries(body.cats).slice(0, 20).map(([k, v]) => [clip(k, 20), !!v]));
    await kv.put(key, JSON.stringify(rec)); return { ok: true, devices: rec.subs.length };
  }
  if (mode === "push-plan") {
    const kind = clip(body.kind || "all", 20), now = Date.now();
    const list = (Array.isArray(body.items) ? body.items : []).filter(x => x && x.at > now && x.at < now + 15 * 864e5).slice(0, 80)
      .map(x => ({ at: Math.round(x.at), t: clip(x.t, 80), b: clip(x.b, 180), u: clip(x.u, 120), c: clip(x.c, 20), id: clip(x.id, 80) }));
    rec.rem = rec.rem || {}; rec.rem[kind] = list; await kv.put(key, JSON.stringify(rec)); return { ok: true, n: list.length };
  }
  if (mode === "push-test") {
    if (!rec.subs.length) throw fail(400, "Auf diesem Konto ist noch kein Gerät für Mitteilungen angemeldet.");
    const r = await sendTo(env, rec, { t: "Ours", b: "So sehen Mitteilungen aus. 👋", u: "home.html" }); if (r.gone) await kv.put(key, JSON.stringify(rec));
    return { ok: true, sent: r.sent, devices: rec.subs.length, info: r.info, version: "push-2" };
  }
  if (mode === "push-notify") {
    const sid = String(body.sid || ""); if (!/^[\w-]{4,60}$/.test(sid)) throw fail(400, "Bereich fehlt.");
    // Mitglieder mit dem Login der Person lesen, die etwas geändert hat (Firebase-Regeln prüfen die Berechtigung)
    const r = await fetch(`${DB_URL}/spaces/${sid}/access.json?auth=${encodeURIComponent(body.token)}`);
    if (!r.ok) throw fail(403, "Kein Zugriff auf diesen Bereich.");
    const ids = Object.keys((await r.json()) || {}).filter(x => x !== uid).slice(0, 20); let sent = 0;
    const msg = { t: clip(body.title, 80), b: clip(body.body, 180), u: clip(body.url, 120) };
    for (const id of ids) {
      const o = await kv.get("u:" + id, "json"); if (!o || !o.subs || !o.subs.length || (o.cats && o.cats.partner === false)) continue;
      const x = await sendTo(env, o, msg); sent += x.sent; if (x.gone) await kv.put("u:" + id, JSON.stringify(o));
    }
    return { ok: true, sent };
  }
  throw fail(400, "Unbekannte Anfrage.");
}
// Neue Umsätze melden: der Helfer merkt sich die Bankverbindung (nur wenn Mitteilungen an sind)
const txKey = t => String(t.id || `${t.date}|${t.amount}|${t.name}`).slice(0, 90);
async function rememberBank(env, uid, session, accs, out) {
  if (!env.PUSH) return; const rec = await env.PUSH.get("u:" + uid, "json"); if (!rec || !rec.subs || !rec.subs.length) return;
  const since = new Date(Date.now() - 12 * 864e5).toISOString().slice(0, 10), seen = new Set();
  out.forEach(a => (a.tx || []).forEach(t => { if (t.date && t.date >= since) seen.add(txKey(t)); }));
  rec.bank = rec.bank || {}; const old = rec.bank[session] || {};
  rec.bank[session] = { acc: accs, seen: [...new Set([...(old.seen || []), ...seen])].slice(-600), polled: old.polled || Date.now() };
  const keys = Object.keys(rec.bank); if (keys.length > 3) keys.slice(0, keys.length - 3).forEach(k => delete rec.bank[k]);
  await env.PUSH.put("u:" + uid, JSON.stringify(rec));
}
const eurFmt = c => new Intl.NumberFormat("de-DE", { style: "currency", currency: "EUR", signDisplay: "always" }).format(c / 100);
async function pollBank(env, rec) {
  let changed = false;
  for (const [session, b] of Object.entries(rec.bank || {})) {
    if (Date.now() - (b.polled || 0) < 6 * 3600e3) continue;   // höchstens 4× am Tag
    b.polled = Date.now(); changed = true;
    const from = new Date(Date.now() - 4 * 864e5).toISOString().slice(0, 10), seen = new Set(b.seen || []), fresh = [];
    try {
      for (const acc of (b.acc || []).slice(0, 5)) {
        const t = await eb(env, "GET", `/accounts/${encodeURIComponent(acc)}/transactions?date_from=${from}`);
        (t.transactions || []).map(normTx).forEach(x => { if (x.pending || !x.amount) return; const k = txKey(x); if (!seen.has(k)) { seen.add(k); fresh.push(x); } });
      }
      b.err = 0;
    } catch (e) { b.err = (b.err || 0) + 1; if (b.err >= 3 || e.status === 502 && /lehnt|abgelaufen|expired/i.test(e.message)) delete rec.bank[session]; continue; }
    b.seen = [...seen].slice(-600);
    if (!fresh.length) continue;
    const msgs = fresh.length <= 3 ? fresh.map(x => ({ t: `${x.amount < 0 ? "💳" : "💰"} ${eurFmt(x.amount)} · ${x.name || "Umsatz"}`, b: x.text || (x.amount < 0 ? "Abbuchung" : "Gutschrift"), u: "budget.html" }))
      : [{ t: `💳 ${fresh.length} neue Umsätze`, b: fresh.slice(0, 3).map(x => `${x.name || "Umsatz"} ${eurFmt(x.amount)}`).join(" · ") + " …", u: "budget.html" }];
    for (const m of msgs) await sendTo(env, rec, m);
  }
  return changed;
}
// läuft per Cron: fällige Erinnerungen verschicken, neue Umsätze melden
async function pushCron(env) {
  if (!env.PUSH) return; const kv = env.PUSH, now = Date.now(); let cursor;
  do {
    const page = await kv.list({ prefix: "u:", cursor }); cursor = page.list_complete ? null : page.cursor;
    for (const k of page.keys) {
      const rec = await kv.get(k.name, "json"); if (!rec) continue; let changed = false;
      if (rec.cats && rec.cats.tx === true && rec.bank && rec.subs && rec.subs.length) { try { if (await pollBank(env, rec)) changed = true; } catch {} }
      for (const kind of Object.keys(rec.rem || {})) {
        const due = rec.rem[kind].filter(x => x.at <= now), rest = rec.rem[kind].filter(x => x.at > now);
        if (!due.length) continue; changed = true; rec.rem[kind] = rest;
        for (const x of due) {
          if (now - x.at > 45 * 60e3) continue;   // zu alt, nicht mehr schicken
          if (rec.cats && rec.cats[x.c] === false) continue;
          if (rec.subs && rec.subs.length) await sendTo(env, rec, { t: x.t, b: x.b, u: x.u || "home.html", id: x.id });
        }
      }
      if (changed) await kv.put(k.name, JSON.stringify(rec));
    }
  } while (cursor);
}
