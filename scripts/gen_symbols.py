#!/usr/bin/env python3
"""Generate HTML API reference from JSON IR files."""

import json
from pathlib import Path
from html import escape

SCRIPT_DIR = Path(__file__).parent
LIBRARIES_JSON = SCRIPT_DIR / "libraries.json"


def load_libraries():
    """Load library definitions from libraries.json."""
    with open(LIBRARIES_JSON, "r", encoding="utf-8") as f:
        return json.load(f)


def strip_prefix(name: str, prefix: str) -> str:
    """Remove C prefix."""
    upper_prefix = prefix.upper()
    if name.startswith(upper_prefix):
        name = name[len(upper_prefix):]
    elif name.startswith(prefix):
        name = name[len(prefix):]
    if name.startswith("_"):
        name = name[1:]
    return name


def make_anchor(display_name: str) -> str:
    """Convert display name to anchor ID."""
    return display_name.lower().replace(" ", "-")


def build_type_index(all_irs: list) -> dict:
    """Build C type name -> module mapping."""
    index = {}
    for ir in all_irs:
        module = ir["module"]
        for decl in ir["decls"]:
            if decl.get("is_dep"):
                continue
            if decl["kind"] in ("struct", "enum"):
                c_name = decl["name"]
                index[c_name] = module
    return index


def linkify_type(ctype: str, type_index: dict) -> str:
    """Convert C type to HTML with links."""
    base = ctype.replace("const ", "").replace(" *", "").replace("*", "").strip()
    if base in type_index:
        module = type_index[base]
        anchor = make_anchor(base)
        linked = ctype.replace(base, f'<a href="#{anchor}" data-module="{module}">{escape(base)}</a>')
        return f'<code>{linked}</code>'
    return f'<code>{escape(ctype)}</code>'


def generate_module_html(ir: dict, type_index: dict) -> str:
    """Generate HTML for a single module."""
    module = ir["module"]
    prefix = ir["prefix"]
    lines = [f'<section class="module" data-module="{module}" id="module-{module}">']
    lines.append(f'<h2 id="{module}">{escape(module)}</h2>')

    enums, structs, funcs, consts = [], [], [], []
    for decl in ir["decls"]:
        if decl.get("is_dep"):
            continue
        kind = decl["kind"]
        if kind == "enum":
            enums.append(decl)
        elif kind == "struct":
            structs.append(decl)
        elif kind == "func":
            funcs.append(decl)
        elif kind == "consts":
            consts.append(decl)

    # Section nav
    nav_items = []
    if consts:
        nav_items.append(f'<a href="#{module}-constants">Constants</a>')
    if enums:
        nav_items.append(f'<a href="#{module}-enums">Enums</a>')
    if structs:
        nav_items.append(f'<a href="#{module}-structs">Structs</a>')
    if funcs:
        nav_items.append(f'<a href="#{module}-functions">Functions</a>')
    if nav_items:
        lines.append(f'<nav class="section-nav">{" | ".join(nav_items)}</nav>')

    # Constants
    if consts:
        lines.append(f'<h3 id="{module}-constants">Constants</h3>')
        lines.append('<table><tr><th>Name</th><th>Value</th></tr>')
        for decl in consts:
            for item in decl["items"]:
                lines.append(f'<tr><td><code>{escape(item["name"])}</code></td><td>{escape(item["value"])}</td></tr>')
        lines.append('</table>')

    # Enums
    if enums:
        lines.append(f'<h3 id="{module}-enums">Enums</h3>')
        for decl in enums:
            c_name = decl["name"]
            anchor = make_anchor(c_name)
            lines.append(f'<h4 id="{anchor}">{escape(c_name)}</h4>')
            lines.append('<table><tr><th>Name</th><th>Value</th></tr>')
            for i, item in enumerate(decl["items"]):
                lines.append(f'<tr><td><code>{escape(item["name"])}</code></td><td>{i}</td></tr>')
            lines.append('</table>')

    # Structs
    if structs:
        lines.append(f'<h3 id="{module}-structs">Structs</h3>')
        for decl in structs:
            c_name = decl["name"]
            anchor = make_anchor(c_name)
            lines.append(f'<h4 id="{anchor}">{escape(c_name)}</h4>')
            if decl.get("fields"):
                lines.append('<table><tr><th>Field</th><th>Type</th></tr>')
                for field in decl["fields"]:
                    linked = linkify_type(field["type"], type_index)
                    lines.append(f'<tr><td><code>{escape(field["name"])}</code></td><td>{linked}</td></tr>')
                lines.append('</table>')
            else:
                lines.append('<p><em>(opaque type)</em></p>')

    # Functions
    if funcs:
        lines.append(f'<h3 id="{module}-functions">Functions</h3>')
        lines.append('<table><tr><th>Function</th><th>Signature</th></tr>')
        for decl in funcs:
            c_name = decl["name"]
            params = decl.get("params", [])
            if params:
                param_strs = [f'<code>{escape(p["name"])}</code>: {linkify_type(p["type"], type_index)}' for p in params]
                param_str = f'({", ".join(param_strs)})'
            else:
                param_str = '<code>()</code>'
            ret = decl["type"].split("(")[0].strip()
            ret_str = linkify_type(ret, type_index)
            lines.append(f'<tr><td><code>{escape(c_name)}</code></td><td>{param_str} → {ret_str}</td></tr>')
        lines.append('</table>')

    lines.append('</section>')
    return '\n'.join(lines)


HTML_TEMPLATE = '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Mane3D API Reference</title>
<style>
* {{ box-sizing: border-box; }}
body {{ background: #111; color: #eee; font-family: system-ui, sans-serif; margin: 0; padding: 20px; line-height: 1.5; }}
a {{ color: #88f; }}
code {{ background: #222; color: #f80; padding: 2px 5px; border-radius: 3px; }}
table {{ border-collapse: collapse; width: 100%; margin: 10px 0; }}
th, td {{ border: 1px solid #444; padding: 6px 10px; text-align: left; }}
th {{ background: #222; }}
h1 {{ margin-top: 0; }}
h2 {{ border-bottom: 1px solid #444; padding-bottom: 5px; margin-top: 30px; }}
h3 {{ color: #aaa; }}
h4 {{ color: #888; margin: 20px 0 10px; }}
[id] {{ scroll-margin-top: 60px; }}
.filters {{ position: sticky; top: 0; background: #111; padding: 10px 0; border-bottom: 1px solid #333; margin-bottom: 20px; z-index: 100; }}
.filters button {{ background: #333; color: #eee; border: 1px solid #555; padding: 8px 16px; margin: 2px; cursor: pointer; border-radius: 4px; }}
.filters button:hover {{ background: #444; }}
.filters button.active {{ background: #558; border-color: #88f; }}
.module {{ display: none; }}
.module.visible {{ display: block; }}
.hidden {{ display: none !important; }}
.section-nav {{ margin: 10px 0 20px; padding: 8px; background: #1a1a1a; border-radius: 4px; }}
</style>
</head>
<body>
<h1>Mane3D API Reference</h1>
<div class="filters">
<button data-filter="all" class="active">All</button>
{filter_buttons}
</div>
{content}
<script>
function setFilter(filter) {{
  document.querySelectorAll('.filters button').forEach(b => {{
    b.classList.toggle('active', b.dataset.filter === filter);
  }});
  document.querySelectorAll('.module').forEach(m => {{
    m.classList.toggle('visible', filter === 'all' || m.dataset.module === filter);
  }});
}}

document.querySelectorAll('.filters button').forEach(btn => {{
  btn.addEventListener('click', () => setFilter(btn.dataset.filter));
}});

// Handle link clicks - switch to target module and scroll
document.querySelectorAll('a[href^="#"]').forEach(link => {{
  link.addEventListener('click', e => {{
    const hash = link.getAttribute('href');
    const target = document.querySelector(hash);
    if (!target) return;
    const module = target.closest('.module');
    if (module) {{
      e.preventDefault();
      setFilter(module.dataset.module);
      setTimeout(() => {{
        target.scrollIntoView({{ behavior: 'smooth' }});
        history.pushState(null, '', hash);
      }}, 10);
    }}
  }});
}});

// Show all by default
setFilter('all');
</script>
</body>
</html>
'''


def main():
    stubs_dir = SCRIPT_DIR.parent / "gen" / "stubs"
    out_dir = SCRIPT_DIR.parent / "reference"
    out_dir.mkdir(exist_ok=True)

    # Load module order from libraries.json
    libraries = load_libraries()
    module_order = [lib["module"] for lib in libraries]

    all_irs = []
    for name in module_order:
        path = stubs_dir / f"{name}.json"
        if path.exists():
            with open(path, "r", encoding="utf-8") as f:
                all_irs.append(json.load(f))

    type_index = build_type_index(all_irs)

    content_parts = [generate_module_html(ir, type_index) for ir in all_irs]
    content = '\n'.join(content_parts)

    modules = [ir["module"] for ir in all_irs]
    filter_buttons = '\n'.join(f'<button data-filter="{m}">{m}</button>' for m in modules)

    html = HTML_TEMPLATE.format(filter_buttons=filter_buttons, content=content)

    out_path = out_dir / "symbols.html"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"Generated: {out_path}")


if __name__ == "__main__":
    main()
