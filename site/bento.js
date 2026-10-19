// The feature cards below the demo: each little picture can be played with.
(() => {
  const $ = (id) => document.getElementById(id);
  const q = (el, sel) => el.querySelector(`[data-b="${sel}"]`);
  const PLAY = '<svg viewBox="0 0 10 10"><path d="M2.5 1.2v7.6L8.8 5z"/></svg>';
  const PAUSE = '<svg viewBox="0 0 10 10"><rect x="2" y="1.5" width="2.2" height="7" rx=".5"/><rect x="5.8" y="1.5" width="2.2" height="7" rx=".5"/></svg>';
  const hm = (s) => `${Math.floor(s / 3600)}:${String(Math.floor(s / 60) % 60).padStart(2, "0")}`;
  const later = (ms, fn) => setTimeout(fn, ms);

  // Menu bar: the square pauses and resumes; the text cycles how much shows.
  const mb = $("b-mb");
  if (mb) {
    let on = true, secs = 84 * 60, mode = 0;
    const item = q(mb, "mb-item"), sq = q(mb, "mb-sq"), time = q(mb, "mb-time"), task = q(mb, "mb-task");
    const draw = () => {
      item.classList.toggle("off", !on);
      sq.innerHTML = on ? PAUSE : PLAY;
      time.textContent = hm(secs);
      time.hidden = mode === 2;
      task.hidden = mode === 1 || !on;
      task.textContent = mode === 2 ? "Design" : " Design";
    };
    item.addEventListener("click", (e) => {
      if (e.target.closest('[data-b="mb-sq"]')) on = !on;
      else mode = (mode + 1) % 3;
      draw();
    });
    setInterval(() => { if (on) { secs += 60; draw(); } }, 4000);
    const clock = q(mb, "clock");
    const tick = () => { clock.textContent = new Date().toLocaleString("en-US", { weekday: "short", hour: "numeric", minute: "2-digit" }).replace(",", ""); };
    tick(); setInterval(tick, 15000);
    draw();
  }

  // Short days: pick any day; Open jumps to the short one; ✕ dismisses.
  const sd = $("b-sd");
  if (sd) {
    const days = [...sd.querySelectorAll("[data-d]")], nudge = q(sd, "nudge");
    const select = (i) => {
      days.forEach((d, n) => d.classList.toggle("sel", n === i));
      days[3].classList.toggle("short", i !== 3 && !nudge.classList.contains("gone"));
      if (i === 3) nudge.classList.add("gone");
    };
    days.forEach((d, i) => d.addEventListener("click", () => select(i)));
    q(sd, "open").addEventListener("click", () => select(3));
    q(sd, "dismiss").addEventListener("click", () => { nudge.classList.add("gone"); days[3].classList.remove("short"); later(2600, reset); });
    const reset = () => { nudge.classList.remove("gone"); select(4); };
    days[3].addEventListener("click", () => later(2600, reset));
    q(sd, "open").addEventListener("click", () => later(2600, reset));
  }

  // Reminder: Start begins a timer, then the reminder comes back later.
  const rm = $("b-rm");
  if (rm) {
    const text = q(rm, "rm-text"), go = q(rm, "rm-go");
    go.addEventListener("click", () => {
      text.innerHTML = "Timer started<small>Website Redesign · Design</small>";
      go.hidden = true;
      later(2800, () => { text.innerHTML = "Nothing tracked yet<small>It's 10:00. Start a timer?</small>"; go.hidden = false; });
    });
  }

  // Search: type, pick a project, then a task.
  const sr = $("b-sr");
  if (sr) {
    const input = sr.querySelector("input"), out = q(sr, "sr-out");
    const projects = [
      { n: "Brand Refresh", c: "ACME-BR", cl: "Acme", t: ["Design", "Strategy", "Meetings"] },
      { n: "Mobile App", c: "ACME-APP", cl: "Acme", t: ["Design", "Development"] },
      { n: "Website Redesign", c: "TB-WEB", cl: "Tractorbeam", t: ["Design", "Development"] },
      { n: "Data Platform", c: "NW-DATA", cl: "Northwind", t: ["Development", "Meetings"] },
    ];
    let open = null;
    const draw = () => {
      const w = input.value.trim().toLowerCase();
      if (open) {
        out.innerHTML = `<span class="msg">${open.n} →</span>` + open.t.map((t) => `<button type="button" class="task" data-t="${t}">${t}</button>`).join("");
        return;
      }
      const hits = w ? projects.filter((p) => `${p.n} ${p.c} ${p.cl}`.toLowerCase().includes(w)) : [];
      out.innerHTML = hits.length ? hits.map((p, i) => `<button type="button" data-p="${projects.indexOf(p)}">${p.n}</button>`).join("") : `<span class="msg">${w ? "No projects match" : "Try acme, web or nw"}</span>`;
    };
    input.addEventListener("input", () => { open = null; draw(); });
    out.addEventListener("click", (e) => {
      const b = e.target.closest("button"); if (!b) return;
      if (b.dataset.p) { open = projects[+b.dataset.p]; return draw(); }
      out.innerHTML = `<span class="done">▶ ${open.n} · ${b.dataset.t}</span>`;
      open = null;
      later(2200, draw);
    });
    draw();
  }

  // Favorites from the footer: the star opens the menu; pick one to run it.
  const ff = $("b-ff");
  if (ff) {
    const star = q(ff, "ff-star"), menu = q(ff, "ff-menu"), items = [...menu.querySelectorAll("button")];
    star.addEventListener("click", () => { menu.classList.toggle("closed"); star.classList.toggle("on", !menu.classList.contains("closed")); });
    items.forEach((b) => b.addEventListener("click", () => {
      const was = b.classList.contains("on");
      items.forEach((x) => { x.classList.remove("on"); x.querySelector("svg").outerHTML = PLAY; });
      if (!was) { b.classList.add("on"); b.querySelector("svg").outerHTML = PAUSE; }
    }));
  }

  // Recent and Suggested: star a recent task; dismiss a suggestion.
  const rs = $("b-rs");
  if (rs) {
    rs.querySelectorAll('[data-b="star"]').forEach((b) => b.addEventListener("click", () => {
      b.classList.toggle("on"); b.textContent = b.classList.contains("on") ? "★" : "☆";
    }));
    const pool = [["Data Platform", "Meetings"], ["Internal", "Admin"], ["Context Launch", "Meetings"], ["Mobile App", "QA & Testing"], ["Website Redesign", "Meetings"]];
    let next = 0;
    const sug = q(rs, "sug");
    const card = () => { const [n, t] = pool[next++ % pool.length]; return `<span class="t sug"><b>${n}</b><span>${t}</span><button type="button" class="x" aria-label="Remove suggestion">×</button></span>`; };
    sug.innerHTML = card() + card();
    sug.addEventListener("click", (e) => {
      const x = e.target.closest(".x"); if (!x) return;
      const t = x.parentElement;
      t.classList.add("out");
      later(200, () => { t.outerHTML = card(); });
    });
  }

  // Idle: Remove or Keep the time away.
  const idle = $("b-idle");
  if (idle) {
    const text = q(idle, "idle-text"), btns = [q(idle, "idle-rm"), q(idle, "idle-keep")];
    const pick = (msg) => {
      text.innerHTML = msg; btns.forEach((b) => { b.hidden = true; }); idle.querySelector(".sep").hidden = true;
      later(2400, () => { text.innerHTML = 'Away for <b class="num">0:42</b>'; btns.forEach((b) => { b.hidden = false; }); idle.querySelector(".sep").hidden = false; });
    };
    btns[0].addEventListener("click", () => pick("Took off <b class=\"num\">0:42</b>"));
    btns[1].addEventListener("click", () => pick("Kept <b class=\"num\">0:42</b>"));
  }

  // Start Again Today: a fresh timer for last Tuesday's task.
  const ag = $("b-ag");
  if (ag) {
    const go = q(ag, "ag-go"), label = go.querySelector("span"), day = q(ag, "ag-day");
    let timer = null, s = 0;
    go.addEventListener("click", () => {
      if (timer) { clearInterval(timer); timer = null; go.classList.remove("run"); label.textContent = "Start Again Today"; day.textContent = "Last Tuesday"; return; }
      s = 0; go.classList.add("run"); day.textContent = "Today";
      label.textContent = "Running 0:00";
      timer = setInterval(() => { s += 1; label.textContent = `Running 0:${String(s).padStart(2, "0")}`; }, 1000);
    });
  }

  // Long names: the play button runs it; the name still slides.
  const ln = $("b-ln");
  if (ln) {
    const go = q(ln, "ln-go");
    go.addEventListener("click", () => { const on = ln.classList.toggle("run"); go.innerHTML = on ? PAUSE : PLAY; });
  }

  // Undo: delete the entry, then bring it back.
  const un = $("b-un");
  if (un) {
    const row = q(un, "un-row"), toast = q(un, "un-toast");
    let t = null;
    const restore = () => { clearTimeout(t); row.hidden = false; toast.hidden = true; };
    q(un, "un-del").addEventListener("click", () => { row.hidden = true; toast.hidden = false; t = later(6000, restore); });
    q(un, "un-undo").addEventListener("click", restore);
  }

  // In step: start or stop on the web and the Mac follows.
  const sy = $("b-sy");
  if (sy) {
    let on = true, s = 42 * 60;
    const a = q(sy, "sy-a"), b = q(sy, "sy-b");
    q(sy, "sy-web").addEventListener("click", () => { on = !on; sy.classList.toggle("off", !on); });
    setInterval(() => { if (on) { s += 60; a.textContent = hm(s); later(600, () => { b.textContent = hm(s); }); } }, 3000);
  }

  // Locked: the open row plays; the lock explains itself.
  const lk = $("b-lk");
  if (lk) {
    const go = q(lk, "lk-go"), pop = q(lk, "lk-pop"), t = q(lk, "lk-t");
    let timer = null, s = 135 * 60;
    go.addEventListener("click", () => {
      if (timer) { clearInterval(timer); timer = null; go.innerHTML = PLAY; go.style.background = ""; go.style.color = ""; return; }
      go.innerHTML = PAUSE; go.style.background = "var(--orange)"; go.style.color = "#fff";
      timer = setInterval(() => { s += 60; t.textContent = hm(s); }, 2000);
    });
    q(lk, "lk-why").addEventListener("click", () => { pop.hidden = !pop.hidden; });
  }

  // Keychain: the lock opens for a moment, but the token stays hidden.
  const kc = $("b-kc");
  if (kc) {
    const dots = q(kc, "kc-dots");
    kc.addEventListener("click", () => {
      kc.classList.add("open"); dots.textContent = "Only sent to Harvest";
      later(1800, () => { kc.classList.remove("open"); dots.textContent = "••••3f9a"; });
    });
  }
})();
