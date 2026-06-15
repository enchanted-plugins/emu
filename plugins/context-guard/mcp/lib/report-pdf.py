#!/usr/bin/env python
"""
Emu Session Report — HTML → single-page PDF (Wixie pattern).

Usage: python report-pdf.py <plugins_dir> [output_path]

1. Reads metrics.jsonl from all plugin state directories.
2. Generates a dark-themed HTML report with inline CSS.
3. Converts to a single-page PDF via weasyprint (preferred) or reportlab (fallback).
4. If neither is available, outputs the HTML path for browser viewing.

No external dependencies beyond Python stdlib are required for the HTML.
PDF conversion requires: pip install weasyprint  OR  pip install reportlab
"""

import json
import os
import sys
import html as html_mod
import tempfile
from datetime import datetime, timezone
from collections import Counter, defaultdict

# ── Data loading ──────────────────────────────────────────────────────

def load_metrics(filepath):
    entries = []
    if not os.path.isfile(filepath):
        return entries
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return entries


def count(entries, event):
    return sum(1 for e in entries if e.get("event") == event)


# ── HTML generation ───────────────────────────────────────────────────

def build_html(plugins_dir):
    sk = load_metrics(os.path.join(plugins_dir, "state-keeper", "state", "metrics.jsonl"))
    ts = load_metrics(os.path.join(plugins_dir, "token-saver", "state", "metrics.jsonl"))
    cg = load_metrics(os.path.join(plugins_dir, "context-guard", "state", "metrics.jsonl"))

    checkpoints   = count(sk, "checkpoint_saved")
    compressions  = count(ts, "bash_compressed")
    duplicates    = count(ts, "duplicate_blocked")
    deltas        = count(ts, "delta_read")
    drift_total   = count(cg, "drift_detected")
    aged          = count(ts, "result_aged")

    turns = [e for e in cg if e.get("event") == "turn"]
    n_turns = len(turns)
    recent = turns[-5:]
    avg_tok = sum(e.get("tokens_est", 0) for e in recent) // max(len(recent), 1) if recent else 0

    runway_str = "N/A"
    runway_pct = 0
    if avg_tok > 0 and n_turns > 0:
        used = avg_tok * n_turns
        left = max(200_000 - used, 0)
        rw = left // avg_tok if avg_tok else 0
        runway_str = str(rw)
        runway_pct = min(used / 200_000, 1.0)

    comp_k  = compressions * 2
    dedup_k = duplicates * 4
    drift_k = (drift_total * 800) // 1000
    total_k = comp_k + dedup_k + drift_k

    # Per-tool
    tool_calls = Counter()
    tool_tok   = defaultdict(int)
    for e in turns:
        t = e.get("tool", "?")
        tool_calls[t] += 1
        tool_tok[t] += e.get("tokens_est", 0)
    total_tt = sum(tool_tok.values()) or 1

    # Drift events
    drifts = [e for e in cg if e.get("event") == "drift_detected"]
    drift_by_p = Counter(e.get("pattern", "?") for e in drifts)

    # Compression rules
    rules = Counter(e.get("rule", "?") for e in ts if e.get("event") == "bash_compressed")

    # Duration
    dur = "?"
    if cg:
        try:
            t0 = datetime.fromisoformat(cg[0]["ts"].replace("Z", "+00:00"))
            t1 = datetime.fromisoformat(cg[-1]["ts"].replace("Z", "+00:00"))
            dur = str(int((t1 - t0).total_seconds() // 60))
        except Exception:
            pass

    # Learnings
    learn_html = ""
    lp = os.path.join(plugins_dir, "context-guard", "state", "learnings.json")
    if os.path.isfile(lp):
        try:
            with open(lp) as f:
                learn = json.load(f)
            sr = learn.get("sessions_recorded", 0)
            learn_html = f'<div class="stat-row"><span class="label">Sessions recorded</span><span class="val">{sr}</span></div>'
            for name, d in sorted(learn.get("strategy_rates", {}).items(), key=lambda x: -x[1].get("rate", 0))[:5]:
                r = d.get("rate", 0)
                fires = d.get("fires", 0)
                pct = int(r * 100)
                learn_html += f'<div class="stat-row"><span class="label">{html_mod.escape(name.replace("_"," "))}</span><span class="val">{pct}% <span class="dim">({fires} fires)</span></span><div class="bar"><div class="fill green" style="width:{pct}%"></div></div></div>'
            for a in learn.get("alerts", [])[:3]:
                learn_html += f'<div class="alert-tag">⚠ {html_mod.escape(a)}</div>'
        except Exception:
            pass

    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    # Build tool rows
    tool_rows = ""
    colors = {"Read": "#58a6ff", "Bash": "#3fb950", "Write": "#d29922",
              "Edit": "#bc8cff", "Grep": "#39d353", "Glob": "#f778ba",
              "MultiEdit": "#79c0ff"}
    for tool, tok in sorted(tool_tok.items(), key=lambda x: -x[1])[:8]:
        pct = tok / total_tt * 100
        c = colors.get(tool, "#8b949e")
        tool_rows += f'''<div class="tool-row">
          <span class="tool-name" style="color:{c}">{html_mod.escape(tool)}</span>
          <span class="tool-calls">{tool_calls[tool]}</span>
          <span class="tool-tokens">~{tok:,}</span>
          <span class="tool-pct">{pct:.0f}%</span>
          <div class="bar"><div class="fill" style="width:{pct}%;background:{c}"></div></div>
        </div>'''

    # Drift rows
    drift_rows = ""
    icons = {"read_loop": ("READ LOOP", "#58a6ff"),
             "edit_revert": ("EDIT-REVERT", "#d29922"),
             "test_fail_loop": ("FAIL LOOP", "#f85149")}
    for ev in drifts:
        p = ev.get("pattern", "?")
        label, clr = icons.get(p, (p.upper(), "#8b949e"))
        turn_n = ev.get("turn", "?")
        target = ev.get("file") or ev.get("cmd") or ""
        if len(target) > 55:
            target = "…" + target[-52:]
        drift_rows += f'''<div class="drift-row">
          <span class="drift-tag" style="background:{clr}">{label}</span>
          <span class="drift-turn">Turn {turn_n}</span>
          <span class="drift-target">{html_mod.escape(target)}</span>
        </div>'''
    if not drift_rows:
        drift_rows = '<div class="no-data">No drift detected this session.</div>'

    # Rule rows
    rule_rows = ""
    for rule, cnt in rules.most_common(10):
        pct = cnt / max(compressions, 1) * 100
        rule_rows += f'''<div class="stat-row">
          <span class="label">{html_mod.escape(rule.replace("_"," "))}</span>
          <span class="val">{cnt}×</span>
          <div class="bar"><div class="fill blue" style="width:{pct}%"></div></div>
        </div>'''

    return f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Emu Session Report</title>
<style>
  @page {{ size: letter; margin: 0; }}
  * {{ margin: 0; padding: 0; box-sizing: border-box; }}
  body {{
    background: #0d1117;
    color: #e6edf3;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
    font-size: 12px;
    line-height: 1.5;
    width: 8.5in;
    min-height: 11in;
    padding: 32px 40px;
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }}

  /* Brand bar */
  .brand-bar {{ height: 3px; background: #39d353; margin: -32px -40px 24px; }}

  /* Header */
  .header {{ display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 24px; }}
  .header h1 {{ font-size: 28px; font-weight: 700; }}
  .header h1 span {{ font-size: 12px; font-weight: 400; color: #8b949e; margin-left: 12px; }}
  .header .meta {{ font-size: 10px; color: #484f58; text-align: right; }}

  /* Summary cards */
  .cards {{ display: flex; gap: 12px; margin-bottom: 24px; }}
  .card {{
    flex: 1;
    background: #161b22;
    border: 1px solid #30363d;
    border-radius: 8px;
    padding: 14px 16px;
    position: relative;
    overflow: hidden;
  }}
  .card::before {{
    content: "";
    position: absolute;
    top: 0; left: 2px; right: 2px;
    height: 3px;
    border-radius: 0 0 2px 2px;
  }}
  .card.blue::before {{ background: #58a6ff; }}
  .card.green::before {{ background: #3fb950; }}
  .card.amber::before {{ background: #d29922; }}
  .card.red::before {{ background: #f85149; }}
  .card .card-title {{ font-size: 9px; color: #8b949e; text-transform: uppercase; letter-spacing: 0.5px; }}
  .card .card-value {{ font-size: 24px; font-weight: 700; margin: 4px 0 2px; }}
  .card .card-sub {{ font-size: 9px; color: #484f58; }}

  /* Sections */
  .section {{ margin-bottom: 20px; }}
  .section h2 {{
    font-size: 14px;
    font-weight: 600;
    padding-bottom: 6px;
    border-bottom: 1px solid #30363d;
    margin-bottom: 12px;
  }}

  /* Stat rows */
  .stat-row {{
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 3px 0;
    font-size: 11px;
  }}
  .stat-row .label {{ width: 200px; }}
  .stat-row .val {{ width: 120px; font-weight: 600; }}
  .stat-row .detail {{ color: #8b949e; flex: 1; }}
  .dim {{ color: #484f58; font-weight: 400; }}

  /* Progress bars */
  .bar {{
    width: 120px;
    height: 8px;
    background: #1c2333;
    border-radius: 4px;
    overflow: hidden;
  }}
  .bar .fill {{
    height: 100%;
    border-radius: 4px;
    transition: width 0.3s;
  }}
  .fill.blue {{ background: #58a6ff; }}
  .fill.green {{ background: #3fb950; }}
  .fill.amber {{ background: #d29922; }}

  /* Runway bar */
  .runway-bar {{
    width: 100%;
    height: 10px;
    background: #1c2333;
    border-radius: 5px;
    overflow: hidden;
    margin-top: 8px;
  }}
  .runway-bar .fill {{ height: 100%; border-radius: 5px; }}

  /* Tool table */
  .tool-row {{
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 4px 0;
    font-size: 11px;
  }}
  .tool-name {{ width: 80px; font-weight: 700; }}
  .tool-calls {{ width: 50px; text-align: right; }}
  .tool-tokens {{ width: 80px; text-align: right; }}
  .tool-pct {{ width: 40px; text-align: right; color: #8b949e; }}
  .tool-row .bar {{ width: 160px; }}

  /* Drift */
  .drift-row {{ display: flex; align-items: center; gap: 10px; padding: 4px 0; }}
  .drift-tag {{
    display: inline-block;
    padding: 2px 10px;
    border-radius: 4px;
    font-size: 8px;
    font-weight: 700;
    color: #0d1117;
    min-width: 80px;
    text-align: center;
  }}
  .drift-turn {{ font-size: 10px; width: 60px; }}
  .drift-target {{ font-size: 10px; color: #8b949e; }}

  .no-data {{ color: #3fb950; font-size: 11px; padding: 4px 0; }}
  .alert-tag {{ font-size: 10px; color: #d29922; padding: 2px 0; }}

  /* Footer */
  .footer {{
    margin-top: 20px;
    padding-top: 10px;
    border-top: 1px solid #30363d;
    display: flex;
    justify-content: space-between;
    font-size: 8px;
    color: #484f58;
  }}
  .brand-bottom {{ height: 3px; background: #39d353; margin: 16px -40px -32px; }}

  /* Two-column layout */
  .cols {{ display: flex; gap: 16px; }}
  .cols > .section {{ flex: 1; }}
</style>
</head>
<body>
<div class="brand-bar"></div>

<div class="header">
  <h1>Emu <span>Session Report</span></h1>
  <div class="meta">{now}<br>Every token accounted for.</div>
</div>

<div class="cards">
  <div class="card {"red" if runway_str != "N/A" and int(runway_str) < 10 else "blue"}">
    <div class="card-title">Runway</div>
    <div class="card-value">~{runway_str} turns</div>
    <div class="card-sub">{avg_tok:,} tokens/turn avg</div>
    <div class="runway-bar"><div class="fill" style="width:{runway_pct*100:.0f}%;background:{"#f85149" if runway_pct > 0.8 else "#d29922" if runway_pct > 0.5 else "#58a6ff"}"></div></div>
  </div>
  <div class="card green">
    <div class="card-title">Token Savings</div>
    <div class="card-value">~{total_k}K tokens</div>
    <div class="card-sub">{compressions} compress + {duplicates} dedup + {drift_total} drift</div>
  </div>
  <div class="card {"amber" if drift_total > 0 else "green"}">
    <div class="card-title">Drift Alerts</div>
    <div class="card-value">{drift_total}</div>
    <div class="card-sub">{drift_by_p.get("read_loop",0)} read / {drift_by_p.get("edit_revert",0)} revert / {drift_by_p.get("test_fail_loop",0)} fail</div>
  </div>
</div>

<div class="cols">
  <div class="section">
    <h2>Token Savings Breakdown</h2>
    <div class="stat-row"><span class="label">Bash compressions</span><span class="val">{compressions}</span><span class="detail">→ ~{comp_k}K tokens</span><div class="bar"><div class="fill blue" style="width:{comp_k/max(total_k,1)*100:.0f}%"></div></div></div>
    <div class="stat-row"><span class="label">Duplicate reads blocked</span><span class="val">{duplicates}</span><span class="detail">→ ~{dedup_k}K tokens</span><div class="bar"><div class="fill green" style="width:{dedup_k/max(total_k,1)*100:.0f}%"></div></div></div>
    <div class="stat-row"><span class="label">Drift interventions</span><span class="val">{drift_total}</span><span class="detail">→ ~{drift_k}K tokens</span><div class="bar"><div class="fill amber" style="width:{drift_k/max(total_k,1)*100:.0f}%"></div></div></div>
    <div class="stat-row"><span class="label">Delta reads served</span><span class="val">{deltas}</span><span class="detail dim">diff vs full file</span></div>
    <div class="stat-row"><span class="label">Results aged</span><span class="val">{aged}</span><span class="detail dim">stale context flagged</span></div>
    <div class="stat-row"><span class="label">Checkpoints saved</span><span class="val">{checkpoints}</span><span class="detail dim">compaction survival</span></div>
  </div>
  <div class="section">
    <h2>Per-Tool Consumption</h2>
    {tool_rows if tool_rows else '<div class="no-data">No tool data yet.</div>'}
  </div>
</div>

<div class="cols">
  <div class="section">
    <h2>Drift Alerts</h2>
    {drift_rows}
  </div>
  <div class="section">
    <h2>Compression Rules</h2>
    {rule_rows if rule_rows else '<div class="no-data">No compressions this session.</div>'}
  </div>
</div>

{"<div class='section'><h2>Accumulated Learnings</h2>" + learn_html + "</div>" if learn_html else ""}

<div class="footer">
  <span>Methodology: conservative multipliers — Bash=2K/ea, DupBlock=4K/ea, Drift=800tok/turn</span>
  <span>Session: {n_turns} turns | ~{dur} min | Emu v2.0.0</span>
</div>
<div class="brand-bottom"></div>
</body>
</html>'''


# ── PDF conversion ────────────────────────────────────────────────────

def html_to_pdf_weasyprint(html_path, pdf_path):
    from weasyprint import HTML
    HTML(filename=html_path).write_pdf(pdf_path)
    return True

def html_to_pdf_reportlab(html_path, pdf_path):
    """Fallback: read text content from HTML and render with reportlab."""
    from reportlab.lib.pagesizes import letter
    from reportlab.lib.colors import HexColor
    from reportlab.pdfgen import canvas as rl_canvas
    import re

    with open(html_path, "r", encoding="utf-8") as f:
        raw = f.read()

    # Strip tags for fallback text rendering
    text = re.sub(r'<style>.*?</style>', '', raw, flags=re.DOTALL)
    text = re.sub(r'<[^>]+>', '', text)
    lines = [l.strip() for l in text.split('\n') if l.strip()]

    w, h = letter
    c = rl_canvas.Canvas(pdf_path, pagesize=letter)
    c.setFillColor(HexColor("#0d1117"))
    c.rect(0, 0, w, h, fill=1, stroke=0)
    c.setFillColor(HexColor("#39d353"))
    c.rect(0, h - 3, w, 3, fill=1, stroke=0)
    c.rect(0, 0, w, 3, fill=1, stroke=0)

    c.setFillColor(HexColor("#e6edf3"))
    c.setFont("Courier", 8)
    y = h - 30
    for line in lines:
        if y < 30:
            c.showPage()
            c.setFillColor(HexColor("#0d1117"))
            c.rect(0, 0, w, h, fill=1, stroke=0)
            c.setFillColor(HexColor("#e6edf3"))
            c.setFont("Courier", 8)
            y = h - 30
        c.drawString(30, y, line[:100])
        y -= 10
    c.save()
    return True


def convert_to_pdf(html_path, pdf_path):
    """Try converters in preference order."""
    # 1. weasyprint — best quality, full CSS
    try:
        return html_to_pdf_weasyprint(html_path, pdf_path)
    except (ImportError, Exception):
        pass

    # 2. reportlab — fallback, text-only rendering
    try:
        return html_to_pdf_reportlab(html_path, pdf_path)
    except (ImportError, Exception):
        pass

    return False


# ── Main ──────────────────────────────────────────────────────────────

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <plugins_dir> [output.pdf]", file=sys.stderr)
        sys.exit(1)

    plugins_dir = sys.argv[1]
    ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    pdf_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(tempfile.gettempdir(), f"emu-report-{ts}.pdf")

    # Step 1: Generate HTML
    html_content = build_html(plugins_dir)
    html_path = pdf_path.replace(".pdf", ".html")
    with open(html_path, "w", encoding="utf-8") as f:
        f.write(html_content)

    # Step 2: Convert to PDF
    ok = convert_to_pdf(html_path, pdf_path)
    if ok and os.path.isfile(pdf_path):
        print(pdf_path)
    else:
        # HTML is still usable
        print(html_path)
        print("(PDF conversion unavailable — install weasyprint: pip install weasyprint)", file=sys.stderr)
