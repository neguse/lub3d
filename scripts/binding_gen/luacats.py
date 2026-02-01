"""
LuaCATS type definition generation module

Generates .lua files with type annotations for IDE autocompletion.
"""

from typing import TYPE_CHECKING

from .codegen import as_pascal_case, as_snake_case, is_func_ptr

if TYPE_CHECKING:
    from .ir import IR, StructInfo, FuncInfo, EnumInfo
    from .types import TypeConverter
    from .struct import StructHandler
    from .callback import CallbackConfig

# Lua reserved keywords
LUA_KEYWORDS = {
    'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for',
    'function', 'goto', 'if', 'in', 'local', 'nil', 'not', 'or',
    'repeat', 'return', 'then', 'true', 'until', 'while'
}


class LuaCATSGenerator:
    """Generates LuaCATS type definition files"""

    def __init__(self, ir: 'IR', type_conv: 'TypeConverter', prefix: str, module_name: str):
        self.ir = ir
        self.type_conv = type_conv
        self.prefix = prefix
        self.module_name = module_name
        self._struct_handlers: dict[str, 'StructHandler'] = {}

    def register_struct_handler(self, struct_name: str, handler: 'StructHandler'):
        """Register struct handler for callback signature lookup"""
        self._struct_handlers[struct_name] = handler

    def generate(self) -> str:
        """Generate complete LuaCATS type definition file"""
        lines = []
        lines.append('---@meta')
        lines.append(f'-- LuaCATS type definitions for sokol.{self.module_name}')
        lines.append('-- Auto-generated, do not edit')
        lines.append('')

        # Collect declarations
        structs = list(self.ir.own_structs().values())
        enums = list(self.ir.enums.values())
        funcs = list(self.ir.funcs.values())

        # Generate struct types first
        for struct in structs:
            lines.extend(self._gen_struct(struct))
            lines.append('')

        # Generate module class with constructors
        lines.append(f'---@class {self.module_name}')
        for struct in structs:
            lines.append(self._gen_constructor_field(struct))
        lines.append(f'local {self.module_name} = {{}}')
        lines.append('')

        # Generate enum types
        for enum in enums:
            lines.extend(self._gen_enum(enum))
            lines.append('')

        # Generate function types
        for func in funcs:
            lines.extend(self._gen_func(func))
            lines.append('')

        lines.append(f'return {self.module_name}')
        return '\n'.join(lines)

    def _gen_struct(self, struct: 'StructInfo') -> list[str]:
        """Generate struct type definition"""
        lines = []
        struct_name = as_pascal_case(struct.name, self.prefix)
        lines.append(f'---@class {self.module_name}.{struct_name}')

        handler = self._struct_handlers.get(struct.name)

        for field in struct.fields:
            if is_func_ptr(field.type):
                # Use callback signature from handler if available
                if handler and field.name in handler.callbacks:
                    cb_config = handler.callbacks[field.name]
                    lua_type = cb_config.signature
                else:
                    lua_type = 'function'
            else:
                lua_type = self.type_conv.luacats_type(field.type, self.prefix)
            lines.append(f'---@field {field.name}? {lua_type}')

        return lines

    def _gen_constructor_field(self, struct: 'StructInfo') -> str:
        """Generate constructor field for module class"""
        struct_name = as_pascal_case(struct.name, self.prefix)
        return f'---@field {struct_name} fun(t?: {self.module_name}.{struct_name}): {self.module_name}.{struct_name}'

    def _gen_enum(self, enum: 'EnumInfo') -> list[str]:
        """Generate enum type definition"""
        lines = []
        enum_name = as_pascal_case(enum.name, self.prefix)
        lines.append(f'---@enum {self.module_name}.{enum_name}')
        lines.append(f'{self.module_name}.{enum_name} = {{')

        next_value = 0
        for item in enum.items:
            short_name = self._get_enum_short_name(enum.name, item.name)
            if short_name == 'FORCE_U32':
                continue
            if item.value is not None:
                next_value = item.value
            # Quote keys that start with digits
            if short_name[0].isdigit():
                lines.append(f'    ["{short_name}"] = {next_value},')
            else:
                lines.append(f'    {short_name} = {next_value},')
            next_value += 1

        lines.append('}')
        return lines

    def _gen_func(self, func: 'FuncInfo') -> list[str]:
        """Generate function type definition"""
        lines = []
        func_name = as_pascal_case(func.name, self.prefix)

        # Parameter annotations
        for param in func.params:
            lua_type = self.type_conv.luacats_type(param.type, self.prefix)
            lines.append(f'---@param {param.name} {lua_type}')

        # Return type
        if func.return_type != 'void':
            lua_ret = self.type_conv.luacats_type(func.return_type, self.prefix)
            lines.append(f'---@return {lua_ret}')

        # Function signature (PascalCase - no reserved word conflicts)
        param_names = ', '.join(p.name for p in func.params)
        lines.append(f'function {self.module_name}.{func_name}({param_names}) end')

        return lines

    def _get_enum_short_name(self, enum_name: str, item_name: str) -> str:
        """Get short name for enum item"""
        item_upper = item_name.upper()
        enum_upper = enum_name.upper()
        if enum_upper.endswith('_T'):
            enum_upper = enum_upper[:-2]

        possible_prefixes = []
        parts = enum_name.split('_')
        if len(parts) >= 2:
            module_part = parts[0].upper() + '_'
            rest_part = ''.join(parts[1:]).upper() + '_'
            possible_prefixes.append(module_part + rest_part)
            possible_prefixes.append('_' + module_part + rest_part)

        module_prefix = self.prefix.upper()
        possible_prefixes.append(module_prefix)
        possible_prefixes.append('_' + module_prefix)

        for pfx in possible_prefixes:
            if item_upper.startswith(pfx):
                return item_name[len(pfx):]

        return item_name
