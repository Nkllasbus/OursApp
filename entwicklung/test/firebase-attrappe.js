/* Firebase-Attrappe für Tests mit Playwright (nicht in den Seiten verwendet).
   Ersetzt firebase-app-compat.js; die übrigen firebase-*.js-Dateien werden leer ausgeliefert.
   Angemeldet ist "Niklas" (uid u1). Startdaten: window.__SEED (vorher per addInitScript setzen). */
(function(){
  const S = { data: JSON.parse(JSON.stringify(window.__SEED || {})), subs: [] };
  const norm = p => String(p || "").replace(/^\/+|\/+$/g, "");
  const get = p => { let o = S.data; for (const k of norm(p).split("/").filter(Boolean)) { if (o == null || typeof o !== "object") return null; o = o[k]; } return o === undefined ? null : o; };
  const clean = v => { if (v && typeof v === "object") { for (const k of Object.keys(v)) { v[k] = clean(v[k]); if (v[k] == null) delete v[k]; } return Object.keys(v).length ? v : null; } return v; };
  const put = (p, v) => { const ks = norm(p).split("/").filter(Boolean); if (!ks.length) { S.data = clean(JSON.parse(JSON.stringify(v))) || {}; return; }
    let o = S.data; ks.slice(0, -1).forEach(k => { if (!o[k] || typeof o[k] !== "object") o[k] = {}; o = o[k]; });
    o[ks[ks.length - 1]] = v == null ? null : JSON.parse(JSON.stringify(v)); S.data = clean(S.data) || {}; };
  const fire = () => S.subs.forEach(s => { const v = get(s.p), j = JSON.stringify(v); if (j !== s.last) { s.last = j; s.cb(snap(s.p, v)); } });
  function snap(p, v) { const key = norm(p).split("/").pop() || null;
    return { key, ref: ref(p), val: () => v == null ? null : JSON.parse(JSON.stringify(v)), exportVal() { return this.val(); }, exists: () => v != null, toJSON: () => v,
      child: k => snap(norm(p) + "/" + k, v && typeof v === "object" ? v[k] : null), hasChild: k => !!(v && v[k] != null),
      hasChildren: () => !!(v && typeof v === "object" && Object.keys(v).length), numChildren: () => v && typeof v === "object" ? Object.keys(v).length : 0,
      forEach(fn) { if (!v || typeof v !== "object") return false; for (const k of Object.keys(v)) if (fn(snap(norm(p) + "/" + k, v[k])) === true) return true; return false; } }; }
  let n = 0;
  function ref(p) { p = norm(p); const r = {
    key: p.split("/").pop() || null, path: p, toString: () => "https://attrappe.firebaseio.com/" + p,
    child: k => ref(p + "/" + k), get parent() { return ref(p.split("/").slice(0, -1).join("/")); }, get root() { return ref(""); }, get ref() { return r; },
    on(ev, cb) { if (ev === "value") { const s = { p, cb, last: JSON.stringify(get(p)) }; S.subs.push(s); setTimeout(() => cb(snap(p, get(p))), 0); }
      else if (ev === "child_added") { const v = get(p) || {}; setTimeout(() => Object.keys(v).forEach(k => cb(snap(p + "/" + k, v[k]))), 0); } return cb; },
    off(ev, cb) { S.subs = S.subs.filter(s => !(s.p === p && (!cb || s.cb === cb))); },
    once(ev, cb) { const s = snap(p, get(p)); if (cb) setTimeout(() => cb(s), 0); return Promise.resolve(s); },
    get() { return Promise.resolve(snap(p, get(p))); },
    set(v) { put(p, v); fire(); return Promise.resolve(); },
    update(o) { for (const [k, v] of Object.entries(o || {})) put(p + "/" + k, v); fire(); return Promise.resolve(); },
    remove() { put(p, null); fire(); return Promise.resolve(); },
    push(v) { const c = ref(p + "/-t" + Date.now().toString(36) + (n++)); if (v !== undefined) c.set(v); const pr = Promise.resolve(c); c.then = pr.then.bind(pr); return c; },
    transaction(fn) { const v = fn(get(p)); if (v !== undefined) put(p, v); fire(); return Promise.resolve({ committed: true, snapshot: snap(p, get(p)) }); },
    onDisconnect: () => ({ set: () => Promise.resolve(), remove: () => Promise.resolve(), update: () => Promise.resolve(), cancel: () => Promise.resolve() }),
    isEqual: o => o && o.path === p,
  }; ["orderByChild", "orderByKey", "orderByValue", "limitToLast", "limitToFirst", "startAt", "endAt", "equalTo", "startAfter", "endBefore"].forEach(m => r[m] = () => r); return r; }
  const user = { uid: "u1", email: "niklas@example.com", displayName: "Niklas", getIdToken: () => Promise.resolve("test-token") };
  const auth = { currentUser: user, onAuthStateChanged(cb) { setTimeout(() => cb(user), 0); return () => {}; }, signOut: () => Promise.resolve(),
    signInWithEmailAndPassword: () => Promise.resolve(), createUserWithEmailAndPassword: () => Promise.resolve(), setPersistence: () => Promise.resolve(),
    getRedirectResult: () => Promise.resolve({}), sendPasswordResetEmail: () => Promise.resolve() };
  const db = { ref, goOffline() {}, goOnline() {} };
  window.__fb = S;
  window.firebase = { apps: [], initializeApp() { this.apps.push({}); return {}; }, app: () => ({}),
    auth: Object.assign(() => auth, { GoogleAuthProvider: function () { this.setCustomParameters = () => {}; this.addScope = () => {}; }, Auth: { Persistence: { LOCAL: "local" } } }),
    database: Object.assign(() => db, { ServerValue: { TIMESTAMP: Date.now() } }), storage: () => ({}), messaging: () => ({}) };
})();
