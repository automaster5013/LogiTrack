from pathlib import Path


css = Path("web/app/showcase/showcase.css").read_text(encoding="utf-8")

required = (
    "height:100dvh",
    "grid-template-rows:64px minmax(0,1fr) auto 38px",
    ".showcaseHero{grid-template-columns:minmax(360px,.87fr) minmax(460px,1.13fr);min-height:0",
    ".simulator{display:grid;grid-template-rows:42px minmax(0,1fr) auto",
    "@media(max-width:700px)",
    ".showcase{grid-template-rows:56px minmax(0,1fr) 74px}",
    ".heroMetrics{display:none}",
    ".simRows{display:none}",
    "@media(max-height:720px) and (min-width:701px)",
)
missing = [boundary for boundary in required if boundary not in css]
if missing:
    raise SystemExit("ERROR: showcase single-viewport layout is missing: " + ", ".join(missing))

print("PASS: showcase keeps its story, simulator, and capabilities within one responsive viewport")
