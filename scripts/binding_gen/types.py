"""
Type conversion module

Provides Lua <-> C type conversion code generation.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional, TYPE_CHECKING

from .codegen import (
    is_int_type, is_float_type, is_prim_type,
    is_string_ptr, is_void_ptr, is_const_void_ptr, is_func_ptr,
    is_1d_array_type, extract_ptr_type, normalize_ptr_type,
    as_pascal_case,
)

if TYPE_CHECKING:
    from .ir import IR


@dataclass
class ConversionContext:
    """Context for type conversion code generation"""
    idx: int              # Lua stack index
    var: str              # C variable name
    type: str             # C type
    prefix: str           # Module prefix (e.g., 'sg_')
    metatable: str = ''   # Metatable name (for structs)
    ir: Optional['IR'] = None  # IR for type lookups


class TypeHandler(ABC):
    """Base class for custom type handlers"""

    @abstractmethod
    def lua_to_c(self, ctx: ConversionContext) -> str:
        """Generate code to convert Lua value to C value"""
        pass

    @abstractmethod
    def c_to_lua(self, ctx: ConversionContext) -> str:
        """Generate code to push C value to Lua stack"""
        pass

    @abstractmethod
    def luacats_type(self) -> str:
        """Return LuaCATS type annotation"""
        pass


class TypeConverter:
    """Manages type conversion between Lua and C"""

    def __init__(self, ir: 'IR', all_prefixes: list[str]):
        self.ir = ir
        self.all_prefixes = all_prefixes
        self._handlers: dict[str, TypeHandler] = {}

    def register(self, type_name: str, handler: TypeHandler):
        """Register a custom type handler"""
        self._handlers[type_name] = handler

    def has_handler(self, type_name: str) -> bool:
        """Check if a custom handler exists for this type"""
        return type_name in self._handlers

    def get_handler(self, type_name: str) -> Optional[TypeHandler]:
        """Get custom handler for type"""
        return self._handlers.get(type_name)

    def lua_to_c(self, type_str: str, idx: int, var: str, prefix: str) -> str:
        """Generate code to get C value from Lua stack"""
        # Check for custom handler
        base_type = extract_ptr_type(type_str) if '*' in type_str else type_str
        if base_type in self._handlers:
            ctx = ConversionContext(idx=idx, var=var, type=type_str, prefix=prefix, ir=self.ir)
            return self._handlers[base_type].lua_to_c(ctx)

        return self._default_lua_to_c(type_str, idx, var, prefix)

    def c_to_lua(self, type_str: str, var: str, prefix: str) -> str:
        """Generate code to push C value to Lua stack"""
        # Check for custom handler
        base_type = extract_ptr_type(type_str) if '*' in type_str else type_str
        if base_type in self._handlers:
            ctx = ConversionContext(idx=0, var=var, type=type_str, prefix=prefix, ir=self.ir)
            return self._handlers[base_type].c_to_lua(ctx)

        return self._default_c_to_lua(type_str, var, prefix)

    def luacats_type(self, type_str: str, prefix: str) -> str:
        """Get LuaCATS type for C type"""
        # Check for custom handler
        base_type = extract_ptr_type(type_str) if '*' in type_str else type_str
        if base_type in self._handlers:
            return self._handlers[base_type].luacats_type()

        return self._default_luacats_type(type_str, prefix)

    def _get_metatable_name(self, struct_name: str) -> str:
        """Get metatable name for a struct"""
        # Find the prefix for this type
        for pfx in self.all_prefixes:
            if struct_name.startswith(pfx):
                return as_pascal_case(struct_name, pfx)
        # Fallback
        parts = struct_name.lower().split('_')
        return ''.join(part.capitalize() for part in parts if part != 't')

    def _is_struct_type(self, type_str: str) -> bool:
        """Check if type is a known struct"""
        return self.ir.is_struct_type(type_str)

    def _is_enum_type(self, type_str: str) -> bool:
        """Check if type is a known enum"""
        return self.ir.is_enum_type(type_str)

    def _is_struct_ptr(self, type_str: str) -> bool:
        """Check if type is a struct pointer"""
        normalized = normalize_ptr_type(type_str)
        if not normalized.endswith('*'):
            return False
        inner = extract_ptr_type(type_str)
        return self._is_struct_type(inner)

    def _is_const_struct_ptr(self, type_str: str) -> bool:
        """Check if type is a const struct pointer"""
        if not type_str.startswith('const '):
            return False
        return self._is_struct_ptr(type_str)

    def _default_lua_to_c(self, type_str: str, idx: int, var: str, prefix: str) -> str:
        """Default Lua -> C conversion"""
        if type_str == 'bool':
            return f'bool {var} = lua_toboolean(L, {idx});'

        elif is_int_type(type_str):
            return f'{type_str} {var} = ({type_str})luaL_checkinteger(L, {idx});'

        elif is_float_type(type_str):
            return f'{type_str} {var} = ({type_str})luaL_checknumber(L, {idx});'

        elif is_string_ptr(type_str):
            return f'const char* {var} = luaL_checkstring(L, {idx});'

        # Check pointer types BEFORE struct type (since is_struct_type also matches pointers)
        elif self._is_const_struct_ptr(type_str):
            inner = extract_ptr_type(type_str)
            mt = self._get_metatable_name(inner)
            return f'const {inner}* {var} = (const {inner}*)luaL_checkudata(L, {idx}, "sokol.{mt}");'

        elif self._is_struct_ptr(type_str):
            inner = extract_ptr_type(type_str)
            mt = self._get_metatable_name(inner)
            return f'{inner}* {var} = ({inner}*)luaL_checkudata(L, {idx}, "sokol.{mt}");'

        elif self._is_struct_type(type_str):
            mt = self._get_metatable_name(type_str)
            return (f'{type_str}* {var}_ptr = ({type_str}*)luaL_checkudata(L, {idx}, "sokol.{mt}");\n'
                    f'    {type_str} {var} = *{var}_ptr;')

        elif self._is_enum_type(type_str):
            return f'{type_str} {var} = ({type_str})luaL_checkinteger(L, {idx});'

        elif is_void_ptr(type_str):
            return f'void* {var} = lua_touserdata(L, {idx});'

        elif is_const_void_ptr(type_str):
            return f'const void* {var} = lua_touserdata(L, {idx});'

        elif type_str in ('const float *', 'const float*'):
            return (f'const float* {var};\n'
                    f'    if (lua_isstring(L, {idx})) {{\n'
                    f'        {var} = (const float*)lua_tostring(L, {idx});\n'
                    f'    }} else {{\n'
                    f'        {var} = (const float*)lua_touserdata(L, {idx});\n'
                    f'    }}')

        elif type_str in ('float *', 'float*'):
            return f'float* {var} = (float*)lua_touserdata(L, {idx});'

        else:
            return f'/* TODO: get {type_str} */ void* {var} = NULL;'

    def _default_c_to_lua(self, type_str: str, var: str, prefix: str) -> str:
        """Default C -> Lua conversion"""
        if type_str == 'void':
            return ''

        elif type_str == 'bool':
            return f'lua_pushboolean(L, {var});'

        elif is_int_type(type_str):
            return f'lua_pushinteger(L, (lua_Integer){var});'

        elif is_float_type(type_str):
            return f'lua_pushnumber(L, (lua_Number){var});'

        elif is_string_ptr(type_str):
            return f'lua_pushstring(L, {var});'

        elif self._is_struct_type(type_str):
            mt = self._get_metatable_name(type_str)
            return (f'{type_str}* ud = ({type_str}*)lua_newuserdatauv(L, sizeof({type_str}), 0);\n'
                    f'    *ud = {var};\n'
                    f'    luaL_setmetatable(L, "sokol.{mt}");')

        elif self._is_enum_type(type_str):
            return f'lua_pushinteger(L, (lua_Integer){var});'

        elif is_void_ptr(type_str) or is_const_void_ptr(type_str):
            return f'lua_pushlightuserdata(L, (void*){var});'

        else:
            return f'/* TODO: push {type_str} */ lua_pushnil(L);'

    def _default_luacats_type(self, type_str: str, prefix: str) -> str:
        """Default LuaCATS type conversion"""
        if type_str == 'void':
            return 'nil'
        elif type_str == 'bool':
            return 'boolean'
        elif is_int_type(type_str):
            return 'integer'
        elif is_float_type(type_str):
            return 'number'
        elif is_string_ptr(type_str):
            return 'string'
        elif is_void_ptr(type_str) or is_const_void_ptr(type_str):
            return 'lightuserdata?'
        elif is_1d_array_type(type_str):
            from .codegen import extract_array_type
            inner = extract_array_type(type_str)
            inner_lua = self.luacats_type(inner, prefix)
            return f'({inner_lua})[]'

        # Struct types
        if self._is_struct_type(type_str) or self._is_struct_ptr(type_str) or self._is_const_struct_ptr(type_str):
            inner = type_str
            if '*' in type_str:
                inner = extract_ptr_type(type_str)
            mt = self._get_metatable_name(inner)
            # Find module for this type
            for pfx in self.all_prefixes:
                if inner.startswith(pfx):
                    from .generator import MODULE_NAMES
                    module = MODULE_NAMES.get(pfx, 'sokol')
                    return f'{module}.{mt}'
            return f'sokol.{mt}'

        # Enum types
        if self._is_enum_type(type_str):
            for pfx in self.all_prefixes:
                if type_str.startswith(pfx):
                    from .generator import MODULE_NAMES
                    module = MODULE_NAMES.get(pfx, 'sokol')
                    enum_name = as_pascal_case(type_str, pfx)
                    return f'{module}.{enum_name}'
            return 'integer'

        return 'any'
