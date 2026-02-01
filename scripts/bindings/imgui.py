"""
ImGui binding generator

Generates Lua bindings for Dear ImGui using the binding_gen framework.

## Naming Convention (PascalCase API)

All function names use PascalCase to match ImGui's C++ style:

    ImGui C++ API          Lua API
    -------------          -------
    ImGui::Begin()      -> imgui.Begin()
    ImGui::End()        -> imgui.End()
    ImGui::Button()     -> imgui.Button()
    ImGui::SliderFloat  -> imgui.SliderFloat()
    ImGui::ColorEdit4   -> imgui.ColorEdit4()

## Overload Handling

Overloaded functions get unique names via parameter type suffix:

    PushID(const char*)     -> PushId_Str
    PushID(int)             -> PushId_Int
    PushID(const void*)     -> PushId_Ptr
"""

import os
import sys
import json
import tempfile
import subprocess
from datetime import datetime
from collections import defaultdict

# Add parent directory to path for binding_gen imports
script_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(script_dir)
if parent_dir not in sys.path:
    sys.path.insert(0, parent_dir)

from binding_gen import IR

# ==============================================================================
# Configuration
# ==============================================================================

# Functions to skip (complex callbacks, internal, etc.)
SKIP_FUNCTIONS = {
    # Internal/advanced
    'GetIO', 'GetPlatformIO', 'GetStyle', 'GetDrawData',
    'GetCurrentContext', 'SetCurrentContext', 'CreateContext', 'DestroyContext',
    # Callbacks we can't easily bind
    'SetNextWindowSizeConstraints', 'SetAllocatorFunctions', 'GetAllocatorFunctions',
    # Functions with complex return types
    'GetWindowDrawList', 'GetBackgroundDrawList', 'GetForegroundDrawList',
    'GetFont', 'GetFontBaked',
    # Multi-select (complex)
    'BeginMultiSelect', 'EndMultiSelect', 'SetNextItemSelectionUserData',
    # Platform-specific
    'GetPlatformIO', 'GetMainViewport',
    # Texture functions (need special handling)
    'Image', 'ImageWithBg', 'ImageButton',
    # ListBox/Combo/Plot with callback
    'ListBox', 'Combo', 'PlotLines', 'PlotHistogram',
    # Style functions (need ImGuiStyle*)
    'ShowStyleEditor', 'StyleColorsDark', 'StyleColorsLight', 'StyleColorsClassic',
    # Font functions (complex)
    'PushFont', 'PopFont',
    # InputText (needs char* buffer)
    'InputText', 'InputTextMultiline', 'InputTextWithHint',
    # ColorPicker has complex ref_col parameter
    'ColorPicker4',
    # Color conversion (out params by ref)
    'ColorConvertRGBtoHSV', 'ColorConvertHSVtoRGB',
    # State storage
    'SetStateStorage', 'GetStateStorage',
    # Ini settings
    'SaveIniSettingsToMemory', 'LoadIniSettingsFromMemory',
    # Mouse pos validation (pointer)
    'IsMousePosValid',
    # Shortcut (complex)
    'Shortcut', 'SetNextItemShortcut',
}

# Functions that have been manually implemented
MANUAL_FUNCTIONS = {
    'NewFrame', 'Render', 'EndFrame',
}

# Lua reserved keywords - need trailing underscore
LUA_KEYWORDS = {'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for',
                'function', 'goto', 'if', 'in', 'local', 'nil', 'not', 'or',
                'repeat', 'return', 'then', 'true', 'until', 'while'}


# ==============================================================================
# IR Generation (from gen_ir_imgui.py)
# ==============================================================================

def _filter_types(s):
    """Replace _Bool with bool."""
    return s.replace('_Bool', 'bool')


def _has_default_value(param):
    """Check if a parameter has a default value in clang AST."""
    if 'inner' not in param:
        return False
    for child in param['inner']:
        kind = child.get('kind', '')
        if kind in ['IntegerLiteral', 'FloatingLiteral', 'CXXNullPtrLiteralExpr',
                    'ImplicitCastExpr', 'CXXDefaultArgExpr', 'CXXConstructExpr',
                    'DeclRefExpr', 'UnaryOperator', 'CStyleCastExpr',
                    'CXXMemberCallExpr', 'CallExpr', 'CXXFunctionalCastExpr',
                    'MaterializeTemporaryExpr', 'ExprWithCleanups']:
            return True
    return False


def _is_out_param(param_type):
    """Check if parameter type is an output parameter (non-const pointer)."""
    t = param_type.strip()
    if t.startswith('const '):
        return False
    if t.endswith('*') and t != 'const char *':
        return True
    return False


def _find_constant_value(node):
    """Recursively find ConstantExpr with evaluated value."""
    if node.get('kind') == 'ConstantExpr' and 'value' in node:
        return node['value']
    for child in node.get('inner', []):
        val = _find_constant_value(child)
        if val is not None:
            return val
    return None


def _parse_struct(decl, source):
    """Parse struct declaration."""
    outp = {'kind': 'struct', 'name': decl['name'], 'fields': []}
    if 'inner' not in decl:
        return outp
    for item_decl in decl['inner']:
        if item_decl['kind'] == 'FullComment':
            continue
        if item_decl['kind'] != 'FieldDecl':
            continue
        item = {}
        if 'name' in item_decl:
            item['name'] = item_decl['name']
        item['type'] = _filter_types(item_decl['type']['qualType'])
        outp['fields'].append(item)
    return outp


def _parse_enum(decl, source):
    """Parse enum declaration."""
    outp = {}
    if 'name' in decl:
        outp['kind'] = 'enum'
        outp['name'] = decl['name']
        needs_value = False
    else:
        outp['kind'] = 'consts'
        needs_value = True
    outp['items'] = []
    if 'inner' not in decl:
        return outp
    next_value = 0
    for item_decl in decl['inner']:
        if item_decl['kind'] == 'FullComment':
            continue
        if item_decl['kind'] == 'EnumConstantDecl':
            item = {'name': item_decl['name']}
            value = _find_constant_value(item_decl)
            if value is not None:
                item['value'] = value
                next_value = int(value) + 1
            else:
                item['value'] = str(next_value)
                next_value += 1
            if needs_value and 'value' not in item:
                continue
            outp['items'].append(item)
    return outp


def _parse_func(decl, source):
    """Parse function declaration."""
    outp = {'kind': 'func', 'name': decl['name'],
            'type': _filter_types(decl['type']['qualType']), 'params': []}

    type_str = decl['type']['qualType']
    if '...' in type_str or 'va_list' in type_str:
        outp['is_vararg'] = True

    if 'inner' in decl:
        for param in decl['inner']:
            if param['kind'] == 'FullComment':
                continue
            if param['kind'] != 'ParmVarDecl':
                continue
            outp_param = {
                'name': param.get('name', ''),
                'type': _filter_types(param['type']['qualType']),
            }
            if _has_default_value(param):
                outp_param['has_default'] = True
            if _is_out_param(outp_param['type']):
                outp_param['is_out'] = True
            outp['params'].append(outp_param)
    return outp


def _extract_namespace_funcs(namespace_decl, source):
    """Extract function declarations from a namespace."""
    funcs = []
    if 'inner' not in namespace_decl:
        return funcs
    for decl in namespace_decl['inner']:
        if decl['kind'] == 'FunctionDecl':
            func = _parse_func(decl, source)
            if func:
                func['namespace'] = namespace_decl.get('name', '')
                funcs.append(func)
    return funcs


def _run_clang(csrc_path, include_paths=None):
    """Run clang++ to get AST dump."""
    clangpp = os.environ.get('CLANGPP', 'clang++')
    cmd = [clangpp, '-std=c++17', '-Xclang', '-ast-dump=json', '-c', csrc_path,
           '-fparse-all-comments', '-DIMGUI_DISABLE_OBSOLETE_FUNCTIONS',
           '-DIMGUI_DISABLE_OBSOLETE_KEYIO']
    if include_paths:
        for path in include_paths:
            cmd.extend(['-I', path])
    return subprocess.check_output(cmd)


def gen_ir(imgui_h_path: str, output_dir: str = None) -> dict:
    """Generate IR from imgui.h using clang AST.

    Args:
        imgui_h_path: Path to imgui.h
        output_dir: Optional directory for JSON output

    Returns:
        IR dictionary
    """
    imgui_h_path = os.path.abspath(imgui_h_path)
    imgui_dir = os.path.dirname(imgui_h_path)

    # Create temporary source file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.cpp', delete=False) as f:
        f.write(f'#include "{imgui_h_path}"\n')
        temp_src = f.name

    try:
        ast = _run_clang(temp_src, include_paths=[imgui_dir])
        inp = json.loads(ast)

        outp = {
            'module': 'imgui',
            'prefix': 'Im',
            'dep_prefixes': [],
            'cpp_mode': True,
            'namespace': 'ImGui',
            'decls': [],
        }

        func_counts = defaultdict(int)

        with open(imgui_h_path, mode='r', newline='') as f:
            source = f.read()

        for decl in inp['inner']:
            # Handle ImGui namespace
            if decl['kind'] == 'NamespaceDecl' and decl.get('name') == 'ImGui':
                funcs = _extract_namespace_funcs(decl, source)
                for func in funcs:
                    func_name = func['name']
                    func['overload_index'] = func_counts[func_name]
                    func_counts[func_name] += 1
                    outp['decls'].append(func)
                continue

            # Handle top-level declarations (structs, enums)
            if decl['kind'] == 'CXXRecordDecl' and 'name' in decl:
                name = decl['name']
                if name.startswith('Im'):
                    outp['decls'].append(_parse_struct(decl, source))
            elif decl['kind'] == 'EnumDecl':
                name = decl.get('name', '')
                if name.startswith('Im') or (decl.get('inner') and
                        any(i.get('name', '').startswith('Im') for i in decl.get('inner', [])
                            if i['kind'] == 'EnumConstantDecl')):
                    outp['decls'].append(_parse_enum(decl, source))

        # Mark functions with overloads
        for decl in outp['decls']:
            if decl['kind'] == 'func':
                func_name = decl['name']
                if func_counts[func_name] > 1:
                    decl['has_overloads'] = True

        # Optionally save JSON
        if output_dir:
            os.makedirs(output_dir, exist_ok=True)
            json_path = os.path.join(output_dir, 'imgui.json')
            with open(json_path, 'w') as f:
                json.dump(outp, f, indent=2)

        return outp

    finally:
        os.unlink(temp_src)


# ==============================================================================
# Binding Generator
# ==============================================================================

def _get_float_array_size(func_name, param_name, param_type):
    """Determine if a float* parameter is actually a fixed-size array."""
    if param_type != 'float *':
        return 0
    for suffix in ['2', '3', '4']:
        if func_name.endswith(suffix):
            if param_name in ('col', 'v', 'color', 'values', 'ref_col'):
                return int(suffix)
    if 'ColorEdit' in func_name or 'ColorPicker' in func_name:
        if param_name == 'col':
            if '4' in func_name:
                return 4
            elif '3' in func_name:
                return 3
    return 0


def _type_to_suffix(t):
    """Convert a C++ type to a mangling suffix."""
    t = t.strip()
    if t == 'bool *':
        return 'Pbool'
    if t == 'int *':
        return 'Pint'
    if t == 'float *':
        return 'Pfloat'
    if t == 'double *':
        return 'Pdouble'
    if t == 'unsigned int *':
        return 'Puint'
    if t.startswith('float') and '[' in t:
        return 'Pfloat'
    if t.startswith('int') and '[' in t:
        return 'Pint'
    if t == 'const char *':
        return 'Str'
    if t in ('int', 'ImS32'):
        return 'Int'
    if t in ('unsigned int', 'ImU32'):
        return 'Uint'
    if t == 'float':
        return 'Float'
    if t == 'double':
        return 'Double'
    if t == 'bool':
        return 'Bool'
    if t == 'size_t':
        return 'Size'
    if t == 'ImGuiID':
        return 'Id'
    if 'ImVec2' in t:
        return 'Vec2'
    if 'ImVec4' in t:
        return 'Vec4'
    if 'void *' in t or 'const void *' in t:
        return 'Ptr'
    if t.startswith('ImGui') and ('Flags' in t or t[5:6].isupper()):
        return 'Int'
    if '*' in t:
        return 'Ptr'
    return 'Int'


class ImGuiBindingGenerator:
    """Generates C++ binding code for ImGui."""

    def __init__(self, ir_dict: dict):
        self.ir_dict = ir_dict
        self.funcs = [d for d in ir_dict['decls'] if d['kind'] == 'func']
        self.structs = [d for d in ir_dict['decls'] if d['kind'] == 'struct']
        self.enums = [d for d in ir_dict['decls'] if d['kind'] in ('enum', 'consts')]
        self.out_lines = []

    def emit(self, line=''):
        self.out_lines.append(line)

    def get_lua_func_name(self, func):
        """Convert ImGui function name to Lua function name (PascalCase).

        PascalCase names don't conflict with Lua keywords (e.g., End vs end).
        """
        name = func['name']

        # Handle overloads
        if func.get('has_overloads'):
            suffix = self._get_overload_suffix(func)
            if suffix:
                name += suffix

        return name

    def _get_overload_suffix(self, func):
        """Generate suffix for overloaded function."""
        params = func.get('params', [])
        if not params:
            return '_Void'
        suffixes = [_type_to_suffix(p['type']) for p in params]
        return '_' + '_'.join(suffixes)

    def should_skip(self, func):
        """Check if function should be skipped."""
        name = func['name']
        if name in SKIP_FUNCTIONS or name in MANUAL_FUNCTIONS:
            return True
        if func.get('is_vararg'):
            return True
        for param in func.get('params', []):
            t = param['type']
            if '(*)' in t and 'InputTextCallback' not in t:
                return True
            if 'va_list' in t or '**' in t:
                return True
        return False

    def get_return_type(self, func):
        """Extract return type from function."""
        func_type = func['type']
        paren = func_type.find('(')
        if paren > 0:
            return func_type[:paren].strip()
        return func_type

    def gen_param_get(self, param, idx, out_params, func_name=''):
        """Generate code to get a parameter from Lua stack."""
        name = param['name'] or f'arg{idx}'
        t = param['type']
        has_default = param.get('has_default', False)
        is_out = param.get('is_out', False)
        lua_idx = idx + 1
        lines = []

        # Check for float array
        array_size = _get_float_array_size(func_name, name, t)
        if array_size > 0:
            lines.append(f'    luaL_checktype(L, {lua_idx}, LUA_TTABLE);')
            lines.append(f'    float {name}[{array_size}];')
            for i in range(array_size):
                lines.append(f'    lua_rawgeti(L, {lua_idx}, {i+1}); {name}[{i}] = (float)lua_tonumber(L, -1); lua_pop(L, 1);')
            out_params.append((name, f'float[{array_size}]'))
            return lines

        # Handle output parameters
        if is_out and t == 'bool *':
            if has_default:
                lines.append(f'    bool {name}_val = true;')
                lines.append(f'    bool* {name} = nullptr;')
                lines.append(f'    if (lua_isboolean(L, {lua_idx})) {{')
                lines.append(f'        {name}_val = lua_toboolean(L, {lua_idx});')
                lines.append(f'        {name} = &{name}_val;')
                lines.append(f'    }}')
            else:
                lines.append(f'    bool {name}_val = lua_toboolean(L, {lua_idx});')
                lines.append(f'    bool* {name} = &{name}_val;')
            out_params.append((name, 'bool'))
            return lines

        if is_out and t == 'int *':
            lines.append(f'    int {name}_val = (int)luaL_checkinteger(L, {lua_idx});')
            lines.append(f'    int* {name} = &{name}_val;')
            out_params.append((name, 'int'))
            return lines

        if is_out and t == 'float *':
            lines.append(f'    float {name}_val = (float)luaL_checknumber(L, {lua_idx});')
            lines.append(f'    float* {name} = &{name}_val;')
            out_params.append((name, 'float'))
            return lines

        if is_out and t == 'double *':
            lines.append(f'    double {name}_val = luaL_checknumber(L, {lua_idx});')
            lines.append(f'    double* {name} = &{name}_val;')
            out_params.append((name, 'double'))
            return lines

        if is_out and t == 'unsigned int *':
            lines.append(f'    unsigned int {name}_val = (unsigned int)luaL_checkinteger(L, {lua_idx});')
            lines.append(f'    unsigned int* {name} = &{name}_val;')
            out_params.append((name, 'unsigned int'))
            return lines

        # const char *
        if t == 'const char *':
            if has_default:
                lines.append(f'    const char* {name} = luaL_optstring(L, {lua_idx}, nullptr);')
            else:
                lines.append(f'    const char* {name} = luaL_checkstring(L, {lua_idx});')
            return lines

        # bool
        if t == 'bool':
            if has_default:
                lines.append(f'    bool {name} = lua_isboolean(L, {lua_idx}) ? lua_toboolean(L, {lua_idx}) : false;')
            else:
                lines.append(f'    bool {name} = lua_toboolean(L, {lua_idx});')
            return lines

        # int/ImGuiID/enums/flags
        if t in ('int', 'ImGuiID', 'ImU32', 'ImS32') or t.startswith('ImGui'):
            if has_default:
                lines.append(f'    int {name} = (int)luaL_optinteger(L, {lua_idx}, 0);')
            else:
                lines.append(f'    int {name} = (int)luaL_checkinteger(L, {lua_idx});')
            return lines

        # unsigned int
        if t == 'unsigned int':
            if has_default:
                lines.append(f'    unsigned int {name} = (unsigned int)luaL_optinteger(L, {lua_idx}, 0);')
            else:
                lines.append(f'    unsigned int {name} = (unsigned int)luaL_checkinteger(L, {lua_idx});')
            return lines

        # float
        if t == 'float':
            if has_default:
                lines.append(f'    float {name} = (float)luaL_optnumber(L, {lua_idx}, 0.0);')
            else:
                lines.append(f'    float {name} = (float)luaL_checknumber(L, {lua_idx});')
            return lines

        # double
        if t == 'double':
            if has_default:
                lines.append(f'    double {name} = luaL_optnumber(L, {lua_idx}, 0.0);')
            else:
                lines.append(f'    double {name} = luaL_checknumber(L, {lua_idx});')
            return lines

        # ImVec2
        if 'ImVec2' in t:
            if has_default:
                lines.append(f'    ImVec2 {name} = ImVec2(0, 0);')
                lines.append(f'    if (lua_istable(L, {lua_idx})) {{')
                lines.append(f'        lua_rawgeti(L, {lua_idx}, 1); {name}.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);')
                lines.append(f'        lua_rawgeti(L, {lua_idx}, 2); {name}.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);')
                lines.append(f'    }}')
            else:
                lines.append(f'    luaL_checktype(L, {lua_idx}, LUA_TTABLE);')
                lines.append(f'    ImVec2 {name};')
                lines.append(f'    lua_rawgeti(L, {lua_idx}, 1); {name}.x = (float)luaL_checknumber(L, -1); lua_pop(L, 1);')
                lines.append(f'    lua_rawgeti(L, {lua_idx}, 2); {name}.y = (float)luaL_checknumber(L, -1); lua_pop(L, 1);')
            return lines

        # ImVec4
        if 'ImVec4' in t:
            if has_default:
                lines.append(f'    ImVec4 {name} = ImVec4(0, 0, 0, 0);')
                lines.append(f'    if (lua_istable(L, {lua_idx})) {{')
                lines.append(f'        lua_rawgeti(L, {lua_idx}, 1); {name}.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);')
                lines.append(f'        lua_rawgeti(L, {lua_idx}, 2); {name}.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);')
                lines.append(f'        lua_rawgeti(L, {lua_idx}, 3); {name}.z = (float)lua_tonumber(L, -1); lua_pop(L, 1);')
                lines.append(f'        lua_rawgeti(L, {lua_idx}, 4); {name}.w = (float)lua_tonumber(L, -1); lua_pop(L, 1);')
                lines.append(f'    }}')
            else:
                lines.append(f'    luaL_checktype(L, {lua_idx}, LUA_TTABLE);')
                lines.append(f'    ImVec4 {name};')
                lines.append(f'    lua_rawgeti(L, {lua_idx}, 1); {name}.x = (float)luaL_checknumber(L, -1); lua_pop(L, 1);')
                lines.append(f'    lua_rawgeti(L, {lua_idx}, 2); {name}.y = (float)luaL_checknumber(L, -1); lua_pop(L, 1);')
                lines.append(f'    lua_rawgeti(L, {lua_idx}, 3); {name}.z = (float)luaL_checknumber(L, -1); lua_pop(L, 1);')
                lines.append(f'    lua_rawgeti(L, {lua_idx}, 4); {name}.w = (float)luaL_checknumber(L, -1); lua_pop(L, 1);')
            return lines

        # float arrays
        if t.startswith('float') and '[' in t:
            size = int(t.split('[')[1].split(']')[0])
            lines.append(f'    luaL_checktype(L, {lua_idx}, LUA_TTABLE);')
            lines.append(f'    float {name}[{size}];')
            for i in range(size):
                lines.append(f'    lua_rawgeti(L, {lua_idx}, {i+1}); {name}[{i}] = (float)luaL_checknumber(L, -1); lua_pop(L, 1);')
            out_params.append((name, f'float[{size}]'))
            return lines

        # int arrays
        if t.startswith('int') and '[' in t:
            size = int(t.split('[')[1].split(']')[0])
            lines.append(f'    luaL_checktype(L, {lua_idx}, LUA_TTABLE);')
            lines.append(f'    int {name}[{size}];')
            for i in range(size):
                lines.append(f'    lua_rawgeti(L, {lua_idx}, {i+1}); {name}[{i}] = (int)luaL_checkinteger(L, -1); lua_pop(L, 1);')
            out_params.append((name, f'int[{size}]'))
            return lines

        # void* (userdata)
        if t in ('void *', 'const void *'):
            if has_default:
                lines.append(f'    void* {name} = lua_isuserdata(L, {lua_idx}) ? lua_touserdata(L, {lua_idx}) : nullptr;')
            else:
                lines.append(f'    void* {name} = lua_touserdata(L, {lua_idx});')
            return lines

        # size_t
        if t == 'size_t':
            lines.append(f'    size_t {name} = (size_t)luaL_checkinteger(L, {lua_idx});')
            return lines

        # Default: try as integer
        lines.append(f'    // TODO: Unsupported type {t}')
        lines.append(f'    int {name} = (int)luaL_optinteger(L, {lua_idx}, 0);')
        return lines

    def gen_func(self, func):
        """Generate binding for a single function."""
        name = func['name']
        lua_name = self.get_lua_func_name(func)
        return_type = self.get_return_type(func)
        params = func.get('params', [])

        lines = []
        lines.append(f'static int l_imgui_{lua_name}(lua_State* L) {{')

        out_params = []
        for i, param in enumerate(params):
            param_lines = self.gen_param_get(param, i, out_params, func_name=name)
            lines.extend(param_lines)

        # Build function call
        param_exprs = []
        for param in params:
            pname = param['name'] or f'arg{params.index(param)}'
            t = param['type']
            if t.startswith('ImGui') and t not in ('ImGuiID', 'ImU32', 'ImS32'):
                param_exprs.append(f'({t}){pname}')
            else:
                param_exprs.append(pname)

        call = f'ImGui::{name}({", ".join(param_exprs)})'

        # Handle return value
        ret_count = 0
        if return_type == 'void':
            lines.append(f'    {call};')
        elif return_type == 'bool':
            lines.append(f'    bool result = {call};')
            lines.append(f'    lua_pushboolean(L, result);')
            ret_count = 1
        elif return_type in ('int', 'ImGuiID', 'ImU32'):
            lines.append(f'    int result = {call};')
            lines.append(f'    lua_pushinteger(L, result);')
            ret_count = 1
        elif return_type == 'float':
            lines.append(f'    float result = {call};')
            lines.append(f'    lua_pushnumber(L, result);')
            ret_count = 1
        elif return_type == 'double':
            lines.append(f'    double result = {call};')
            lines.append(f'    lua_pushnumber(L, result);')
            ret_count = 1
        elif return_type == 'const char *':
            lines.append(f'    const char* result = {call};')
            lines.append(f'    if (result) lua_pushstring(L, result); else lua_pushnil(L);')
            ret_count = 1
        elif 'ImVec2' in return_type:
            lines.append(f'    ImVec2 result = {call};')
            lines.append(f'    lua_newtable(L);')
            lines.append(f'    lua_pushnumber(L, result.x); lua_rawseti(L, -2, 1);')
            lines.append(f'    lua_pushnumber(L, result.y); lua_rawseti(L, -2, 2);')
            ret_count = 1
        elif 'ImVec4' in return_type:
            lines.append(f'    ImVec4 result = {call};')
            lines.append(f'    lua_newtable(L);')
            lines.append(f'    lua_pushnumber(L, result.x); lua_rawseti(L, -2, 1);')
            lines.append(f'    lua_pushnumber(L, result.y); lua_rawseti(L, -2, 2);')
            lines.append(f'    lua_pushnumber(L, result.z); lua_rawseti(L, -2, 3);')
            lines.append(f'    lua_pushnumber(L, result.w); lua_rawseti(L, -2, 4);')
            ret_count = 1
        else:
            lines.append(f'    {call};')

        # Push output parameters
        for out_name, out_type in out_params:
            if out_type == 'bool':
                lines.append(f'    lua_pushboolean(L, {out_name}_val);')
                ret_count += 1
            elif out_type in ('int', 'unsigned int'):
                lines.append(f'    lua_pushinteger(L, {out_name}_val);')
                ret_count += 1
            elif out_type in ('float', 'double'):
                lines.append(f'    lua_pushnumber(L, {out_name}_val);')
                ret_count += 1
            elif out_type.startswith('float['):
                size = int(out_type.split('[')[1].split(']')[0])
                lines.append(f'    lua_newtable(L);')
                for i in range(size):
                    lines.append(f'    lua_pushnumber(L, {out_name}[{i}]); lua_rawseti(L, -2, {i+1});')
                ret_count += 1
            elif out_type.startswith('int['):
                size = int(out_type.split('[')[1].split(']')[0])
                lines.append(f'    lua_newtable(L);')
                for i in range(size):
                    lines.append(f'    lua_pushinteger(L, {out_name}[{i}]); lua_rawseti(L, -2, {i+1});')
                ret_count += 1

        lines.append(f'    return {ret_count};')
        lines.append(f'}}')
        lines.append('')
        return lines

    def generate(self):
        """Generate the complete binding file."""
        self.emit('// Auto-generated ImGui Lua bindings')
        self.emit(f'// Generated on {datetime.now().isoformat()}')
        self.emit('// Do not edit manually!')
        self.emit('')
        self.emit('#include "imgui.h"')
        self.emit('')
        self.emit('extern "C" {')
        self.emit('#include "lua.h"')
        self.emit('#include "lauxlib.h"')
        self.emit('#include "lualib.h"')
        self.emit('}')
        self.emit('')

        # Forward declarations
        self.emit('// Forward declarations')
        generated_funcs = []
        for func in self.funcs:
            if self.should_skip(func):
                continue
            lua_name = self.get_lua_func_name(func)
            self.emit(f'static int l_imgui_{lua_name}(lua_State* L);')
            generated_funcs.append((func, lua_name))

        self.emit('')
        self.emit('// Implementation')
        self.emit('')

        # Implementations
        for func, lua_name in generated_funcs:
            try:
                lines = self.gen_func(func)
                for line in lines:
                    self.emit(line)
            except Exception as e:
                self.emit(f'// Error generating {func["name"]}: {e}')
                self.emit('')

        # Registration table
        self.emit('// Registration table')
        self.emit('static const luaL_Reg imgui_gen_funcs[] = {')
        for func, lua_name in generated_funcs:
            self.emit(f'    {{"{lua_name}", l_imgui_{lua_name}}},')
        self.emit('    {NULL, NULL}')
        self.emit('};')
        self.emit('')

        # Registration function
        self.emit('// Register generated functions into existing table')
        self.emit('extern "C" void luaopen_imgui_gen(lua_State* L, int table_idx) {')
        self.emit('    for (const luaL_Reg* r = imgui_gen_funcs; r->name; r++) {')
        self.emit('        lua_pushcfunction(L, r->func);')
        self.emit('        lua_setfield(L, table_idx, r->name);')
        self.emit('    }')
        self.emit('}')

        return '\n'.join(self.out_lines)


# ==============================================================================
# LuaCATS Generator
# ==============================================================================

class LuaCATSGenerator:
    """Generate LuaCATS type definitions for IDE autocomplete."""

    def __init__(self, ir_dict: dict, binding_gen: ImGuiBindingGenerator):
        self.ir_dict = ir_dict
        self.binding_gen = binding_gen
        self.funcs = [d for d in ir_dict['decls'] if d['kind'] == 'func']
        self.enums = [d for d in ir_dict['decls'] if d['kind'] in ('enum', 'consts')]
        self.out_lines = []

    def emit(self, line=''):
        self.out_lines.append(line)

    def lua_type(self, c_type, func_name='', param_name=''):
        """Convert C type to Lua type annotation."""
        c_type = c_type.strip()
        if c_type in ('int', 'unsigned int', 'ImGuiID', 'ImU32', 'ImS32', 'size_t'):
            return 'integer'
        if c_type in ('float', 'double'):
            return 'number'
        if c_type == 'bool':
            return 'boolean'
        if c_type == 'const char *':
            return 'string'
        if c_type == 'void':
            return 'nil'
        if 'ImVec2' in c_type:
            return 'number[]'
        if 'ImVec4' in c_type:
            return 'number[]'
        if c_type == 'float *':
            array_size = _get_float_array_size(func_name, param_name, c_type)
            if array_size > 0:
                return 'number[]'
            return 'number'
        if c_type == 'bool *':
            return 'boolean'
        if c_type in ('int *', 'double *', 'unsigned int *'):
            return 'number'
        if c_type.startswith('float') and '[' in c_type:
            return 'number[]'
        if c_type.startswith('ImGui'):
            return 'integer'
        if '*' in c_type:
            return 'any'
        return 'any'

    def gen_func_annotation(self, func, lua_name):
        """Generate @param and @return annotations."""
        lines = []
        params = func.get('params', [])
        return_type = self.binding_gen.get_return_type(func)
        func_name = func['name']

        # Collect output params
        out_params = []
        for param in params:
            t = param['type']
            if param.get('is_out') or (t.endswith('*') and t not in ('const char *', 'const void *', 'void *') and '(*)' not in t):
                out_params.append(param)

        # @param annotations
        for param in params:
            if param in out_params:
                continue
            pname = param['name'] or 'arg'
            ptype = self.lua_type(param['type'], func_name, pname)
            optional = '?' if param.get('has_default') else ''
            lines.append(f'---@param {pname}{optional} {ptype}')

        # @return annotations
        returns = []
        if return_type != 'void':
            returns.append(self.lua_type(return_type, func_name, ''))
        for out_param in out_params:
            out_pname = out_param['name'] or 'out'
            returns.append(self.lua_type(out_param['type'], func_name, out_pname))

        if returns:
            lines.append(f'---@return {", ".join(returns)}')

        return lines

    def generate(self):
        """Generate complete LuaCATS file."""
        self.emit('---@meta')
        self.emit('-- LuaCATS type definitions for imgui')
        self.emit('-- Auto-generated, do not edit')
        self.emit('')
        self.emit('---@class imgui')
        self.emit('local imgui = {}')
        self.emit('')

        # Enum constants
        self.emit('-- Enum constants')
        for enum in self.enums:
            name = enum.get('name', '')
            if name.startswith('_') or 'Private' in name:
                continue
            self.emit(f'-- {name}')
            for item in enum.get('items', []):
                item_name = item['name']
                lua_const = item_name
                if lua_const.startswith('ImGui'):
                    lua_const = lua_const[5:]
                self.emit(f'imgui.{lua_const} = {item.get("value", 0)}')
            self.emit('')

        # Function annotations
        self.emit('-- Functions')
        for func in self.funcs:
            if self.binding_gen.should_skip(func):
                continue
            lua_name = self.binding_gen.get_lua_func_name(func)
            annotations = self.gen_func_annotation(func, lua_name)
            for line in annotations:
                self.emit(line)
            self.emit(f'function imgui.{lua_name}(...) end')
            self.emit('')

        self.emit('return imgui')
        return '\n'.join(self.out_lines)


# ==============================================================================
# Public API
# ==============================================================================

def generate(imgui_root: str, output_root: str):
    """Generate ImGui Lua bindings.

    Args:
        imgui_root: Path to imgui directory (containing imgui.h)
        output_root: Path to project root
    """
    imgui_h = os.path.join(imgui_root, 'imgui.h')
    if not os.path.exists(imgui_h):
        print(f"Error: imgui.h not found at {imgui_h}")
        return

    gen_dir = os.path.join(output_root, 'gen')

    print(f"Generating ImGui IR from {imgui_h}...")
    ir_dict = gen_ir(imgui_h, output_dir=gen_dir)

    func_count = len([d for d in ir_dict['decls'] if d['kind'] == 'func'])
    struct_count = len([d for d in ir_dict['decls'] if d['kind'] == 'struct'])
    enum_count = len([d for d in ir_dict['decls'] if d['kind'] in ('enum', 'consts')])
    print(f"Found {func_count} functions, {struct_count} structs, {enum_count} enums")

    # Generate C++ bindings
    bindings_path = os.path.join(gen_dir, 'bindings', 'imgui_gen.cpp')
    print(f"Generating bindings to {bindings_path}...")
    gen = ImGuiBindingGenerator(ir_dict)
    code = gen.generate()

    os.makedirs(os.path.dirname(bindings_path), exist_ok=True)
    with open(bindings_path, 'w') as f:
        f.write(code)
    print(f"Generated {len(gen.out_lines)} lines of C++ bindings")

    # Generate LuaCATS types
    types_path = os.path.join(gen_dir, 'types', 'imgui.lua')
    print(f"Generating type definitions to {types_path}...")
    types_gen = LuaCATSGenerator(ir_dict, gen)
    types_code = types_gen.generate()

    os.makedirs(os.path.dirname(types_path), exist_ok=True)
    with open(types_path, 'w') as f:
        f.write(types_code)
    print(f"Generated {len(types_gen.out_lines)} lines of LuaCATS types")

    print("Done!")
