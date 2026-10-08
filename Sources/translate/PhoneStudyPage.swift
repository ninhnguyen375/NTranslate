// The single page the phone loads from `PhoneStudyServer`. Kept inline so the server has no
// resource bundle to find; the token rides in the page URL and is passed to every API call.
enum PhoneStudyPage {
    /// Home-screen install. No service worker: the page is served over plain HTTP on Tailscale,
    /// which iOS does not count as a secure context, so it only runs while the Mac is reachable.
    static let manifest = #"""
{"name":"NTranslate Study","short_name":"NTranslate","start_url":"/?t=__TOKEN__","scope":"/","display":"standalone",
 "background_color":"#f2f2f7","theme_color":"#0a84ff","icons":[{"src":"/icon.png?t=__TOKEN__","sizes":"512x512","type":"image/png","purpose":"any"}]}
"""#

    static let html = #"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="NTranslate">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="mobile-web-app-capable" content="yes">
<meta name="theme-color" content="#f2f2f7" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#000000" media="(prefers-color-scheme: dark)">
<link rel="manifest" href="/manifest.json?t=__TOKEN__">
<link rel="apple-touch-icon" href="/icon.png?t=__TOKEN__">
<link rel="icon" type="image/png" href="/icon.png?t=__TOKEN__">
<title>NTranslate Study</title>
<style>
:root { --bg:#f2f2f7; --card:#fff; --text:#1c1c1e; --muted:#6e6e73; --line:rgba(60,60,67,.14); --accent:#0a84ff; --accent-soft:rgba(10,132,255,.12); --again:#ff453a; --hard:#ff9f0a; --easy:#30b850; --me:#0a84ff; --me-text:#fff; --shadow:0 1px 2px rgba(0,0,0,.04), 0 4px 16px rgba(0,0,0,.06); --blur:rgba(242,242,247,.82); }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg:#000; --card:#1c1c1e; --text:#f5f5f7; --muted:#98989d; --line:rgba(84,84,88,.5); --accent-soft:rgba(10,132,255,.22); --me:#0a5fcc; --shadow:none; --blur:rgba(0,0,0,.78); color-scheme:dark; } }
:root[data-theme="dark"] { --bg:#000; --card:#1c1c1e; --text:#f5f5f7; --muted:#98989d; --line:rgba(84,84,88,.5); --accent-soft:rgba(10,132,255,.22); --me:#0a5fcc; --shadow:none; --blur:rgba(0,0,0,.78); color-scheme:dark; }
* { box-sizing:border-box; -webkit-tap-highlight-color:transparent; }
html, body { overflow-x:clip; touch-action:pan-x pan-y; }
/* iOS Safari ignores user-scalable=no; pan-only touch-action blocks pinch and double-tap zoom. */
body { margin:0; background:var(--bg); color:var(--text); font:17px/1.47 -apple-system, system-ui, sans-serif; -webkit-font-smoothing:antialiased; padding-bottom:calc(150px + env(safe-area-inset-bottom)); }
header { position:fixed; top:0; left:0; right:0; z-index:2; background:linear-gradient(#000 0 env(safe-area-inset-top), var(--blur) 0); -webkit-backdrop-filter:saturate(180%) blur(20px); backdrop-filter:saturate(180%) blur(20px); padding:calc(14px + env(safe-area-inset-top)) 16px 10px; display:flex; align-items:center; gap:8px; }
header h1 { transition:font-size .2s; font-size:28px; font-weight:700; letter-spacing:-.02em; margin:0; flex:1; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
header .icon + h1, header.compact h1 { font-size:19px; letter-spacing:0; }
#meta { background:var(--card); border-radius:999px; padding:3px 10px; font-variant-numeric:tabular-nums; }
#meta:empty { display:none; }
main { padding:4px 16px 0; max-width:640px; margin:0 auto; }
button { font:inherit; border:0; border-radius:12px; padding:13px 14px; background:var(--card); color:var(--text); cursor:pointer; transition:transform .18s cubic-bezier(.34,1.56,.64,1), opacity .15s, background-color .2s, color .2s, box-shadow .2s; display:inline-flex; align-items:center; justify-content:center; gap:6px; }
button:active { transform:scale(.93); opacity:.85; }
@keyframes pop { from { opacity:0; transform:scale(.85) translateY(10px); } }
.dock button, .grades button, .sbar button, .card .icon.round { animation:pop .38s cubic-bezier(.34,1.56,.64,1) backwards; }
.dock button:nth-child(2), .grades button:nth-child(2), .sbar button:nth-child(2) { animation-delay:.06s; }
.dock button:nth-child(3), .grades button:nth-child(3) { animation-delay:.12s; }
nav button svg { transition:transform .25s cubic-bezier(.34,1.56,.64,1); }
nav button.on svg { transform:scale(1.15) translateY(-1px); }
nav button:active svg { transform:scale(.82); }
.seg button, .list button, .pills button { transition:background-color .2s, color .2s, box-shadow .2s, transform .18s; }
.seg button:active, .pills button:active { transform:scale(.94); }
.sbar { position:fixed; left:16px; bottom:var(--sb, 80px); z-index:2; display:flex; flex-direction:column; gap:12px; }
.sbar button.icon { width:51px; height:51px; padding:0; border-radius:999px; background:color-mix(in srgb, var(--card) 45%, transparent); color:var(--accent); border:1px solid var(--line); box-shadow:0 4px 14px rgba(0,0,0,.16); }
.sbar button svg { width:24px; height:24px; }
@media (prefers-reduced-motion: reduce) { * { animation:none !important; transition:none !important; } }
button:disabled { opacity:.5; }
button svg { width:18px; height:18px; flex:none; }
.icon { background:none; padding:6px 8px; color:var(--accent); font-size:17px; }
.icon.round { background:var(--accent-soft); border-radius:999px; width:40px; height:40px; padding:0; vertical-align:middle; }
.muted { color:var(--muted); font-size:14px; }
.card { background:var(--card); border-radius:20px; padding:24px 18px; margin:8px 0 12px; box-shadow:var(--shadow); }
.term { font-size:32px; font-weight:700; letter-spacing:-.02em; text-align:center; display:flex; align-items:center; justify-content:center; gap:12px; flex-wrap:wrap; }
.context { color:var(--muted); font-size:15px; margin-top:14px; max-height:6.5em; overflow:auto; text-align:center; font-style:italic; }
.back { white-space:pre-wrap; font-size:16px; border-top:1px solid var(--line); margin-top:18px; padding-top:18px; animation:fade .2s ease; }
@keyframes fade { from { opacity:0; transform:translateY(4px); } }
.progress { height:4px; background:var(--line); border-radius:2px; overflow:hidden; margin:2px 0 10px; }
.progress div { height:100%; background:var(--accent); transition:width .3s; }
.dock { position:fixed; left:0; right:0; z-index:2; bottom:max(calc(max(8px, env(safe-area-inset-bottom) - 12px) + 84px), var(--kb, 0px)); padding:10px 16px; display:flex; flex-direction:column; gap:8px; background:var(--blur); -webkit-backdrop-filter:blur(20px); backdrop-filter:blur(20px); }
.dock .row { margin:0; }
.dock button { width:100%; }
.tap-hint { text-align:center; margin-top:14px; }
.toast { position:fixed; left:50%; transform:translateX(-50%); z-index:7; display:flex; align-items:center; gap:10px; padding:6px 6px 6px 16px; border-radius:14px; background:var(--text); color:var(--bg); font-size:15px; box-shadow:0 6px 20px rgba(0,0,0,.25); width:max-content; max-width:calc(100% - 32px); }
.toast button { background:none; color:var(--accent); font-weight:600; min-height:40px; padding:8px 12px; }
.toast button:empty { display:none; }
#kbProxy { position:fixed; top:0; left:0; width:1px; height:1px; opacity:0; font-size:16px; border:0; padding:0; }
.grades { display:grid; grid-template-columns:repeat(3,1fr); gap:10px; position:fixed; left:0; right:0; bottom:calc(max(8px, env(safe-area-inset-bottom) - 12px) + 84px); padding:10px 16px; background:var(--blur); -webkit-backdrop-filter:blur(20px); backdrop-filter:blur(20px); }
.grades button { color:#fff; font-weight:600; padding:15px 8px; border-radius:14px; }
.reveal, .primary { width:100%; background:var(--accent); color:#fff; font-weight:600; }
.done-state { text-align:center; padding:40px 18px; }
.done-state svg { width:56px; height:56px; color:var(--easy); }
.list { background:var(--card); border-radius:16px; overflow:hidden; box-shadow:var(--shadow); }
.list button { display:flex; flex-direction:column; align-items:flex-start; width:100%; text-align:left; margin:0; border-radius:0; padding:13px 34px 13px 16px; position:relative; border-bottom:1px solid var(--line); }
.list button:last-child { border-bottom:0; }
.list button::after { content:''; position:absolute; right:16px; top:50%; width:8px; height:8px; border:solid var(--muted); border-width:2px 2px 0 0; transform:translateY(-50%) rotate(45deg); opacity:.6; }
.list button:active { transform:none; background:var(--line); }
.list .done { color:var(--muted); }
select { font:inherit; padding:11px 12px; border-radius:12px; border:0; background:var(--card); color:var(--text); width:100%; margin:4px 0 12px; box-shadow:var(--shadow); -webkit-appearance:none; appearance:none; background-image:linear-gradient(45deg,transparent 50%,var(--muted) 50%),linear-gradient(135deg,var(--muted) 50%,transparent 50%); background-position:calc(100% - 20px) 50%,calc(100% - 15px) 50%; background-size:5px 5px; background-repeat:no-repeat; }
.turn { display:flex; margin:10px 0; }
.turn.b { justify-content:flex-end; }
.bubble { max-width:84%; background:var(--card); border-radius:20px 20px 20px 6px; padding:10px 14px; box-shadow:var(--shadow); transition:box-shadow .2s; }
.turn.b .bubble { background:var(--me); color:var(--me-text); border-radius:20px 20px 6px 20px; }
.bubble .who { font-size:12px; font-weight:600; color:var(--muted); text-transform:uppercase; letter-spacing:.04em; }
.bubble .tr { margin-top:6px; padding-top:6px; border-top:1px solid var(--line); }
.turn.b .bubble .tr { border-color:rgba(255,255,255,.25); }
.hide-tr .tr { display:none; }
.bubble.playing { box-shadow:0 0 0 3px var(--hard); }
nav { position:fixed; left:12px; right:12px; bottom:max(8px, calc(env(safe-area-inset-bottom) - 12px)); z-index:3; display:grid; grid-template-columns:1fr 1fr 1fr; background:var(--blur); -webkit-backdrop-filter:saturate(180%) blur(20px); backdrop-filter:saturate(180%) blur(20px); border:1px solid var(--line); border-radius:28px; padding:5px; box-shadow:0 6px 20px rgba(0,0,0,.12); }
nav button { background:none; border-radius:22px; padding:8px 2px; color:var(--muted); font-size:12.5px; font-weight:650; flex-direction:column; gap:2px; }
nav button svg { width:24px; height:24px; }
nav button.on { background:var(--card); color:var(--accent); font-weight:700; box-shadow:0 1px 6px rgba(0,0,0,.14); }
nav button:active { transform:none; }
.hidden { display:none !important; }
#install { position:fixed; left:12px; right:12px; bottom:calc(62px + env(safe-area-inset-bottom)); z-index:4; background:var(--card); border-radius:20px; padding:16px 16px 14px; box-shadow:0 0 0 100vmax rgba(0,0,0,.45), 0 8px 30px rgba(0,0,0,.25); }
#install h2 { font-size:17px; margin:0 32px 4px 0; }
#install ol { margin:8px 0 0; padding-left:22px; font-size:15px; line-height:1.5; }
#install li + li { margin-top:4px; }
#install .x { position:absolute; top:10px; right:10px; width:32px; height:32px; padding:0; border-radius:999px; background:var(--bg); color:var(--muted); justify-content:center; }
textarea { font:inherit; width:100%; min-height:130px; border-radius:16px; border:0; background:var(--card); color:var(--text); padding:14px; resize:vertical; box-shadow:var(--shadow); outline:none; }
textarea:focus { box-shadow:0 0 0 3px var(--accent-soft); }
.row { display:flex; gap:10px; margin:12px 0; }
.row > * { flex:1; }
.seg { display:flex; background:var(--line); border-radius:10px; padding:2px; margin-bottom:4px; }
.seg button { flex:1; padding:8px; border-radius:8px; background:none; font-size:15px; }
.seg button.on { background:var(--card); font-weight:600; box-shadow:0 1px 3px rgba(0,0,0,.12); }
.seg button:active { transform:none; }
.sec { margin:18px 0 0; }
.sec h3 { font-size:11px; font-weight:700; letter-spacing:.08em; color:var(--muted); margin:0 0 7px; text-transform:uppercase; }
.box { background:var(--bg); border-radius:12px; padding:10px 12px; }
.card .box { background:var(--bg); }
.mean { display:flex; gap:8px; align-items:baseline; margin:3px 0; }
.pos { font:600 12px ui-monospace, Menlo, monospace; color:var(--accent); flex:none; }
.hero { display:flex; align-items:center; gap:10px; flex-wrap:wrap; }
.hero .hw { font-size:28px; font-weight:700; letter-spacing:-.02em; }
.ipa { font:14px ui-monospace, Menlo, monospace; color:var(--muted); }
.spbar { position:sticky; bottom:0; display:flex; flex-direction:column; align-items:flex-start; gap:12px; padding:10px 0; pointer-events:none; }
.spbar button, .sbar button { pointer-events:auto; }
.spbar button.icon { width:51px; height:51px; padding:0; border-radius:999px; background:color-mix(in srgb, var(--card) 45%, transparent); color:var(--accent); border:1px solid var(--line); box-shadow:0 4px 14px rgba(0,0,0,.16); animation:pop .38s cubic-bezier(.34,1.56,.64,1) backwards; }
.spbar button svg { width:24px; height:24px; }
.chips { display:flex; flex-wrap:wrap; gap:6px; }
.chip { background:var(--accent-soft); color:var(--text); border-radius:999px; padding:5px 11px; font-size:14px; }
.chip i { color:var(--muted); font-style:normal; font-size:13px; }
.pills { display:flex; gap:6px; margin-bottom:8px; overflow-x:auto; }
.pills button { padding:5px 12px; border-radius:999px; font-size:13px; background:var(--bg); color:var(--muted); }
.pills button.on { background:var(--accent); color:#fff; font-weight:600; }
.ex { padding:9px 0; border-top:1px solid var(--line); }
.ex:first-child { border-top:0; padding-top:0; }
.ex:last-child { padding-bottom:0; }
.ex .lv { font-size:10px; font-weight:700; letter-spacing:.06em; color:var(--muted); margin-right:6px; }
.ex .vi { color:var(--muted); font-size:14px; margin-top:3px; }
.ex b, .bubble b { color:var(--accent); }
.turn.b .bubble b { color:#fff; text-decoration:underline; }
.conf { display:grid; grid-template-columns:1fr 1fr; gap:8px; margin-bottom:8px; }
.conf > div { background:var(--bg); border-radius:12px; padding:10px; border-top:3px solid var(--accent); font-size:14px; }
.conf > div + div { border-top-color:var(--again); }
.conf strong { display:block; font-size:16px; }
.conf .s { color:var(--muted); margin-top:4px; font-style:italic; }
.col { display:flex; flex-direction:column; gap:3px; padding:10px 0; border-top:1px solid var(--line); font-size:15px; }
.col:first-child { border-top:0; padding-top:0; }
.col:last-child { padding-bottom:0; }
.col span:first-child { font-weight:600; }
.col span:last-child { color:var(--muted); font-size:14px; line-height:1.45; }
.col span:last-child:empty { display:none; }
.cloze { background:var(--accent-soft); border-radius:12px; padding:12px; }
.cloze input { font:inherit; flex:1; min-width:0; padding:9px 11px; border-radius:10px; border:1px solid var(--line); background:var(--card); color:var(--text); }
.cloze .fb { font-size:14px; margin-top:6px; min-height:1em; }
.imgs { display:grid; grid-template-columns:1fr 1fr; gap:6px; margin:4px 0 10px; }
.imgs:empty { display:none; }
.imgs a { display:block; aspect-ratio:4/3; border-radius:12px; overflow:hidden; background:var(--bg); }
.imgs img { width:100%; height:100%; object-fit:cover; display:block; }
.small { padding:7px 10px; font-size:14px; border-radius:10px; background:var(--accent-soft); color:var(--accent); }
.small.danger { color:var(--again); background:rgba(255,69,58,.12); }
.small.ok { color:var(--easy); background:rgba(48,184,80,.14); }
.prow { background:var(--card); border-bottom:1px solid var(--line); padding:12px 16px; }
.prow:last-child { border-bottom:0; }
.prow .t { font-weight:600; }
.prow.isdone .t { color:var(--easy); }
.pwrap { position:relative; overflow:hidden; border-bottom:1px solid var(--line); }
.pwrap:last-child { border-bottom:0; }
.pwrap .prow { position:relative; z-index:1; border-bottom:0; touch-action:pan-y; transition:transform .25s; }
.pacts { position:absolute; top:0; right:0; bottom:0; display:flex; }
.pacts button { width:72px; border-radius:0; flex-direction:column; gap:3px; font-size:12px; font-weight:600; color:#fff; padding:0; }
.pacts .ok { background:var(--easy); }
.pacts .rs { background:#8e8e93; }
.pacts .danger { background:var(--again); }
.prow .dot { width:9px; height:9px; border-radius:50%; background:var(--accent); flex:none; align-self:center; }
.plist { border-radius:16px; overflow:hidden; box-shadow:var(--shadow); }
.bubble .tools { display:flex; gap:8px; margin-top:8px; }
.bubble .tools button { padding:8px 14px; border-radius:12px; font-size:15px; background:rgba(127,127,127,.15); color:inherit; }
.bubble .tools svg { width:20px; height:20px; }
.turn.b .bubble .tools button { background:rgba(255,255,255,.18); }
.bubble .src, .bubble .tr { font-size:16px; color:inherit; }
/* text-shadow blur instead of filter: iOS Safari smears a filtered layer into a colored streak past the bubble edge. */
.blur { cursor:pointer; user-select:none; -webkit-user-select:none; }
.blur, .blur * { color:transparent !important; text-shadow:0 0 9px var(--text); }
.turn.b .blur, .turn.b .blur * { text-shadow:0 0 9px var(--me-text); }
.week { display:flex; align-items:flex-end; gap:6px; height:70px; }
.week div { flex:1; display:flex; flex-direction:column; align-items:center; justify-content:flex-end; height:100%; font-size:11px; color:var(--muted); gap:3px; }
.week i { display:block; width:100%; background:var(--accent); border-radius:4px; min-height:3px; }
.week div:last-child i { background:var(--easy); }
.stack { display:flex; height:10px; border-radius:5px; overflow:hidden; background:var(--bg); margin:4px 0 10px; }
.bk { display:flex; align-items:center; gap:8px; padding:6px 0; border-top:1px solid var(--line); font-size:15px; }
.bk:first-of-type { border-top:0; }
.bk .dot { width:10px; height:10px; border-radius:50%; flex:none; }
.bk .c { margin-left:auto; font-weight:600; font-variant-numeric:tabular-nums; }
#theme { margin-left:4px; }
.prompt { font-size:19px; text-align:center; white-space:pre-wrap; }
.qkind { text-align:center; margin-bottom:10px; }
.answer { display:flex; gap:8px; margin-top:16px; }
.answer input { font:inherit; flex:1; min-width:0; padding:12px 14px; border-radius:12px; border:1px solid var(--line); background:var(--bg); color:var(--text); }
.choices { display:grid; grid-template-columns:1fr 1fr; gap:8px; }
.choices button { background:var(--card); font-weight:600; box-shadow:inset 0 0 0 1px var(--line); }
.choices button.right { background:var(--easy); color:#fff; }
.choices button.wrong { background:var(--again); color:#fff; }
.qfb { text-align:center; margin-top:12px; font-weight:600; }
.grades button.suggest { box-shadow:0 0 0 3px var(--text); }
button.tinted { background:var(--accent-soft); color:var(--accent); font-weight:600; }
button.green { background:rgba(48,184,80,.15); color:var(--easy); font-weight:600; }
button.orange { background:rgba(255,159,10,.15); color:var(--hard); font-weight:600; }
button.gray { background:rgba(142,142,147,.16); color:var(--text); font-weight:600; }
button { min-height:44px; }
.icon, .small, .chip, .pills button, .seg button, .bubble .tools button, nav button { min-height:0; }
.primary, .reveal { box-shadow:0 4px 14px rgba(10,132,255,.3); }
#group { flex-wrap:wrap; margin-bottom:12px; }
#group button { background:var(--card); color:var(--text); padding:8px 14px; font-size:14px; }
#group button.on { background:var(--accent); color:#fff; }
.qchips { display:grid; grid-template-columns:repeat(4,1fr); gap:6px; margin-top:8px; }
.qchips button { min-height:38px; padding:6px 4px; border-radius:10px; font-size:14px; background:var(--bg); color:var(--text); }
.qchips button.on { background:var(--accent); color:#fff; font-weight:600; }
.qdetail { font-size:13px; margin:8px 0 0; }
.dash { display:grid; gap:12px; }
.dash .due { display:flex; align-items:center; justify-content:space-between; gap:12px; padding:16px; border-radius:14px; color:#fff; background:linear-gradient(135deg, var(--accent), color-mix(in srgb, var(--accent) 60%, #5e5ce6)); }
.dash .due .n { font-size:44px; font-weight:700; letter-spacing:-.03em; line-height:1; font-variant-numeric:tabular-nums; }
.dash .due .l { font-size:13px; font-weight:600; opacity:.85; text-transform:uppercase; letter-spacing:.06em; }
.dash .due svg { width:40px; height:40px; opacity:.35; flex:none; }
.dash .dkpi { display:grid; grid-template-columns:repeat(3,1fr); gap:8px; }
.dash .dkpi div { display:flex; flex-direction:column; align-items:center; gap:2px; padding:10px 4px; border-radius:12px; background:var(--bg); }
.dash .dkpi b { font-size:20px; line-height:1.2; font-variant-numeric:tabular-nums; }
.dash .dkpi span { font-size:12px; color:var(--muted); }
.prow { display:flex; gap:12px; }
.prow .lead { width:38px; height:38px; border-radius:11px; flex:none; display:flex; align-items:center; justify-content:center; background:var(--accent-soft); color:var(--accent); }
.prow.isdone .lead { background:rgba(48,184,80,.15); color:var(--easy); }
.prow .lead svg { width:20px; height:20px; }
.prow .body { flex:1; min-width:0; }
.small svg { width:15px; height:15px; }
.grades button svg { width:20px; height:20px; }
nav button.on svg { stroke-width:2.3; }
nav button svg { padding:2px 8px; width:40px; height:28px; }
.lvtag { display:inline-block; font-size:11px; font-weight:700; letter-spacing:.06em; color:var(--accent); background:var(--accent-soft); border-radius:6px; padding:2px 7px; }
.scene { font-size:14px; color:var(--muted); margin:0 0 8px; }
input.text { font:inherit; width:100%; padding:12px 14px; border-radius:12px; border:0; background:var(--card); color:var(--text); box-shadow:var(--shadow); margin-bottom:10px; }
label.lb { display:block; font-size:13px; color:var(--muted); margin:8px 0 4px; }
.small, .seg button { min-height:44px; }
.bubble .tools button { min-height:44px; min-width:48px; }
.chip, .pills button { min-height:40px; }
nav { grid-template-columns:repeat(4,1fr); }
.hrow { display:block; width:100%; text-align:left; background:var(--card); border-radius:0; border-bottom:1px solid var(--line); padding:12px 16px; }
.hrow:last-child { border-bottom:0; }
.hrow:active { transform:none; background:var(--line); }
.hrow .s { font-weight:600; display:-webkit-box; -webkit-line-clamp:2; -webkit-box-orient:vertical; overflow:hidden; }
.hrow .r { color:var(--muted); font-size:15px; display:-webkit-box; -webkit-line-clamp:2; -webkit-box-orient:vertical; overflow:hidden; }
.hrow .d { font-size:12px; color:var(--muted); margin-top:4px; }
.qa { margin-top:12px; }
.scrim { position:fixed; inset:0; z-index:5; background:rgba(0,0,0,.35); opacity:0; pointer-events:none; transition:opacity .25s; }
.scrim.open { opacity:1; pointer-events:auto; animation:scrim-in .25s ease; }
@keyframes scrim-in { from { opacity:0; } }
.drawer { position:fixed; left:0; right:0; bottom:0; z-index:6; max-height:88vh; max-height:88dvh; display:flex; flex-direction:column; background:var(--bg); border-radius:20px 20px 0 0; padding:0 16px; transform:translateY(105%); transition:transform .28s cubic-bezier(.2,.8,.2,1); box-shadow:0 -8px 30px rgba(0,0,0,.18); }
.drawer.open { transform:none; }
/* Lock the page behind an open drawer; grab, header and scrim never pan, only drawerBody scrolls. */
html:has(.drawer.open), html:has(.drawer.open) body { overflow:hidden; }
.scrim, .drawer .grab, .dhead { touch-action:none; }
.drawer .grab { width:36px; height:5px; border-radius:3px; background:var(--line); margin:8px auto 4px; }
.dhead { display:flex; align-items:center; justify-content:space-between; gap:8px; padding:4px 0 8px; }
#drawerBody { flex:1; min-height:0; overflow-y:auto; touch-action:pan-y; -webkit-overflow-scrolling:touch; margin:0 -16px; padding:0 16px calc(24px + env(safe-area-inset-bottom)); }
.dhead b { flex:1; }
.hrow-wrap { display:flex; align-items:flex-start; background:var(--card); border-bottom:1px solid var(--line); }
.hrow-wrap:last-child { border-bottom:0; }
.hrow-wrap .hrow { flex:1; min-width:0; border-bottom:0; padding-right:4px; }
.hdel { background:none; color:var(--muted); opacity:.55; padding:12px 14px 12px 6px; min-height:0; }
.hdel svg { width:18px; height:18px; }
.hdel:active { opacity:1; color:var(--again); transform:none; }
.dhead b { font-size:19px; }
@media (min-width:700px) { .drawer { max-width:640px; margin:0 auto; } }
.selbar { position:fixed; left:50%; transform:translateX(-50%); bottom:calc(146px + env(safe-area-inset-bottom)); z-index:4; display:flex; gap:6px; padding:6px; border-radius:999px; background:var(--text); box-shadow:0 6px 20px rgba(0,0,0,.25); }
.selbar button { background:none; color:var(--bg); font-weight:600; padding:8px 14px; border-radius:999px; min-height:40px; }
.selbar button + button { border-left:1px solid rgba(127,127,127,.4); border-radius:0 999px 999px 0; }
.qa .q { font-weight:600; margin-top:12px; }
.qa .a { white-space:pre-wrap; margin-top:4px; }
/* Translate drawer: flat white sheet, no nested cards; Ask input sticks to the bottom. */
.drawer { background:var(--card); }
.lbar { display:flex; align-items:center; justify-content:space-between; gap:4px; margin:10px 0 2px; }
.lbar select { flex:0 1 auto; font-size:15px; font-weight:600; color:var(--accent); }
.lbar select { width:auto; margin:0; padding:6px 28px 6px 10px; box-shadow:none; outline:none; border-radius:8px; background:transparent url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%230a84ff' stroke-width='3' stroke-linecap='round'%3E%3Cpath d='m6 9 6 6 6-6'/%3E%3C/svg%3E") no-repeat right 10px center / 12px; }
.lbar select:first-child { margin-left:-10px; }
.lbar select:last-child { margin-right:-10px; }
.lbar select:focus-visible { background-color:var(--accent-soft); }
.lbar select:last-child { text-align:right; text-align-last:right; }
.lbar select:disabled { opacity:.5; }
#drawer textarea { background:none; box-shadow:none; border-radius:0; border-bottom:1px solid var(--line); padding:8px 0; min-height:90px; font-size:20px; resize:none; }
#drawer textarea:focus { box-shadow:none; border-bottom-color:var(--accent); }
.irow { display:flex; align-items:center; justify-content:space-between; margin:8px 0 4px; }
.irow .primary { width:auto; padding:9px 18px; }
#drawer .card { background:none; box-shadow:none; padding:0; border-radius:0; margin:12px 0 0; }
#drawer .box { background:none; padding:0; }
.rlang { font-size:11px; font-weight:700; letter-spacing:.08em; color:var(--muted); text-transform:uppercase; }
.rtext { display:flex; align-items:flex-start; gap:8px; }
.rtext div { flex:1; white-space:pre-wrap; font-size:24px; font-weight:600; line-height:1.3; }
#drawer .qa, #drawer .qa .sec { display:contents; }
#drawer .qa h3 { display:none; }
#drawer .qa .answer { position:sticky; bottom:calc(-24px - env(safe-area-inset-bottom)); background:var(--card); margin:16px -16px 0; padding:10px 16px calc(10px + env(safe-area-inset-bottom)); border-top:1px solid var(--line); }
#drawer .qa .answer input { border-radius:999px; }
#drawer .qa .answer button { border-radius:999px; width:44px !important; height:44px; flex:none; padding:0; }
</style>
</head>
<body>
<header><button id="back" class="icon hidden" aria-label="Back">&lsaquo; Back</button><h1 id="title">Review</h1><span id="meta" class="muted"></span><button id="installOpen" class="icon round hidden" aria-label="Install on Home Screen"><svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="4" width="16" height="16" rx="4"/><path d="M12 8v8M8 12h8"/></svg></button><button id="theme" class="icon round" aria-label="Toggle dark mode"></button></header>
<main id="view"></main>
<div id="selbar" class="selbar hidden"><button data-sel="learn"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3l1.8 4.7L18.5 9.5 13.8 11.3 12 16l-1.8-4.7L5.5 9.5l4.7-1.8z"/></svg>Learn</button><button data-sel="translate"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 5h8M8 3v2M10 5c-1 4-3.5 7-6 8.5M6 9c1.2 2 3 3.5 5 4.5"/><path d="M13 21l4-9 4 9M14.5 18h5"/></svg>Translate</button></div>
<div id="scrim" class="scrim"></div>
<div id="drawer" class="drawer" role="dialog" aria-label="Translate"><div class="grab"></div><div class="dhead"><b>Translate</b><button id="drawerMark" class="icon round hidden" aria-label="Bookmark"></button><button id="drawerClose" class="icon round" aria-label="Close"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M6 6l12 12M18 6 6 18"/></svg></button></div><div id="drawerBody"></div></div>
<div id="dock" class="dock hidden"></div>
<div id="sbar" class="sbar hidden"></div>
<div id="toast" class="toast hidden"></div>
<input id="kbProxy" aria-hidden="true" tabindex="-1">
<div id="grades" class="grades hidden">
  <button style="background:var(--again)" data-g="0"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5"/></svg>Again</button>
  <button style="background:var(--hard)" data-g="1"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><path d="M5 12h14"/></svg>Hard</button>
  <button style="background:var(--easy)" data-g="2"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><path d="m5 12 5 5L20 7"/></svg>Easy</button>
  <button id="autoGrade" class="hidden" style="grid-column:1/-1;padding:17px 8px"></button>
</div>
<div id="install" class="hidden"><button class="x" id="installClose" aria-label="Close"><svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg></button><h2>Install on Home Screen</h2><div class="muted">Open the app like a native one, full screen.</div><ol><li>Tap the page menu button on the left of the address bar, then tap <b>Share</b>.</li><li>Scroll down and tap <b>Add to Home Screen</b>.</li><li>Keep <b>Open as Web App</b> on, then tap <b>Add</b>.</li></ol></div>
<nav><button id="openTranslate"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 5h8M8 3v2M10 5c-1 4-3.5 7-6 8.5M6 9c1.2 2 3 3.5 5 4.5"/><path d="M13 21l4-9 4 9M14.5 18h5"/></svg>Translate</button><button id="tabReview" class="on"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="6" width="14" height="14" rx="2"/><path d="M7 3h12a2 2 0 0 1 2 2v12"/></svg>Study</button><button id="tabDialogues"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.6A8 8 0 1 1 21 12z"/></svg>Dialogues</button><button id="tabHistory"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>History</button></nav>
<script>
const token = new URLSearchParams(location.search).get('t') || '';
const $ = id => document.getElementById(id);
const api = (path, opts) => fetch(path + (path.includes('?') ? '&' : '?') + 't=' + token, opts)
  .then(async r => { if (!r.ok) throw new Error((await r.text()) || r.status); return r; });
// The app may ship a newer page while this tab stays open; offer a reload instead of serving stale UI.
const checkVersion = () => api('/version').then(r => r.text()).then(v => { if (v !== '__VERSION__') toast('New version available', 'Reload', () => location.reload(), 0); }).catch(() => {});
document.addEventListener('visibilitychange', () => { if (!document.hidden) checkVersion(); });
setInterval(checkVersion, 60000);
// Any write may change what the lists show, so the read cache starts over.
const post = (path, body) => { cache.clear(); return api(path, { method:'POST', body: JSON.stringify(body) }); };
// Stale-while-revalidate: paint the last response at once, then repaint if the Mac sends something newer.
// navSeq moves on every screen change so a late response never paints over another screen.
const cache = new Map();
let navSeq = 0;
// quiet: the caller keeps its own controls on screen, so no Loading placeholder.
async function swr(path, render, quiet) {
  const seq = navSeq, hit = cache.get(path);
  let slow;
  if (hit) render(JSON.parse(hit));
  else if (!quiet) slow = setTimeout(() => { if (seq === navSeq) $('view').innerHTML = '<p class="muted">Loading…</p>'; }, 200);
  try {
    const text = await api(path).then(r => r.text());
    cache.set(path, text);
    if (text !== hit && seq === navSeq) render(JSON.parse(text));
  } catch (err) { if (!hit) throw err; }
  finally { clearTimeout(slow); }
}
const esc = s => (s || '').replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const reEsc = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
// Bolds every listed word (and its simple inflections) inside already-escaped text.
const mark = (html, words) => {
  const list = (words || []).map(w => (w || '').trim()).filter(Boolean);
  if (!list.length) return html;
  return html.replace(new RegExp('\\b(' + list.map(reEsc).join('|') + ')(s|es|ed|d|ing)?\\b', 'gi'), '<b>$&</b>');
};
const player = new Audio();
const svg = d => '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + d + '</svg>';
const SPEAKER = svg('<path d="M11 5 6 9H3v6h3l5 4V5z"/><path d="M15.5 8.5a5 5 0 0 1 0 7M18.5 5.5a9 9 0 0 1 0 13"/>');
const SLOW = svg('<path d="M4 15c0-4 3-7 7-7s7 3 7 7H4z"/><path d="M18 13h2a2 2 0 0 0 0-4h-1M7 15v3M15 15v3"/>');
const IC = {
  swap: svg('<path d="M7 4v16M3 16l4 4 4-4M17 20V4M13 8l4-4 4 4"/>'),
  play: svg('<path d="M7 4v16l13-8z"/>'),
  shuffle: svg('<path d="M16 3h5v5M4 20 21 3M21 16v5h-5M15 15l6 6M4 4l5 5"/>'),
  sparkles: svg('<path d="M12 3l1.8 4.7L18.5 9.5 13.8 11.3 12 16l-1.8-4.7L5.5 9.5l4.7-1.8z"/><path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z"/>'),
  plus: svg('<path d="M12 5v14M5 12h14"/>'),
  check: svg('<path d="m5 12 5 5L20 7"/>'),
  x: svg('<path d="M6 6l12 12M18 6 6 18"/>'),
  trash: svg('<path d="M4 7h16M10 11v6M14 11v6M5 7l1 13h12l1-13M9 7V4h6v3"/>'),
  reset: svg('<path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5"/>'),
  eye: svg('<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>'),
  skip: svg('<path d="M5 5l8 7-8 7zM15 5v14"/>'),
  next: svg('<path d="M5 12h14M13 6l6 6-6 6"/>'),
  undo: svg('<path d="M9 14 4 9l5-5"/><path d="M4 9h11a5 5 0 0 1 0 10h-3"/>'),
  bookmark: svg('<path d="M6 3h12v18l-6-4-6 4z"/>'),
  wand: svg('<path d="M15 4V2M15 10V8M11 6h2M17 6h2M3 21l12-12"/>'),
  chat: svg('<path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.6A8 8 0 1 1 21 12z"/>'),
};
const CHECK = svg('<circle cx="12" cy="12" r="10"/><path d="m8 12 3 3 5-6"/>');
const STOP = svg('<rect x="6" y="6" width="12" height="12" rx="2"/>');
// Dark/light toggle; with nothing stored the page follows the phone setting.
const SUN = svg('<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>');
const MOON = svg('<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/>');
const store = { get: k => { try { return localStorage.getItem(k); } catch (e) { return null; } }, set: (k, v) => { try { localStorage.setItem(k, v); } catch (e) {} } };
// ponytail: iOS-only guide; the steps match Safari, other browsers just never see it.
(() => {
  const installed = navigator.standalone || matchMedia('(display-mode: standalone)').matches;
  if (installed || !/iPhone|iPad|iPod/.test(navigator.userAgent)) return;
  const box = document.getElementById('install'), open = document.getElementById('installOpen');
  const show = on => { box.classList.toggle('hidden', !on); open.classList.toggle('hidden', on); };
  show(!store.get('installDismissed'));
  document.getElementById('installClose').onclick = () => { show(false); store.set('installDismissed', '1'); };
  open.onclick = () => show(true);
})();

const isDark = () => (document.documentElement.dataset.theme || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light')) === 'dark';
function applyTheme(t) { if (t) document.documentElement.dataset.theme = t; $('theme').innerHTML = isDark() ? SUN : MOON; }
applyTheme(store.get('theme'));
$('theme').onclick = () => { const t = isDark() ? 'light' : 'dark'; store.set('theme', t); applyTheme(t); };
let state = { tab:'review', cards:[], index:0, done:0, filter: store.get('dialogueGroup') || '' };

function play(text, id, lang, slow) {
  const q = 'text=' + encodeURIComponent(text) + (id ? '&id=' + id : '') + (lang ? '&lang=' + encodeURIComponent(lang) : '');
  return new Promise(resolve => {
    player.src = '/api/audio?' + q + '&t=' + token;
    player.playbackRate = slow ? 0.7 : 1;
    player.onended = player.onerror = resolve;
    player.play().catch(resolve);
  });
}

// Set after setHeader by screens mid-lesson; Back and tab switches ask before leaving.
let leaveMsg = null;
const leaveOk = () => !leaveMsg || confirm(leaveMsg);
function setHeader(title, meta, back) {
  navSeq++; leaveMsg = null;
  $('title').textContent = title; $('meta').textContent = meta || '';
  $('back').classList.toggle('hidden', !back);
  $('back').onclick = back ? () => { if (leaveOk()) back(); } : null;
  $('grades').classList.add('hidden');
  $('sbar').classList.add('hidden');
  setDock('');
}

// Bottom bar for each screen's main actions, so they sit under the thumb.
function setSpeak(html) {
  $('sbar').innerHTML = html || '';
  $('sbar').classList.toggle('hidden', !html);
  pad();
}
const SPK = '<button class="icon round" id="say" aria-label="Speak">' + SPEAKER + '</button><button class="icon round" id="saySlow" aria-label="Speak slowly">' + SLOW + '</button>';
function setDock(html) {
  $('dock').innerHTML = html;
  $('dock').classList.toggle('hidden', !html);
  pad();
}
// Keeps the end of the page clear of whichever bottom bar is showing.
function pad() {
  const bar = [$('dock'), $('grades')].find(b => !b.classList.contains('hidden'));
  $('view').style.paddingBottom = bar ? bar.offsetHeight + 'px' : '';
  const nav = 'calc(max(8px, env(safe-area-inset-bottom) - 12px) + 84px)';
  const base = bar === $('dock') ? 'max(' + nav + ', var(--kb, 0px))' : nav;
  document.documentElement.style.setProperty('--sb', 'calc(' + base + ' + ' + (bar ? bar.offsetHeight : 0) + 'px + 10px)');
  return bar ? bar.offsetHeight : 0;
}

let toastTimer;
// ms 0 keeps the toast up until something replaces it.
function toast(msg, label, action, ms) {
  const t = $('toast'); clearTimeout(toastTimer);
  t.innerHTML = '<span>' + esc(msg) + '</span><button>' + (label || '') + '</button>';
  t.querySelector('button').onclick = () => { t.classList.add('hidden'); action && action(); };
  t.style.bottom = 'calc(' + (pad() + 76) + 'px + env(safe-area-inset-bottom))';
  t.classList.remove('hidden');
  if (ms !== 0) toastTimer = setTimeout(() => t.classList.add('hidden'), ms || 3000);
}
const fail = err => toast('Failed: ' + err.message);
// Deletes wait out an Undo window instead of asking first; ids in `pending` stay hidden meanwhile.
const pending = new Set();
function deferDelete(id, msg, commit, refresh) {
  pending.add(id); refresh();
  let undone = false;
  toast(msg, 'Undo', () => { undone = true; pending.delete(id); refresh(); }, 4000);
  setTimeout(async () => {
    if (undone) return;
    try { await commit(); } catch (err) { fail(err); }
    pending.delete(id);
  }, 4000);
}

// iOS only raises the keyboard for focus() inside a tap. Focusing this proxy during the tap
// keeps the keyboard up until the real input takes focus after the async load.
const primeKeyboard = () => $('kbProxy').focus({ preventScroll:true });
function focusInput(el) {
  if (el) el.focus({ preventScroll:true });
  else if (document.activeElement === $('kbProxy')) $('kbProxy').blur();
}

// Horizontal drag on a card; past the threshold it fires left or right. Vertical drags still scroll.
function swipeable(el, left, right) {
  let x0 = null, y0, dx = 0, lock = null;
  el.addEventListener('touchstart', e => {
    const t = e.touches[0];
    x0 = e.touches.length > 1 || t.clientX < 24 ? null : t.clientX; y0 = t.clientY; dx = 0; lock = null;
  }, { passive:true });
  el.addEventListener('touchmove', e => {
    if (x0 === null || !el.dataset.swipe) return;
    const mx = e.touches[0].clientX - x0, my = e.touches[0].clientY - y0;
    if (lock === null && Math.abs(mx) + Math.abs(my) > 10) lock = Math.abs(mx) > Math.abs(my) && !getSelection().toString() ? 'x' : 'y';
    if (lock !== 'x') return;
    e.preventDefault(); dx = mx;
    const side = dx > 0 ? right : left;
    el.style.transition = 'none';
    el.style.transform = 'translateX(' + dx + 'px) rotate(' + dx / 30 + 'deg)';
    el.style.boxShadow = Math.abs(dx) > 90 ? '0 0 0 3px ' + side[0] : '';
  }, { passive:false });
  el.addEventListener('touchend', () => {
    if (lock !== 'x') return;
    el.style.transition = ''; el.style.transform = ''; el.style.boxShadow = '';
    if (Math.abs(dx) > 90) (dx > 0 ? right : left)[1]();
    lock = null;
  });
}

// Learn card: same sections and order as the Mac card.
function learnHTML(c, hero) {
  const sec = (title, body) => '<div class="sec"><h3>' + title + '</h3>' + body + '</div>';
  const chips = list => '<div class="chips">' + list.map(p => '<button class="chip" data-look="' + esc(p.text) + '">' + esc(p.text) +
    (p.gloss ? ' <i>' + esc(p.gloss) + '</i>' : '') + '</button>').join('') + '</div>';
  let h = '';
  const pairs = list => '<div class="box">' + list.map(p => '<div class="col"><span>' + esc(p.text) + '</span><span>' + esc(p.gloss) + '</span></div>').join('') + '</div>';
  const lines = list => '<div class="box">' + list.map(l => '<div class="mean"><span>' + esc(l) + '</span></div>').join('') + '</div>';
  if (hero && c.headword) h += '<div class="hero"><span class="hw">' + esc(c.headword) + '</span>' + (c.pronunciation ? '<span class="ipa">' + esc(c.pronunciation) + '</span>' : '') +
    '</div>';
  else if (c.pronunciation) h += '<div class="ipa">' + esc(c.pronunciation) + '</div>';
  if (c.headword) h += '<div class="imgs" data-imgs="' + esc(c.headword) + '"></div>';
  if (c.meanings.length) h += sec('Meaning', '<div class="box">' + c.meanings.map(m => '<div class="mean">' + (m.text ? '<span class="pos">' + esc(m.text) + '</span>' : '') + '<span>' + esc(m.gloss) + '</span></div>').join('') + '</div>');
  if (c.naturalMeaning) h += sec('Meaning', lines([c.naturalMeaning]));
  if (c.grammar.length) h += sec('Grammar', lines(c.grammar.map(g => '• ' + g)));
  if (c.phrases.length) h += sec('Useful Phrases', pairs(c.phrases));
  if (c.synonyms.length) h += sec('Synonyms', chips(c.synonyms));
  if (c.antonyms.length) h += sec('Antonyms', chips(c.antonyms));
  if (c.examples.length) {
    const levels = ['All', ...['Easy','Medium','Hard'].filter(l => c.examples.some(e => e.level === l))];
    h += sec('Examples', (levels.length > 2 ? '<div class="pills">' + levels.map((l, i) => '<button data-lv="' + l + '"' + (i ? '' : ' class="on"') + '>' + l + '</button>').join('') + '</div>' : '') +
      '<div class="box">' + c.examples.map(e => '<div class="ex" data-level="' + e.level + '">' + (e.level ? '<span class="lv">' + e.level.toUpperCase() + '</span>' : '') +
        mark(esc(e.sentence), [c.headword]) + (e.translation ? '<div class="vi">' + esc(e.translation) + '</div>' : '') + '</div>').join('') + '</div>');
  }
  if (!c.headword && c.confusables.length) h += sec('Easily Confused', pairs(c.confusables.map(x => ({ text: x.other, gloss: [x.difference, x.sentence].filter(Boolean).join(' · ') }))));
  else if (c.confusables.length) {
    const gloss = c.meanings[0] ? c.meanings[0].gloss : '';
    h += sec('Easily Confused', c.confusables.map(x => '<div class="conf"><div><strong>' + esc(c.headword) + '</strong>' + esc(gloss) +
      '</div><div><strong>' + esc(x.other) + '</strong>' + esc(x.difference) + (x.sentence ? '<div class="s">' + esc(x.sentence) + '</div>' : '') + '</div></div>').join(''));
  }
  if (c.family.length) h += sec('Word Family', chips(c.family));
  if (c.collocations.length) h += sec('Collocations', pairs(c.collocations));
  if (c.chunks.length) h += sec('Pronunciation', pairs(c.chunks));
  if (c.variation) h += sec('Natural Variation', lines([c.variation]));
  if (c.mnemonic) h += sec('Mnemonic', '<div>' + esc(c.mnemonic) + '</div>');
  if (c.cloze) {
    const hint = c.cloze.answer.split(' ').map(w => w[0] + w.slice(1).replace(/[\p{L}\p{N}]/gu, '_').split('').join(' ')).join('   ');
    h += sec('Self-Check', '<div class="cloze"><div>' + esc(c.cloze.prompt.replace('___', hint)) + '</div><div class="row"><input id="clozeIn" placeholder="Type the answer" autocapitalize="off" autocorrect="off">' +
      '<button id="clozeGo" class="primary" style="flex:0 0 auto;width:auto">' + IC.check + 'Check</button></div><div id="clozeFb" class="fb"></div></div>');
  }
  return '<div class="learn">' + h + '</div>';
}

function wireLearn(root, c, opts) {
  root.querySelectorAll('[data-say]').forEach(b => b.onclick = () => play(c.headword, opts.id, 'English', b.dataset.say === 'slow'));
  root.querySelectorAll('[data-look]').forEach(b => b.onclick = () => lookUp(b.dataset.look));
  root.querySelectorAll('[data-lv]').forEach(p => p.onclick = () => {
    root.querySelectorAll('[data-lv]').forEach(q => q.classList.toggle('on', q === p));
    root.querySelectorAll('.ex').forEach(e => e.classList.toggle('hidden', p.dataset.lv !== 'All' && e.dataset.level !== p.dataset.lv));
  });
  if (c.cloze && root.querySelector('#clozeGo')) {
    let fails = 0;
    const norm = s => s.toLowerCase().replace(/\s+/g, ' ').trim();
    const check = () => {
      const fb = root.querySelector('#clozeFb');
      if (norm(root.querySelector('#clozeIn').value) === norm(c.cloze.answer)) { fb.textContent = 'Correct: ' + c.cloze.answer; fb.style.color = 'var(--easy)'; return; }
      fails++;
      fb.style.color = fails >= 2 ? 'var(--text)' : 'var(--again)';
      fb.textContent = fails >= 2 ? 'Answer: ' + c.cloze.answer : 'Not quite. Try again, or check once more to see the answer.';
    };
    root.querySelector('#clozeGo').onclick = check;
    root.querySelector('#clozeIn').onkeydown = e => { if (e.key === 'Enter') check(); };
  }
  loadImages(root);
}

// Two related photos, like the Mac card. Tapping one opens the image search.
async function loadImages(root) {
  const box = root.querySelector('[data-imgs]'); if (!box) return;
  const term = box.dataset.imgs;
  try {
    const urls = await api('/api/images?term=' + encodeURIComponent(term)).then(r => r.json());
    const page = 'https://www.google.com/search?tbm=isch&q=' + encodeURIComponent(term);
    box.innerHTML = urls.slice(0, 2).map(u => '<a href="' + page + '" target="_blank" rel="noopener"><img src="' + esc(u) + '" alt="" loading="lazy" onerror="this.parentNode.remove()"></a>').join('');
  } catch (e) {}
}

function lookUp(word) { openDrawer('learn', word); }

// Review home: the same numbers as the Mac Study home screen.
const BUCKET_COLORS = { Due:'var(--hard)', Learning:'var(--accent)', New:'#8e8e93', Mastered:'var(--easy)', Leech:'var(--again)' };
async function loadReview() {
  setHeader('Study', '');
  await swr('/api/stats', renderReview);
}
function renderReview(st) {
  const max = Math.max(1, ...st.last7Days);
  const days = st.last7Days.map((n, i) => { const d = new Date(); d.setDate(d.getDate() - 6 + i); return { n, l: i === 6 ? 'Today' : 'SMTWTFS'[d.getDay()] }; });
  const total = Math.max(1, st.totalSaved);
  $('view').innerHTML = '<div class="card dash"><div class="due"><div><div class="n">' + st.dueToday + '</div><div class="l">Due today</div></div>' +
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="6" width="14" height="14" rx="2"/><path d="M7 3h12a2 2 0 0 1 2 2v12"/></svg></div>' +
    '<div class="dkpi"><div><b>' + st.dueTomorrow + '</b><span>Tomorrow</span></div><div><b>' + st.dayStreak + '</b><span>Streak</span></div>' +
    '<div><b>' + st.totalSaved + '</b><span>Saved</span></div></div></div>' +
    '<div class="card"><div class="sec" style="margin:0"><h3>Question Type</h3><div class="qchips">' +
      QTYPES.map(q => '<button data-q="' + q.id + '"' + (q.id === qkind() ? ' class="on"' : '') + '>' + q.title + '</button>').join('') +
      '</div><p class="muted qdetail" id="qdetail">' + QTYPES.find(q => q.id === qkind()).detail + '</p></div></div>' +
    '<div class="card"><div class="sec" style="margin:0"><h3>Last 7 Days</h3><div class="week">' +
      days.map(d => '<div><span>' + (d.n || '') + '</span><i style="height:' + (100 * d.n / max) + '%"></i>' + d.l + '</div>').join('') + '</div></div></div>' +
    '<div class="card"><div class="sec" style="margin:0"><h3>Deck</h3><div class="stack">' +
      st.buckets.map(b => '<i style="width:' + (100 * b.count / total) + '%;background:' + BUCKET_COLORS[b.label] + '"></i>').join('') + '</div>' +
      st.buckets.map(b => '<div class="bk"><span class="dot" style="background:' + BUCKET_COLORS[b.label] + '"></span>' + b.label +
        ' <span class="muted">' + b.detail + '</span><span class="c">' + b.count + '</span></div>').join('') +
      '<div class="bk">Known words <span class="muted">marked as known</span><span class="c">' + st.knownWords + '</span></div></div></div>';
  setDock('<div class="row"><button id="practice" class="gray"' + (st.totalSaved ? '' : ' disabled') + '>' + IC.reset + 'Review All</button><button id="shuffle" class="gray"' + (st.totalSaved ? '' : ' disabled') + '>' + IC.shuffle + 'Shuffled</button></div>' +
    '<div class="row"><button id="newWords" class="tinted">' + IC.sparkles + 'New Words</button><button id="start" class="primary"' + (st.dueToday ? '' : ' disabled') + '>' + IC.play + 'Start Review</button></div>');
  $('start').onclick = () => { primeKeyboard(); startReview(); };
  $('practice').onclick = () => { primeKeyboard(); startReview('practice'); };
  $('shuffle').onclick = () => { primeKeyboard(); startReview('shuffle'); };
  $('view').querySelectorAll('[data-q]').forEach(b => b.onclick = () => {
    store.set('qkind', b.dataset.q);
    $('view').querySelectorAll('[data-q]').forEach(x => x.classList.toggle('on', x === b));
    $('qdetail').textContent = QTYPES.find(q => q.id === b.dataset.q).detail;
  });
  $('newWords').onclick = () => loadNewWords();
}

// Same options as the Mac Study home; ids are ReviewPlanner.QuestionKind raw values.
const QTYPES = [
  { id:'', title:'Auto', detail:'New cards start with recognition; older cards ask you to recall.' },
  { id:'0', title:'Flip', detail:'See the word, grade yourself, then flip the answer.' },
  { id:'1', title:'Cloze', detail:'Fill in the missing word in an example sentence.' },
  { id:'3', title:'Recall', detail:'See the meaning, type the original word.' },
  { id:'4', title:'Listen', detail:'Hear the word, then type it.' },
  { id:'2', title:'Contrast', detail:'Pick the right word between two lookalikes.' },
  { id:'5', title:'Collocation', detail:'Type the common pairing from its meaning.' },
  { id:'6', title:'Family', detail:'Type a related form from its gloss.' },
];
const qkind = () => store.get('qkind') || '';

// mode: undefined = due cards (writes the schedule); 'practice' / 'shuffle' = Mac's Review All, no grades saved.
async function startReview(mode) {
  $('view').innerHTML = '<p class="muted">Loading…</p>';
  const q = [qkind() ? 'kind=' + qkind() : '', mode ? 'all=1' : ''].filter(Boolean).join('&');
  state.cards = await api('/api/cards' + (q ? '?' + q : '')).then(r => r.json());
  if (mode === 'shuffle') for (let i = state.cards.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [state.cards[i], state.cards[j]] = [state.cards[j], state.cards[i]]; }
  state.practice = !!mode;
  state.index = 0; state.done = 0;
  renderCard();
}

// Learn New Words: the Mac queue from the vocabulary pack, with Known / Learn / Skip.
let nw = { level:'all', words:[], index:0, learned:0, shown:false };
async function loadNewWords(level) {
  if (level !== undefined) nw.level = level;
  $('view').innerHTML = '<p class="muted">Loading…</p>';
  const d = await api('/api/newwords?level=' + nw.level).then(r => r.json());
  Object.assign(nw, { words: d.words, index: 0, total: d.total, levels: d.levels });
  renderNewWord();
}

function renderNewWord() {
  const known = nw.level === 'known';
  const w = nw.words[nw.index];
  setHeader('New Words', nw.total ? (nw.total - nw.index) + ' left' : '', loadReview);
  leaveMsg = 'Leave new words?';
  const picker = '<select id="lvl">' + nw.levels.map(l => '<option value="' + l.id + '"' + (l.id === nw.level ? ' selected' : '') + '>' + esc(l.label) + ' (' + l.count + ')</option>').join('') + '</select>' +
    (nw.learned ? '<p class="muted" style="margin:0 0 8px">' + nw.learned + ' added to the deck this session.</p>' : '');
  if (!w) {
    if (nw.total > nw.words.length) return loadNewWords();
    setSpeak('');
    $('view').innerHTML = picker + '<div class="card done-state">' + CHECK + '<p class="muted">' + (known ? 'No words in the Known list yet.' : 'No more words at this level. Choose another level.') + '</p></div>';
  } else {
    $('view').innerHTML = picker + '<div class="card" id="nwCard"><div style="text-align:center"><span class="lvtag">' + esc(w.level) + '</span></div>' +
      '<div class="term" style="margin-top:8px">' + esc(w.word) + '</div>' +
      '<p id="nwHint" class="muted tap-hint">Tap to show the card. Swipe right to learn, left to ' + (known ? 'go next' : 'skip') + '.</p>' +
      '<div id="nwBack" class="back hidden">' + (w.card ? learnHTML(w.card, false) : esc(w.back)) + '</div></div>';
    const skip = known ? 'next' : 'skip';
    setDock('<div class="row"><button data-d="' + (known ? 'unknown' : 'known') + '" class="green">' + (known ? IC.undo + 'Unmark' : IC.check + 'Known') + '</button>' +
      '<button data-d="learn" class="primary">' + IC.plus + 'Learn</button><button data-d="' + skip + '" class="gray">' + (known ? IC.next + 'Next' : IC.skip + 'Skip') + '</button></div>');
    setSpeak(SPK);
    $('say').onclick = () => play(w.word, null, 'English');
    $('saySlow').onclick = () => play(w.word, null, 'English', true);
    const card = $('nwCard');
    card.onclick = e => {
      if (e.target.closest('button, a, input') || !$('nwBack').classList.contains('hidden')) return;
      $('nwBack').classList.remove('hidden'); $('nwHint').remove(); if (w.card) wireLearn($('nwBack'), w.card, {});
    };
    card.dataset.swipe = '1';
    swipeable(card, ['var(--muted)', () => decideNewWord(w, skip)], ['var(--accent)', () => decideNewWord(w, 'learn')]);
    $('dock').querySelectorAll('[data-d]').forEach(b => b.onclick = () => decideNewWord(w, b.dataset.d));
    play(w.word, null, 'English');
  }
  $('lvl').onchange = e => { nw.learned = 0; loadNewWords(e.target.value); };
  scrollTo(0, 0);
}

async function decideNewWord(w, d) {
  if (d !== 'next') {
    try { await post('/api/newword', { word: w.word, decision: d }); }
    catch (err) { fail(err); return; }
  }
  if (d === 'learn') nw.learned++;
  // Skip goes to the back of the queue, like the Mac; Unmark Known and Learn from Known leave the list.
  if (d === 'skip') nw.words.push(nw.words.splice(nw.index, 1)[0]);
  else if (d === 'unknown' || (d === 'learn' && nw.level === 'known')) { nw.words.splice(nw.index, 1); nw.total--; }
  else nw.index++;
  const lv = nw.levels.find(l => l.id === nw.level);
  if (lv && d !== 'skip' && d !== 'next') lv.count = Math.max(0, lv.count - 1);
  renderNewWord();
}

function renderCard() {
  const card = state.cards[state.index];
  if (!card) {
    focusInput(null);
    setHeader('Review', '', loadReview);
    $('view').innerHTML = '<div class="card done-state">' + CHECK + '<div class="term">All done</div><p class="muted">' +
      (state.done ? state.done + ' cards reviewed.' : 'No cards due today.') + '</p></div>';
    return;
  }
  setHeader(state.practice ? 'Practice' : 'Review', (state.index + 1) + ' / ' + state.cards.length, loadReview);
  leaveMsg = 'Leave this review?';
  const q = card.question && card.question.kind !== 'flip' ? card.question : null;
  const note = card.question && card.question.note ? '<p class="muted" style="text-align:center">' + esc(card.question.note) + '</p>' : '';
  const termHTML = '<div class="term">' + esc(card.term) + '</div>' +
    (card.context ? '<div class="context">' + mark(esc(card.context), [card.term]) + '</div>' : '');
  // A question hides the term and its audio until the card is flipped, except Listen, which is the audio.
  let front = termHTML;
  if (q) {
    front = '<div class="qkind"><span class="lvtag">' + esc(q.kind.toUpperCase()) + '</span></div>' +
      '<div class="prompt">' + esc(q.prompt) + '</div>' +
      (q.choices ? ''
        : '<div class="answer"><input id="ans" placeholder="Type the answer" autocapitalize="off" autocorrect="off" autocomplete="off" enterkeyhint="done"><button id="check" class="primary" style="width:auto">' + IC.check + 'Check</button></div>') +
      '<div id="qfb" class="qfb"></div>';
  }
  $('view').innerHTML = '<div class="progress"><div style="width:' + (100 * state.index / state.cards.length) + '%"></div></div>' + note +
    '<div class="card"><div id="front">' + front + '</div>' +
    (q ? '' : '<p id="tapHint" class="muted tap-hint">Tap the card to show the answer.</p>') +
    '<div id="backText" class="back hidden">' + (card.card ? learnHTML(card.card, false) : esc(card.back)) + '</div></div>';
  setDock((q && q.choices ? '<div class="choices">' + q.choices.map(c => '<button data-c="' + esc(c) + '">' + esc(c) + '</button>').join('') + '</div>' : '') +
    '<button id="reveal" class="' + (q && q.choices ? 'tinted' : 'reveal') + '">' + IC.eye + 'Show Answer</button>');
  const cardEl = $('view').querySelector('.card');
  const shownAt = Date.now();
  let suggested = null, revealed = false;
  const wireTerm = () => {
    $('say').onclick = () => play(card.term, card.id);
    $('saySlow').onclick = () => play(card.term, card.id, null, true);
  };
  const reveal = () => {
    if (revealed) return;
    revealed = true;
    if (q) $('front').innerHTML = termHTML;
    setSpeak(SPK); wireTerm();
    if ($('tapHint')) $('tapHint').remove();
    $('backText').classList.remove('hidden');
    if ($('ans')) $('ans').blur();
    // Flipping a question without answering counts as not recalled, like the Mac.
    if (q && suggested === null) suggested = 0;
    $('grades').querySelectorAll('[data-g]').forEach(b => b.classList.toggle('suggest', b.id !== 'autoGrade' && +b.dataset.g === suggested));
    // The answered grade becomes one big button; the three small ones stay for overriding it.
    const auto = $('autoGrade');
    auto.classList.toggle('hidden', suggested === null);
    if (suggested !== null) {
      auto.dataset.g = suggested;
      auto.style.background = GRADES[suggested][1];
      auto.innerHTML = IC.next + 'Continue as ' + GRADES[suggested][0];
    }
    setDock('');
    $('grades').classList.remove('hidden'); pad(); play(card.term, card.id);
    cardEl.dataset.swipe = '1';
    if (card.card) wireLearn($('backText'), card.card, { id: card.id });
  };
  // Same grading as ReviewPlanner.autoGrade: wrong is Again, a one-letter slip or a slow answer is Hard.
  const answered = (correct, near, shown) => {
    suggested = !correct ? (near ? 1 : 0) : (Date.now() - shownAt <= 6000 ? 2 : 1);
    const fb = $('qfb');
    fb.style.color = correct ? 'var(--easy)' : near ? 'var(--hard)' : 'var(--again)';
    fb.textContent = correct ? 'Correct' : (near ? 'Almost: ' : 'Answer: ') + q.answer;
    setTimeout(() => { const keep = fb.outerHTML; reveal(); $('front').insertAdjacentHTML('beforeend', keep); }, correct ? 500 : 1200);
  };
  swipeable(cardEl, ['var(--again)', () => gradeCard(0)], ['var(--easy)', () => gradeCard(2)]);
  if (!q) {
    setSpeak(SPK); wireTerm();
    cardEl.onclick = e => { if (!e.target.closest('button, a, input')) reveal(); };
  } else if (q.choices) {
    $('dock').querySelectorAll('[data-c]').forEach(b => b.onclick = () => {
      if (suggested !== null) return;
      const ok = b.dataset.c === q.answer;
      b.classList.add(ok ? 'right' : 'wrong');
      if (!ok) $('dock').querySelector('[data-c="' + CSS.escape(q.answer) + '"]').classList.add('right');
      answered(ok, false);
    });
  } else {
    const check = () => {
      const v = $('ans').value; if (!v.trim()) return;
      $('ans').disabled = true; $('check').disabled = true;
      answered(norm(v) === norm(q.answer), nearMiss(v, q.answer));
    };
    $('check').onclick = check;
    $('ans').onkeydown = e => { if (e.key === 'Enter') check(); };
    if (q.kind === 'listen') {
      setSpeak(SPK); wireTerm();
      play(card.term, card.id);
    }
  }
  focusInput($('ans'));
  $('reveal').onclick = reveal;
}

const norm = s => s.toLowerCase().replace(/\s+/g, ' ').trim();
// One typo on a word of 4+ letters is a near miss, like ReviewPlanner.isNearMiss.
function nearMiss(typed, answer) {
  const a = norm(typed), b = norm(answer);
  if (a === b || b.length < 4 || Math.abs(a.length - b.length) > 1) return false;
  let prev = [...Array(b.length + 1).keys()];
  for (let i = 1; i <= a.length; i++) {
    const cur = [i];
    for (let j = 1; j <= b.length; j++) cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    prev = cur;
  }
  return prev[b.length] <= 1;
}

const GRADES = [['Again', 'var(--again)'], ['Hard', 'var(--hard)'], ['Easy', 'var(--easy)']];
const needsTyping = c => c && c.question && c.question.kind !== 'flip' && !c.question.choices;
let grading = false;
async function gradeCard(g) {
  const card = state.cards[state.index];
  if (!card || grading) return;
  // Again re-queues this card, so it can also be the next one when it was last.
  if (needsTyping(state.cards[state.index + 1] || (g === 0 ? card : null))) primeKeyboard();
  grading = true;
  try { if (!state.practice) await post('/api/grade', { id: card.id, grade: g }); }
  catch (err) { toast('Could not save grade: ' + err.message); return; }
  finally { grading = false; }
  // Again comes back later in the same session, like the Mac review.
  if (g === 0) state.cards.splice(Math.min(state.index + 4, state.cards.length), 0, card);
  else state.done++;
  state.index++; renderCard(); scrollTo(0, 0);
}
$('grades').onclick = e => { const b = e.target.closest('[data-g]'); if (b) gradeCard(+b.dataset.g); };

// Dialogues
async function loadDialogues() {
  setHeader('Dialogues', '');
  await swr('/api/passages', renderDialogues);
}
function renderDialogues(all) {
  const items = all.filter(i => !pending.has(i.key));
  const groups = [...new Set(items.map(i => i.group).filter(Boolean))].sort();
  if (!groups.includes(state.filter)) state.filter = '';
  const shown = items.filter(i => !state.filter || i.group === state.filter);
  $('meta').textContent = shown.length + ' passages';
  setDock('<button id="create" class="primary">' + IC.plus + 'Create Dialogue</button>');
  $('view').innerHTML = (groups.length ? '<div class="pills" id="group">' + ['', ...groups].map(g => '<button data-g="' + esc(g) + '"' + (g === state.filter ? ' class="on"' : '') + '>' + (g ? esc(g) : 'All') + '</button>').join('') + '</div>' : '') +
    '<div class="plist">' + shown.map(i => '<div class="pwrap"><div class="pacts">' +
      '<button class="ok" data-a="' + (i.isDone ? 'undone' : 'done') + '">' + IC.check + (i.isDone ? 'Undone' : 'Done') + '</button>' +
      (i.count ? '<button class="rs" data-a="reset">' + IC.reset + 'Reset</button>' : '') +
      '<button class="danger" data-a="delete">' + IC.trash + 'Delete</button></div>' +
      '<div class="prow' + (i.isDone ? ' isdone' : '') + '" data-k="' + i.key + '"><span class="lead">' + (i.isDone ? IC.check : IC.chat) + '</span><div class="body"><div class="t">' + esc(i.title) + '</div>' +
      '<div class="muted">' + esc(i.subtitle) + '</div></div>' + (i.isDone ? '' : '<span class="dot"></span>') + '</div></div>').join('') + '</div>';
  if ($('group')) $('group').onclick = e => { const b = e.target.closest('[data-g]'); if (!b) return; state.filter = b.dataset.g; store.set('dialogueGroup', state.filter); loadDialogues(); };
  $('create').onclick = showCreate;
  // Swipe a row left to reveal its actions; one row open at a time, any other tap closes it.
  let open = null;
  const shut = () => { if (open) open.style.transform = ''; open = null; };
  $('view').querySelectorAll('.pwrap').forEach(w => {
    const row = w.querySelector('.prow'), acts = w.querySelector('.pacts'), key = row.dataset.k;
    let x0 = null, y0, dx = 0, lock = null, base = 0;
    row.onpointerdown = e => { x0 = e.clientX; y0 = e.clientY; dx = 0; lock = null; base = open === row ? -acts.offsetWidth : 0; };
    row.onpointermove = e => {
      if (x0 === null) return;
      const mx = e.clientX - x0, my = e.clientY - y0;
      if (lock === null && Math.abs(mx) + Math.abs(my) > 10) { lock = Math.abs(mx) > Math.abs(my) ? 'x' : 'y'; if (lock === 'x') { row.setPointerCapture(e.pointerId); if (open !== row) shut(); } }
      if (lock !== 'x') return;
      dx = mx; row.style.transition = 'none';
      row.style.transform = 'translateX(' + Math.min(0, Math.max(-acts.offsetWidth - 24, base + dx)) + 'px)';
    };
    row.onpointerup = row.onpointercancel = () => {
      if (x0 === null) return; x0 = null; row.style.transition = '';
      if (lock !== 'x') return;
      if (base + dx < -acts.offsetWidth / 2) { row.style.transform = 'translateX(' + -acts.offsetWidth + 'px)'; open = row; }
      else { row.style.transform = ''; if (open === row) open = null; }
    };
    row.onclick = () => { if (lock === 'x') return; if (open) return shut(); openPassage(key); };
    acts.onclick = async e => {
      const a = (e.target.closest('[data-a]') || {}).dataset?.a;
      if (!a) return;
      if (a === 'delete') return deferDelete(key, 'Passage deleted', () => post('/api/passage', { key, action: a }), loadDialogues);
      try { await post('/api/passage', { key, action: a }); loadDialogues(); }
      catch (err) { fail(err); }
    };
  });
}

function showCreate() {
  setHeader('Create Dialogue', '', loadDialogues);
  $('view').innerHTML = '<label class="lb" for="words">Words (comma separated)</label><input id="words" class="text" placeholder="e.g. deploy, rollback, flaky" autocapitalize="off">' +
    '<label class="lb" for="scene">Scenario (optional)</label><textarea id="scene" placeholder="Describe the situation"></textarea>' +
    '<div id="out"></div>';
  setDock('<button id="make" class="primary">' + IC.wand + 'Generate</button>');
  $('words').focus();
  $('make').onclick = async () => {
    const words = $('words').value.split(',').map(w => w.trim()).filter(Boolean), scenario = $('scene').value.trim();
    if (!words.length && !scenario) return;
    $('make').disabled = true; $('out').innerHTML = '<p class="muted">Generating a dialogue…</p>';
    try { const r = await post('/api/weave', { words, scenario }).then(r => r.json()); openPassage(r.key); }
    catch (err) { $('out').innerHTML = '<p class="muted">Failed: ' + esc(err.message) + '</p>'; $('make').disabled = false; }
  };
}

let readMode = 'both';
async function openPassage(key) {
  const p = await api('/api/passage?key=' + key).then(r => r.json());
  setHeader(p.title, '', () => { stop = true; player.pause(); loadDialogues(); });
  if (!p.isDone) leaveMsg = 'Leave this dialogue?';
  let stop = false;
  const body = p.turns.length
    ? p.turns.map((t, i) => '<div class="turn ' + (t.speaker.toUpperCase() === 'A' ? 'a' : 'b') + '"><div class="bubble" data-i="' + i + '">' +
        '<div class="src">' + mark(esc(t.source), p.words) + '</div><div class="tr">' + esc(t.translation) + '</div>' +
        '<div class="tools"><button data-p="n" aria-label="Speak">' + SPEAKER + '</button><button data-p="s" aria-label="Speak slowly">' + SLOW + '</button><button data-p="l">' + IC.sparkles + 'Learn</button></div></div></div>').join('')
    : '<div class="card back" style="border:0;margin:0">' + mark(esc(p.text), p.words) + '</div>';
  $('view').innerHTML = (p.scenario ? '<p class="scene">' + esc(p.scenario) + '</p>' : '') +
    (p.words.length ? '<div class="chips" style="margin-bottom:10px">' + p.words.map(w => '<button class="chip" data-look="' + esc(w) + '">' + esc(w) + '</button>').join('') + '</div>' : '') +
    '<div class="seg"><button data-m="src">English</button><button data-m="tr">Vietnamese</button><button data-m="both">Both</button></div>' +
    '<div id="turns">' + body + '</div>';
  setDock('<div class="row"><button id="markDone" class="' + (p.isDone ? 'green' : 'tinted') + '">' + IC.check + (p.isDone ? 'Done Again' : 'Mark Done') + '</button>' +
    '<button id="all" class="primary">' + SPEAKER + 'Play All</button></div>');
  const turns = $('turns');
  const seg = [...$('view').querySelectorAll('[data-m]')];
  // Both languages stay on screen; the one not chosen is blurred until tapped, like the Mac.
  const paint = () => {
    seg.forEach(b => b.classList.toggle('on', b.dataset.m === readMode));
    turns.querySelectorAll('.bubble').forEach(b => {
      const open = b.classList.contains('both');
      b.querySelector('.src').classList.toggle('blur', !open && readMode === 'tr');
      b.querySelector('.tr').classList.toggle('blur', !open && readMode === 'src');
    });
  };
  seg.forEach(b => b.onclick = () => { readMode = b.dataset.m; turns.querySelectorAll('.both').forEach(x => x.classList.remove('both')); paint(); }); paint();
  $('view').querySelectorAll('[data-look]').forEach(b => b.onclick = () => lookUp(b.dataset.look));
  // A marked word looks up its base form from p.words ("copies" -> "copy" when only the stem is listed).
  const lookMarked = el => { const t = el.textContent.toLowerCase(); lookUp(p.words.filter(w => t.startsWith(w.toLowerCase())).sort((a, b) => b.length - a.length)[0] || el.textContent); };
  $('view').querySelectorAll('.back b').forEach(b => b.onclick = () => lookMarked(b));
  const bubbles = [...turns.querySelectorAll('.bubble')];
  const lit = i => bubbles.forEach((b, j) => b.classList.toggle('playing', i === j));
  bubbles.forEach((b, i) => b.onclick = async e => {
    const btn = e.target.closest('[data-p]');
    // Tapping blurred text reveals that line and speaks it, like the Mac.
    if (!btn) {
      if (!e.target.closest('.blur')) { const w = e.target.closest('.src b'); if (w) lookMarked(w); return; }
      b.classList.add('both'); paint();
      stop = true; lit(i); await play(p.turns[i].source, null, 'English'); lit(-1);
      return;
    }
    if (btn.dataset.p === 'l') return lookUp(p.turns[i].source);
    stop = true; lit(i); await play(p.turns[i].source, null, 'English', btn.dataset.p === 's'); lit(-1);
  });
  let playing = false;
  $('all').onclick = async () => {
    if (playing) { stop = true; player.pause(); return; }
    stop = false; playing = true; $('all').innerHTML = STOP + 'Stop';
    for (let i = 0; i < p.turns.length && !stop; i++) { lit(i); bubbles[i].scrollIntoView({ block:'center', behavior:'smooth' }); await play(p.turns[i].source, null, 'English'); }
    lit(-1); playing = false; $('all').innerHTML = SPEAKER + 'Play All';
  };
  $('markDone').onclick = async () => {
    try { await post('/api/passage', { key, action:'done' }); stop = true; player.pause(); loadDialogues(); }
    catch (err) { fail(err); }
  };
  scrollTo(0, 0);
}

// Translate drawer: opens over any screen, from the nav button or from selected text.
let tr = { mode:'translate', source:'Auto', target:'Auto', text:'', result:null };
// Auto: Vietnamese text goes to English, anything else to Vietnamese. Learn always explains in Vietnamese.
const VI = /[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ]/i;
const other = l => l === 'English' ? 'Vietnamese' : 'English';
const targetFor = text => tr.target !== 'Auto' ? tr.target : tr.source !== 'Auto' && tr.mode !== 'learn' ? other(tr.source) : tr.mode === 'learn' || !VI.test(text) ? 'Vietnamese' : 'English';
function openDrawer(mode, text) {
  if (mode) tr.mode = mode;
  const fresh = text !== undefined && text !== tr.text;
  if (text !== undefined) tr.text = text;
  if (fresh) tr.result = null;
  $('selbar').classList.add('hidden');
  loadTranslate();
  $('drawer').classList.add('open'); $('scrim').classList.add('open');
  if (fresh && tr.text.trim()) runTranslate();
  else if (!tr.text) setTimeout(() => $('trInput').focus(), 250);
}
// Head bookmark follows the record the result is stored as.
function paintMark() {
  const r = tr.result, m = $('drawerMark');
  m.classList.toggle('hidden', !(r && r.id));
  if (!r || !r.id) return;
  m.innerHTML = r.isSaved ? IC.bookmark.replace('fill="none"', 'fill="currentColor"') : IC.bookmark;
  m.style.color = r.isSaved ? 'var(--easy)' : '';
  m.setAttribute('aria-label', r.isSaved ? 'Remove bookmark' : 'Bookmark');
}
$('drawerMark').onclick = async () => {
  const r = tr.result; if (!r || !r.id) return;
  try { await post('/api/record', { id: r.id, action: r.isSaved ? 'unsave' : 'save' }); r.isSaved = !r.isSaved; paintMark(); if ($('hlist')) fetchHistory(); }
  catch (err) { fail(err); }
};
function closeDrawer() { $('drawer').classList.remove('open'); $('scrim').classList.remove('open'); document.activeElement.blur(); }

function loadTranslate() {
  $('drawerBody').innerHTML = '<div class="seg"><button data-m="translate">Translate</button><button data-m="learn">Learn</button></div>' +
    '<div class="lbar"><select id="trSource" aria-label="Source language"><option>Auto</option><option>English</option><option>Vietnamese</option></select><button id="trSwap" class="icon" aria-label="Swap languages">' + IC.swap + '</button>' +
    '<select id="trTarget" aria-label="Target language"><option>Auto</option><option>Vietnamese</option><option>English</option></select></div>' +
    '<textarea id="trInput" placeholder="Type a word or sentence"></textarea>' +
    '<div class="irow"><button id="speakIn" class="icon round" aria-label="Play">' + SPEAKER + '</button><button id="trGo" class="primary">Translate</button></div><div id="trOut"></div>';
  $('trInput').value = tr.text; $('trTarget').value = tr.target;
  $('trSource').value = tr.source;
  // Swap flips the direction; a finished translation also moves its result into the input and runs again.
  $('trSwap').onclick = () => {
    const r = tr.result, done = r && r.mode === 'translate' && r.text;
    tr.source = done ? r.target : targetFor(tr.text); tr.target = other(tr.source);
    if (done) { tr.text = r.text; tr.result = null; }
    loadTranslate();
    if (done) runTranslate();
  };
  const seg = [...$('drawerBody').querySelectorAll('[data-m]')];
  const paint = () => { seg.forEach(b => b.classList.toggle('on', b.dataset.m === tr.mode)); $('trGo').innerHTML = tr.mode === 'learn' ? IC.sparkles + 'Learn' : IC.next + 'Translate'; $('trSource').disabled = tr.mode === 'learn'; };
  // Switching mode with text present runs it again, so Learn/Translate is one tap.
  seg.forEach(b => b.onclick = () => { if (tr.mode === b.dataset.m) return; tr.mode = b.dataset.m; paint(); if (tr.text.trim()) runTranslate(); }); paint();
  $('trTarget').onchange = e => tr.target = e.target.value;
  $('trSource').onchange = e => tr.source = e.target.value;
  $('trInput').oninput = e => tr.text = e.target.value;
  $('speakIn').onclick = () => tr.text.trim() && play(tr.text.trim(), null, tr.mode === 'learn' ? 'English' : tr.source !== 'Auto' ? tr.source : targetFor(tr.text) !== 'English' ? 'English' : 'Vietnamese');
  $('trGo').onclick = runTranslate;
  if (tr.result) renderResult(); else paintMark();
}

async function runTranslate() {
  const text = tr.text.trim(); if (!text) return;
  $('trInput').blur();
  $('trGo').disabled = true; $('trOut').innerHTML = '<p class="muted">Working…</p>';
  try {
    const target = targetFor(text);
    const r = await post('/api/translate', { text, mode: tr.mode, target, source: tr.mode === 'learn' || tr.source === 'Auto' ? undefined : tr.source });
    tr.result = Object.assign(await r.json(), { mode: tr.mode, source: text, target });
    renderResult();
    if ($('hlist')) fetchHistory();
  } catch (err) { $('trOut').innerHTML = '<p class="muted">Failed: ' + esc(err.message) + '</p>'; }
  $('trGo').disabled = false;
}

function renderResult() {
  const r = tr.result, out = $('trOut'); paintMark();
  const structured = r.mode === 'learn' && r.card;
  out.innerHTML = '<div class="card">' + (structured ? learnHTML(r.card, true) : '<div class="rlang">' + esc(r.target) + '</div>' +
    '<div class="rtext"><div>' + esc(r.text) + '</div></div>') + '</div>' +
    '<div class="spbar">' + (structured ? '<button class="icon round" data-say="1" aria-label="Speak">' + SPEAKER + '</button><button class="icon round" data-say="slow" aria-label="Speak slowly">' + SLOW + '</button>'
      : '<button id="speakOut" class="icon round" aria-label="Play result">' + SPEAKER + '</button>') + '</div>';
  out.insertAdjacentHTML('beforeend', askHTML());
  wireAsk(out, { source: r.source, result: r.text, target: r.target, sourceLang: r.sourceLanguage });
  if (structured) wireLearn(out, r.card, {});
  // Learn cards explain an English term, so the term is what gets spoken.
  if ($('speakOut')) $('speakOut').onclick = () => r.mode === 'learn' ? play(r.source, null, 'English') : play(r.text, null, r.target);
}

// Selecting text anywhere outside the drawer offers Learn / Translate for it.
let selText = '';
document.addEventListener('selectionchange', () => {
  const sel = getSelection(), t = sel.toString().trim();
  const inDrawer = sel.anchorNode && $('drawer').contains(sel.anchorNode);
  selText = t && !inDrawer && t.length <= 500 ? t : '';
  $('selbar').classList.toggle('hidden', !selText);
});
$('selbar').onclick = e => { const b = e.target.closest('[data-sel]'); if (b && selText) { const t = selText; getSelection().removeAllRanges(); openDrawer(b.dataset.sel, t); } };
$('scrim').onclick = closeDrawer;
{
  const d = $('drawer'), db = $('drawerBody'); let y0 = null, dy = 0;
  // Handle drags at once; the body only once it is scrolled to the top and the drag goes down.
  let handle = false, lock = null, x0 = 0;
  d.addEventListener('touchstart', e => {
    const t = e.touches[0]; handle = !!e.target.closest('.grab, .dhead');
    y0 = handle || (db.scrollTop <= 0 && !e.target.closest('input, textarea')) ? t.clientY : null; x0 = t.clientX; dy = 0; lock = null;
  }, { passive:true });
  d.addEventListener('touchmove', e => {
    if (y0 === null) return;
    const my = e.touches[0].clientY - y0, mx = e.touches[0].clientX - x0;
    if (!handle && lock === null && Math.abs(mx) + Math.abs(my) > 8) lock = my > Math.abs(mx) && db.scrollTop <= 0 && !getSelection().toString() ? 'y' : 'no';
    if (!handle && lock !== 'y') { if (lock === 'no') y0 = null; return; }
    e.preventDefault(); dy = Math.max(0, e.touches[0].clientY - y0);
    d.style.transition = 'none'; d.style.transform = 'translateY(' + dy + 'px)';
  }, { passive:false });
  d.addEventListener('touchend', () => {
    if (y0 === null) return;
    d.style.transition = ''; d.style.transform = ''; y0 = null;
    if (dy > 80) closeDrawer();
  });
}
$('drawerClose').onclick = closeDrawer;

// Ask: follow-up questions about one translation, kept for this screen only.
const askHTML = () => '<div class="card qa"><div class="sec" style="margin:0"><h3>Ask</h3><div id="qaLog"></div>' +
  '<div class="answer"><input id="qaIn" placeholder="Ask about this result" enterkeyhint="send"><button id="qaGo" class="primary" style="width:auto">' + IC.next + '</button></div></div></div>';
function wireAsk(root, ctx) {
  const history = [];
  const send = async () => {
    const input = root.querySelector('#qaIn'), go = root.querySelector('#qaGo'), q = input.value.trim(); if (!q) return;
    const log = root.querySelector('#qaLog');
    log.insertAdjacentHTML('beforeend', '<div class="q">' + esc(q) + '</div><div class="a muted">Thinking…</div>');
    const a = log.lastElementChild; input.value = ''; go.disabled = true;
    try {
      const r = await post('/api/ask', Object.assign({ question: q, history }, ctx)).then(r => r.json());
      a.textContent = r.text; a.classList.remove('muted'); history.push({ question: q, answer: r.text });
    } catch (err) { a.textContent = 'Failed: ' + err.message; }
    go.disabled = false;
  };
  root.querySelector('#qaGo').onclick = send;
  root.querySelector('#qaIn').onkeydown = e => { if (e.key === 'Enter') send(); };
}

// History: same search and order as the Mac window.
let hist = { q:'', saved:false, items:[] };
let histTimer;
async function loadHistory() {
  setHeader('History', '');
  setDock('<input id="hq" class="text" type="search" placeholder="Search" autocapitalize="off" autocorrect="off" enterkeyhint="search" style="margin:0">');
  $('view').innerHTML = '<div class="seg" style="margin-bottom:10px"><button data-s="0">All</button><button data-s="1">Saved</button></div><div id="hlist"></div>';
  $('hq').value = hist.q;
  const seg = [...$('view').querySelectorAll('[data-s]')];
  const paint = () => seg.forEach(b => b.classList.toggle('on', (b.dataset.s === '1') === hist.saved));
  seg.forEach(b => b.onclick = () => { hist.saved = b.dataset.s === '1'; paint(); fetchHistory(); }); paint();
  $('hq').oninput = e => { hist.q = e.target.value; clearTimeout(histTimer); histTimer = setTimeout(fetchHistory, 250); };
  await fetchHistory();
}
const histPath = () => '/api/history?q=' + encodeURIComponent(hist.q.trim()) + (hist.saved ? '&saved=1' : '');
function fetchHistory() { return swr(histPath(), renderHistory, true); }
function renderHistory(all) {
  hist.items = all.filter(h => !pending.has(h.id));
  if (!$('hlist')) return;
  $('meta').textContent = hist.items.length + (hist.items.length >= 100 ? '+' : '');
  $('hlist').innerHTML = hist.items.length ? '<div class="plist">' + hist.items.map((h, i) => '<div class="hrow-wrap"><button class="hrow" data-h="' + i + '"><div class="s">' + esc(h.source) + '</div>' +
      '<div class="r">' + esc(h.result) + '</div><div class="d">' + (h.isSaved ? 'Saved · ' : '') + (h.mode === 'learn' ? 'Learn · ' : '') + esc(h.date) + '</div></button>' +
      '<button class="hdel" data-del="' + i + '" aria-label="Delete">' + IC.trash + '</button></div>').join('') + '</div>'
    : '<div class="card done-state"><p class="muted">' + (hist.q ? 'No matches.' : 'Nothing here yet.') + '</p></div>';
  $('hlist').querySelectorAll('[data-h]').forEach(b => b.onclick = () => openRecord(hist.items[+b.dataset.h]));
  $('hlist').querySelectorAll('[data-del]').forEach(b => b.onclick = () => {
    const h = hist.items[+b.dataset.del];
    deferDelete(h.id, 'Record deleted', () => post('/api/record', { id: h.id, action: 'delete' }), () => cache.has(histPath()) ? renderHistory(JSON.parse(cache.get(histPath()))) : fetchHistory());
  });
}
// A history row opens in the drawer with its stored result; the list only carries a preview.
async function openRecord(h) {
  try {
    const full = await api('/api/record?id=' + h.id).then(r => { if (!r.ok) throw new Error(r.statusText); return r.json(); });
    tr.mode = full.mode; tr.text = full.source; tr.target = 'Auto';
    tr.result = { text: full.result, card: full.card, mode: full.mode, source: full.source, target: full.target, id: full.id, isSaved: full.isSaved };
    openDrawer();
    $('drawerBody').scrollTop = 0;
  } catch (err) { fail(err); }
}

// Each tab comes back where it was left; with cached data the page is already full height.
const scrollPos = {};
function switchTab(tab) {
  if (!leaveOk()) return;
  scrollPos[state.tab] = scrollY;
  state.tab = tab; player.pause();
  $('tabReview').classList.toggle('on', tab === 'review');
  $('tabDialogues').classList.toggle('on', tab === 'dialogues');
  $('tabHistory').classList.toggle('on', tab === 'history');
  ({ review: loadReview, dialogues: loadDialogues, history: loadHistory })[tab]().catch(err => { $('view').innerHTML = '<p class="muted">Could not reach the Mac: ' + esc(err.message) + '</p>'; });
  scrollTo(0, scrollPos[tab] || 0);
}
// Standalone web apps get no system back swipe, so a swipe from the left edge presses Back.
{
  let edge = null;
  document.addEventListener('touchstart', e => {
    const t = e.touches[0];
    edge = t.clientX < 24 && !$('back').classList.contains('hidden') && !$('drawer').classList.contains('open') ? [t.clientX, t.clientY] : null;
  }, { passive:true });
  document.addEventListener('touchend', e => {
    if (!edge) return;
    const t = e.changedTouches[0];
    if (t.clientX - edge[0] > 80 && Math.abs(t.clientY - edge[1]) < 60) $('back').click();
    edge = null;
  }, { passive:true });
}
// The header is fixed so it stays put during iOS rubber-band overscroll; body padding takes its place in the flow.
new ResizeObserver(() => { document.body.style.paddingTop = document.querySelector('header').offsetHeight + 'px'; }).observe(document.querySelector('header'));
addEventListener('scroll', () => document.querySelector('header').classList.toggle('compact', scrollY > 24), { passive:true });
// Fixed bars ride above the on-screen keyboard instead of hiding behind it.
if (window.visualViewport) {
  const kb = () => document.documentElement.style.setProperty('--kb', Math.max(0, innerHeight - visualViewport.height - visualViewport.offsetTop) + 'px');
  visualViewport.addEventListener('resize', kb); visualViewport.addEventListener('scroll', kb);
}
$('tabReview').onclick = () => switchTab('review');
$('tabDialogues').onclick = () => switchTab('dialogues');
$('openTranslate').onclick = () => openDrawer();
$('tabHistory').onclick = () => switchTab('history');
switchTab('review');
// Warm the other tabs so their first open paints from cache.
setTimeout(() => ['/api/passages', histPath()].forEach(p => api(p).then(r => r.text()).then(t => cache.set(p, t)).catch(() => {})), 500);
</script>
</body>
</html>
"""#
}
