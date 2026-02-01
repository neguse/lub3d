"""
Main generator module

Orchestrates all components to generate complete Lua bindings.
"""

import os
import sys
import shutil
from typing import Optional, Callable, TYPE_CHECKING

from .ir import IR
from .codegen import CodeGen, as_pascal_case, as_snake_case
from .types import TypeConverter, TypeHandler
from .struct import StructGenerator, StructHandler
from .func import FuncGenerator
from .callback import CallbackGenerator, CallbackConfig
from .enum import EnumGenerator
from .luacats import LuaCATSGenerator

# Module names for each prefix
MODULE_NAMES = {
    'slog_': 'log',
    'sg_': 'gfx',
    'sapp_': 'app',
    'stm_': 'time',
    'saudio_': 'audio',
    'sgl_': 'gl',
    'sdtx_': 'debugtext',
    'sshape_': 'shape',
    'sglue_': 'glue',
}

# Header paths relative to sokol root
HEADER_PATHS = {
    'slog_': 'sokol_log.h',
    'sg_': 'sokol_gfx.h',
    'sapp_': 'sokol_app.h',
    'stm_': 'sokol_time.h',
    'saudio_': 'sokol_audio.h',
    'sgl_': 'util/sokol_gl.h',
    'sdtx_': 'util/sokol_debugtext.h',
    'sshape_': 'util/sokol_shape.h',
    'sglue_': 'sokol_glue.h',
}

# Header file names (for stubs)
HEADER_NAMES = {
    'slog_': 'sokol_log.h',
    'sg_': 'sokol_gfx.h',
    'sapp_': 'sokol_app.h',
    'stm_': 'sokol_time.h',
    'saudio_': 'sokol_audio.h',
    'sgl_': 'sokol_gl.h',
    'sdtx_': 'sokol_debugtext.h',
    'sshape_': 'sokol_shape.h',
    'sglue_': 'sokol_glue.h',
}

# C source file names
C_SOURCE_NAMES = {
    'slog_': 'sokol_log.c',
    'sg_': 'sokol_gfx.c',
    'sapp_': 'sokol_app.c',
    'stm_': 'sokol_time.c',
    'saudio_': 'sokol_audio.c',
    'sgl_': 'sokol_gl.c',
    'sdtx_': 'sokol_debugtext.c',
    'sshape_': 'sokol_shape.c',
    'sglue_': 'sokol_glue.c',
}

# Module dependencies
MODULE_DEPS = {
    'slog_': [],
    'sg_': ['slog_'],
    'sapp_': ['slog_'],
    'stm_': [],
    'saudio_': ['slog_'],
    'sgl_': ['slog_', 'sg_'],
    'sdtx_': ['slog_', 'sg_'],
    'sshape_': ['slog_', 'sg_'],
    'sglue_': ['slog_', 'sg_', 'sapp_'],
}

# All known prefixes
ALL_PREFIXES = list(MODULE_NAMES.keys())

# Lua reserved keywords
LUA_KEYWORDS = {
    'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for',
    'function', 'goto', 'if', 'in', 'local', 'nil', 'not', 'or',
    'repeat', 'return', 'then', 'true', 'until', 'while'
}


class ModuleConfig:
    """Configuration for a module"""

    def __init__(self, prefix: str):
        self.prefix = prefix
        self.module_name = MODULE_NAMES.get(prefix, prefix.rstrip('_'))
        self.ignores: set[str] = set()
        self.type_handlers: dict[str, TypeHandler] = {}
        self.struct_handlers: dict[str, StructHandler] = {}
        self.callback_configs: dict[str, dict[str, CallbackConfig]] = {}


class Generator:
    """Main binding generator"""

    def __init__(self, sokol_root: str, output_root: str, bindgen_path: str):
        self.sokol_root = sokol_root
        self.output_root = output_root
        self.bindgen_path = bindgen_path
        self.stubs_root = os.path.join(output_root, 'gen/stubs')
        self.bindings_root = os.path.join(output_root, 'gen/bindings')
        self.types_root = os.path.join(output_root, 'gen/types/sokol')
        self._modules: dict[str, ModuleConfig] = {}
        self._global_ignores: set[str] = set()

    def ignore(self, *names: str):
        """Add symbols to ignore globally"""
        self._global_ignores.update(names)

    def module(self, prefix: str) -> ModuleConfig:
        """Get or create module configuration"""
        if prefix not in self._modules:
            self._modules[prefix] = ModuleConfig(prefix)
        return self._modules[prefix]

    def type_handler(self, prefix: str, type_name: str):
        """Decorator to register a type handler"""
        def decorator(cls):
            config = self.module(prefix)
            config.type_handlers[type_name] = cls()
            return cls
        return decorator

    def struct_handler(self, prefix: str, struct_name: str):
        """Decorator to register a struct handler"""
        def decorator(handler: StructHandler):
            config = self.module(prefix)
            config.struct_handlers[struct_name] = handler
            return handler
        return decorator

    def prepare(self):
        """Prepare output directories"""
        print('=== Generating Lua bindings:')
        os.makedirs(self.stubs_root, exist_ok=True)
        os.makedirs(self.bindings_root, exist_ok=True)
        os.makedirs(self.types_root, exist_ok=True)

    def generate_all(self):
        """Generate bindings for all configured modules"""
        self.prepare()
        for prefix in MODULE_NAMES:
            self.generate_module(prefix)

    def generate_module(self, prefix: str):
        """Generate bindings for a single module"""
        if prefix not in MODULE_NAMES:
            print(f'  >> warning: skipping generation for {prefix} prefix...')
            return

        header_path = os.path.join(self.sokol_root, HEADER_PATHS[prefix])
        dep_prefixes = MODULE_DEPS.get(prefix, [])
        module_name = MODULE_NAMES[prefix]

        print(f'  {header_path} => {module_name}')

        # Copy header files to stubs
        self._copy_headers(header_path, prefix, dep_prefixes)

        # Generate IR using sokol/bindgen
        ir = self._generate_ir(header_path, prefix, dep_prefixes, module_name)

        # Generate C bindings
        c_code = self._generate_c_code(ir, prefix, dep_prefixes)
        c_output = os.path.join(self.bindings_root, f'sokol_{module_name}.c')
        with open(c_output, 'w', newline='\n') as f:
            f.write(c_code)

        # Generate LuaCATS types
        luacats = self._generate_luacats(ir, prefix, module_name)
        types_output = os.path.join(self.types_root, f'{module_name}.lua')
        with open(types_output, 'w', newline='\n') as f:
            f.write(luacats)

    def _copy_headers(self, header_path: str, prefix: str, dep_prefixes: list[str]):
        """Copy header files to stubs directory"""
        shutil.copyfile(header_path, os.path.join(self.stubs_root, os.path.basename(header_path)))

        # Copy dependency headers
        for dep_prefix in dep_prefixes:
            if dep_prefix in HEADER_NAMES:
                dep_header = HEADER_NAMES[dep_prefix]
                dep_path = header_path.replace(os.path.basename(header_path), dep_header)
                if os.path.exists(dep_path):
                    shutil.copyfile(dep_path, os.path.join(self.stubs_root, dep_header))

        # Create stub .c file for clang
        self._create_stub_c(prefix, dep_prefixes)

    def _create_stub_c(self, prefix: str, dep_prefixes: list[str]):
        """Create stub C file for clang parsing"""
        if prefix not in HEADER_NAMES:
            return
        content = ''
        for dep_prefix in dep_prefixes:
            if dep_prefix in HEADER_NAMES:
                content += f'#include "{HEADER_NAMES[dep_prefix]}"\n'
        content += f'#include "{HEADER_NAMES[prefix]}"\n'

        c_file = os.path.join(self.stubs_root, C_SOURCE_NAMES[prefix])
        with open(c_file, 'w', newline='\n') as f:
            f.write(content)

    def _generate_ir(self, header_path: str, prefix: str, dep_prefixes: list[str],
                     module_name: str) -> IR:
        """Generate IR using sokol/bindgen"""
        # Add bindgen to path
        sys.path.insert(0, self.bindgen_path)
        import gen_ir

        csource_path = os.path.join(self.stubs_root, C_SOURCE_NAMES[prefix])
        csource_path = os.path.abspath(csource_path)

        orig_dir = os.getcwd()
        os.chdir(self.stubs_root)
        ir_dict = gen_ir.gen(header_path, csource_path, module_name, prefix, dep_prefixes)
        os.chdir(orig_dir)

        return IR.from_dict(ir_dict)

    def _generate_c_code(self, ir: IR, prefix: str, dep_prefixes: list[str]) -> str:
        """Generate C binding code"""
        gen = CodeGen()
        module_name = MODULE_NAMES[prefix]
        config = self._modules.get(prefix, ModuleConfig(prefix))

        # Header
        gen.line('/* machine generated, do not edit */')
        gen.line('#include <lua.h>')
        gen.line('#include <lauxlib.h>')
        gen.line('#include <lualib.h>')
        gen.line('#include <string.h>')
        gen.line()

        # Include sokol headers
        for dep_prefix in dep_prefixes:
            if dep_prefix in HEADER_NAMES:
                gen.line(f'#include "{HEADER_NAMES[dep_prefix]}"')

        # sokol_glue needs sokol_app.h
        if prefix == 'sglue_':
            gen.line('#include "sokol_app.h"')

        gen.line(f'#include "{HEADER_NAMES[prefix]}"')
        gen.line()

        # MANE3D_API macro
        gen.line('#ifndef MANE3D_API')
        gen.line('  #ifdef _WIN32')
        gen.line('    #ifdef MANE3D_EXPORTS')
        gen.line('      #define MANE3D_API __declspec(dllexport)')
        gen.line('    #else')
        gen.line('      #define MANE3D_API __declspec(dllimport)')
        gen.line('    #endif')
        gen.line('  #else')
        gen.line('    #define MANE3D_API')
        gen.line('  #endif')
        gen.line('#endif')
        gen.line()

        # Create generators
        type_conv = TypeConverter(ir, ALL_PREFIXES)
        callback_gen = CallbackGenerator(ir, prefix, ALL_PREFIXES)
        struct_gen = StructGenerator(ir, type_conv, callback_gen, prefix, ALL_PREFIXES)
        func_gen = FuncGenerator(ir, type_conv, prefix)
        enum_gen = EnumGenerator(prefix)

        # Register custom handlers
        for type_name, handler in config.type_handlers.items():
            type_conv.register(type_name, handler)
        for struct_name, handler in config.struct_handlers.items():
            struct_gen.register_handler(struct_name, handler)

        # Collect declarations
        own_structs = list(ir.own_structs().values())
        funcs = [f for f in ir.funcs.values()
                 if f.name not in self._global_ignores
                 and f.name not in config.ignores]
        enums = list(ir.enums.values())
        consts = ir.consts

        # Generate struct bindings
        for struct in own_structs:
            struct_gen.generate(struct, gen)

        # Generate function wrappers
        for func in funcs:
            func_gen.generate(func, gen)

        # Generate enum registration
        for enum in enums:
            enum_gen.generate(enum, gen)

        # Generate const registration
        const_ids = []
        for const in consts:
            const_id = enum_gen.generate_consts(const, gen)
            const_ids.append(const_id)

        # Generate metatable registration
        self._gen_metatable_registration(own_structs, struct_gen, gen)

        # Generate luaopen function
        self._gen_luaopen(module_name, prefix, funcs, own_structs, enums, const_ids,
                          struct_gen, gen)

        return gen.output()

    def _gen_metatable_registration(self, structs, struct_gen: StructGenerator, gen: CodeGen):
        """Generate metatable registration function"""
        gen.line('static void register_metatables(lua_State *L) {')
        gen.indent()

        for struct in structs:
            mt_name = struct_gen.get_metatable_name(struct.name)
            gen.line(f'luaL_newmetatable(L, "sokol.{mt_name}");')
            gen.line(f'lua_pushcfunction(L, l_{struct.name}__index);')
            gen.line('lua_setfield(L, -2, "__index");')
            gen.line(f'lua_pushcfunction(L, l_{struct.name}__newindex);')
            gen.line('lua_setfield(L, -2, "__newindex");')
            gen.line('lua_pop(L, 1);')
            gen.line()

        gen.dedent()
        gen.line('}')
        gen.line()

    def _gen_luaopen(self, module_name: str, prefix: str, funcs, structs, enums,
                     const_ids: list[int], struct_gen: StructGenerator, gen: CodeGen):
        """Generate luaopen function"""
        gen.line(f'static const luaL_Reg {module_name}_funcs[] = {{')
        gen.indent()

        # Add function wrappers (PascalCase)
        for func in funcs:
            lua_name = as_pascal_case(func.name, prefix)
            gen.line(f'{{"{lua_name}", l_{func.name}}},')

        # Add struct constructors
        for struct in structs:
            lua_name = struct_gen.get_metatable_name(struct.name)
            gen.line(f'{{"{lua_name}", l_{struct.name}_new}},')

        gen.line('{NULL, NULL}')
        gen.dedent()
        gen.line('};')
        gen.line()

        gen.line(f'MANE3D_API int luaopen_sokol_{module_name}(lua_State *L) {{')
        gen.indent()
        gen.line('register_metatables(L);')
        gen.line(f'luaL_newlib(L, {module_name}_funcs);')

        # Register enums
        for enum in enums:
            gen.line(f'register_{enum.name}(L);')

        # Register consts
        for const_id in const_ids:
            gen.line(f'register_consts_{const_id}(L);')

        gen.line('return 1;')
        gen.dedent()
        gen.line('}')

    def _generate_luacats(self, ir: IR, prefix: str, module_name: str) -> str:
        """Generate LuaCATS type definitions"""
        config = self._modules.get(prefix, ModuleConfig(prefix))
        type_conv = TypeConverter(ir, ALL_PREFIXES)

        # Register custom type handlers
        for type_name, handler in config.type_handlers.items():
            type_conv.register(type_name, handler)

        luacats_gen = LuaCATSGenerator(ir, type_conv, prefix, module_name)

        # Register struct handlers for callback signatures
        for struct_name, handler in config.struct_handlers.items():
            luacats_gen.register_struct_handler(struct_name, handler)

        return luacats_gen.generate()
