"""
Struct binding generation module

Generates constructors, field accessors, and metamethods for struct types.
"""

from dataclasses import dataclass, field
from typing import Optional, TYPE_CHECKING

from .codegen import (
    CodeGen, as_pascal_case,
    is_int_type, is_float_type, is_string_ptr,
    is_void_ptr, is_const_void_ptr, is_func_ptr,
    is_1d_array_type, is_2d_array_type,
    extract_array_type, extract_array_sizes,
)

if TYPE_CHECKING:
    from .ir import IR, StructInfo, FieldInfo
    from .types import TypeConverter
    from .callback import CallbackGenerator, CallbackConfig


@dataclass
class StructHandler:
    """Configuration for struct binding generation"""
    callbacks: dict[str, 'CallbackConfig'] = field(default_factory=dict)
    custom_init: bool = False
    validate_keys: bool = False
    skip_fields: list[str] = field(default_factory=list)


class StructGenerator:
    """Generates struct bindings"""

    def __init__(self, ir: 'IR', type_conv: 'TypeConverter', callback_gen: 'CallbackGenerator',
                 prefix: str, all_prefixes: list[str]):
        self.ir = ir
        self.type_conv = type_conv
        self.callback_gen = callback_gen
        self.prefix = prefix
        self.all_prefixes = all_prefixes
        self._handlers: dict[str, StructHandler] = {}

    def register_handler(self, struct_name: str, handler: StructHandler):
        """Register custom handler for a struct"""
        self._handlers[struct_name] = handler

    def get_handler(self, struct_name: str) -> StructHandler:
        """Get handler for struct (or default)"""
        return self._handlers.get(struct_name, StructHandler())

    def get_metatable_name(self, struct_name: str) -> str:
        """Get metatable name for struct"""
        for pfx in self.all_prefixes:
            if struct_name.startswith(pfx):
                return as_pascal_case(struct_name, pfx)
        parts = struct_name.lower().split('_')
        return ''.join(part.capitalize() for part in parts if part != 't')

    def generate(self, struct: 'StructInfo', gen: CodeGen):
        """Generate all bindings for a struct"""
        handler = self.get_handler(struct.name)
        fields = [f for f in struct.fields if f.name not in handler.skip_fields]
        callback_fields = [f for f in fields if is_func_ptr(f.type) and '...' not in f.type]

        # Generate shared lua_State for callbacks
        if callback_fields:
            gen.line(f'static lua_State* g_{struct.name}_L = NULL;')
            gen.line()

        # Generate callback trampolines
        for field in callback_fields:
            cb_config = handler.callbacks.get(field.name)
            self.callback_gen.generate_trampoline(struct.name, field, cb_config, gen)

        # Generate constructor
        self._gen_constructor(struct.name, fields, handler, gen)

        # Generate field accessors
        for field in fields:
            if not is_func_ptr(field.type):
                self._gen_getter(struct.name, field, gen)
                self._gen_setter(struct.name, field, gen)

        # Generate metamethods
        self._gen_index(struct.name, fields, gen)
        self._gen_newindex(struct.name, fields, gen)

    def _gen_constructor(self, struct_name: str, fields: list['FieldInfo'],
                         handler: StructHandler, gen: CodeGen):
        """Generate constructor function"""
        mt_name = self.get_metatable_name(struct_name)

        # Special case: sg_range can be created from string (binary data)
        if struct_name == 'sg_range':
            self._gen_sg_range_constructor(gen)
            return

        gen.line(f'static int l_{struct_name}_new(lua_State *L) {{')
        gen.indent()

        # Create userdata
        gen.line(f'{struct_name}* ud = ({struct_name}*)lua_newuserdatauv(L, sizeof({struct_name}), 0);')
        gen.line(f'memset(ud, 0, sizeof({struct_name}));')
        gen.line(f'luaL_setmetatable(L, "sokol.{mt_name}");')
        gen.line()

        # Initialize from table
        gen.line('/* If first arg is a table, use it to initialize fields */')
        gen.line('if (lua_istable(L, 1)) {')
        gen.indent()

        for field in fields:
            if is_func_ptr(field.type):
                if '...' in field.type:
                    continue
                cb_config = handler.callbacks.get(field.name)
                self.callback_gen.generate_struct_init(struct_name, field.name, cb_config, gen)
            elif is_1d_array_type(field.type):
                self._gen_array_init(struct_name, field, gen)
            elif is_2d_array_type(field.type):
                continue  # Skip 2D arrays
            else:
                self._gen_field_init(struct_name, field, gen)

        gen.dedent()
        gen.line('}')
        gen.line('return 1;')
        gen.dedent()
        gen.line('}')
        gen.line()

    def _gen_sg_range_constructor(self, gen: CodeGen):
        """Generate special constructor for sg_range that accepts string"""
        gen.line('static int l_sg_range_new(lua_State *L) {')
        gen.indent()
        gen.line('/* sg_range can be created from a string (binary data) or table */')
        gen.line('sg_range* ud = (sg_range*)lua_newuserdatauv(L, sizeof(sg_range), 1);')
        gen.line('memset(ud, 0, sizeof(sg_range));')
        gen.line('luaL_setmetatable(L, "sokol.Range");')
        gen.line()
        gen.line('if (lua_isstring(L, 1)) {')
        gen.indent()
        gen.line('/* Initialize from string (binary data) */')
        gen.line('size_t len;')
        gen.line('const char* data = lua_tolstring(L, 1, &len);')
        gen.line('ud->ptr = data;')
        gen.line('ud->size = len;')
        gen.line('/* Keep reference to string to prevent GC */')
        gen.line('lua_pushvalue(L, 1);')
        gen.line('lua_setiuservalue(L, -2, 1);')
        gen.dedent()
        gen.line('} else if (lua_istable(L, 1)) {')
        gen.indent()
        gen.line('lua_getfield(L, 1, "ptr");')
        gen.line('if (!lua_isnil(L, -1)) ud->ptr = lua_touserdata(L, -1);')
        gen.line('lua_pop(L, 1);')
        gen.line('lua_getfield(L, 1, "size");')
        gen.line('if (!lua_isnil(L, -1)) ud->size = (size_t)lua_tointeger(L, -1);')
        gen.line('lua_pop(L, 1);')
        gen.dedent()
        gen.line('}')
        gen.line('return 1;')
        gen.dedent()
        gen.line('}')
        gen.line()

    def _gen_field_init(self, struct_name: str, field: 'FieldInfo', gen: CodeGen):
        """Generate field initialization from table"""
        name = field.name
        ftype = field.type

        gen.line(f'lua_getfield(L, 1, "{name}");')
        gen.line('if (!lua_isnil(L, -1)) {')
        gen.indent()

        if ftype == 'bool':
            gen.line(f'ud->{name} = lua_toboolean(L, -1);')
        elif is_int_type(ftype):
            gen.line(f'ud->{name} = ({ftype})lua_tointeger(L, -1);')
        elif is_float_type(ftype):
            gen.line(f'ud->{name} = ({ftype})lua_tonumber(L, -1);')
        elif is_string_ptr(ftype):
            gen.line(f'ud->{name} = lua_tostring(L, -1);')
        elif self.ir.is_struct_type(ftype):
            inner_mt = self.get_metatable_name(ftype)
            # Special case: sg_range can be initialized from a string
            if ftype == 'sg_range':
                gen.line('if (lua_isstring(L, -1)) {')
                gen.indent()
                gen.line('/* Initialize sg_range from binary string */')
                gen.line('size_t len;')
                gen.line('const char* data = lua_tolstring(L, -1, &len);')
                gen.line(f'ud->{name}.ptr = data;')
                gen.line(f'ud->{name}.size = len;')
                gen.dedent()
                gen.line('} else if (lua_istable(L, -1)) {')
            else:
                gen.line('if (lua_istable(L, -1)) {')
            gen.indent()
            gen.line('/* Initialize from inline table */')
            gen.line(f'lua_pushcfunction(L, l_{ftype}_new);')
            gen.line('lua_pushvalue(L, -2);')
            gen.line('lua_call(L, 1, 1);')
            gen.line(f'{ftype}* val = ({ftype}*)luaL_testudata(L, -1, "sokol.{inner_mt}");')
            gen.line(f'if (val) ud->{name} = *val;')
            gen.line('lua_pop(L, 1);')
            gen.dedent()
            gen.line('} else {')
            gen.indent()
            gen.line(f'{ftype}* val = ({ftype}*)luaL_testudata(L, -1, "sokol.{inner_mt}");')
            gen.line(f'if (val) ud->{name} = *val;')
            gen.dedent()
            gen.line('}')
        elif self.ir.is_enum_type(ftype):
            gen.line(f'ud->{name} = ({ftype})lua_tointeger(L, -1);')
        elif is_void_ptr(ftype) or is_const_void_ptr(ftype):
            gen.line(f'ud->{name} = lua_touserdata(L, -1);')

        gen.dedent()
        gen.line('}')
        gen.line('lua_pop(L, 1);')

    def _gen_array_init(self, struct_name: str, field: 'FieldInfo', gen: CodeGen):
        """Generate array field initialization from table"""
        name = field.name
        ftype = field.type
        array_type = extract_array_type(ftype)
        sizes = extract_array_sizes(ftype)
        size = sizes[0] if sizes else 0

        gen.line(f'lua_getfield(L, 1, "{name}");')
        gen.line('if (lua_istable(L, -1)) {')
        gen.indent()
        gen.line(f'for (int i = 0; i < {size}; i++) {{')
        gen.indent()
        gen.line('lua_rawgeti(L, -1, i + 1);')
        gen.line('if (!lua_isnil(L, -1)) {')
        gen.indent()

        if array_type == 'bool':
            gen.line(f'ud->{name}[i] = lua_toboolean(L, -1);')
        elif is_int_type(array_type):
            gen.line(f'ud->{name}[i] = ({array_type})lua_tointeger(L, -1);')
        elif is_float_type(array_type):
            gen.line(f'ud->{name}[i] = ({array_type})lua_tonumber(L, -1);')
        elif self.ir.is_struct_type(array_type):
            inner_mt = self.get_metatable_name(array_type)
            # Special case: sg_range can be initialized from a string
            if array_type == 'sg_range':
                gen.line('if (lua_isstring(L, -1)) {')
                gen.indent()
                gen.line('/* Initialize sg_range from binary string */')
                gen.line('size_t len;')
                gen.line('const char* data = lua_tolstring(L, -1, &len);')
                gen.line(f'ud->{name}[i].ptr = data;')
                gen.line(f'ud->{name}[i].size = len;')
                gen.dedent()
                gen.line('} else if (lua_istable(L, -1)) {')
            else:
                gen.line('if (lua_istable(L, -1)) {')
            gen.indent()
            gen.line('/* Initialize from inline table */')
            gen.line(f'lua_pushcfunction(L, l_{array_type}_new);')
            gen.line('lua_pushvalue(L, -2);')
            gen.line('lua_call(L, 1, 1);')
            gen.line(f'{array_type}* val = ({array_type}*)luaL_testudata(L, -1, "sokol.{inner_mt}");')
            gen.line(f'if (val) ud->{name}[i] = *val;')
            gen.line('lua_pop(L, 1);')
            gen.dedent()
            gen.line('} else {')
            gen.indent()
            gen.line(f'{array_type}* val = ({array_type}*)luaL_testudata(L, -1, "sokol.{inner_mt}");')
            gen.line(f'if (val) ud->{name}[i] = *val;')
            gen.dedent()
            gen.line('}')
        elif self.ir.is_enum_type(array_type):
            gen.line(f'ud->{name}[i] = ({array_type})lua_tointeger(L, -1);')

        gen.dedent()
        gen.line('}')
        gen.line('lua_pop(L, 1);')
        gen.dedent()
        gen.line('}')
        gen.dedent()
        gen.line('}')
        gen.line('lua_pop(L, 1);')

    def _gen_getter(self, struct_name: str, field: 'FieldInfo', gen: CodeGen):
        """Generate field getter"""
        name = field.name
        ftype = field.type
        mt_name = self.get_metatable_name(struct_name)

        gen.line(f'static int l_{struct_name}_get_{name}(lua_State *L) {{')
        gen.indent()
        gen.line(f'{struct_name}* self = ({struct_name}*)luaL_checkudata(L, 1, "sokol.{mt_name}");')

        if is_1d_array_type(ftype):
            self._gen_array_getter(field, gen)
        elif is_2d_array_type(ftype):
            gen.line('/* 2D array not yet supported */')
            gen.line('lua_pushnil(L);')
        else:
            push_code = self.type_conv.c_to_lua(ftype, f'self->{name}', self.prefix)
            if push_code:
                gen.line(push_code)
            else:
                gen.line('lua_pushnil(L);')

        gen.line('return 1;')
        gen.dedent()
        gen.line('}')
        gen.line()

    def _gen_array_getter(self, field: 'FieldInfo', gen: CodeGen):
        """Generate array field getter"""
        name = field.name
        ftype = field.type
        array_type = extract_array_type(ftype)
        sizes = extract_array_sizes(ftype)
        size = sizes[0] if sizes else 0

        gen.line('lua_newtable(L);')
        gen.line(f'for (int i = 0; i < {size}; i++) {{')
        gen.indent()

        if array_type == 'bool':
            gen.line(f'lua_pushboolean(L, self->{name}[i]);')
        elif is_int_type(array_type):
            gen.line(f'lua_pushinteger(L, (lua_Integer)self->{name}[i]);')
        elif is_float_type(array_type):
            gen.line(f'lua_pushnumber(L, (lua_Number)self->{name}[i]);')
        elif self.ir.is_struct_type(array_type):
            inner_mt = self.get_metatable_name(array_type)
            gen.line(f'{array_type}* ud = ({array_type}*)lua_newuserdatauv(L, sizeof({array_type}), 0);')
            gen.line(f'*ud = self->{name}[i];')
            gen.line(f'luaL_setmetatable(L, "sokol.{inner_mt}");')
        elif self.ir.is_enum_type(array_type):
            gen.line(f'lua_pushinteger(L, (lua_Integer)self->{name}[i]);')
        else:
            gen.line('lua_pushnil(L); /* unsupported array type */')

        gen.line('lua_rawseti(L, -2, i + 1);')
        gen.dedent()
        gen.line('}')

    def _gen_setter(self, struct_name: str, field: 'FieldInfo', gen: CodeGen):
        """Generate field setter"""
        name = field.name
        ftype = field.type
        mt_name = self.get_metatable_name(struct_name)

        gen.line(f'static int l_{struct_name}_set_{name}(lua_State *L) {{')
        gen.indent()
        gen.line(f'{struct_name}* self = ({struct_name}*)luaL_checkudata(L, 1, "sokol.{mt_name}");')

        if is_1d_array_type(ftype):
            self._gen_array_setter(field, gen)
        elif is_2d_array_type(ftype):
            gen.line('/* 2D array not yet supported */')
        elif ftype == 'bool':
            gen.line(f'self->{name} = lua_toboolean(L, 2);')
        elif is_int_type(ftype):
            gen.line(f'self->{name} = ({ftype})luaL_checkinteger(L, 2);')
        elif is_float_type(ftype):
            gen.line(f'self->{name} = ({ftype})luaL_checknumber(L, 2);')
        elif is_string_ptr(ftype):
            gen.line(f'self->{name} = luaL_checkstring(L, 2);')
        elif self.ir.is_struct_type(ftype):
            inner_mt = self.get_metatable_name(ftype)
            gen.line(f'{ftype}* val = ({ftype}*)luaL_checkudata(L, 2, "sokol.{inner_mt}");')
            gen.line(f'self->{name} = *val;')
        elif self.ir.is_enum_type(ftype):
            gen.line(f'self->{name} = ({ftype})luaL_checkinteger(L, 2);')
        elif is_void_ptr(ftype) or is_const_void_ptr(ftype):
            gen.line(f'self->{name} = lua_touserdata(L, 2);')
        else:
            gen.line(f'/* TODO: set {ftype} */')

        gen.line('return 0;')
        gen.dedent()
        gen.line('}')
        gen.line()

    def _gen_array_setter(self, field: 'FieldInfo', gen: CodeGen):
        """Generate array field setter"""
        name = field.name
        ftype = field.type
        array_type = extract_array_type(ftype)
        sizes = extract_array_sizes(ftype)
        size = sizes[0] if sizes else 0

        gen.line('luaL_checktype(L, 2, LUA_TTABLE);')
        gen.line(f'for (int i = 0; i < {size}; i++) {{')
        gen.indent()
        gen.line('lua_rawgeti(L, 2, i + 1);')
        gen.line('if (!lua_isnil(L, -1)) {')
        gen.indent()

        if array_type == 'bool':
            gen.line(f'self->{name}[i] = lua_toboolean(L, -1);')
        elif is_int_type(array_type):
            gen.line(f'self->{name}[i] = ({array_type})lua_tointeger(L, -1);')
        elif is_float_type(array_type):
            gen.line(f'self->{name}[i] = ({array_type})lua_tonumber(L, -1);')
        elif self.ir.is_struct_type(array_type):
            inner_mt = self.get_metatable_name(array_type)
            gen.line(f'{array_type}* val = ({array_type}*)luaL_testudata(L, -1, "sokol.{inner_mt}");')
            gen.line(f'if (val) self->{name}[i] = *val;')
        elif self.ir.is_enum_type(array_type):
            gen.line(f'self->{name}[i] = ({array_type})lua_tointeger(L, -1);')

        gen.dedent()
        gen.line('}')
        gen.line('lua_pop(L, 1);')
        gen.dedent()
        gen.line('}')

    def _gen_index(self, struct_name: str, fields: list['FieldInfo'], gen: CodeGen):
        """Generate __index metamethod"""
        gen.line(f'static int l_{struct_name}__index(lua_State *L) {{')
        gen.indent()
        gen.line('const char* key = luaL_checkstring(L, 2);')

        for field in fields:
            if not is_func_ptr(field.type):
                gen.line(f'if (strcmp(key, "{field.name}") == 0) return l_{struct_name}_get_{field.name}(L);')

        gen.line('return 0;')
        gen.dedent()
        gen.line('}')
        gen.line()

    def _gen_newindex(self, struct_name: str, fields: list['FieldInfo'], gen: CodeGen):
        """Generate __newindex metamethod"""
        gen.line(f'static int l_{struct_name}__newindex(lua_State *L) {{')
        gen.indent()
        gen.line('const char* key = luaL_checkstring(L, 2);')

        for field in fields:
            if not is_func_ptr(field.type):
                gen.line(f'if (strcmp(key, "{field.name}") == 0) return l_{struct_name}_set_{field.name}(L);')

        gen.line('return luaL_error(L, "unknown field: %s", key);')
        gen.dedent()
        gen.line('}')
        gen.line()
