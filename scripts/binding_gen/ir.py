"""
IR (Intermediate Representation) module

Reads and represents clang AST JSON data from sokol/bindgen.
"""

from dataclasses import dataclass, field
from typing import Optional
import json
import os
import subprocess
import re


@dataclass
class FieldInfo:
    """Struct field information"""
    name: str
    type: str
    is_array: bool = False
    array_sizes: list[int] = field(default_factory=list)

    @property
    def is_func_ptr(self) -> bool:
        return '(*)' in self.type


@dataclass
class StructInfo:
    """Struct type information"""
    name: str
    fields: list[FieldInfo]
    comment: str = ""


@dataclass
class ParamInfo:
    """Function parameter information"""
    name: str
    type: str


@dataclass
class FuncInfo:
    """Function declaration information"""
    name: str
    type: str  # Full function type signature
    params: list[ParamInfo]
    comment: str = ""

    @property
    def return_type(self) -> str:
        """Extract return type from full type signature"""
        return self.type[:self.type.index('(')].strip()


@dataclass
class EnumItem:
    """Enum item (constant)"""
    name: str
    value: Optional[int] = None


@dataclass
class EnumInfo:
    """Enum type information"""
    name: str
    items: list[EnumItem]
    is_anonymous: bool = False
    comment: str = ""


@dataclass
class IR:
    """Intermediate representation of a C header"""
    module: str
    prefix: str
    dep_prefixes: list[str]
    structs: dict[str, StructInfo]
    funcs: dict[str, FuncInfo]
    enums: dict[str, EnumInfo]
    consts: list[EnumInfo]  # Anonymous enums
    comment: str = ""

    @classmethod
    def load(cls, json_path: str) -> 'IR':
        """Load IR from a JSON file"""
        with open(json_path, 'r') as f:
            data = json.load(f)
        return cls._from_dict(data)

    @classmethod
    def from_dict(cls, data: dict) -> 'IR':
        """Create IR from a dictionary (e.g., from gen_ir.gen())"""
        return cls._from_dict(data)

    @classmethod
    def _from_dict(cls, data: dict) -> 'IR':
        """Internal: Parse dict into IR"""
        structs = {}
        funcs = {}
        enums = {}
        consts = []

        for decl in data.get('decls', []):
            kind = decl.get('kind')
            is_dep = decl.get('is_dep', False)

            if kind == 'struct':
                struct = cls._parse_struct(decl)
                struct_key = f"dep:{struct.name}" if is_dep else struct.name
                structs[struct_key] = struct

            elif kind == 'func':
                func = cls._parse_func(decl)
                funcs[func.name] = func

            elif kind == 'enum':
                enum = cls._parse_enum(decl)
                enums[enum.name] = enum

            elif kind == 'consts':
                const = cls._parse_enum(decl)
                const.is_anonymous = True
                consts.append(const)

        return cls(
            module=data.get('module', ''),
            prefix=data.get('prefix', ''),
            dep_prefixes=data.get('dep_prefixes', []),
            structs=structs,
            funcs=funcs,
            enums=enums,
            consts=consts,
            comment=data.get('comment', ''),
        )

    @staticmethod
    def _parse_struct(decl: dict) -> StructInfo:
        """Parse struct declaration"""
        fields = []
        for f in decl.get('fields', []):
            if 'name' not in f:
                continue
            field_type = f['type']
            is_array = '[' in field_type
            array_sizes = []
            if is_array:
                # Extract array sizes like [4] or [4][4]
                matches = re.findall(r'\[(\d+)\]', field_type)
                array_sizes = [int(m) for m in matches]
            fields.append(FieldInfo(
                name=f['name'],
                type=field_type,
                is_array=is_array,
                array_sizes=array_sizes,
            ))
        return StructInfo(
            name=decl['name'],
            fields=fields,
            comment=decl.get('comment', ''),
        )

    @staticmethod
    def _parse_func(decl: dict) -> FuncInfo:
        """Parse function declaration"""
        params = []
        for p in decl.get('params', []):
            params.append(ParamInfo(
                name=p['name'],
                type=p['type'],
            ))
        return FuncInfo(
            name=decl['name'],
            type=decl['type'],
            params=params,
            comment=decl.get('comment', ''),
        )

    @staticmethod
    def _parse_enum(decl: dict) -> EnumInfo:
        """Parse enum declaration"""
        items = []
        for item in decl.get('items', []):
            value = int(item['value']) if 'value' in item else None
            items.append(EnumItem(
                name=item['name'],
                value=value,
            ))
        return EnumInfo(
            name=decl.get('name', ''),
            items=items,
            comment=decl.get('comment', ''),
        )

    def get_struct(self, name: str) -> Optional[StructInfo]:
        """Get struct by name, including dependency structs"""
        if name in self.structs:
            return self.structs[name]
        dep_key = f"dep:{name}"
        if dep_key in self.structs:
            return self.structs[dep_key]
        return None

    def is_struct_type(self, type_name: str) -> bool:
        """Check if type is a known struct"""
        clean = type_name.replace('const ', '').replace('*', '').strip()
        return self.get_struct(clean) is not None

    def is_enum_type(self, type_name: str) -> bool:
        """Check if type is a known enum"""
        return type_name in self.enums

    def own_structs(self) -> dict[str, StructInfo]:
        """Return only non-dependency structs"""
        return {k: v for k, v in self.structs.items() if not k.startswith('dep:')}

    def dep_structs(self) -> dict[str, StructInfo]:
        """Return only dependency structs"""
        return {k.replace('dep:', ''): v for k, v in self.structs.items() if k.startswith('dep:')}
