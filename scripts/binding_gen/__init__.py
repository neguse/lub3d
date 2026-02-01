"""
binding_gen - Lua binding generation framework for C libraries

This framework provides building blocks for generating Lua C API bindings
from clang AST JSON (IR). It is designed to be extended by library-specific
generators that customize type conversion, callback handling, etc.
"""

from .ir import IR, StructInfo, FieldInfo, FuncInfo, ParamInfo, EnumInfo, EnumItem
from .types import TypeConverter, TypeHandler, ConversionContext
from .codegen import CodeGen
from .struct import StructGenerator, StructHandler
from .func import FuncGenerator
from .callback import CallbackGenerator, CallbackConfig
from .enum import EnumGenerator
from .luacats import LuaCATSGenerator
from .generator import Generator

__all__ = [
    'IR', 'StructInfo', 'FieldInfo', 'FuncInfo', 'ParamInfo', 'EnumInfo', 'EnumItem',
    'TypeConverter', 'TypeHandler', 'ConversionContext',
    'CodeGen',
    'StructGenerator', 'StructHandler',
    'FuncGenerator',
    'CallbackGenerator', 'CallbackConfig',
    'EnumGenerator',
    'LuaCATSGenerator',
    'Generator',
]
