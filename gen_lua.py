#-------------------------------------------------------------------------------
#   gen_lua.py
#
#   Generate Lua 5.5 C API bindings.
#-------------------------------------------------------------------------------
import argparse
import os, shutil, sys

# Parse arguments first to get bindgen path
parser = argparse.ArgumentParser(description='Generate Lua bindings for sokol')
parser.add_argument('--bindgen', default=os.path.join(os.path.dirname(__file__), 'deps/sokol/bindgen'),
                    help='Path to sokol/bindgen directory')
parser.add_argument('--sokol', default=os.path.join(os.path.dirname(__file__), 'deps/sokol'),
                    help='Path to sokol directory (for headers)')
args = parser.parse_args()

# Add bindgen to path for gen_ir and gen_util
sys.path.insert(0, args.bindgen)
import gen_ir
import gen_util as util

sokol_root = args.sokol

bindings_root = '.'
stubs_root = f'{bindings_root}/gen/stubs'
module_root = f'{bindings_root}/gen/bindings'

module_names = {
    'slog_':    'log',
    'sg_':      'gfx',
    'sapp_':    'app',
    'stm_':     'time',
    'saudio_':  'audio',
    'sgl_':     'gl',
    'sdtx_':    'debugtext',
    'sshape_':  'shape',
    'sglue_':   'glue',
}

c_source_names = {
    'slog_':    'sokol_log.c',
    'sg_':      'sokol_gfx.c',
    'sapp_':    'sokol_app.c',
    'stm_':     'sokol_time.c',
    'saudio_':  'sokol_audio.c',
    'sgl_':     'sokol_gl.c',
    'sdtx_':    'sokol_debugtext.c',
    'sshape_':  'sokol_shape.c',
    'sglue_':   'sokol_glue.c',
}

# Map prefix to header path (relative to sokol root)
header_paths = {
    'slog_':    'sokol_log.h',
    'sg_':      'sokol_gfx.h',
    'sapp_':    'sokol_app.h',
    'stm_':     'sokol_time.h',
    'saudio_':  'sokol_audio.h',
    'sgl_':     'util/sokol_gl.h',
    'sdtx_':    'util/sokol_debugtext.h',
    'sshape_':  'util/sokol_shape.h',
    'sglue_':   'sokol_glue.h',
}

# Map prefix to header filename (for stub files)
header_names = {
    'slog_':    'sokol_log.h',
    'sg_':      'sokol_gfx.h',
    'sapp_':    'sokol_app.h',
    'stm_':     'sokol_time.h',
    'saudio_':  'sokol_audio.h',
    'sgl_':     'sokol_gl.h',
    'sdtx_':    'sokol_debugtext.h',
    'sshape_':  'sokol_shape.h',
    'sglue_':   'sokol_glue.h',
}

ignores = [
    'sdtx_printf',
    'sdtx_vprintf',
    'sg_install_trace_hooks',
    'sg_trace_hooks',
]

# Functions that use callbacks - need special handling
callback_funcs = [
    'sapp_run',
    'saudio_setup',
]

struct_types = []
enum_types = []
out_lines = ''

def reset_globals():
    global struct_types
    global enum_types
    global out_lines
    global consts_counter
    struct_types = []
    enum_types = []
    out_lines = ''
    consts_counter = 0

def l(s):
    global out_lines
    out_lines += s + '\n'

def check_ignore(name):
    return name in ignores

def is_callback_func(name):
    return name in callback_funcs

# prefix_bla_blub to bla_blub
def as_snake_case(s, prefix):
    outp = s.lower()
    if outp.startswith(prefix):
        outp = outp[len(prefix):]
    return outp

# All known prefixes for type name detection
all_prefixes = ['sg_', 'sapp_', 'slog_', 'stm_', 'saudio_', 'sgl_', 'sdtx_', 'sshape_', 'sglue_']

def get_type_prefix(type_name):
    """Get the original prefix for a type (e.g., sg_swapchain -> sg_)"""
    for pfx in all_prefixes:
        if type_name.startswith(pfx):
            return pfx
    return None

# prefix_bla_blub to BlaBlub
def as_pascal_case(s, prefix):
    parts = s.lower().split('_')
    outp = ''
    start = 1 if parts[0] + '_' == prefix else 0
    for part in parts[start:]:
        if part != 't':
            outp += part.capitalize()
    return outp

def as_struct_metatable_name(type_name):
    """Get the metatable name for a struct type, using its original prefix"""
    # Detect the type's original prefix
    type_prefix = get_type_prefix(type_name)
    if type_prefix:
        return as_pascal_case(type_name, type_prefix)
    # Fallback: remove all underscores and capitalize
    parts = type_name.lower().split('_')
    return ''.join(part.capitalize() for part in parts if part != 't')

def is_prim_type(s):
    return s in ['int', 'bool', 'char', 'int8_t', 'uint8_t', 'int16_t', 'uint16_t',
                 'int32_t', 'uint32_t', 'int64_t', 'uint64_t', 'float', 'double',
                 'uintptr_t', 'intptr_t', 'size_t']

def is_int_type(s):
    return s in ['int', 'int8_t', 'uint8_t', 'int16_t', 'uint16_t',
                 'int32_t', 'uint32_t', 'int64_t', 'uint64_t', 'size_t',
                 'uintptr_t', 'intptr_t', 'char']

def is_float_type(s):
    return s in ['float', 'double']

def is_struct_type(s):
    return s in struct_types

def is_enum_type(s):
    return s in enum_types

def is_const_struct_ptr(s):
    # Normalize spacing for comparison
    normalized = s.replace(' *', '*').replace('* ', '*')
    for struct_type in struct_types:
        if normalized == f"const {struct_type}*":
            return True
    return False

def is_struct_ptr(s):
    # Normalize spacing for comparison
    normalized = s.replace(' *', '*').replace('* ', '*')
    for struct_type in struct_types:
        if normalized == f"{struct_type}*":
            return True
    return False

def get_lua_push_code(type_str, var_name, prefix):
    """Generate code to push a C value onto the Lua stack"""
    if type_str == 'void':
        return None
    elif type_str == 'bool':
        return f'lua_pushboolean(L, {var_name});'
    elif is_int_type(type_str):
        return f'lua_pushinteger(L, (lua_Integer){var_name});'
    elif is_float_type(type_str):
        return f'lua_pushnumber(L, (lua_Number){var_name});'
    elif util.is_string_ptr(type_str):
        return f'lua_pushstring(L, {var_name});'
    elif is_struct_type(type_str):
        struct_name = as_struct_metatable_name(type_str)
        return f'{type_str}* ud = ({type_str}*)lua_newuserdatauv(L, sizeof({type_str}), 0);\n    *ud = {var_name};\n    luaL_setmetatable(L, "sokol.{struct_name}");'
    elif is_enum_type(type_str):
        return f'lua_pushinteger(L, (lua_Integer){var_name});'
    elif util.is_void_ptr(type_str) or util.is_const_void_ptr(type_str):
        return f'lua_pushlightuserdata(L, (void*){var_name});'
    else:
        return f'/* TODO: push {type_str} */ lua_pushnil(L);'

def get_lua_to_code(type_str, arg_index, var_name, prefix):
    """Generate code to get a C value from the Lua stack"""
    if type_str == 'bool':
        return f'bool {var_name} = lua_toboolean(L, {arg_index});'
    elif is_int_type(type_str):
        return f'{type_str} {var_name} = ({type_str})luaL_checkinteger(L, {arg_index});'
    elif is_float_type(type_str):
        return f'{type_str} {var_name} = ({type_str})luaL_checknumber(L, {arg_index});'
    elif util.is_string_ptr(type_str):
        return f'const char* {var_name} = luaL_checkstring(L, {arg_index});'
    elif is_struct_type(type_str):
        struct_name = as_struct_metatable_name(type_str)
        return f'{type_str}* {var_name}_ptr = ({type_str}*)luaL_checkudata(L, {arg_index}, "sokol.{struct_name}");\n    {type_str} {var_name} = *{var_name}_ptr;'
    elif is_const_struct_ptr(type_str):
        inner_type = util.extract_ptr_type(type_str)
        struct_name = as_struct_metatable_name(inner_type)
        # Special case: const sg_range* can accept string
        if inner_type == 'sg_range':
            return f'''sg_range {var_name}_storage;
    const sg_range* {var_name};
    if (lua_isstring(L, {arg_index})) {{
        size_t {var_name}_len;
        const char* {var_name}_str = lua_tolstring(L, {arg_index}, &{var_name}_len);
        {var_name}_storage.ptr = {var_name}_str;
        {var_name}_storage.size = {var_name}_len;
        {var_name} = &{var_name}_storage;
    }} else {{
        {var_name} = (const sg_range*)luaL_checkudata(L, {arg_index}, "sokol.{struct_name}");
    }}'''
        return f'const {inner_type}* {var_name} = (const {inner_type}*)luaL_checkudata(L, {arg_index}, "sokol.{struct_name}");'
    elif is_struct_ptr(type_str):
        inner_type = util.extract_ptr_type(type_str)
        struct_name = as_struct_metatable_name(inner_type)
        return f'{inner_type}* {var_name} = ({inner_type}*)luaL_checkudata(L, {arg_index}, "sokol.{struct_name}");'
    elif is_enum_type(type_str):
        return f'{type_str} {var_name} = ({type_str})luaL_checkinteger(L, {arg_index});'
    elif util.is_void_ptr(type_str):
        return f'void* {var_name} = lua_touserdata(L, {arg_index});'
    elif util.is_const_void_ptr(type_str):
        return f'const void* {var_name} = lua_touserdata(L, {arg_index});'
    else:
        return f'/* TODO: get {type_str} */ void* {var_name} = NULL;'

def get_result_type(decl):
    """Extract result type from function declaration"""
    decl_type = decl['type']
    return decl_type[:decl_type.index('(')].strip()

def gen_func_wrapper(decl, prefix):
    """Generate a Lua C API wrapper function"""
    func_name = decl['name']
    lua_name = as_snake_case(func_name, prefix)
    result_type = get_result_type(decl)

    l(f'static int l_{func_name}(lua_State *L) {{')

    # Get parameters from Lua stack
    arg_names = []
    for i, param in enumerate(decl['params']):
        param_name = param['name']
        param_type = param['type']
        to_code = get_lua_to_code(param_type, i + 1, param_name, prefix)
        l(f'    {to_code}')
        arg_names.append(param_name)

    # Call the C function
    args_str = ', '.join(arg_names)
    if result_type == 'void':
        l(f'    {func_name}({args_str});')
        l('    return 0;')
    else:
        l(f'    {result_type} result = {func_name}({args_str});')
        push_code = get_lua_push_code(result_type, 'result', prefix)
        if push_code:
            l(f'    {push_code}')
            l('    return 1;')
        else:
            l('    return 0;')

    l('}')
    l('')

def gen_array_field_init(field_name, field_type, prefix):
    """Generate code to initialize an array field from a Lua table"""
    array_type = util.extract_array_type(field_type)
    array_sizes = util.extract_array_sizes(field_type)
    size = array_sizes[0]

    l(f'        lua_getfield(L, 1, "{field_name}");')
    l(f'        if (lua_istable(L, -1)) {{')
    l(f'            for (int i = 0; i < {size}; i++) {{')
    l(f'                lua_rawgeti(L, -1, i + 1);')
    l(f'                if (!lua_isnil(L, -1)) {{')
    if array_type == 'bool':
        l(f'                    ud->{field_name}[i] = lua_toboolean(L, -1);')
    elif is_int_type(array_type):
        l(f'                    ud->{field_name}[i] = ({array_type})lua_tointeger(L, -1);')
    elif is_float_type(array_type):
        l(f'                    ud->{field_name}[i] = ({array_type})lua_tonumber(L, -1);')
    elif is_struct_type(array_type):
        inner_struct_name = as_struct_metatable_name(array_type)
        # Special case: sg_range can be initialized from a string
        if array_type == 'sg_range':
            l(f'                    if (lua_isstring(L, -1)) {{')
            l(f'                        /* Initialize sg_range from binary string */')
            l(f'                        size_t len;')
            l(f'                        const char* data = lua_tolstring(L, -1, &len);')
            l(f'                        ud->{field_name}[i].ptr = data;')
            l(f'                        ud->{field_name}[i].size = len;')
            l(f'                    }} else if (lua_istable(L, -1)) {{')
        else:
            l(f'                    if (lua_istable(L, -1)) {{')
        l(f'                        /* Initialize from inline table */')
        l(f'                        lua_pushcfunction(L, l_{array_type}_new);')
        l(f'                        lua_pushvalue(L, -2);')
        l(f'                        lua_call(L, 1, 1);')
        l(f'                        {array_type}* val = ({array_type}*)luaL_testudata(L, -1, "sokol.{inner_struct_name}");')
        l(f'                        if (val) ud->{field_name}[i] = *val;')
        l(f'                        lua_pop(L, 1);')
        l(f'                    }} else {{')
        l(f'                        {array_type}* val = ({array_type}*)luaL_testudata(L, -1, "sokol.{inner_struct_name}");')
        l(f'                        if (val) ud->{field_name}[i] = *val;')
        l(f'                    }}')
    elif is_enum_type(array_type):
        l(f'                    ud->{field_name}[i] = ({array_type})lua_tointeger(L, -1);')
    l(f'                }}')
    l(f'                lua_pop(L, 1);')
    l(f'            }}')
    l(f'        }}')
    l(f'        lua_pop(L, 1);')

def gen_struct_new(struct_name, c_struct_name, fields, prefix):
    """Generate a constructor function for a struct that accepts optional table"""
    # Special case for sg_range: accept string as binary data
    if c_struct_name == 'sg_range':
        l(f'static int l_{c_struct_name}_new(lua_State *L) {{')
        l(f'    /* sg_range can be created from a string (binary data) or table */')
        l(f'    {c_struct_name}* ud = ({c_struct_name}*)lua_newuserdatauv(L, sizeof({c_struct_name}), 1);')
        l(f'    memset(ud, 0, sizeof({c_struct_name}));')
        l(f'    luaL_setmetatable(L, "sokol.{struct_name}");')
        l('')
        l('    if (lua_isstring(L, 1)) {')
        l('        /* Initialize from string (binary data) */')
        l('        size_t len;')
        l('        const char* data = lua_tolstring(L, 1, &len);')
        l('        ud->ptr = data;')
        l('        ud->size = len;')
        l('        /* Keep reference to string to prevent GC */')
        l('        lua_pushvalue(L, 1);')
        l('        lua_setiuservalue(L, -2, 1);')
        l('    } else if (lua_istable(L, 1)) {')
        l('        lua_getfield(L, 1, "ptr");')
        l('        if (!lua_isnil(L, -1)) ud->ptr = lua_touserdata(L, -1);')
        l('        lua_pop(L, 1);')
        l('        lua_getfield(L, 1, "size");')
        l('        if (!lua_isnil(L, -1)) ud->size = (size_t)lua_tointeger(L, -1);')
        l('        lua_pop(L, 1);')
        l('    }')
        l('    return 1;')
        l('}')
        l('')
        return

    l(f'static int l_{c_struct_name}_new(lua_State *L) {{')
    l(f'    {c_struct_name}* ud = ({c_struct_name}*)lua_newuserdatauv(L, sizeof({c_struct_name}), 0);')
    l(f'    memset(ud, 0, sizeof({c_struct_name}));')
    l(f'    luaL_setmetatable(L, "sokol.{struct_name}");')
    l('')
    l('    /* If first arg is a table, use it to initialize fields */')
    l('    if (lua_istable(L, 1)) {')

    for field in fields:
        field_name = field['name']
        field_type = field['type']
        if util.is_func_ptr(field_type):
            continue
        if util.is_1d_array_type(field_type):
            gen_array_field_init(field_name, field_type, prefix)
            continue
        if util.is_2d_array_type(field_type):
            continue  # Skip 2D arrays for now
        l(f'        lua_getfield(L, 1, "{field_name}");')
        l(f'        if (!lua_isnil(L, -1)) {{')
        if field_type == 'bool':
            l(f'            ud->{field_name} = lua_toboolean(L, -1);')
        elif is_int_type(field_type):
            l(f'            ud->{field_name} = ({field_type})lua_tointeger(L, -1);')
        elif is_float_type(field_type):
            l(f'            ud->{field_name} = ({field_type})lua_tonumber(L, -1);')
        elif util.is_string_ptr(field_type):
            l(f'            ud->{field_name} = lua_tostring(L, -1);')
        elif is_struct_type(field_type):
            inner_struct_name = as_struct_metatable_name(field_type)
            # Special case: sg_range can be initialized from a string
            if field_type == 'sg_range':
                l(f'            if (lua_isstring(L, -1)) {{')
                l(f'                /* Initialize sg_range from binary string */')
                l(f'                size_t len;')
                l(f'                const char* data = lua_tolstring(L, -1, &len);')
                l(f'                ud->{field_name}.ptr = data;')
                l(f'                ud->{field_name}.size = len;')
                l(f'            }} else if (lua_istable(L, -1)) {{')
            else:
                l(f'            if (lua_istable(L, -1)) {{')
            l(f'                /* Initialize from inline table */')
            l(f'                lua_pushcfunction(L, l_{field_type}_new);')
            l(f'                lua_pushvalue(L, -2);')
            l(f'                lua_call(L, 1, 1);')
            l(f'                {field_type}* val = ({field_type}*)luaL_testudata(L, -1, "sokol.{inner_struct_name}");')
            l(f'                if (val) ud->{field_name} = *val;')
            l(f'                lua_pop(L, 1);')
            l(f'            }} else {{')
            l(f'                {field_type}* val = ({field_type}*)luaL_testudata(L, -1, "sokol.{inner_struct_name}");')
            l(f'                if (val) ud->{field_name} = *val;')
            l(f'            }}')
        elif is_enum_type(field_type):
            l(f'            ud->{field_name} = ({field_type})lua_tointeger(L, -1);')
        elif util.is_void_ptr(field_type) or util.is_const_void_ptr(field_type):
            l(f'            ud->{field_name} = lua_touserdata(L, -1);')
        l('        }')
        l('        lua_pop(L, 1);')

    l('    }')
    l('    return 1;')
    l('}')
    l('')

def gen_struct_field_getter(struct_name, c_struct_name, field, prefix):
    """Generate a getter for a struct field"""
    field_name = field['name']
    field_type = field['type']

    l(f'static int l_{c_struct_name}_get_{field_name}(lua_State *L) {{')
    l(f'    {c_struct_name}* self = ({c_struct_name}*)luaL_checkudata(L, 1, "sokol.{struct_name}");')

    if util.is_1d_array_type(field_type):
        array_type = util.extract_array_type(field_type)
        array_sizes = util.extract_array_sizes(field_type)
        size = array_sizes[0]
        l(f'    lua_newtable(L);')
        l(f'    for (int i = 0; i < {size}; i++) {{')
        if array_type == 'bool':
            l(f'        lua_pushboolean(L, self->{field_name}[i]);')
        elif is_int_type(array_type):
            l(f'        lua_pushinteger(L, (lua_Integer)self->{field_name}[i]);')
        elif is_float_type(array_type):
            l(f'        lua_pushnumber(L, (lua_Number)self->{field_name}[i]);')
        elif is_struct_type(array_type):
            inner_struct_name = as_struct_metatable_name(array_type)
            l(f'        {array_type}* ud = ({array_type}*)lua_newuserdatauv(L, sizeof({array_type}), 0);')
            l(f'        *ud = self->{field_name}[i];')
            l(f'        luaL_setmetatable(L, "sokol.{inner_struct_name}");')
        elif is_enum_type(array_type):
            l(f'        lua_pushinteger(L, (lua_Integer)self->{field_name}[i]);')
        else:
            l(f'        lua_pushnil(L); /* unsupported array type */')
        l(f'        lua_rawseti(L, -2, i + 1);')
        l(f'    }}')
    elif util.is_2d_array_type(field_type):
        l(f'    /* 2D array not yet supported */')
        l('    lua_pushnil(L);')
    else:
        push_code = get_lua_push_code(field_type, f'self->{field_name}', prefix)
        if push_code:
            l(f'    {push_code}')
        else:
            l('    lua_pushnil(L);')

    l('    return 1;')
    l('}')
    l('')

def gen_struct_field_setter(struct_name, c_struct_name, field, prefix):
    """Generate a setter for a struct field"""
    field_name = field['name']
    field_type = field['type']

    l(f'static int l_{c_struct_name}_set_{field_name}(lua_State *L) {{')
    l(f'    {c_struct_name}* self = ({c_struct_name}*)luaL_checkudata(L, 1, "sokol.{struct_name}");')

    if util.is_1d_array_type(field_type):
        array_type = util.extract_array_type(field_type)
        array_sizes = util.extract_array_sizes(field_type)
        size = array_sizes[0]
        l(f'    luaL_checktype(L, 2, LUA_TTABLE);')
        l(f'    for (int i = 0; i < {size}; i++) {{')
        l(f'        lua_rawgeti(L, 2, i + 1);')
        l(f'        if (!lua_isnil(L, -1)) {{')
        if array_type == 'bool':
            l(f'            self->{field_name}[i] = lua_toboolean(L, -1);')
        elif is_int_type(array_type):
            l(f'            self->{field_name}[i] = ({array_type})lua_tointeger(L, -1);')
        elif is_float_type(array_type):
            l(f'            self->{field_name}[i] = ({array_type})lua_tonumber(L, -1);')
        elif is_struct_type(array_type):
            inner_struct_name = as_struct_metatable_name(array_type)
            l(f'            {array_type}* val = ({array_type}*)luaL_testudata(L, -1, "sokol.{inner_struct_name}");')
            l(f'            if (val) self->{field_name}[i] = *val;')
        elif is_enum_type(array_type):
            l(f'            self->{field_name}[i] = ({array_type})lua_tointeger(L, -1);')
        l(f'        }}')
        l(f'        lua_pop(L, 1);')
        l(f'    }}')
    elif util.is_2d_array_type(field_type):
        l(f'    /* 2D array not yet supported */')
    elif util.is_func_ptr(field_type):
        l(f'    /* Function pointer field not supported */')
    else:
        if field_type == 'bool':
            l(f'    self->{field_name} = lua_toboolean(L, 2);')
        elif is_int_type(field_type):
            l(f'    self->{field_name} = ({field_type})luaL_checkinteger(L, 2);')
        elif is_float_type(field_type):
            l(f'    self->{field_name} = ({field_type})luaL_checknumber(L, 2);')
        elif util.is_string_ptr(field_type):
            l(f'    self->{field_name} = luaL_checkstring(L, 2);')
        elif is_struct_type(field_type):
            inner_struct_name = as_struct_metatable_name(field_type)
            l(f'    {field_type}* val = ({field_type}*)luaL_checkudata(L, 2, "sokol.{inner_struct_name}");')
            l(f'    self->{field_name} = *val;')
        elif is_enum_type(field_type):
            l(f'    self->{field_name} = ({field_type})luaL_checkinteger(L, 2);')
        elif util.is_void_ptr(field_type) or util.is_const_void_ptr(field_type):
            l(f'    self->{field_name} = lua_touserdata(L, 2);')
        else:
            l(f'    /* TODO: set {field_type} */')

    l('    return 0;')
    l('}')
    l('')

def gen_struct_index(struct_name, c_struct_name, fields, prefix):
    """Generate __index metamethod for struct"""
    l(f'static int l_{c_struct_name}__index(lua_State *L) {{')
    l(f'    const char* key = luaL_checkstring(L, 2);')

    for field in fields:
        field_name = field['name']
        if util.is_func_ptr(field['type']):
            continue
        l(f'    if (strcmp(key, "{field_name}") == 0) return l_{c_struct_name}_get_{field_name}(L);')

    l('    return 0;')
    l('}')
    l('')

def gen_struct_newindex(struct_name, c_struct_name, fields, prefix):
    """Generate __newindex metamethod for struct"""
    l(f'static int l_{c_struct_name}__newindex(lua_State *L) {{')
    l(f'    const char* key = luaL_checkstring(L, 2);')

    for field in fields:
        field_name = field['name']
        if util.is_func_ptr(field['type']):
            continue
        l(f'    if (strcmp(key, "{field_name}") == 0) return l_{c_struct_name}_set_{field_name}(L);')

    l(f'    return luaL_error(L, "unknown field: %s", key);')
    l('}')
    l('')

def gen_struct_bindings(decl, prefix):
    """Generate all bindings for a struct"""
    c_struct_name = decl['name']
    struct_name = as_pascal_case(c_struct_name, prefix)
    fields = [f for f in decl['fields'] if 'name' in f]

    # Generate constructor
    gen_struct_new(struct_name, c_struct_name, fields, prefix)

    # Generate field accessors
    for field in fields:
        if not util.is_func_ptr(field['type']):
            gen_struct_field_getter(struct_name, c_struct_name, field, prefix)
            gen_struct_field_setter(struct_name, c_struct_name, field, prefix)

    # Generate metamethods
    gen_struct_index(struct_name, c_struct_name, fields, prefix)
    gen_struct_newindex(struct_name, c_struct_name, fields, prefix)

def get_enum_item_short_name(enum_name, item_name, prefix):
    """Get a short name for an enum item by stripping common prefixes"""
    item_upper = item_name.upper()

    # Build possible prefixes from enum name
    # sg_load_action -> SG_LOADACTION_ or SGLOADACTION_
    enum_upper = enum_name.upper()
    # Remove trailing _t if present
    if enum_upper.endswith('_T'):
        enum_upper = enum_upper[:-2]

    # Try: SG_LOADACTION_ (keeping underscores between module and rest)
    # enum is sg_load_action, items are SG_LOADACTION_CLEAR
    # so we want to find the common part: SG_ + LOADACTION_ = SG_LOADACTION_
    possible_prefixes = []

    # Try exact match with underscores removed after module prefix
    # sg_load_action -> sg_ + load_action -> SG_ + LOADACTION
    parts = enum_name.split('_')
    if len(parts) >= 2:
        module_part = parts[0].upper() + '_'
        rest_part = ''.join(parts[1:]).upper() + '_'
        possible_prefixes.append(module_part + rest_part)
        possible_prefixes.append('_' + module_part + rest_part)

    # Try just module prefix (SG_, SAPP_, etc.)
    module_prefix = prefix.upper()
    possible_prefixes.append(module_prefix)
    possible_prefixes.append('_' + module_prefix)

    for pfx in possible_prefixes:
        if item_upper.startswith(pfx):
            return item_name[len(pfx):]

    return item_name

def gen_enum_constants(decl, prefix):
    """Generate enum constants registration"""
    enum_name = decl['name']
    lua_enum_name = as_pascal_case(enum_name, prefix)

    l(f'static void register_{enum_name}(lua_State *L) {{')
    l(f'    lua_newtable(L);')

    for item in decl['items']:
        item_name = item['name']
        short_name = get_enum_item_short_name(enum_name, item_name, prefix)

        if 'value' in item:
            l(f'    lua_pushinteger(L, {item["value"]});')
        else:
            l(f'    lua_pushinteger(L, {item_name});')
        l(f'    lua_setfield(L, -2, "{short_name}");')

    l(f'    lua_setfield(L, -2, "{lua_enum_name}");')
    l('}')
    l('')

consts_counter = 0

def gen_consts(decl, prefix):
    """Generate anonymous enum constants"""
    global consts_counter
    consts_counter += 1
    l(f'static void register_consts_{consts_counter}(lua_State *L) {{')
    for item in decl['items']:
        item_name = item['name']
        lua_name = as_snake_case(item_name, prefix).upper()
        l(f'    lua_pushinteger(L, {item["value"]});')
        l(f'    lua_setfield(L, -2, "{lua_name}");')
    l('}')
    l('')
    return consts_counter

def gen_metatable_registration(structs, prefix):
    """Generate code to register all metatables"""
    l('static void register_metatables(lua_State *L) {')

    for struct_decl in structs:
        c_struct_name = struct_decl['name']
        struct_name = as_pascal_case(c_struct_name, prefix)

        l(f'    luaL_newmetatable(L, "sokol.{struct_name}");')
        l(f'    lua_pushcfunction(L, l_{c_struct_name}__index);')
        l(f'    lua_setfield(L, -2, "__index");')
        l(f'    lua_pushcfunction(L, l_{c_struct_name}__newindex);')
        l(f'    lua_setfield(L, -2, "__newindex");')
        l(f'    lua_pop(L, 1);')
        l('')

    l('}')
    l('')

def gen_luaopen(module_name, prefix, funcs, structs, enums, consts_ids):
    """Generate the luaopen function"""
    l(f'static const luaL_Reg {module_name}_funcs[] = {{')

    # Add function wrappers
    for func_decl in funcs:
        func_name = func_decl['name']
        lua_name = as_snake_case(func_name, prefix)
        l(f'    {{"{lua_name}", l_{func_name}}},')

    # Add struct constructors
    for struct_decl in structs:
        c_struct_name = struct_decl['name']
        lua_name = as_pascal_case(c_struct_name, prefix)
        l(f'    {{"{lua_name}", l_{c_struct_name}_new}},')

    l('    {NULL, NULL}')
    l('};')
    l('')

    l(f'MANE3D_API int luaopen_sokol_{module_name}(lua_State *L) {{')
    l('    register_metatables(L);')
    l(f'    luaL_newlib(L, {module_name}_funcs);')

    # Register enums
    for enum_decl in enums:
        enum_name = enum_decl['name']
        l(f'    register_{enum_name}(L);')

    # Register anonymous consts
    for const_id in consts_ids:
        l(f'    register_consts_{const_id}(L);')

    l('    return 1;')
    l('}')

def pre_parse(inp):
    global struct_types
    global enum_types
    for decl in inp['decls']:
        kind = decl['kind']
        if kind == 'struct':
            struct_types.append(decl['name'])
        elif kind == 'enum':
            enum_types.append(decl['name'])

def gen_module(inp, c_prefix, dep_prefixes):
    pre_parse(inp)
    module_name = module_names[c_prefix]
    prefix = inp['prefix']

    # Header
    l('/* machine generated, do not edit */')
    l('#include <lua.h>')
    l('#include <lauxlib.h>')
    l('#include <lualib.h>')
    l('#include <string.h>')
    l('')

    # Include sokol headers
    for dep_prefix in dep_prefixes:
        dep_module = module_names.get(dep_prefix)
        if dep_module:
            l(f'#include "{header_names[dep_prefix]}"')

    # sokol_glue needs sokol_app.h
    if c_prefix == 'sglue_':
        l('#include "sokol_app.h"')

    # Determine header name
    if c_prefix in ['sgl_', 'sdtx_', 'sshape_']:
        header_subdir = 'util/'
    else:
        header_subdir = ''
    header_name = {
        'slog_': 'sokol_log.h',
        'sg_': 'sokol_gfx.h',
        'sapp_': 'sokol_app.h',
        'stm_': 'sokol_time.h',
        'saudio_': 'sokol_audio.h',
        'sgl_': 'sokol_gl.h',
        'sdtx_': 'sokol_debugtext.h',
        'sshape_': 'sokol_shape.h',
        'sglue_': 'sokol_glue.h',
    }.get(c_prefix, f'sokol_{module_name}.h')

    l(f'#include "{header_name}"')
    l('')

    l('#ifndef MANE3D_API')
    l('  #ifdef _WIN32')
    l('    #ifdef MANE3D_EXPORTS')
    l('      #define MANE3D_API __declspec(dllexport)')
    l('    #else')
    l('      #define MANE3D_API __declspec(dllimport)')
    l('    #endif')
    l('  #else')
    l('    #define MANE3D_API')
    l('  #endif')
    l('#endif')
    l('')

    # Collect declarations by type
    funcs = []
    structs = []
    enums = []
    consts = []

    for decl in inp['decls']:
        if decl['is_dep']:
            continue
        kind = decl['kind']
        if kind == 'func' and not check_ignore(decl['name']) and not is_callback_func(decl['name']):
            funcs.append(decl)
        elif kind == 'struct':
            structs.append(decl)
        elif kind == 'enum':
            enums.append(decl)
        elif kind == 'consts':
            consts.append(decl)

    # Generate struct bindings
    for struct_decl in structs:
        gen_struct_bindings(struct_decl, prefix)

    # Generate function wrappers
    for func_decl in funcs:
        gen_func_wrapper(func_decl, prefix)

    # Generate enum registration functions
    for enum_decl in enums:
        gen_enum_constants(enum_decl, prefix)

    # Generate const registration
    consts_ids = []
    for const_decl in consts:
        const_id = gen_consts(const_decl, prefix)
        consts_ids.append(const_id)

    # Generate metatable registration
    gen_metatable_registration(structs, prefix)

    # Generate luaopen function
    gen_luaopen(module_name, prefix, funcs, structs, enums, consts_ids)

def get_csource_path(c_prefix):
    return f'{stubs_root}/{c_source_names[c_prefix]}'

def create_stub_c_file(c_prefix, dep_prefixes):
    """Create a stub .c file that includes the header for clang parsing"""
    if c_prefix not in header_names:
        return
    header = header_names[c_prefix]
    c_file = c_source_names[c_prefix]
    stub_content = ''
    # Include dependency headers first
    for dep_prefix in dep_prefixes:
        if dep_prefix in header_names:
            stub_content += f'#include "{header_names[dep_prefix]}"\n'
    stub_content += f'#include "{header}"\n'
    with open(f'{stubs_root}/{c_file}', 'w', newline='\n') as f:
        f.write(stub_content)

types_root = f'{bindings_root}/gen/types'

def lua_type_from_c(type_str, prefix):
    """Convert C type to LuaCATS type annotation"""
    if type_str == 'void':
        return 'nil'
    elif type_str == 'bool':
        return 'boolean'
    elif is_int_type(type_str):
        return 'integer'
    elif is_float_type(type_str):
        return 'number'
    elif util.is_string_ptr(type_str):
        return 'string'
    elif type_str == 'sg_range' or type_str == 'const sg_range *' or type_str == 'sg_range *':
        return 'gfx.Range|string'
    elif is_struct_type(type_str):
        module = module_names.get(get_type_prefix(type_str), 'sokol')
        struct_name = as_struct_metatable_name(type_str)
        return f'{module}.{struct_name}'
    elif is_const_struct_ptr(type_str) or is_struct_ptr(type_str):
        inner_type = util.extract_ptr_type(type_str)
        module = module_names.get(get_type_prefix(inner_type), 'sokol')
        struct_name = as_struct_metatable_name(inner_type)
        return f'{module}.{struct_name}'
    elif is_enum_type(type_str):
        type_prefix = get_type_prefix(type_str)
        # Cross-module enum references use integer to avoid undefined type warnings
        if type_prefix != prefix:
            return 'integer'
        module = module_names.get(type_prefix, 'sokol')
        enum_name = as_pascal_case(type_str, type_prefix or '')
        return f'{module}.{enum_name}'
    elif util.is_void_ptr(type_str) or util.is_const_void_ptr(type_str):
        return 'lightuserdata?'
    elif util.is_1d_array_type(type_str):
        inner = util.extract_array_type(type_str)
        inner_lua = lua_type_from_c(inner, prefix)
        return f'{inner_lua}[]'
    else:
        return 'any'

def gen_luacats_types(inp, prefix, module_name):
    """Generate LuaCATS type definition file"""
    lines = []
    lines.append('---@meta')
    lines.append(f'-- LuaCATS type definitions for sokol.{module_name}')
    lines.append(f'-- Auto-generated, do not edit')
    lines.append('')

    # Collect structs and enums
    structs = []
    enums = []
    funcs = []
    for decl in inp['decls']:
        if decl.get('is_dep'):
            continue
        kind = decl['kind']
        if kind == 'struct':
            structs.append(decl)
        elif kind == 'enum':
            enums.append(decl)
        elif kind == 'func' and not check_ignore(decl['name']):
            funcs.append(decl)

    # Generate struct types first (so they're defined before being referenced)
    for struct_decl in structs:
        struct_name = as_struct_metatable_name(struct_decl['name'])
        lines.append(f'---@class {module_name}.{struct_name}')
        for field in struct_decl.get('fields', []):
            field_name = field['name']
            field_type = field['type']
            lua_type = lua_type_from_c(field_type, prefix)
            # Handle sg_range specially - can be string
            if field_type == 'sg_range':
                lua_type = 'gfx.Range|string'
            lines.append(f'---@field {field_name}? {lua_type}')
        lines.append('')

    # Define module class with struct constructors as fields
    lines.append(f'---@class {module_name}')
    for struct_decl in structs:
        c_struct_name = struct_decl['name']
        struct_name = as_struct_metatable_name(c_struct_name)
        # sg_range can be initialized from string
        if c_struct_name == 'sg_range':
            lines.append(f'---@field {struct_name} fun(t?: {module_name}.{struct_name}|string): {module_name}.{struct_name}')
        else:
            lines.append(f'---@field {struct_name} fun(t?: {module_name}.{struct_name}): {module_name}.{struct_name}')
    lines.append(f'local {module_name} = {{}}')
    lines.append('')

    # Generate enum types with actual values (LuaCATS @enum)
    for enum_decl in enums:
        enum_name = as_pascal_case(enum_decl['name'], prefix)
        lines.append(f'---@enum {module_name}.{enum_name}')
        lines.append(f'{module_name}.{enum_name} = {{')
        next_value = 0
        for item in enum_decl['items']:
            short_name = get_enum_item_short_name(enum_decl['name'], item['name'], prefix)
            if short_name == 'FORCE_U32':
                continue
            if 'value' in item:
                next_value = int(item['value'])
            # Quote keys that start with digits for valid Lua syntax
            if short_name[0].isdigit():
                lines.append(f'    ["{short_name}"] = {next_value},')
            else:
                lines.append(f'    {short_name} = {next_value},')
            next_value += 1
        lines.append('}')
        lines.append('')

    # Lua reserved keywords
    lua_keywords = {'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for',
                    'function', 'goto', 'if', 'in', 'local', 'nil', 'not', 'or',
                    'repeat', 'return', 'then', 'true', 'until', 'while'}

    # Generate function types
    for func_decl in funcs:
        if is_callback_func(func_decl['name']):
            continue
        func_name = as_snake_case(func_decl['name'], prefix)
        params = func_decl.get('params', [])
        result_type = get_result_type(func_decl)

        # Build param annotations
        for param in params:
            param_name = param['name']
            param_type = param['type']
            lua_type = lua_type_from_c(param_type, prefix)
            lines.append(f'---@param {param_name} {lua_type}')

        # Return type
        if result_type != 'void':
            lua_ret = lua_type_from_c(result_type, prefix)
            lines.append(f'---@return {lua_ret}')

        # Function signature - use bracket syntax for reserved keywords
        param_names = ', '.join(p['name'] for p in params)
        if func_name in lua_keywords:
            lines.append(f'{module_name}["{func_name}"] = function({param_names}) end')
        else:
            lines.append(f'function {module_name}.{func_name}({param_names}) end')
        lines.append('')

    lines.append(f'return {module_name}')
    return '\n'.join(lines)

def prepare():
    print('=== Generating Lua bindings:')
    if not os.path.isdir(module_root):
        os.makedirs(module_root)
    if not os.path.isdir(stubs_root):
        os.makedirs(stubs_root)
    if not os.path.isdir(types_root):
        os.makedirs(types_root)

def gen(c_header_path, c_prefix, dep_c_prefixes):
    if c_prefix not in module_names:
        print(f'  >> warning: skipping generation for {c_prefix} prefix...')
        return
    reset_globals()
    print(f'  {c_header_path} => {module_names[c_prefix]}')
    # Copy header file to stubs dir for clang parsing
    shutil.copyfile(c_header_path, f'{stubs_root}/{os.path.basename(c_header_path)}')
    # Copy dependency headers
    for dep_prefix in dep_c_prefixes:
        if dep_prefix in header_names:
            dep_header = header_names[dep_prefix]
            dep_header_path = c_header_path.replace(os.path.basename(c_header_path), dep_header)
            if os.path.exists(dep_header_path):
                shutil.copyfile(dep_header_path, f'{stubs_root}/{dep_header}')
    # Create stub .c file for clang parsing
    create_stub_c_file(c_prefix, dep_c_prefixes)
    csource_path = os.path.abspath(get_csource_path(c_prefix))
    module_name = module_names[c_prefix]
    # Change to stubs dir so gen_ir writes .json there
    orig_dir = os.getcwd()
    os.chdir(stubs_root)
    ir = gen_ir.gen(c_header_path, csource_path, module_name, c_prefix, dep_c_prefixes)
    os.chdir(orig_dir)
    gen_module(ir, c_prefix, dep_c_prefixes)
    with open(f"{module_root}/sokol_{module_name}.c", 'w', newline='\n') as f_outp:
        f_outp.write(out_lines)
    # Generate LuaCATS type definitions
    prefix = ir['prefix']
    luacats_content = gen_luacats_types(ir, prefix, module_name)
    types_sokol_dir = f"{types_root}/sokol"
    if not os.path.isdir(types_sokol_dir):
        os.makedirs(types_sokol_dir)
    with open(f"{types_sokol_dir}/{module_name}.lua", 'w', newline='\n') as f_types:
        f_types.write(luacats_content)

module_deps = {
    'slog_':    [],
    'sg_':      ['slog_'],
    'sapp_':    ['slog_'],
    'stm_':     [],
    'saudio_':  ['slog_'],
    'sgl_':     ['slog_', 'sg_'],
    'sdtx_':    ['slog_', 'sg_'],
    'sshape_':  ['slog_', 'sg_'],
    'sglue_':   ['slog_', 'sg_', 'sapp_'],
}

if __name__ == '__main__':
    prepare()
    for prefix in module_names:
        header_path = header_paths.get(prefix)
        deps = module_deps.get(prefix, [])
        gen(f'{sokol_root}/{header_path}', prefix, deps)
