#!/usr/bin/env python3
"""
Generate ImGui Lua bindings from imgui.h
Based on sokol/bindgen approach but extended for C++ and ImGui specifics.

## Naming Convention (aligned with Sokol)

All function names use snake_case to match Sokol's Lua API style:

    ImGui C++ API          Lua API
    -------------          -------
    ImGui::Begin()      -> imgui.begin()
    ImGui::End()        -> imgui.end_()    (underscore to avoid Lua keyword)
    ImGui::Button()     -> imgui.button()
    ImGui::SliderFloat  -> imgui.slider_float()
    ImGui::ColorEdit4   -> imgui.color_edit4()
    ImGui::TreeNode     -> imgui.tree_node()
    ImGui::PushID       -> imgui.push_id()

This matches Sokol's naming:
    sg_make_buffer      -> sg.make_buffer()
    sg_begin_pass       -> sg.begin_pass()

Lua reserved keywords (and, break, do, else, end, for, function, if, in,
local, nil, not, or, repeat, return, then, true, until, while) get a
trailing underscore when used as function names.

## Overload Handling Strategy

Generate all overloads with unique names via parameter type mangling.

### Mangling Rules

Function name: CamelCase -> snake_case + _ + parameter_type_suffix

Type mapping:
    const char*         -> str
    int                 -> int
    unsigned int        -> uint
    float               -> float
    double              -> double
    bool                -> bool
    ImVec2              -> vec2
    ImVec4              -> vec4
    void* / const void* -> ptr
    ImGuiID             -> id
    size_t              -> size
    bool*               -> pbool
    int*                -> pint
    float*              -> pfloat
    float[]             -> pfloat
    other pointers      -> ptr

Examples:
    PushID(const char*)              -> push_id_str
    PushID(const char*, const char*) -> push_id_str_str
    PushID(const void*)              -> push_id_ptr
    PushID(int)                      -> push_id_int

    PushStyleVar(int, float)         -> push_style_var_int_float
    PushStyleVar(int, ImVec2)        -> push_style_var_int_vec2

    GetColorU32(int, float)          -> get_color_u32_int_float
    GetColorU32(ImVec4)              -> get_color_u32_vec4
    GetColorU32(uint, float)         -> get_color_u32_uint_float

## Two-Layer Architecture

### Layer 1: C API (internal, gen/bindings/imgui_gen.cpp)
All overloads with explicit mangled names. Not exposed directly to Lua scripts.
    l_imgui_push_id_str         -- PushID(const char*)
    l_imgui_push_id_int         -- PushID(int)
    l_imgui_push_style_var_int_float  -- PushStyleVar(idx, float)
    l_imgui_push_style_var_int_vec2   -- PushStyleVar(idx, ImVec2)

### Layer 2: Lua API (user-facing, lib/imgui.lua)
Clean snake_case API with automatic type dispatch.
    imgui.push_id(id)           -- dispatches based on type(id)
    imgui.push_style_var(idx, val)  -- dispatches based on type(val)
    imgui.begin(name, p_open, flags)
    imgui.button(label, size)

### Dispatch Rules

ID functions (push_id, get_id, tree_push, etc.):
    - Use tostring() for universal handling
    imgui.push_id = function(id)
        return imgui._push_id_str(tostring(id))
    end

Type-dependent functions (push_style_var, etc.):
    - Dispatch based on Lua type()
    imgui.push_style_var = function(idx, val)
        if type(val) == "table" then
            return imgui._push_style_var_int_vec2(idx, val)
        else
            return imgui._push_style_var_int_float(idx, val)
        end
    end

Output parameters:
    - Returned as multiple values
    local clicked, selected = imgui.selectable("Item", is_selected)

### Skipped Functions
- va_args functions (Text, TreeNode fmt variants, etc.)
- Functions with callback parameters
- Complex pointer types (ImGuiStyle*, ImGuiStorage*, etc.)
- char* buffers (InputText family)
"""
import sys
import os
import json
from datetime import datetime

# Add scripts directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import gen_ir_imgui as ir
import gen_util_imgui as util

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

# Functions that have been manually implemented and should not be auto-generated
# These are ImGui:: function names (CamelCase)
MANUAL_FUNCTIONS = {
    'NewFrame', 'Render', 'EndFrame',
}

# Lua reserved keywords - need to be renamed with trailing underscore
LUA_KEYWORDS = {'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for',
                'function', 'goto', 'if', 'in', 'local', 'nil', 'not', 'or',
                'repeat', 'return', 'then', 'true', 'until', 'while'}

# Detect float array size from function name suffix or parameter name
# e.g., ColorEdit3 -> col is float[3], SliderFloat4 -> v is float[4]
def get_float_array_size(func_name, param_name, param_type):
    """Determine if a float* parameter is actually a fixed-size array."""
    if param_type != 'float *':
        return 0

    # Check function name suffix for array size
    for suffix in ['2', '3', '4']:
        if func_name.endswith(suffix):
            # Common array parameter names
            if param_name in ('col', 'v', 'color', 'values', 'ref_col'):
                return int(suffix)

    # Special cases based on function name patterns
    if 'ColorEdit' in func_name or 'ColorPicker' in func_name:
        if param_name == 'col':
            if '4' in func_name:
                return 4
            elif '3' in func_name:
                return 3

    return 0

# Type mappings for Lua
TYPE_MAP = {
    'void': 'void',
    'bool': 'bool',
    'int': 'int',
    'unsigned int': 'unsigned int',
    'float': 'float',
    'double': 'double',
    'const char *': 'const char *',
    'ImGuiID': 'ImGuiID',
    'ImU32': 'ImU32',
    'ImS32': 'int',
    'ImS64': 'long long',
    'ImU64': 'unsigned long long',
}

class ImGuiBindingGenerator:
    def __init__(self, ir_data):
        self.ir = ir_data
        self.funcs = [d for d in ir_data['decls'] if d['kind'] == 'func']
        self.structs = [d for d in ir_data['decls'] if d['kind'] == 'struct']
        self.enums = [d for d in ir_data['decls'] if d['kind'] in ('enum', 'consts')]
        self.out_lines = []

    def emit(self, line=''):
        self.out_lines.append(line)

    def get_lua_func_name(self, func):
        """Convert ImGui function name to Lua function name (snake_case)."""
        name = func['name']
        # Convert CamelCase to snake_case
        result = []
        for i, c in enumerate(name):
            if c.isupper():
                if i > 0 and not name[i-1].isupper():
                    result.append('_')
                result.append(c.lower())
            else:
                result.append(c)
        lua_name = ''.join(result)

        # Handle overloads
        if func.get('has_overloads'):
            suffix = self._get_overload_suffix(func)
            if suffix:
                lua_name += suffix

        # Avoid Lua reserved keywords by adding underscore
        if lua_name in LUA_KEYWORDS:
            lua_name += '_'

        return lua_name

    def _type_to_suffix(self, t):
        """Convert a C++ type to a mangling suffix."""
        t = t.strip()
        # Output pointer types
        if t == 'bool *':
            return 'pbool'
        if t == 'int *':
            return 'pint'
        if t == 'float *':
            return 'pfloat'
        if t == 'double *':
            return 'pdouble'
        if t == 'unsigned int *':
            return 'puint'
        # Float arrays
        if t.startswith('float') and '[' in t:
            return 'pfloat'
        if t.startswith('int') and '[' in t:
            return 'pint'
        # Basic types
        if t == 'const char *':
            return 'str'
        if t == 'int' or t == 'ImS32':
            return 'int'
        if t == 'unsigned int' or t == 'ImU32':
            return 'uint'
        if t == 'float':
            return 'float'
        if t == 'double':
            return 'double'
        if t == 'bool':
            return 'bool'
        if t == 'size_t':
            return 'size'
        if t == 'ImGuiID':
            return 'id'
        # ImVec types
        if 'ImVec2' in t:
            return 'vec2'
        if 'ImVec4' in t:
            return 'vec4'
        # Void pointers
        if 'void *' in t or 'const void *' in t:
            return 'ptr'
        # ImGui flags/enums (treat as int)
        if t.startswith('ImGui') and ('Flags' in t or t[5:6].isupper()):
            return 'int'
        # Other pointers
        if '*' in t:
            return 'ptr'
        # Default
        return 'int'

    def _get_overload_suffix(self, func):
        """Generate suffix for overloaded function using all parameter types."""
        params = func.get('params', [])
        if not params:
            return '_void'

        # Build suffix from all parameter types
        suffixes = []
        for param in params:
            t = param['type']
            suffix = self._type_to_suffix(t)
            suffixes.append(suffix)

        return '_' + '_'.join(suffixes)

    def should_skip(self, func):
        """Check if function should be skipped."""
        name = func['name']

        # Skip functions in skip list
        if name in SKIP_FUNCTIONS:
            return True

        # Skip manually implemented functions
        if name in MANUAL_FUNCTIONS:
            return True

        # Skip variadic functions
        if func.get('is_vararg'):
            return True

        # Skip functions with unsupported parameter types
        for param in func.get('params', []):
            t = param['type']
            # Skip callbacks (except InputTextCallback)
            if '(*)' in t and 'InputTextCallback' not in t:
                return True
            # Skip va_list
            if 'va_list' in t:
                return True
            # Skip complex pointer types
            if '**' in t:
                return True

        return False

    def get_return_type(self, func):
        """Extract return type from function."""
        func_type = func['type']
        # "bool (const char *, bool *, int)" -> "bool"
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

        # Check if this is a float array (e.g., ColorEdit3's col parameter)
        array_size = get_float_array_size(func_name, name, t)
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

        # int/ImGuiID/enums/flags (all ImGui* types are ints)
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

        # float arrays (col[3], col[4], v[2], etc.)
        if t.startswith('float') and '[' in t:
            # Extract array size
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

        # char* buffer (for InputText)
        if t == 'char *':
            lines.append(f'    // char* buffer not directly supported, use InputText helper')
            lines.append(f'    char* {name} = nullptr;')
            return lines

        # size_t
        if t == 'size_t':
            lines.append(f'    size_t {name} = (size_t)luaL_checkinteger(L, {lua_idx});')
            return lines

        # Default: try to pass as integer
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

        # Track output parameters
        out_params = []

        # Get parameters from Lua stack
        for i, param in enumerate(params):
            param_lines = self.gen_param_get(param, i, out_params, func_name=name)
            lines.extend(param_lines)

        # Build function call with proper type casts
        param_exprs = []
        for param in params:
            pname = param['name'] or f'arg{params.index(param)}'
            t = param['type']
            # Cast int to ImGui enum types
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
            # Unknown return type - just call it
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

        # Generate forward declarations
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

        # Generate implementations
        for func, lua_name in generated_funcs:
            try:
                lines = self.gen_func(func)
                for line in lines:
                    self.emit(line)
            except Exception as e:
                self.emit(f'// Error generating {func["name"]}: {e}')
                self.emit('')

        # Generate registration table
        self.emit('// Registration table')
        self.emit('static const luaL_Reg imgui_gen_funcs[] = {')
        for func, lua_name in generated_funcs:
            self.emit(f'    {{"{lua_name}", l_imgui_{lua_name}}},')
        self.emit('    {NULL, NULL}')
        self.emit('};')
        self.emit('')

        # Generate registration function (called by imgui_sokol.cpp)
        self.emit('// Register generated functions into existing table')
        self.emit('extern "C" void luaopen_imgui_gen(lua_State* L, int table_idx) {')
        self.emit('    for (const luaL_Reg* r = imgui_gen_funcs; r->name; r++) {')
        self.emit('        lua_pushcfunction(L, r->func);')
        self.emit('        lua_setfield(L, table_idx, r->name);')
        self.emit('    }')
        self.emit('}')

        return '\n'.join(self.out_lines)


class LuaCATSGenerator:
    """Generate LuaCATS type definitions for IDE autocomplete."""

    def __init__(self, ir_data, binding_gen):
        self.ir = ir_data
        self.binding_gen = binding_gen
        self.funcs = [d for d in ir_data['decls'] if d['kind'] == 'func']
        self.enums = [d for d in ir_data['decls'] if d['kind'] in ('enum', 'consts')]
        self.out_lines = []

    def emit(self, line=''):
        self.out_lines.append(line)

    def lua_type(self, c_type, func_name='', param_name=''):
        """Convert C type to Lua type annotation."""
        c_type = c_type.strip()
        # Basic types
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
        # ImVec types
        if 'ImVec2' in c_type:
            return 'number[]'  # {x, y}
        if 'ImVec4' in c_type:
            return 'number[]'  # {x, y, z, w}
        # Output pointers - check if it's a float array first
        if c_type == 'float *':
            array_size = get_float_array_size(func_name, param_name, c_type)
            if array_size > 0:
                return 'number[]'
            return 'number'
        if c_type == 'bool *':
            return 'boolean'
        if c_type in ('int *', 'double *', 'unsigned int *'):
            return 'number'
        # Float arrays
        if c_type.startswith('float') and '[' in c_type:
            return 'number[]'
        # ImGui enums/flags
        if c_type.startswith('ImGui'):
            return 'integer'
        # Pointers
        if '*' in c_type:
            return 'any'
        return 'any'

    def gen_func_annotation(self, func, lua_name):
        """Generate @param and @return annotations for a function."""
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

        # Generate enum constants
        self.emit('-- Enum constants')
        for enum in self.enums:
            name = enum['name']
            # Skip internal enums
            if name.startswith('_') or 'Private' in name:
                continue
            self.emit(f'-- {name}')
            for item in enum.get('items', []):
                item_name = item['name']
                # Convert to lua-friendly name (remove ImGui prefix)
                lua_const = item_name
                if lua_const.startswith('ImGui'):
                    lua_const = lua_const[5:]
                self.emit(f'imgui.{lua_const} = {item.get("value", 0)}')
            self.emit('')

        # Generate function annotations
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


def main():
    if len(sys.argv) < 2:
        print("Usage: gen_imgui.py <imgui.h path> [output.cpp]")
        sys.exit(1)

    imgui_h = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else 'gen/bindings/imgui_gen.cpp'

    # Determine gen directory (same as output directory root)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.abspath(os.path.join(script_dir, '..'))
    gen_dir = os.path.join(root_dir, 'gen')

    print(f"Generating ImGui IR from {imgui_h}...")
    ir_data = ir.gen_imgui(imgui_h, 'imgui', output_dir=gen_dir)

    print(f"Found {len([d for d in ir_data['decls'] if d['kind'] == 'func'])} functions")
    print(f"Found {len([d for d in ir_data['decls'] if d['kind'] == 'struct'])} structs")
    print(f"Found {len([d for d in ir_data['decls'] if d['kind'] in ('enum', 'consts')])} enums")

    print(f"Generating bindings to {output_path}...")
    gen = ImGuiBindingGenerator(ir_data)
    code = gen.generate()

    # Ensure output directory exists
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    with open(output_path, 'w') as f:
        f.write(code)

    print(f"Generated {len(gen.out_lines)} lines of C++ bindings")

    # Generate LuaCATS type definitions
    types_path = 'gen/types/imgui.lua'
    print(f"Generating type definitions to {types_path}...")
    types_gen = LuaCATSGenerator(ir_data, gen)
    types_code = types_gen.generate()

    os.makedirs(os.path.dirname(types_path), exist_ok=True)

    with open(types_path, 'w') as f:
        f.write(types_code)

    print(f"Generated {len(types_gen.out_lines)} lines of LuaCATS types")
    print("Done!")

if __name__ == '__main__':
    main()
