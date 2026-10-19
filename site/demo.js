// The full-app demo: Harvestbeam's window on a Mac desktop, working with
// example data that lives only in this page. Everything the app does by
// hand works here: search, timers, the week, favorites, editing, planning.
(() => {
  const root = document.getElementById("dm");
  if (!root) return;
  const $ = (sel, el = root) => el.querySelector(sel);
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

  const PLAY = '<svg viewBox="0 0 10 10"><path d="M2.5 1.2v7.6L8.8 5z"/></svg>';
  const PAUSE = '<svg viewBox="0 0 10 10"><rect x="2" y="1.5" width="2.2" height="7" rx=".5"/><rect x="5.8" y="1.5" width="2.2" height="7" rx=".5"/></svg>';
  const LOCK = '<svg viewBox="0 0 16 16"><rect x="3" y="7" width="10" height="7" rx="1.5"/><path d="M5.5 7V5a2.5 2.5 0 0 1 5 0v2"/></svg>';
  const CHEV = '<svg class="chev" viewBox="0 0 10 10"><path d="M2 3.5 5 6.5 8 3.5"/></svg>';

  // Example projects, like the app's demo mode.
  const P = [
    { name: "Website Redesign", code: "TB-WEB", client: "Tractorbeam", tasks: ["Design", "Development", "Meetings", "QA & Testing"] },
    { name: "Context Launch", code: "TB-CTX", client: "Tractorbeam", tasks: ["Strategy", "Development", "Meetings"] },
    { name: "Internal", code: null, client: "Tractorbeam", tasks: ["Admin", "Meetings", "Business Development"] },
    { name: "Brand Refresh", code: "ACME-BR", client: "Acme Co", tasks: ["Design", "Strategy", "Meetings"] },
    { name: "Mobile App", code: "ACME-APP", client: "Acme Co", tasks: ["Design", "Development", "QA & Testing"] },
    { name: "Website Design and Development", code: "DAF-DP-01", client: "Dallas Art Fair", tasks: ["Product Design", "Development"] },
    { name: "Data Platform", code: "NW-DATA", client: "Northwind", tasks: ["Development", "Meetings"] },
  ];
  const key = (p, t) => `${p}:${t}`;
  const proj = (k) => P[+k.split(":")[0]];
  const taskOf = (k) => k.slice(k.indexOf(":") + 1);

  // Dates as day numbers, so "yesterday" is just day - 1.
  const DAY = 86400000;
  const dnum = (d) => Math.floor((d.getTime() - d.getTimezoneOffset() * 60000) / DAY);
  const ddate = (n) => { const d = new Date(n * DAY); return new Date(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()); };
  const today = dnum(new Date());
  const weekStart = (n) => n - ((ddate(n).getDay() + 6) % 7); // Monday
  const LETTERS = ["S", "M", "T", "W", "T", "F", "S"];
  const hm = (s) => { s = Math.max(0, Math.round(s)); return `${Math.floor(s / 3600)}:${String(Math.floor(s / 60) % 60).padStart(2, "0")}`; };
  const dayTitle = (n) => {
    const d = ddate(n), md = d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
    return n === today ? `Today, ${md}` : n === today - 1 ? `Yesterday, ${md}` : d.toLocaleDateString("en-US", { weekday: "long", month: "short", day: "numeric" });
  };
  const wdName = (n) => ddate(n).toLocaleDateString("en-US", { weekday: "long" });

  // Example history: a few weeks of weekdays, last week approved, older Acme
  // work invoiced, and one short day earlier this week.
  let S;
  function seed() {
    let id = 1, r = 7;
    const rnd = () => (r = (r * 9301 + 49297) % 233280) / 233280;
    const entries = [];
    const usual = [[0, "Design"], [0, "Development"], [1, "Strategy"], [3, "Design"], [2, "Meetings"], [4, "Development"], [5, "Product Design"], [6, "Development"], [2, "Admin"]];
    const ws = weekStart(today);
    // The most recent weekday before today is the short one.
    let shortDay = today - 1;
    while ([0, 6].includes(ddate(shortDay).getDay())) shortDay--;
    for (let n = today - 24; n < today; n++) {
      const wd = ddate(n).getDay();
      if (wd === 0 || wd === 6) continue;
      let left = n === shortDay ? 3.2 * 3600 : (7.4 + rnd() * 1.4) * 3600;
      const picks = [...usual].sort(() => rnd() - 0.5).slice(0, 3 + Math.floor(rnd() * 2));
      picks.forEach(([p, t], i) => {
        const secs = i === picks.length - 1 ? left : Math.round((left / (picks.length - i)) * (0.7 + rnd() * 0.6) / 300) * 300;
        left -= secs;
        const lock = n < ws - 7 && P[p].client === "Acme Co" ? "invoiced" : n < ws ? "approved" : null;
        entries.push({ id: id++, day: n, k: key(p, t), secs: Math.max(900, secs), notes: "", lock, order: id });
      });
    }
    const add = (p, t, secs, notes, running) => entries.push({ id: id++, day: today, k: key(p, t), secs, notes, lock: null, order: id, running: !!running, startedAt: running ? Date.now() : 0 });
    add(3, "Meetings", 2580, "Kickoff with the Acme team");
    add(5, "Product Design", 3060, "");
    add(0, "Design", 1680, "Menu bar timer explorations", true);
    entries.find((e) => e.id === 1).notes = "";
    return {
      entries, selected: today, open: true, query: "", picked: null, sel: 0,
      favorites: [key(1, "Strategy"), key(0, "Development"), key(3, "Design"), key(5, "Product Design")],
      hidden: new Set(), closed: new Set(), dismissed: new Set(), nudges: true,
      pop: null, undo: null, idCount: id,
    };
  }
  S = seed();

  // Derived lists
  const running = () => S.entries.find((e) => e.running);
  const elapsed = (e, now = Date.now()) => e.secs + (e.running ? (now - e.startedAt) / 1000 : 0);
  const secsOn = (n) => S.entries.reduce((t, e) => (e.day === n ? t + elapsed(e) : t), 0);
  const usualDay = 7 * 3600;
  const shortDays = () => {
    const out = [];
    for (let n = today - 7; n < today; n++) {
      const wd = ddate(n).getDay();
      if (wd !== 0 && wd !== 6 && secsOn(n) < usualDay * 0.75) out.push(n);
    }
    return out;
  };
  const recents = () => {
    const seen = new Set(S.favorites), out = [];
    [...S.entries].sort((a, b) => b.day - a.day || b.order - a.order).forEach((e) => {
      if (!seen.has(e.k) && out.length < 4) { seen.add(e.k); out.push(e.k); }
    });
    return out;
  };
  const suggested = () => {
    const shown = new Set([...S.favorites, ...recents(), ...S.hidden]);
    const score = {};
    S.entries.forEach((e) => { if (!shown.has(e.k)) score[e.k] = (score[e.k] || 0) + elapsed(e) / (1 + (today - e.day) / 10); });
    const extra = [key(4, "QA & Testing"), key(6, "Meetings"), key(2, "Business Development"), key(1, "Meetings")].filter((k) => !shown.has(k));
    return [...Object.keys(score).sort((a, b) => score[b] - score[a]), ...extra].filter((k, i, a) => a.indexOf(k) === i).slice(0, 4);
  };

  // Timers
  function stopRunning() {
    const r = running();
    if (r) { r.secs = elapsed(r); r.running = false; }
  }
  function startTask(k) {
    const r = running();
    if (r && r.k === k && r.day === today) { stopRunning(); return render(); }
    stopRunning();
    const e = S.entries.find((x) => x.day === today && x.k === k && !x.lock);
    if (e) { e.running = true; e.startedAt = Date.now(); }
    else S.entries.push({ id: S.idCount++, day: today, k, secs: 0, notes: "", lock: null, order: S.idCount, running: true, startedAt: Date.now() });
    S.selected = today;
    render();
  }
  function toggleEntry(id) {
    const e = S.entries.find((x) => x.id === id);
    if (!e || e.lock) return;
    if (e.running) { stopRunning(); return render(); }
    if (e.day !== today) return startTask(e.k);
    stopRunning();
    e.running = true; e.startedAt = Date.now();
    render();
  }

  // Search: projects grouped by client, then that project's tasks.
  function results() {
    const q = S.query.trim().toLowerCase();
    if (!q) return [];
    const words = q.split(/\s+/);
    const hit = P.map((p, i) => ({ p, i, hay: `${p.client} ${p.name} ${p.code || ""} ${p.tasks.join(" ")}`.toLowerCase() }))
      .filter((x) => words.every((w) => x.hay.includes(w)));
    const rows = [];
    let client = null;
    hit.sort((a, b) => a.p.client.localeCompare(b.p.client)).forEach(({ p, i }) => {
      if (p.client !== client) { client = p.client; rows.push({ type: "grp", label: client }); }
      rows.push({ type: "proj", i });
      if (S.picked === i) p.tasks.forEach((t) => rows.push({ type: "task", i, t }));
    });
    return rows;
  }
  const pickable = (rows) => rows.filter((r) => r.type !== "grp");
  function pick(r) {
    if (r.type === "proj") { S.picked = S.picked === r.i ? null : r.i; S.sel = Math.max(0, pickable(results()).findIndex((x) => x.type === "proj" && x.i === r.i)); return render(); }
    S.query = ""; S.picked = null; S.sel = 0; $("#dm-ask").value = "";
    startTask(key(r.i, r.t));
  }

  // Rendering
  function tile(k, kind) {
    const p = proj(k), t = taskOf(k), r = running(), on = r && r.k === k && r.day === today, fav = S.favorites.includes(k);
    const star = kind !== "fav" ? `<button class="star${fav ? " on" : ""}" data-star="${esc(k)}" aria-label="${fav ? "Unstar" : "Star"}">${fav ? "★" : "☆"}</button>` : "";
    const rm = kind === "sug" ? `<button class="rm" data-hide="${esc(k)}" aria-label="Remove from Suggested">×</button>` : "";
    return `<div class="dm-tile${on ? " run" : ""}" data-tile="${esc(k)}" data-kind="${kind}">
      <div class="info">${p.code ? `<div class="cd">${esc(p.code)}</div>` : ""}<div class="nm dm-mq"><span>${esc(p.name)}</span></div><div class="tk">${esc(t)}</div></div>
      ${rm}${star}<span class="go2">${on ? PAUSE : PLAY}</span></div>`;
  }
  function section(id, title, icon, keys, kind, empty) {
    if (!keys.length && !empty) return "";
    const closed = S.closed.has(id);
    return `<div class="dm-sec ${kind}${closed ? " closed" : ""}" data-sec="${id}">
      <div class="hd" data-fold="${id}">${icon}${title}${CHEV}${closed ? `<span style="color:var(--faint);font-weight:400">${keys.length}</span>` : ""}</div>
      <div class="tiles">${keys.length ? keys.map((k) => tile(k, kind)).join("") : `<div style="grid-column:1/-1;text-align:center;color:var(--muted);font-size:12px;padding:12px;border:1px dashed color-mix(in srgb,var(--orange) 30%,transparent);border-radius:12px">${empty}</div>`}</div></div>`;
  }
  function entryRow(e) {
    const p = proj(e.k), lock = e.lock;
    const btn = lock ? `<button class="dm-btn lk" data-lock="${e.id}" aria-label="Why it's locked">${LOCK}</button>`
      : `<button class="dm-btn${e.running ? " on" : ""}" data-toggle="${e.id}" aria-label="${e.running ? "Pause" : "Start"}">${e.running ? PAUSE : PLAY}</button>`;
    return `<div class="dm-entry${e.running ? " run" : ""}${lock ? " locked" : ""}" data-entry="${e.id}" title="${lock ? "Double-click to see why it's locked" : "Double-click to edit"}">
      <div class="who"><div class="c">${esc(p.client)}</div><div class="p dm-mq"><span>${esc(p.code ? `[${p.code}] ${p.name}` : p.name)}</span></div><div class="k">${esc(taskOf(e.k))}</div>${e.notes ? `<div class="n">${esc(e.notes)}</div>` : ""}</div>
      <span class="hrs" ${e.running ? 'data-live="run"' : ""}>${hm(elapsed(e))}</span>${btn}</div>`;
  }
  function body() {
    const rows = results();
    if (S.query.trim()) {
      const flat = pickable(rows);
      if (!flat.length) return `<div class="dm-card dm-empty">No projects match “${esc(S.query)}”</div>`;
      let n = -1;
      return `<div class="dm-card dm-res">${rows.map((r) => {
        if (r.type === "grp") return `<div class="grp">${esc(r.label)}</div>`;
        n++;
        if (r.type === "proj") { const p = P[r.i]; return `<div class="dm-r${S.sel === n ? " sel" : ""}${S.picked === r.i ? " open" : ""}" data-r="${n}"><span class="lb">${esc(p.code ? `[${p.code}] ${p.name}` : p.name)}</span><svg class="ic" viewBox="0 0 10 10"><path d="M3.5 2 6.5 5 3.5 8"/></svg></div>`; }
        const rr = running(), on = rr && rr.k === key(r.i, r.t), fav = S.favorites.includes(key(r.i, r.t));
        return `<div class="dm-r task${S.sel === n ? " sel" : ""}${on ? " on" : ""}" data-r="${n}"><span class="lb">${esc(r.t)}</span>${fav ? '<span class="fv">★</span>' : ""}<span class="ic">${on ? PAUSE : PLAY}</span></div>`;
      }).join("")}</div>`;
    }
    const ws = weekStart(S.selected);
    const shorts = S.nudges ? shortDays() : [];
    let week = "";
    for (let i = 0; i < 7; i++) {
      const n = ws + i, s = secsOn(n);
      week += `<button class="dm-day${n === S.selected ? " sel" : ""}${n === today ? " today" : ""}${s < 60 ? " zero" : ""}${shorts.includes(n) && n !== S.selected ? " short" : ""}" data-day="${n}"><b>${LETTERS[ddate(n).getDay()]}</b><span ${n === today ? 'data-live="today"' : ""}>${hm(s)}</span></button>`;
    }
    const nudgeDay = shorts.filter((n) => n !== S.selected && !S.dismissed.has(n)).pop();
    const nudge = nudgeDay !== undefined ? `<div class="dm-nudge"><div class="w"><b>${secsOn(nudgeDay) < 60 ? `Nothing tracked ${wdName(nudgeDay)}` : `${wdName(nudgeDay)} only has ${hm(secsOn(nudgeDay))}`}</b><small>${hm(usualDay - secsOn(nudgeDay))} short of a usual day</small></div><button class="go" data-day="${nudgeDay}">Open ${wdName(nudgeDay)}</button><button class="x" data-dismiss="${nudgeDay}" aria-label="Dismiss">✕</button></div>` : "";
    const list = S.entries.filter((e) => e.day === S.selected).sort((a, b) => a.order - b.order);
    const entries = list.length ? `<div class="dm-card">${list.map(entryRow).join("")}</div>`
      : `<div class="dm-card dm-empty">${S.selected === today ? "Nothing tracked yet today" : "No time tracked"}<button class="dm-pill" data-new>+ New Entry</button></div>`;
    const STAR = '<svg viewBox="0 0 16 16"><path d="m8 1.5 1.9 4 4.4.5-3.3 3 .9 4.4L8 11.2l-3.9 2.2.9-4.4-3.3-3 4.4-.5Z"/></svg>';
    const CLOCK = '<svg viewBox="0 0 12 12"><circle cx="6" cy="6" r="4.6"/><path d="M6 3.2V6l1.9 1.2"/></svg>';
    const SPARK = '<svg viewBox="0 0 12 12"><path d="M6 1 7 5l4 1-4 1-1 4-1-4-4-1 4-1Z"/></svg>';
    return `<div class="dm-week"><button class="arr" data-shift="-1" aria-label="Previous day">‹</button><div class="days">${week}</div><button class="arr" data-shift="1" aria-label="Next day">›</button></div>
      ${nudge}${entries}
      ${section("fav", "Favorites", STAR, S.favorites, "fav", "Drag a task here, or star it, to keep it handy")}
      ${section("recent", "Recent", CLOCK, recents(), "recent")}
      ${section("sug", "Suggested", SPARK, suggested(), "sug")}
      <button class="dm-hint" data-focus>Search to find any of your ${P.reduce((t, p) => t + p.tasks.length, 0)} tasks</button>`;
  }
  function render() {
    const scroll = $(".dm-scroll"), top = scroll ? scroll.scrollTop : 0;
    $(".dm-scroll").innerHTML = body();
    $(".dm-scroll").scrollTop = top;
    const r = running();
    $("#dm-ttl").innerHTML = `${esc(dayTitle(S.selected))}<span data-live="week">Week ${hm(weekTotal())}</span>`;
    const item = $("#dm-item");
    item.querySelector(".dm-sq").classList.toggle("off", !r);
    item.querySelector(".dm-sq").innerHTML = r ? PAUSE : PLAY;
    item.querySelector(".task").textContent = r ? taskOf(r.k) : "";
    item.querySelector(".task").style.display = r ? "" : "none";
    item.classList.toggle("on", S.open);
    $(".dm-win").classList.toggle("hidden", !S.open);
    $("#dm-toast").innerHTML = S.undo ? `<div class="dm-toast">Deleted ${esc(proj(S.undo.e.k).name)} · ${hm(S.undo.e.secs)}<span class="sp"></span><button class="dm-pill" data-undo>Undo</button></div>` : "";
    tick();
    renderPop();
  }
  const weekTotal = () => { const ws = weekStart(S.selected); let t = 0; for (let i = 0; i < 7; i++) t += secsOn(ws + i); return t; };
  function tick() {
    const r = running();
    root.querySelectorAll('[data-live="run"]').forEach((el) => { if (r) el.textContent = hm(elapsed(r)); });
    root.querySelectorAll('[data-live="today"]').forEach((el) => { el.textContent = hm(secsOn(today)); });
    const wk = root.querySelector('[data-live="week"]'); if (wk) wk.textContent = `Week ${hm(weekTotal())}`;
    $("#dm-item .t").textContent = r ? hm(elapsed(r)) : hm(secsOn(today));
    $("#dm-clock").textContent = new Date().toLocaleString("en-US", { weekday: "short", hour: "numeric", minute: "2-digit" }).replace(",", "");
  }
  setInterval(tick, 1000);

  // Popovers and menus
  function openPop(kind, data = {}) { S.pop = { kind, ...data }; renderPop(); }
  function closePop() { S.pop = null; renderPop(); }
  function renderPop() {
    const host = $("#dm-pops");
    $(".dm-dim").classList.toggle("on", !!S.pop && !["favmenu", "gear", "ctx"].includes(S.pop?.kind));
    if (!S.pop) { host.innerHTML = ""; return; }
    const { kind } = S.pop;
    const win = $(".dm-win").getBoundingClientRect(), sc = win.width / 420 || 1;
    let place = null;
    const at = (el, w = 280, below = true) => {
      const r = el.getBoundingClientRect(), cx = (r.left - win.left) / sc + r.width / sc / 2;
      const left = Math.max(10, Math.min(420 - w - 10, cx - w / 2));
      place = { top: (r.top - win.top) / sc, bottom: (r.bottom - win.top) / sc, ax: cx - left, below };
      return below ? `left:${left}px;top:${place.bottom + 10}px;--ax:${cx - left}px` : `left:${left}px;bottom:${592 - place.top + 10}px;--ax:${cx - left}px`;
    };
    const projOpts = (sel) => P.map((p, i) => `<option value="${i}"${i === sel ? " selected" : ""}>${esc(p.code ? `[${p.code}] ${p.name}` : p.name)} (${esc(p.client)})</option>`).join("");
    const taskOpts = (i, sel) => P[i].tasks.map((t) => `<option${t === sel ? " selected" : ""}>${esc(t)}</option>`).join("");
    let html = "";
    if (kind === "lock") {
      const e = S.entries.find((x) => x.id === S.pop.id);
      const inv = e.lock === "invoiced";
      html = `<div class="dm-pop" style="${at(S.pop.anchor)}"><div class="why">${inv ? '<svg viewBox="0 0 16 16"><path d="M4 1.5h5.5L12 4v10.5H4Z M6 7h4M6 9.5h4"/></svg>' : '<svg viewBox="0 0 16 16"><path d="m3 8.5 3 3 7-7"/></svg>'}<div><b>${inv ? "Invoiced" : "Approved"}</b><p>${inv ? "This time is on invoice #1042, so Harvest won't let it change. To edit it, ask an admin to take it off the invoice." : "This timesheet has been approved, so Harvest won't let it change. To edit it, ask whoever approved it to unapprove it."}</p></div></div><div class="row"><button class="b" data-again="${e.id}">Start Again Today</button><button class="b pri" data-close>OK</button></div></div>`;
    } else if (kind === "edit" || kind === "new") {
      const e = kind === "edit" ? S.entries.find((x) => x.id === S.pop.id) : null;
      const pi = e ? +e.k.split(":")[0] : (S.pop.p ?? 0), tk = e ? taskOf(e.k) : P[pi].tasks[0];
      const isToday = (e ? e.day : S.selected) === today, starts = !e && isToday;
      const fav = S.favorites.includes(key(pi, tk));
      const title = (e ? "Edit Time Entry" : "New Time Entry") + (isToday ? "" : ` · ${dayTitle(e ? e.day : S.selected)}`);
      html = `<div class="dm-pop dm-ed" style="${at(S.pop.anchor, 340, kind === "edit")}"><h4>${esc(title)}</h4>
        <div class="grp"><select data-f="p" aria-label="Project">${projOpts(pi)}</select><select data-f="t" aria-label="Task">${taskOpts(pi, tk)}</select></div>
        <div class="nh"><textarea data-f="n" rows="2" placeholder="Notes (optional)" aria-label="Notes">${esc(e ? e.notes : "")}</textarea><input class="hrs" data-f="h" value="${e ? hm(elapsed(e)) : ""}" placeholder="0:00" aria-label="Hours" title="${starts ? "h:mm or decimal. Leave empty to start a timer." : "h:mm or decimal"}"></div>
        <div class="row"><button class="fav${fav ? " on" : ""}" data-edfav>${fav ? "★" : "☆"} Favorite</button><span class="sp"></span><button class="b" data-close>Cancel</button>${e ? `<button class="b pri" data-save="${e.id}">Save Entry</button>` : `<button class="b pri" data-create>${starts ? "Start Timer" : "Save Entry"}</button>`}</div></div>`;
    } else if (kind === "plan") {
      const props = S.pop.props || [];
      html = `<div class="dm-pop" style="${at(S.pop.anchor, 320, false)};width:320px"><h4>What are you working on today?</h4>
        <textarea data-f="plan" placeholder="Context strategy all morning, an hour on the Acme design, then the Northwind call">${esc(S.pop.text || "")}</textarea>
        ${props.length ? `<div class="props">${props.map((x) => `<div class="prop"><b>${esc(x.t)}</b><span class="p">${esc(P[x.p].name)}</span><span class="h">${hm(x.s)}</span></div>`).join("")}</div>` : `<div class="note">✦ Matched right here in your browser, like the app does on your Mac.</div>`}
        <div class="row"><button class="b" data-close>Cancel</button>${props.length ? `<button class="b pri" data-addplan>Add ${props.length} ${props.length === 1 ? "Entry" : "Entries"}</button>` : `<button class="b pri" data-suggest>Suggest Entries</button>`}</div></div>`;
    } else if (kind === "favmenu") {
      const r = running();
      html = `<div class="dm-menu" style="${at(S.pop.anchor, 220, false)}">${S.favorites.length ? S.favorites.map((k) => `<button data-start="${esc(k)}">${r && r.k === k ? PAUSE : PLAY}${esc(proj(k).name)} · ${esc(taskOf(k))}</button>`).join("") : '<div class="muted">Star a task to add it here</div>'}</div>`;
    } else if (kind === "gear") {
      html = `<div class="dm-menu" style="${at(S.pop.anchor, 230, false)}"><button data-nudges><span class="ck">${S.nudges ? "✓" : ""}</span>Point Out Short Days</button><button data-restore><span class="ck"></span>Show Removed Suggestions</button><div class="sep"></div><button data-reset><span class="ck"></span>Reset the Demo</button><button data-quit><span class="ck"></span>Close Window</button></div>`;
    } else if (kind === "ctx") {
      const e = S.entries.find((x) => x.id === S.pop.id), fav = S.favorites.includes(e.k), wr = win;
      const x = Math.min(420 - 220, (S.pop.x - wr.left) / sc), y = Math.min(592 - 190, (S.pop.y - wr.top) / sc);
      const items = [`<button data-ctx="again">${e.day === today ? "Start a Fresh Timer" : "Start Again Today"}</button>`, '<div class="sep"></div>'];
      if (e.lock) items.push(`<button data-ctx="why">Why Is This ${e.lock === "invoiced" ? "Invoiced" : "Approved"}?</button>`, `<button data-ctx="fav">${fav ? "Remove from Favorites" : "Add to Favorites"}</button>`);
      else items.push('<button data-ctx="edit">Edit Entry</button>', `<button data-ctx="fav">${fav ? "Remove from Favorites" : "Add to Favorites"}</button>`, `<button data-ctx="toggle">${e.running ? "Stop Timer" : "Start Timer"}</button>`, '<button data-ctx="del" class="danger">Delete Entry</button>');
      html = `<div class="dm-menu" style="left:${x}px;top:${y}px">${items.join("")}</div>`;
    } else if (kind === "summary") {
      const y = today - 1, m = ddate(today).getMonth();
      const month = S.entries.reduce((t, e) => (ddate(e.day).getMonth() === m ? t + elapsed(e) : t), 0);
      const ws = weekStart(today); let wk = 0; for (let i = 0; i < 7; i++) wk += secsOn(ws + i);
      html = `<div class="dm-pop" style="${at(S.pop.anchor)};padding:12px 0 0"><h4>Time Summary</h4><div class="sum"><div><small>Hours Today</small><b>${hm(secsOn(today))}</b></div><div><small>Hours Yesterday</small><b>${hm(secsOn(y))}</b></div><div><small>Hours This Week</small><b>${hm(wk)}</b></div><div><small>Hours This Month</small><b>${hm(month)}</b></div></div></div>`;
    }
    host.innerHTML = html;
    // Keep it inside the window: open upward when there's no room below.
    const el = host.firstElementChild;
    if (el && place && el.classList.contains("dm-pop")) {
      if (!place.below) el.classList.add("up");
      else if (place.bottom + 10 + el.offsetHeight > 584) {
        el.classList.add("up");
        el.style.top = `${Math.max(8, place.top - 10 - el.offsetHeight)}px`;
      }
    }
    host.querySelector("textarea, input:not([disabled])")?.focus({ preventScroll: true });
  }

  // Plan the day: a few words per clause, matched to projects and tasks.
  function plan(text) {
    const clauses = text.split(/,|;|\bthen\b|\band then\b|\. /i).map((c) => c.trim()).filter(Boolean);
    const out = [];
    for (const c of clauses) {
      const l = c.toLowerCase();
      let best = null, bestScore = 0;
      P.forEach((p, i) => p.tasks.forEach((t) => {
        let sc = 0;
        `${p.name} ${p.client} ${p.code || ""}`.toLowerCase().split(/[\s-]+/).forEach((w) => { if (w.length > 2 && l.includes(w)) sc += 2; });
        t.toLowerCase().split(/\s+/).forEach((w) => { if (w.length > 2 && l.includes(w)) sc += 1.5; });
        if (/call|meeting|sync|standup/.test(l) && t === "Meetings") sc += 1.2;
        if (/design|mock/.test(l) && /Design/.test(t)) sc += 1;
        if (/build|code|dev/.test(l) && t === "Development") sc += 1;
        if (sc > bestScore) { bestScore = sc; best = { p: i, t }; }
      }));
      if (!best || bestScore < 2) continue;
      let s = 3600;
      const h = l.match(/(\d+(?:\.\d+)?)\s*(h|hour)/), mm = l.match(/(\d+)\s*(m|min)/);
      if (/all (morning|afternoon)|morning|afternoon/.test(l)) s = 3 * 3600;
      if (/half (an )?hour/.test(l)) s = 1800;
      if (/an hour|one hour/.test(l)) s = 3600;
      if (h) s = parseFloat(h[1]) * 3600; else if (mm) s = +mm[1] * 60;
      if (/call|meeting|sync/.test(l) && !h && !mm && !/hour|morning|afternoon/.test(l)) s = 1800;
      out.push({ ...best, s });
    }
    return out;
  }

  // Events
  const ask = $("#dm-ask");
  ask.addEventListener("input", () => { S.query = ask.value; S.picked = null; S.sel = 0; render(); });
  ask.addEventListener("keydown", (ev) => {
    const flat = pickable(results());
    if (ev.key === "ArrowDown" && flat.length) { S.sel = Math.min(flat.length - 1, S.sel + 1); ev.preventDefault(); render(); }
    else if (ev.key === "ArrowUp" && flat.length) { S.sel = Math.max(0, S.sel - 1); ev.preventDefault(); render(); }
    else if (ev.key === "Enter" && flat[S.sel]) { ev.preventDefault(); pick(flat[S.sel]); }
    else if (ev.key === "Escape") {
      ev.preventDefault();
      if (S.picked !== null) { S.picked = null; render(); }
      else if (S.query) { S.query = ""; ask.value = ""; render(); }
      else { S.open = false; ask.blur(); render(); }
    }
  });

  root.addEventListener("click", (ev) => {
    const t = ev.target.closest("[data-edfav],[data-ctx],[data-r],[data-toggle],[data-lock],[data-day],[data-shift],[data-dismiss],[data-star],[data-hide],[data-fold],[data-tile],[data-new],[data-focus],[data-undo],[data-close],[data-save],[data-del],[data-create],[data-suggest],[data-addplan],[data-start],[data-nudges],[data-restore],[data-reset],[data-quit],[data-again],[data-foot],[data-tb],#dm-item,.dm-dim,.lights i");
    if (S.pop && !ev.target.closest(".dm-pop,.dm-menu") && !(t && t.dataset.foot === S.pop.kind)) {
      closePop();
      if (!t || t.classList.contains("dm-dim")) return;
    }
    if (!t) return;
    const d = t.dataset;
    if (t.id === "dm-item") {
      const sq = ev.target.closest(".dm-sq");
      if (sq) { const r = running(); if (r) stopRunning(); else { const last = [...S.entries].filter((e) => e.day === today).sort((a, b) => b.order - a.order)[0]; if (last) toggleEntry(last.id); } return render(); }
      S.open = !S.open; render(); if (S.open) ask.focus({ preventScroll: true }); return;
    }
    if (t.matches(".lights i")) { S.open = false; return render(); }
    if (d.r !== undefined) return pick(pickable(results())[+d.r]);
    if (d.toggle) return toggleEntry(+d.toggle);
    if (d.lock) return openPop("lock", { id: +d.lock, anchor: t });
    if (d.day) { S.selected = +d.day; return render(); }
    if (d.shift) { S.selected += +d.shift; return render(); }
    if (d.dismiss) { S.dismissed.add(+d.dismiss); return render(); }
    if (d.star) { ev.stopPropagation(); const i = S.favorites.indexOf(d.star); i >= 0 ? S.favorites.splice(i, 1) : S.favorites.push(d.star); return render(); }
    if (d.hide) { ev.stopPropagation(); S.hidden.add(d.hide); return render(); }
    if (d.fold) { S.closed.has(d.fold) ? S.closed.delete(d.fold) : S.closed.add(d.fold); return render(); }
    if (d.tile) { if (!dragMoved) startTask(d.tile); return; }
    if (d.new !== undefined) return openPop("new", { anchor: t });
    if (d.focus !== undefined) return ask.focus();
    if (d.undo !== undefined) { S.entries.push(S.undo.e); S.undo = null; return render(); }
    if (d.close !== undefined) return closePop();
    if (d.ctx) {
      const e = S.entries.find((x) => x.id === S.pop.id), anchor = root.querySelector(`[data-entry="${e.id}"] .hrs`);
      closePop();
      if (d.ctx === "again") { if (e.day === today) { stopRunning(); S.entries.push({ id: S.idCount++, day: today, k: e.k, secs: 0, notes: "", lock: null, order: S.idCount, running: true, startedAt: Date.now() }); return render(); } return startTask(e.k); }
      if (d.ctx === "edit") return openPop("edit", { id: e.id, anchor });
      if (d.ctx === "why") return openPop("lock", { id: e.id, anchor });
      if (d.ctx === "fav") { const i = S.favorites.indexOf(e.k); i >= 0 ? S.favorites.splice(i, 1) : S.favorites.push(e.k); return render(); }
      if (d.ctx === "toggle") return toggleEntry(e.id);
      if (d.ctx === "del") { const i = S.entries.indexOf(e); if (e.running) stopRunning(); S.entries.splice(i, 1); S.undo = { e }; render(); clearTimeout(S.undoTimer); S.undoTimer = setTimeout(() => { S.undo = null; render(); }, 8000); return; }
    }
    if (d.again) { const e = S.entries.find((x) => x.id === +d.again); closePop(); return startTask(e.k); }
    if (d.start) { closePop(); return startTask(d.start); }
    if (d.foot) {
      if (S.pop && S.pop.kind === d.foot) return closePop();
      return openPop(d.foot, { anchor: t });
    }
    if (d.tb === "today") { S.selected = today; return render(); }
    if (d.tb === "summary") return S.pop?.kind === "summary" ? closePop() : openPop("summary", { anchor: t });
    const pop = $("#dm-pops");
    const f = (n) => pop.querySelector(`[data-f="${n}"]`);
    const parseH = (v) => { v = v.trim(); if (!v) return null; if (v.includes(":")) { const [h, m] = v.split(":"); return (+h || 0) * 3600 + (+m || 0) * 60; } return parseFloat(v) * 3600 || null; };
    if (t.matches("[data-edfav]")) {
      const k = key(+f("p").value, f("t").value), i = S.favorites.indexOf(k);
      i >= 0 ? S.favorites.splice(i, 1) : S.favorites.push(k);
      t.classList.toggle("on", i < 0); t.textContent = `${i < 0 ? "★" : "☆"} Favorite`;
      return render();
    }
    if (d.save) {
      const e = S.entries.find((x) => x.id === +d.save);
      e.k = key(+f("p").value, f("t").value); e.notes = f("n").value.trim();
      const h = parseH(f("h").value); if (h !== null && !e.running) e.secs = h;
      closePop(); return render();
    }
    if (d.del) {
      const i = S.entries.findIndex((x) => x.id === +d.del), e = S.entries[i];
      if (e.running) stopRunning();
      S.entries.splice(i, 1); S.undo = { e }; closePop(); render();
      clearTimeout(S.undoTimer); S.undoTimer = setTimeout(() => { S.undo = null; render(); }, 8000);
      return;
    }
    if (d.create !== undefined) {
      const k = key(+f("p").value, f("t").value), h = parseH(f("h").value), notes = f("n").value.trim();
      closePop();
      if (h === null && S.selected === today) { startTask(k); const r = running(); if (r) r.notes = notes; return render(); }
      S.entries.push({ id: S.idCount++, day: S.selected, k, secs: h || 0, notes, lock: null, order: S.idCount });
      return render();
    }
    if (d.suggest !== undefined) { const text = f("plan").value; S.pop.text = text; S.pop.props = plan(text); return renderPop(); }
    if (d.addplan !== undefined) {
      S.pop.props.forEach((x) => S.entries.push({ id: S.idCount++, day: S.selected, k: key(x.p, x.t), secs: x.s, notes: "", lock: null, order: S.idCount }));
      closePop(); return render();
    }
    if (d.nudges !== undefined) { S.nudges = !S.nudges; closePop(); return render(); }
    if (d.restore !== undefined) { S.hidden.clear(); closePop(); return render(); }
    if (d.reset !== undefined) { S = seed(); ask.value = ""; return render(); }
    if (d.quit !== undefined) { S.open = false; closePop(); return render(); }
  });
  root.addEventListener("input", (ev) => {
    if (ev.target.dataset.f === "h" && S.pop?.kind === "new" && S.selected === today) {
      const b = $("#dm-pops [data-create]"); if (b) b.textContent = ev.target.value.trim() ? "Save Entry" : "Start Timer";
    }
  });
  root.addEventListener("change", (ev) => {
    if (ev.target.dataset.f === "p") {
      const t = $('#dm-pops [data-f="t"]');
      t.innerHTML = P[+ev.target.value].tasks.map((x) => `<option>${esc(x)}</option>`).join("");
    }
  });
  root.addEventListener("contextmenu", (ev) => {
    const row = ev.target.closest("[data-entry]");
    if (!row) return;
    ev.preventDefault();
    const e = S.entries.find((x) => x.id === +row.dataset.entry);
    openPop("ctx", { id: e.id, anchor: row, x: ev.clientX, y: ev.clientY });
  });
  root.addEventListener("dblclick", (ev) => {
    const row = ev.target.closest("[data-entry]");
    if (!row || ev.target.closest("button")) return;
    const e = S.entries.find((x) => x.id === +row.dataset.entry);
    openPop(e.lock ? "lock" : "edit", { id: e.id, anchor: row.querySelector(".hrs") });
  });
  root.addEventListener("keydown", (ev) => {
    if (ev.key === "Escape" && S.pop) { ev.stopPropagation(); closePop(); }
    if (ev.key === "Enter" && (ev.metaKey || ev.ctrlKey) && S.pop?.kind === "plan") $("#dm-pops [data-suggest], #dm-pops [data-addplan]")?.click();
  });

  // Hover a name that doesn't fit and it slides across.
  root.addEventListener("mouseover", (ev) => {
    const host = ev.target.closest(".dm-tile, .dm-entry");
    if (!host || host.dataset.mq) return;
    host.dataset.mq = "1";
    host.querySelectorAll(".dm-mq").forEach((m) => {
      const over = m.firstElementChild.scrollWidth - m.clientWidth;
      if (over > 2 && !reduce) { m.style.setProperty("--shift", `${-(over + 16)}px`); m.style.setProperty("--dur", `${Math.max(1.6, over / 30)}s`); m.classList.add("go"); }
    });
    host.addEventListener("mouseleave", () => { delete host.dataset.mq; host.querySelectorAll(".dm-mq").forEach((m) => m.classList.remove("go")); }, { once: true });
  });

  // Drag a tile into Favorites, or within Favorites to reorder: later lands
  // after the tile you drop on, earlier lands before it.
  let drag = null, dragMoved = false;
  root.addEventListener("pointerdown", (ev) => {
    const el = ev.target.closest(".dm-tile");
    if (!el || ev.button !== 0 || ev.target.closest("button")) return;
    drag = { el, k: el.dataset.tile, x: ev.clientX, y: ev.clientY, moving: false };
    dragMoved = false;
    ev.preventDefault(); // no text selection or native drag in its place
  });
  root.addEventListener("dragstart", (ev) => ev.preventDefault());
  addEventListener("pointercancel", () => { if (drag) { drag.ghost?.remove(); $(".dm-dropline")?.remove(); drag.el.classList.remove("lift"); drag = null; } });
  addEventListener("pointermove", (ev) => {
    if (!drag) return;
    const win = $(".dm-win"), wr = win.getBoundingClientRect(), sc = wr.width / 420;
    if (!drag.moving) {
      if (Math.hypot(ev.clientX - drag.x, ev.clientY - drag.y) < 4) return;
      drag.moving = dragMoved = true;
      const r = drag.el.getBoundingClientRect();
      drag.gx = (drag.x - r.left) / sc; drag.gy = (drag.y - r.top) / sc;
      drag.ghost = drag.el.cloneNode(true);
      drag.ghost.classList.add("dm-ghost");
      drag.ghost.style.width = `${r.width / sc}px`;
      win.appendChild(drag.ghost);
      drag.el.classList.add("lift");
    }
    drag.ghost.style.left = `${(ev.clientX - wr.left) / sc - drag.gx}px`;
    drag.ghost.style.top = `${(ev.clientY - wr.top) / sc - drag.gy}px`;
    // Where it would land in Favorites
    const fav = $('[data-sec="fav"]'), line = $(".dm-dropline");
    line?.remove();
    drag.target = undefined;
    if (!fav) return;
    const fr = fav.getBoundingClientRect();
    if (ev.clientX < fr.left || ev.clientX > fr.right || ev.clientY < fr.top || ev.clientY > fr.bottom) return;
    const tiles = [...fav.querySelectorAll(".dm-tile")].filter((t) => t !== drag.el);
    let best = null, bd = Infinity;
    tiles.forEach((t) => { const r = t.getBoundingClientRect(), dd = Math.hypot(ev.clientX - (r.left + r.width / 2), ev.clientY - (r.top + r.height / 2)); if (dd < bd) { bd = dd; best = t; } });
    drag.target = best ? best.dataset.tile : null;
    if (best) {
      const r = best.getBoundingClientRect(), from = S.favorites.indexOf(drag.k), to = S.favorites.indexOf(drag.target);
      const after = from >= 0 && from < to;
      const l = document.createElement("div");
      l.className = "dm-dropline";
      l.style.left = `${((after ? r.right + 4 : r.left - 5) - wr.left) / sc}px`;
      l.style.top = `${(r.top - wr.top) / sc + 6}px`;
      l.style.height = `${r.height / sc - 12}px`;
      win.appendChild(l);
    }
  });
  addEventListener("pointerup", () => {
    if (!drag) return;
    const { moving, ghost, k, target } = drag;
    drag = null;
    ghost?.remove(); $(".dm-dropline")?.remove();
    if (!moving) return;
    if (target !== undefined) {
      const from = S.favorites.indexOf(k), to = target ? S.favorites.indexOf(target) : -1;
      if (from >= 0) S.favorites.splice(from, 1);
      if (target === null || to < 0) S.favorites.push(k);
      else { const idx = S.favorites.indexOf(target); S.favorites.splice(from >= 0 && from < to ? idx + 1 : idx, 0, k); }
    }
    render();
    setTimeout(() => { dragMoved = false; }, 0);
  });

  // Drag the window by its title bar, kept on the desk.
  const tb = $(".dm-tb"), winEl = $(".dm-win");
  tb.addEventListener("pointerdown", (ev) => {
    if (ev.target.closest("button, .lights")) return;
    const sc = winEl.getBoundingClientRect().width / 420, x0 = ev.clientX, y0 = ev.clientY, l0 = winEl.offsetLeft, t0 = winEl.offsetTop;
    tb.classList.add("grab");
    const move = (e) => {
      winEl.style.left = `${Math.max(-300, Math.min(1040 - 120, l0 + (e.clientX - x0) / sc))}px`;
      winEl.style.top = `${Math.max(26, Math.min(680 - 60, t0 + (e.clientY - y0) / sc))}px`;
    };
    const up = () => { tb.classList.remove("grab"); removeEventListener("pointermove", move); removeEventListener("pointerup", up); };
    addEventListener("pointermove", move); addEventListener("pointerup", up);
  });

  // Scale the whole desk to fit narrow screens.
  const fit = $(".dm-fit") || root.parentElement, desk = root;
  function scale() {
    const w = fit.clientWidth, s = Math.min(1, w / 1040);
    desk.style.transform = s < 1 ? `scale(${s})` : "";
    fit.style.height = `${680 * s}px`;
  }
  new ResizeObserver(scale).observe(fit);
  scale();
  render();
})();
