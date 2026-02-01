"""
Enum binding generation module

Generates enum constants registration.
"""

from typing import TYPE_CHECKING

from .codegen import CodeGen, as_pascal_case, as_snake_case

if TYPE_CHECKING:
    from .ir import EnumInfo


class EnumGenerator:
    """Generates enum constant bindings"""

    def __init__(self, prefix: str):
        self.prefix = prefix
        self._counter = 0

    def generate(self, enum: 'EnumInfo', gen: CodeGen):
        """Generate enum constants registration"""
        enum_name = enum.name
        lua_enum_name = as_pascal_case(enum_name, self.prefix)

        gen.line(f'static void register_{enum_name}(lua_State *L) {{')
        gen.indent()
        gen.line('lua_newtable(L);')

        for item in enum.items:
            short_name = self._get_short_name(enum_name, item.name)
            if item.value is not None:
                gen.line(f'lua_pushinteger(L, {item.value});')
            else:
                gen.line(f'lua_pushinteger(L, {item.name});')
            gen.line(f'lua_setfield(L, -2, "{short_name}");')

        gen.line(f'lua_setfield(L, -2, "{lua_enum_name}");')
        gen.dedent()
        gen.line('}')
        gen.line()

    def generate_consts(self, enum: 'EnumInfo', gen: CodeGen) -> int:
        """Generate anonymous enum constants registration"""
        self._counter += 1
        const_id = self._counter

        gen.line(f'static void register_consts_{const_id}(lua_State *L) {{')
        gen.indent()

        for item in enum.items:
            lua_name = as_snake_case(item.name, self.prefix).upper()
            gen.line(f'lua_pushinteger(L, {item.value});')
            gen.line(f'lua_setfield(L, -2, "{lua_name}");')

        gen.dedent()
        gen.line('}')
        gen.line()

        return const_id

    def _get_short_name(self, enum_name: str, item_name: str) -> str:
        """Get short name for enum item by stripping common prefix"""
        item_upper = item_name.upper()

        # Build possible prefixes from enum name
        # sg_load_action -> SG_LOADACTION_
        enum_upper = enum_name.upper()
        if enum_upper.endswith('_T'):
            enum_upper = enum_upper[:-2]

        possible_prefixes = []

        # Try: SG_LOADACTION_ (module prefix + rest without underscores)
        parts = enum_name.split('_')
        if len(parts) >= 2:
            module_part = parts[0].upper() + '_'
            rest_part = ''.join(parts[1:]).upper() + '_'
            possible_prefixes.append(module_part + rest_part)
            possible_prefixes.append('_' + module_part + rest_part)

        # Try just module prefix (SG_, SAPP_, etc.)
        module_prefix = self.prefix.upper()
        possible_prefixes.append(module_prefix)
        possible_prefixes.append('_' + module_prefix)

        for pfx in possible_prefixes:
            if item_upper.startswith(pfx):
                return item_name[len(pfx):]

        return item_name
