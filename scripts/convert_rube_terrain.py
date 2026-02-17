"""Convert RUBE C++ dump (physicsDrivenParticles.cpp) to Lua terrain data."""

import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent
INPUT = REPO_ROOT / "deps" / "iforce2d-advanced-topics" / "physicsDrivenParticles.cpp"
OUTPUT = REPO_ROOT / "examples" / "b2d_tutorial" / "scenes" / "terrain_data.lua"

FLOAT_RE = r"[-+]?\d+\.\d+e[+-]\d+f?"


def parse_float(s: str) -> float:
    return float(s.rstrip("f"))


def parse(src: str) -> list[dict]:
    bodies: list[dict] = []
    # Split into body blocks: { b2BodyDef ... }
    # Only take static bodies (type 0) = bodies[0] and bodies[1]
    body_blocks = re.split(r"\n\{(?=\s*\n\s*b2BodyDef)", src)
    for block in body_blocks:
        if "b2BodyDef" not in block:
            continue
        # Extract body type
        m_type = re.search(r"bd\.type\s*=\s*b2BodyType\((\d+)\)", block)
        if not m_type:
            continue
        body_type = int(m_type.group(1))
        if body_type != 0:  # Only static bodies
            continue

        # Extract position
        m_pos = re.search(
            rf"bd\.position\.Set\(({FLOAT_RE}),\s*({FLOAT_RE})\)", block
        )
        if not m_pos:
            continue
        pos_x = parse_float(m_pos.group(1))
        pos_y = parse_float(m_pos.group(2))

        fixtures: list[dict] = []
        # Split fixture blocks
        fixture_blocks = re.findall(
            r"\{\s*\n\s*b2FixtureDef.*?\n\s*bodies\[\d+\]->CreateFixture",
            block,
            re.DOTALL,
        )
        for fb in fixture_blocks:
            m_friction = re.search(rf"fd\.friction\s*=\s*({FLOAT_RE})", fb)
            friction = parse_float(m_friction.group(1)) if m_friction else 0.25

            # Check for polygon shape
            if "b2PolygonShape" in fb:
                verts = []
                for m in re.finditer(
                    rf"vs\[\d+\]\.Set\(({FLOAT_RE}),\s*({FLOAT_RE})\)", fb
                ):
                    verts.append((parse_float(m.group(1)), parse_float(m.group(2))))
                m_count = re.search(r"shape\.Set\(vs,\s*(\d+)\)", fb)
                count = int(m_count.group(1)) if m_count else len(verts)
                verts = verts[:count]
                fixtures.append(
                    {"type": "polygon", "friction": friction, "vertices": verts}
                )
            elif "b2CircleShape" in fb:
                m_r = re.search(rf"shape\.m_radius\s*=\s*({FLOAT_RE})", fb)
                m_c = re.search(
                    rf"shape\.m_p\.Set\(({FLOAT_RE}),\s*({FLOAT_RE})\)", fb
                )
                radius = parse_float(m_r.group(1)) if m_r else 0.5
                cx = parse_float(m_c.group(1)) if m_c else 0.0
                cy = parse_float(m_c.group(2)) if m_c else 0.0
                fixtures.append(
                    {
                        "type": "circle",
                        "friction": friction,
                        "radius": radius,
                        "center": (cx, cy),
                    }
                )

        bodies.append({"position": (pos_x, pos_y), "fixtures": fixtures})

    return bodies


def fmt(v: float) -> str:
    s = f"{v:.6f}"
    s = s.rstrip("0").rstrip(".")
    return s


def emit_lua(bodies: list[dict]) -> str:
    lines = ["-- Auto-generated from physicsDrivenParticles.cpp", "return {"]
    for bi, body in enumerate(bodies):
        px, py = body["position"]
        lines.append(f"  {{ position = {{{fmt(px)}, {fmt(py)}}}, fixtures = {{")
        for fi, fix in enumerate(body["fixtures"]):
            fr = fmt(fix["friction"])
            if fix["type"] == "polygon":
                vs = ", ".join(f"{{{fmt(x)}, {fmt(y)}}}" for x, y in fix["vertices"])
                comma = "," if fi < len(body["fixtures"]) - 1 else ","
                lines.append(
                    f"    {{ friction = {fr}, vertices = {{{vs}}} }}{comma}"
                )
            elif fix["type"] == "circle":
                cx, cy = fix["center"]
                r = fmt(fix["radius"])
                comma = "," if fi < len(body["fixtures"]) - 1 else ","
                lines.append(
                    f"    {{ friction = {fr}, type = \"circle\", radius = {r}, center = {{{fmt(cx)}, {fmt(cy)}}} }}{comma}"
                )
        lines.append(f"  }}}},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    src = INPUT.read_text(encoding="utf-8")
    bodies = parse(src)
    print(f"Parsed {len(bodies)} static bodies:")
    for i, b in enumerate(bodies):
        print(f"  body {i}: {len(b['fixtures'])} fixtures at {b['position']}")
    lua = emit_lua(bodies)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(lua, encoding="utf-8")
    print(f"Written to {OUTPUT}")


if __name__ == "__main__":
    main()
