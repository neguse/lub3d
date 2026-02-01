"""
Callback binding generation module

Generates callback trampolines with support for both direct reference
and table lookup (hot-reload) modes.
"""

from dataclasses import dataclass
from typing import Optional, TYPE_CHECKING

from .codegen import (
    CodeGen, parse_func_ptr,
    is_int_type, is_float_type, is_string_ptr,
    is_void_ptr, is_const_void_ptr, extract_ptr_type,
    as_pascal_case,
)

if TYPE_CHECKING:
    from .ir import IR, FieldInfo


@dataclass
class CallbackConfig:
    """Configuration for callback generation"""
    hotreload: bool = False
    signature: str = "fun()"


class CallbackGenerator:
    """Generates callback trampoline functions"""

    def __init__(self, ir: 'IR', prefix: str, all_prefixes: list[str]):
        self.ir = ir
        self.prefix = prefix
        self.all_prefixes = all_prefixes
        self._hotreload_table_declared: set[str] = set()  # Track which structs have table_ref declared

    def get_metatable_name(self, struct_name: str) -> str:
        """Get metatable name for struct"""
        for pfx in self.all_prefixes:
            if struct_name.startswith(pfx):
                return as_pascal_case(struct_name, pfx)
        parts = struct_name.lower().split('_')
        return ''.join(part.capitalize() for part in parts if part != 't')

    def generate_trampoline(self, struct_name: str, field: 'FieldInfo',
                           config: Optional[CallbackConfig], gen: CodeGen):
        """Generate trampoline function for a callback field"""
        field_name = field.name
        field_type = field.type

        result_type, args = parse_func_ptr(field_type)
        if not result_type and result_type != 'void':
            return

        config = config or CallbackConfig()

        if config.hotreload:
            self._gen_table_lookup_trampoline(struct_name, field_name, result_type, args, gen)
        else:
            self._gen_direct_ref_trampoline(struct_name, field_name, result_type, args, gen)

    def _gen_direct_ref_trampoline(self, struct_name: str, field_name: str,
                                    result_type: str, args: list[str], gen: CodeGen):
        """Generate direct reference trampoline (current behavior)"""
        # Global reference variable
        gen.line(f'static int g_{struct_name}_{field_name}_ref = LUA_NOREF;')
        gen.line()

        # Function signature
        if args:
            c_args = ', '.join([f'{arg} arg{i}' for i, arg in enumerate(args)])
        else:
            c_args = 'void'

        gen.line(f'static {result_type} trampoline_{struct_name}_{field_name}({c_args}) {{')
        gen.indent()

        # Early return with default value
        default_val = self._get_default_value(result_type)
        if result_type != 'void':
            gen.line(f'if (g_{struct_name}_{field_name}_ref == LUA_NOREF) return {default_val};')
        else:
            gen.line(f'if (g_{struct_name}_{field_name}_ref == LUA_NOREF) return;')

        gen.line(f'lua_State* L = g_{struct_name}_L;')
        gen.line(f'lua_rawgeti(L, LUA_REGISTRYINDEX, g_{struct_name}_{field_name}_ref);')

        # Push arguments
        for i, arg in enumerate(args):
            push_lines = self._get_arg_push_code(arg, f'arg{i}', i)
            for line in push_lines:
                gen.line(line)

        # Call and handle return
        self._gen_pcall_and_return(result_type, len(args), field_name, gen)

        gen.dedent()
        gen.line('}')
        gen.line()

    def _gen_table_lookup_trampoline(self, struct_name: str, field_name: str,
                                      result_type: str, args: list[str], gen: CodeGen):
        """Generate table lookup trampoline (hot-reload support)"""
        # Global table reference (shared per struct, declared only once)
        if struct_name not in self._hotreload_table_declared:
            gen.line(f'static int g_{struct_name}_table_ref = LUA_NOREF;')
            gen.line()
            self._hotreload_table_declared.add(struct_name)

        # Function signature
        if args:
            c_args = ', '.join([f'{arg} arg{i}' for i, arg in enumerate(args)])
        else:
            c_args = 'void'

        gen.line(f'static {result_type} trampoline_{struct_name}_{field_name}({c_args}) {{')
        gen.indent()

        # Early return with default value
        default_val = self._get_default_value(result_type)
        if result_type != 'void':
            gen.line(f'if (g_{struct_name}_table_ref == LUA_NOREF) return {default_val};')
        else:
            gen.line(f'if (g_{struct_name}_table_ref == LUA_NOREF) return;')

        gen.line(f'lua_State* L = g_{struct_name}_L;')
        gen.line()

        # Table lookup for the callback
        gen.line('/* Look up callback from table */')
        gen.line(f'lua_rawgeti(L, LUA_REGISTRYINDEX, g_{struct_name}_table_ref);')
        gen.line(f'lua_getfield(L, -1, "{field_name}");')
        gen.line('lua_remove(L, -2);')
        gen.line()

        gen.line('if (!lua_isfunction(L, -1)) {')
        gen.indent()
        gen.line('lua_pop(L, 1);')
        if result_type != 'void':
            gen.line(f'return {default_val};')
        else:
            gen.line('return;')
        gen.dedent()
        gen.line('}')

        # Push arguments
        for i, arg in enumerate(args):
            push_lines = self._get_arg_push_code(arg, f'arg{i}', i)
            for line in push_lines:
                gen.line(line)

        # Call and handle return
        self._gen_pcall_and_return(result_type, len(args), field_name, gen)

        gen.dedent()
        gen.line('}')
        gen.line()

    def _gen_pcall_and_return(self, result_type: str, num_args: int,
                               field_name: str, gen: CodeGen):
        """Generate lua_pcall and return value handling"""
        if result_type != 'void':
            gen.line(f'if (lua_pcall(L, {num_args}, 1, 0) != LUA_OK) {{')
            gen.indent()
            gen.line(f'slog_func("callback", 0, 0, lua_tostring(L, -1), 0, "{field_name}", 0);')
            gen.line('lua_pop(L, 1);')
            default_val = self._get_default_value(result_type)
            gen.line(f'return {default_val};')
            gen.dedent()
            gen.line('}')

            # Convert return value
            if result_type == 'bool':
                gen.line(f'{result_type} ret = lua_toboolean(L, -1);')
            elif is_int_type(result_type):
                gen.line(f'{result_type} ret = ({result_type})lua_tointeger(L, -1);')
            elif is_float_type(result_type):
                gen.line(f'{result_type} ret = ({result_type})lua_tonumber(L, -1);')
            elif is_void_ptr(result_type):
                gen.line(f'{result_type} ret = lua_touserdata(L, -1);')
            else:
                gen.line(f'{result_type} ret = ({result_type}){{0}}; /* TODO: unsupported return type */')
            gen.line('lua_pop(L, 1);')
            gen.line('return ret;')
        else:
            gen.line(f'if (lua_pcall(L, {num_args}, 0, 0) != LUA_OK) {{')
            gen.indent()
            gen.line(f'slog_func("callback", 0, 0, lua_tostring(L, -1), 0, "{field_name}", 0);')
            gen.line('lua_pop(L, 1);')
            gen.dedent()
            gen.line('}')

    def _get_arg_push_code(self, arg_type: str, var_name: str, unique_idx: int) -> list[str]:
        """Generate code to push a callback argument onto the Lua stack"""
        ud_name = f'ud_cb_{unique_idx}'

        # For const struct pointers, push a copy of the struct
        if arg_type.startswith('const ') and '*' in arg_type:
            inner_type = extract_ptr_type(arg_type)
            if self.ir.is_struct_type(inner_type):
                struct_name = self.get_metatable_name(inner_type)
                return [
                    f'{inner_type}* {ud_name} = ({inner_type}*)lua_newuserdatauv(L, sizeof({inner_type}), 0);',
                    f'*{ud_name} = *{var_name};',
                    f'luaL_setmetatable(L, "sokol.{struct_name}");'
                ]

        # For non-const struct pointers, push a copy
        if '*' in arg_type and not arg_type.startswith('const '):
            inner_type = extract_ptr_type(arg_type)
            if self.ir.is_struct_type(inner_type):
                struct_name = self.get_metatable_name(inner_type)
                return [
                    f'{inner_type}* {ud_name} = ({inner_type}*)lua_newuserdatauv(L, sizeof({inner_type}), 0);',
                    f'*{ud_name} = *{var_name};',
                    f'luaL_setmetatable(L, "sokol.{struct_name}");'
                ]

        # Primitive types
        clean_type = arg_type.replace('const ', '').strip()
        if clean_type == 'bool':
            return [f'lua_pushboolean(L, {var_name});']
        elif is_int_type(clean_type):
            return [f'lua_pushinteger(L, (lua_Integer){var_name});']
        elif is_float_type(clean_type):
            return [f'lua_pushnumber(L, (lua_Number){var_name});']
        elif is_string_ptr(clean_type):
            return [f'lua_pushstring(L, {var_name});']
        elif is_void_ptr(clean_type) or is_const_void_ptr(clean_type):
            return [f'lua_pushlightuserdata(L, (void*){var_name});']
        # For any other pointer types, push as lightuserdata
        elif '*' in clean_type:
            return [f'lua_pushlightuserdata(L, (void*){var_name});']

        return [f'lua_pushnil(L); /* TODO: push {arg_type} */']

    def _get_default_value(self, result_type: str) -> str:
        """Get default return value for callback"""
        if result_type == 'void':
            return ''
        elif result_type == 'bool':
            return 'false'
        elif is_int_type(result_type):
            return '0'
        elif is_float_type(result_type):
            return '0.0f' if result_type == 'float' else '0.0'
        elif is_void_ptr(result_type):
            return 'NULL'
        else:
            return '0'

    def generate_struct_init(self, struct_name: str, field_name: str,
                              config: Optional[CallbackConfig], gen: CodeGen):
        """Generate code to initialize callback in struct constructor"""
        config = config or CallbackConfig()

        gen.line(f'lua_getfield(L, 1, "{field_name}");')
        gen.line('if (lua_isfunction(L, -1)) {')
        gen.indent()

        if config.hotreload:
            # Table lookup mode: store reference to the table itself
            gen.line('/* Hot-reload mode: store table reference */')
            gen.line(f'if (g_{struct_name}_table_ref == LUA_NOREF) {{')
            gen.indent()
            gen.line('lua_pushvalue(L, 1);')
            gen.line(f'g_{struct_name}_table_ref = luaL_ref(L, LUA_REGISTRYINDEX);')
            gen.line(f'g_{struct_name}_L = L;')
            gen.dedent()
            gen.line('}')
            gen.line(f'ud->{field_name} = trampoline_{struct_name}_{field_name};')
            gen.line('lua_pop(L, 1);')
        else:
            # Direct reference mode: store reference to the function
            gen.line(f'g_{struct_name}_{field_name}_ref = luaL_ref(L, LUA_REGISTRYINDEX);')
            gen.line(f'g_{struct_name}_L = L;')
            gen.line(f'ud->{field_name} = trampoline_{struct_name}_{field_name};')

        gen.dedent()
        gen.line('} else {')
        gen.indent()
        gen.line('lua_pop(L, 1);')
        gen.dedent()
        gen.line('}')
