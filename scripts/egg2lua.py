#!/usr/bin/env python3
"""
egg2lua.py - Convert Panda3D .egg files to Lua table format

Usage: python egg2lua.py input.egg output.lua
"""

import sys
import re
import os


class EggParser:
    """Parser for Panda3D .egg files"""

    # Pre-compiled regex patterns
    RE_SCALAR = re.compile(r"<Scalar>\s*(\w+)\s*{\s*(\S+)\s*}")
    RE_VERTEX = re.compile(r"<Vertex>\s*(\d+)\s*{")
    RE_UV = re.compile(r"<UV>\s*{\s*([\d.e+-]+)\s+([\d.e+-]+)\s*}")
    RE_NORMAL = re.compile(r"<Normal>\s*{\s*([\d.e+-]+)\s+([\d.e+-]+)\s+([\d.e+-]+)\s*}")
    RE_RGBA = re.compile(r"<RGBA>\s*{\s*([\d.e+-]+)\s+([\d.e+-]+)\s+([\d.e+-]+)\s+([\d.e+-]+)\s*}")
    RE_POLYGON = re.compile(r"<Polygon>\s*{")
    RE_GROUP = re.compile(r"<Group>\s*(\S+)\s*{")
    RE_TREF = re.compile(r"<TRef>\s*{\s*(\S+)\s*}")
    RE_MREF = re.compile(r"<MRef>\s*{\s*(\S+)\s*}")
    RE_VREF = re.compile(r"<VertexRef>\s*{([^}]+)}")
    RE_VREF_REF = re.compile(r"<Ref>")

    def __init__(self):
        self.textures = {}
        self.materials = {}
        self.vertex_pools = {}
        self.groups = []
        self.coordinate_system = "Z-Up"

    def parse(self, content):
        """Parse egg file content"""
        content = re.sub(r"//.*$", "", content, flags=re.MULTILINE)
        content_len = len(content)

        pos = 0
        while pos < content_len:
            pos = self._skip_whitespace(content, pos, content_len)
            if pos >= content_len:
                break

            if content[pos] == "<":
                end = content.find(">", pos)
                if end == -1:
                    break
                tag = content[pos + 1 : end].strip()
                pos = end + 1

                pos = self._skip_whitespace(content, pos, content_len)

                name_start = pos
                while pos < content_len and content[pos] not in "{\n":
                    pos += 1
                name = content[name_start:pos].strip()

                pos = self._skip_whitespace(content, pos, content_len)
                if pos < content_len and content[pos] == "{":
                    block_end = self._find_block_end(content, pos, content_len)
                    block_content = content[pos + 1 : block_end]

                    if tag == "CoordinateSystem":
                        self.coordinate_system = block_content.strip()
                    elif tag == "Texture":
                        self._parse_texture(name, block_content)
                    elif tag == "Material":
                        self._parse_material(name, block_content)
                    elif tag == "VertexPool":
                        self._parse_vertex_pool(name, block_content)
                    elif tag == "Group":
                        self._parse_group(name, block_content)

                    pos = block_end + 1
            else:
                pos += 1

    def _skip_whitespace(self, content, pos, content_len):
        while pos < content_len and content[pos] in " \t\n\r":
            pos += 1
        return pos

    def _find_block_end(self, content, start, content_len):
        """Find matching closing brace - optimized"""
        depth = 1
        pos = start + 1
        while pos < content_len:
            # Find next brace of either type
            next_open = content.find("{", pos)
            next_close = content.find("}", pos)

            if next_close == -1:
                return content_len

            if next_open == -1 or next_close < next_open:
                depth -= 1
                if depth == 0:
                    return next_close
                pos = next_close + 1
            else:
                depth += 1
                pos = next_open + 1

        return content_len

    def _parse_texture(self, name, content):
        """Parse texture block"""
        tex = {"path": "", "wrap_u": "repeat", "wrap_v": "repeat", "envtype": "modulate"}

        lines = content.strip().split("\n")
        for line in lines:
            line = line.strip()
            if line.startswith('"') and line.endswith('"'):
                tex["path"] = os.path.basename(line[1:-1])
            elif "<Scalar>" in line:
                m = self.RE_SCALAR.search(line)
                if m:
                    key, val = m.group(1), m.group(2)
                    if key == "wrapu":
                        tex["wrap_u"] = val
                    elif key == "wrapv":
                        tex["wrap_v"] = val
                    elif key == "envtype":
                        tex["envtype"] = val

        self.textures[name] = tex

    def _parse_material(self, name, content):
        """Parse material block"""
        mat = {
            "diffuse": [0.8, 0.8, 0.8],
            "ambient": [1, 1, 1],
            "specular": [0.5, 0.5, 0.5],
            "emission": [0, 0, 0],
            "shininess": 10,
        }

        for m in self.RE_SCALAR.finditer(content):
            key, val = m.group(1), float(m.group(2))
            if key == "diffr":
                mat["diffuse"][0] = val
            elif key == "diffg":
                mat["diffuse"][1] = val
            elif key == "diffb":
                mat["diffuse"][2] = val
            elif key == "ambr":
                mat["ambient"][0] = val
            elif key == "ambg":
                mat["ambient"][1] = val
            elif key == "ambb":
                mat["ambient"][2] = val
            elif key == "specr":
                mat["specular"][0] = val
            elif key == "specg":
                mat["specular"][1] = val
            elif key == "specb":
                mat["specular"][2] = val
            elif key == "emitr":
                mat["emission"][0] = val
            elif key == "emitg":
                mat["emission"][1] = val
            elif key == "emitb":
                mat["emission"][2] = val
            elif key == "shininess":
                mat["shininess"] = val

        self.materials[name] = mat

    def _parse_vertex_pool(self, name, content):
        """Parse vertex pool block"""
        vertices = []
        content_len = len(content)

        for m in self.RE_VERTEX.finditer(content):
            idx = int(m.group(1))
            start = m.end()
            end = self._find_block_end(content, start - 1, content_len)
            vertex_content = content[start:end]

            vertex = self._parse_vertex(vertex_content)

            while len(vertices) <= idx:
                vertices.append(None)
            vertices[idx] = vertex

        self.vertex_pools[name] = vertices

    def _parse_vertex(self, content):
        """Parse single vertex data"""
        vertex = {
            "pos": [0, 0, 0],
            "uv": [0, 0],
            "normal": [0, 1, 0],
            "rgba": [1, 1, 1, 1],
        }

        lines = content.strip().split("\n")
        if lines:
            parts = lines[0].strip().split()
            if len(parts) >= 3:
                vertex["pos"] = [float(parts[0]), float(parts[1]), float(parts[2])]

        # Search in full content for sub-elements
        m = self.RE_UV.search(content)
        if m:
            vertex["uv"] = [float(m.group(1)), float(m.group(2))]

        m = self.RE_NORMAL.search(content)
        if m:
            nx, ny, nz = float(m.group(1)), float(m.group(2)), float(m.group(3))
            length = (nx * nx + ny * ny + nz * nz) ** 0.5
            if length > 0.0001:
                vertex["normal"] = [nx / length, ny / length, nz / length]

        m = self.RE_RGBA.search(content)
        if m:
            vertex["rgba"] = [
                float(m.group(1)),
                float(m.group(2)),
                float(m.group(3)),
                float(m.group(4)),
            ]

        return vertex

    def _parse_group(self, name, content):
        """Parse group block (contains polygons)"""
        group = {"name": name, "polygons": []}
        content_len = len(content)

        # Find all polygons
        for m in self.RE_POLYGON.finditer(content):
            start = m.end()
            end = self._find_block_end(content, start - 1, content_len)
            polygon_content = content[start:end]

            polygon = self._parse_polygon(polygon_content)
            group["polygons"].append(polygon)

        # Recursively parse nested groups
        for m in self.RE_GROUP.finditer(content):
            nested_name = m.group(1)
            start = m.end()
            end = self._find_block_end(content, start - 1, content_len)
            nested_content = content[start:end]

            self._parse_group(f"{name}/{nested_name}", nested_content)

        if group["polygons"]:
            self.groups.append(group)

    def _parse_polygon(self, content):
        """Parse polygon block"""
        polygon = {"texture_refs": [], "material_ref": None, "vertex_refs": []}

        for m in self.RE_TREF.finditer(content):
            polygon["texture_refs"].append(m.group(1))

        m = self.RE_MREF.search(content)
        if m:
            polygon["material_ref"] = m.group(1)

        m = self.RE_VREF.search(content)
        if m:
            ref_content = m.group(1)
            ref_m = self.RE_VREF_REF.search(ref_content)
            if ref_m:
                indices_str = ref_content[: ref_m.start()]
            else:
                indices_str = ref_content
            indices = [int(x) for x in indices_str.split() if x.isdigit()]
            polygon["vertex_refs"] = indices

        return polygon


def generate_lua(parser, output_path):
    """Generate Lua module from parsed egg data"""

    lines = []
    lines.append("-- Generated by egg2lua.py")
    lines.append("-- Coordinate system: " + parser.coordinate_system)
    lines.append("")
    lines.append("local M = {}")
    lines.append("")

    # Textures
    lines.append("-- Texture definitions")
    lines.append("M.textures = {")
    for name, tex in parser.textures.items():
        safe_name = name.replace("-", "_")
        lines.append(f'  ["{safe_name}"] = {{')
        lines.append(f'    path = "{tex["path"]}",')
        lines.append(f'    wrap_u = "{tex["wrap_u"]}",')
        lines.append(f'    wrap_v = "{tex["wrap_v"]}",')
        lines.append(f'    envtype = "{tex["envtype"]}",')
        lines.append("  },")
    lines.append("}")
    lines.append("")

    # Materials
    lines.append("-- Material definitions")
    lines.append("M.materials = {")
    for name, mat in parser.materials.items():
        safe_name = name.replace("-", "_")
        lines.append(f'  ["{safe_name}"] = {{')
        lines.append(f"    diffuse = {{{mat['diffuse'][0]}, {mat['diffuse'][1]}, {mat['diffuse'][2]}}},")
        lines.append(f"    ambient = {{{mat['ambient'][0]}, {mat['ambient'][1]}, {mat['ambient'][2]}}},")
        lines.append(f"    specular = {{{mat['specular'][0]}, {mat['specular'][1]}, {mat['specular'][2]}}},")
        lines.append(f"    emission = {{{mat['emission'][0]}, {mat['emission'][1]}, {mat['emission'][2]}}},")
        lines.append(f"    shininess = {mat['shininess']},")
        lines.append("  },")
    lines.append("}")
    lines.append("")

    # Build meshes by material
    meshes_by_material = {}

    for group in parser.groups:
        for polygon in group["polygons"]:
            mat_name = polygon["material_ref"] or "default"
            if mat_name not in meshes_by_material:
                meshes_by_material[mat_name] = {
                    "vertices": [],
                    "indices": [],
                    "textures": [],
                }
            mesh = meshes_by_material[mat_name]

            pool_name = list(parser.vertex_pools.keys())[0] if parser.vertex_pools else None
            if not pool_name:
                continue
            pool = parser.vertex_pools[pool_name]

            if not mesh["textures"] and polygon["texture_refs"]:
                mesh["textures"] = polygon["texture_refs"]

            base_idx = len(mesh["vertices"])
            for vi in polygon["vertex_refs"]:
                if vi < len(pool) and pool[vi]:
                    mesh["vertices"].append(pool[vi])

            n = len(polygon["vertex_refs"])
            for i in range(1, n - 1):
                mesh["indices"].extend([base_idx, base_idx + i, base_idx + i + 1])

    # Write meshes
    lines.append("-- Mesh data (by material)")
    lines.append("M.meshes = {")
    for mat_name, mesh in meshes_by_material.items():
        safe_name = mat_name.replace("-", "_")
        lines.append(f'  ["{safe_name}"] = {{')

        tex_refs = ", ".join(f'"{t.replace("-", "_")}"' for t in mesh["textures"])
        lines.append(f"    textures = {{{tex_refs}}},")

        lines.append("    -- Format: x, y, z, nx, ny, nz, u, v")
        lines.append("    vertices = {")
        for v in mesh["vertices"]:
            p = v["pos"]
            n = v["normal"]
            uv = v["uv"]
            lines.append(f"      {p[0]}, {p[1]}, {p[2]}, {n[0]}, {n[1]}, {n[2]}, {uv[0]}, {uv[1]},")
        lines.append("    },")

        lines.append("    indices = {")
        for i in range(0, len(mesh["indices"]), 12):
            chunk = mesh["indices"][i : i + 12]
            lines.append("      " + ", ".join(str(x) for x in chunk) + ",")
        lines.append("    },")

        lines.append(f'    material = "{safe_name}",')
        lines.append(f"    vertex_count = {len(mesh['vertices'])},")
        lines.append(f"    index_count = {len(mesh['indices'])},")
        lines.append("  },")
    lines.append("}")
    lines.append("")

    lines.append("return M")
    lines.append("")

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def main():
    if len(sys.argv) < 3:
        print("Usage: python egg2lua.py input.egg output.lua")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]

    print(f"Parsing {input_path}...")

    with open(input_path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()

    parser = EggParser()
    parser.parse(content)

    print(f"  Textures: {len(parser.textures)}")
    print(f"  Materials: {len(parser.materials)}")
    print(f"  Vertex pools: {len(parser.vertex_pools)}")
    print(f"  Groups: {len(parser.groups)}")

    total_polys = sum(len(g["polygons"]) for g in parser.groups)
    print(f"  Total polygons: {total_polys}")

    print(f"Generating {output_path}...")
    generate_lua(parser, output_path)
    print("Done!")


if __name__ == "__main__":
    main()
