/* Ours: Seiten, Bilder und Firebase-Skripte für die Offline-Nutzung zwischenspeichern */
const CACHE="ours-v6";
const CORE=["./","index.html","rezepte.html","haushalt.html","budget.html","chat.html","gym.html","mail.html","home.html","kalender.html","reise.html","raum.html","manifest.json","ours-mark.png","ours-logo.png","apple-touch-icon.png",
  "https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js","https://www.gstatic.com/firebasejs/10.12.2/firebase-database-compat.js","https://www.gstatic.com/firebasejs/10.12.2/firebase-auth-compat.js"];
const IMGS=["Ab_Roller-0.jpg", "Ab_Roller-1.jpg", "Arnold_Dumbbell_Press-0.jpg", "Arnold_Dumbbell_Press-1.jpg", "Barbell_Bench_Press_-_Medium_Grip-0.jpg", "Barbell_Bench_Press_-_Medium_Grip-1.jpg", "Barbell_Curl-0.jpg", "Barbell_Curl-1.jpg", "Barbell_Deadlift-0.jpg", "Barbell_Deadlift-1.jpg", "Barbell_Glute_Bridge-0.jpg", "Barbell_Glute_Bridge-1.jpg", "Barbell_Hack_Squat-0.jpg", "Barbell_Hack_Squat-1.jpg", "Barbell_Hip_Thrust-0.jpg", "Barbell_Hip_Thrust-1.jpg", "Barbell_Incline_Bench_Press_-_Medium_Grip-0.jpg", "Barbell_Incline_Bench_Press_-_Medium_Grip-1.jpg", "Barbell_Seated_Calf_Raise-0.jpg", "Barbell_Seated_Calf_Raise-1.jpg", "Barbell_Shoulder_Press-0.jpg", "Barbell_Shoulder_Press-1.jpg", "Barbell_Squat-0.jpg", "Barbell_Squat-1.jpg", "Bent_Over_Barbell_Row-0.jpg", "Bent_Over_Barbell_Row-1.jpg", "Bicycling_Stationary-0.jpg", "Bicycling_Stationary-1.jpg", "Butterfly-0.jpg", "Butterfly-1.jpg", "Cable_Crossover-0.jpg", "Cable_Crossover-1.jpg", "Cable_Crunch-0.jpg", "Cable_Crunch-1.jpg", "Cable_Rope_Overhead_Triceps_Extension-0.jpg", "Cable_Rope_Overhead_Triceps_Extension-1.jpg", "Calf_Press_On_The_Leg_Press_Machine-0.jpg", "Calf_Press_On_The_Leg_Press_Machine-1.jpg", "Close-Grip_Barbell_Bench_Press-0.jpg", "Close-Grip_Barbell_Bench_Press-1.jpg", "Concentration_Curls-0.jpg", "Concentration_Curls-1.jpg", "Crunches-0.jpg", "Crunches-1.jpg", "Dips_-_Chest_Version-0.jpg", "Dips_-_Chest_Version-1.jpg", "Dips_-_Triceps_Version-0.jpg", "Dips_-_Triceps_Version-1.jpg", "Dumbbell_Bench_Press-0.jpg", "Dumbbell_Bench_Press-1.jpg", "Dumbbell_Bicep_Curl-0.jpg", "Dumbbell_Bicep_Curl-1.jpg", "Dumbbell_Flyes-0.jpg", "Dumbbell_Flyes-1.jpg", "Dumbbell_Lunges-0.jpg", "Dumbbell_Lunges-1.jpg", "Dumbbell_Shoulder_Press-0.jpg", "Dumbbell_Shoulder_Press-1.jpg", "Elliptical_Trainer-0.jpg", "Elliptical_Trainer-1.jpg", "Face_Pull-0.jpg", "Face_Pull-1.jpg", "Farmers_Walk-0.jpg", "Farmers_Walk-1.jpg", "Front_Barbell_Squat-0.jpg", "Front_Barbell_Squat-1.jpg", "Front_Dumbbell_Raise-0.jpg", "Front_Dumbbell_Raise-1.jpg", "Glute_Kickback-0.jpg", "Glute_Kickback-1.jpg", "Hammer_Curls-0.jpg", "Hammer_Curls-1.jpg", "Hanging_Leg_Raise-0.jpg", "Hanging_Leg_Raise-1.jpg", "Hyperextensions_Back_Extensions-0.jpg", "Hyperextensions_Back_Extensions-1.jpg", "Leg_Extensions-0.jpg", "Leg_Extensions-1.jpg", "Leg_Press-0.jpg", "Leg_Press-1.jpg", "Lying_Leg_Curls-0.jpg", "Lying_Leg_Curls-1.jpg", "Lying_Triceps_Press-0.jpg", "Lying_Triceps_Press-1.jpg", "One-Arm_Dumbbell_Row-0.jpg", "One-Arm_Dumbbell_Row-1.jpg", "Palms-Up_Barbell_Wrist_Curl_Over_A_Bench-0.jpg", "Palms-Up_Barbell_Wrist_Curl_Over_A_Bench-1.jpg", "Plank-0.jpg", "Plank-1.jpg", "Preacher_Curl-0.jpg", "Preacher_Curl-1.jpg", "Pullups-0.jpg", "Pullups-1.jpg", "Pushups-0.jpg", "Pushups-1.jpg", "Reverse_Barbell_Curl-0.jpg", "Reverse_Barbell_Curl-1.jpg", "Reverse_Flyes-0.jpg", "Reverse_Flyes-1.jpg", "Romanian_Deadlift-0.jpg", "Romanian_Deadlift-1.jpg", "Rope_Jumping-0.jpg", "Rope_Jumping-1.jpg", "Rowing_Stationary-0.jpg", "Rowing_Stationary-1.jpg", "Running_Treadmill-0.jpg", "Running_Treadmill-1.jpg", "Russian_Twist-0.jpg", "Russian_Twist-1.jpg", "Seated_Cable_Rows-0.jpg", "Seated_Cable_Rows-1.jpg", "Seated_Leg_Curl-0.jpg", "Seated_Leg_Curl-1.jpg", "Side_Lateral_Raise-0.jpg", "Side_Lateral_Raise-1.jpg", "Split_Squat_with_Dumbbells-0.jpg", "Split_Squat_with_Dumbbells-1.jpg", "Stairmaster-0.jpg", "Stairmaster-1.jpg", "Standing_Biceps_Cable_Curl-0.jpg", "Standing_Biceps_Cable_Curl-1.jpg", "Standing_Calf_Raises-0.jpg", "Standing_Calf_Raises-1.jpg", "Thigh_Abductor-0.jpg", "Thigh_Abductor-1.jpg", "Tricep_Dumbbell_Kickback-0.jpg", "Tricep_Dumbbell_Kickback-1.jpg", "Triceps_Pushdown-0.jpg", "Triceps_Pushdown-1.jpg", "Triceps_Pushdown_-_Rope_Attachment-0.jpg", "Triceps_Pushdown_-_Rope_Attachment-1.jpg", "Upright_Barbell_Row-0.jpg", "Upright_Barbell_Row-1.jpg", "Wide-Grip_Lat_Pulldown-0.jpg", "Wide-Grip_Lat_Pulldown-1.jpg"].map(f=>"gym-img/"+f);
self.addEventListener("install",e=>{
  e.waitUntil((async()=>{ const c=await caches.open(CACHE);
    await Promise.all(CORE.map(u=>c.add(new Request(u,{cache:"reload"})).catch(()=>{})));
    // Übungsbilder im Hintergrund, Fehler sind egal
    Promise.all(IMGS.map(u=>c.match(u).then(h=>h||c.add(u)).catch(()=>{})));
    self.skipWaiting(); })());
});
self.addEventListener("activate",e=>{ e.waitUntil((async()=>{ for(const k of await caches.keys()) if(k!==CACHE) await caches.delete(k); await self.clients.claim(); })()); });
const timeout=(p,ms)=>new Promise((res,rej)=>{ const t=setTimeout(()=>rej(new Error("timeout")),ms); p.then(v=>{ clearTimeout(t); res(v); },e=>{ clearTimeout(t); rej(e); }); });
self.addEventListener("fetch",e=>{
  const r=e.request; if(r.method!=="GET") return;
  const u=new URL(r.url), same=u.origin===location.origin;
  if(same&&u.pathname.endsWith("version.json")) return;   // immer frisch vom Netz
  const page=r.mode==="navigate"||(same&&(u.pathname.endsWith(".html")||u.pathname.endsWith("/")));
  if(page){
    // Seiten: sofort aus dem Speicher (schneller Wechsel, auch ohne Netz), im Hintergrund aktualisieren
    const key=u.origin+u.pathname;
    e.respondWith((async()=>{ const c=await caches.open(CACHE), hit=(await c.match(key))||(await c.match(r,{ignoreSearch:true}));
      const net=fetch(r).then(res=>{ if(res&&res.ok&&res.type!=="opaqueredirect") c.put(key,res.clone()); return res; });
      if(hit){ e.waitUntil(net.catch(()=>{})); return hit; }
      try{ return await timeout(net,8000); }catch(err){ return (await c.match(u.origin+u.pathname.replace(/[^/]*$/,"home.html")))||(await c.match("home.html"))||Response.error(); } })());
    return;
  }
  const asset=same||/(^|\.)gstatic\.com$|fonts\.googleapis\.com$|fonts\.gstatic\.com$/.test(u.hostname);
  if(!asset) return;   // Firebase-Datenbank, Helfer, Spotify usw. normal laufen lassen
  // Bilder, Skripte, Schriften: zuerst aus dem Speicher
  e.respondWith((async()=>{ const c=await caches.open(CACHE), hit=await c.match(r,{ignoreSearch:same});
    if(hit) return hit;
    try{ const res=await fetch(r); if(res&&(res.ok||res.type==="opaque")) c.put(r,res.clone()); return res; }catch(err){ return Response.error(); } })());
});

/* ---------- Mitteilungen ---------- */
self.addEventListener("push",e=>{
  let d={}; try{ d=e.data?e.data.json():{}; }catch(err){ d={b:e.data?e.data.text():""}; }
  e.waitUntil(self.registration.showNotification(d.t||"Ours",{body:d.b||"",icon:"apple-touch-icon.png",badge:"ours-mark.png",tag:d.id||undefined,data:{u:d.u||"home.html"}}));
});
self.addEventListener("notificationclick",e=>{
  e.notification.close(); const url=new URL(e.notification.data&&e.notification.data.u||"home.html",self.registration.scope).href;
  e.waitUntil((async()=>{ const all=await self.clients.matchAll({type:"window",includeUncontrolled:true});
    for(const c of all){ if("focus" in c){ await c.focus(); if("navigate" in c) return c.navigate(url).catch(()=>{}); return; } }
    return self.clients.openWindow(url); })());
});
