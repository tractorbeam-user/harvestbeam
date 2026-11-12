#!/usr/bin/env bash
# Renders the app's screens (the debug snapshots) and writes a gallery page,
# build/preview/index.html, to look through in a browser. Rerun after changes;
# the page reloads itself when the snapshots change.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="build/preview"
swift build -q
rm -rf "$OUT.new" && mkdir -p "$OUT.new"
.build/debug/HarvestBar --snapshots "$OUT.new" >/dev/null 2>&1
rm -rf "$OUT" && mv "$OUT.new" "$OUT"
STAMP="$(date +%s)"
{
cat <<HTML
<!doctype html><html><head><meta charset="utf-8"><title>Harvestbeam preview</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root{--bg:#f6f4f1;--fg:#222;--muted:#777;--card:#fff;--line:#e6e1da}
@media (prefers-color-scheme:dark){:root{--bg:#1c1b1a;--fg:#eee;--muted:#999;--card:#262524;--line:#3a3836}}
body{margin:0;background:var(--bg);color:var(--fg);font:14px -apple-system,system-ui,sans-serif}
header{position:sticky;top:0;background:var(--bg);border-bottom:1px solid var(--line);padding:12px 16px;display:flex;gap:12px;align-items:center;z-index:1}
h1{font-size:15px;margin:0}
.muted{color:var(--muted);font-size:12px}
label{font-size:12px;display:flex;gap:6px;align-items:center}
input[type=search]{flex:1;max-width:260px;padding:6px 10px;border-radius:8px;border:1px solid var(--line);background:var(--card);color:var(--fg)}
main{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:16px;padding:16px}
figure{margin:0;background:var(--card);border:1px solid var(--line);border-radius:12px;padding:10px}
figure img{width:100%;height:auto;border-radius:6px;display:block}
figcaption{font-size:12px;color:var(--muted);margin-top:6px;word-break:break-all}
</style></head><body>
<header><h1>Harvestbeam preview</h1><span class="muted">rendered $(date "+%b %-d, %-I:%M %p")</span>
<input type="search" id="q" placeholder="Filter (e.g. favorites, prefs)">
<label><input type="checkbox" id="dark"> Dark</label></header><main id="grid">
HTML
for f in $(ls "$OUT" | grep -- '-light.png$' | sort -V); do
  base="${f%-light.png}"
  echo "<figure data-name=\"$base\"><img loading=\"lazy\" data-base=\"$base\" src=\"$base-light.png?$STAMP\"><figcaption>$base</figcaption></figure>"
done
cat <<HTML
</main><script>
const stamp="$STAMP";
const q=document.getElementById('q'),dark=document.getElementById('dark');
try{q.value=localStorage.getItem('q')||'';dark.checked=localStorage.getItem('dark')==='1'}catch(e){}
function apply(){const t=q.value.toLowerCase();
 document.querySelectorAll('figure').forEach(f=>{f.style.display=f.dataset.name.includes(t)?'':'none'});
 document.querySelectorAll('img').forEach(i=>{i.src=i.dataset.base+(dark.checked?'-dark':'-light')+'.png?'+stamp});
 try{localStorage.setItem('q',q.value);localStorage.setItem('dark',dark.checked?'1':'0')}catch(e){}}
q.oninput=apply;dark.onchange=apply;apply();
// Reload when a newer render lands.
setInterval(()=>fetch('stamp.txt?'+Date.now()).then(r=>r.text()).then(s=>{if(s.trim()!==stamp)location.reload()}).catch(()=>{}),3000);
</script></body></html>
HTML
} > "$OUT/index.html"
echo "$STAMP" > "$OUT/stamp.txt"
echo "Preview: $(pwd)/$OUT/index.html"
