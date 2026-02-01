"""
Code generation utilities

Provides helpers for generating C and Lua code.
"""

from typing import Optional


class CodeGen:
    """Code generation helper with indentation support"""

    def __init__(self):
        self._lines: list[str] = []
        self._indent: int = 0
        self._indent_str: str = '    '  # 4 spaces

    def line(self, text: str = ''):
        """Add a line with current indentation"""
        if text:
            self._lines.append(self._indent_str * self._indent + text)
        else:
            self._lines.append('')

    def lines(self, *texts: str):
        """Add multiple lines"""
        for text in texts:
            self.line(text)

    def raw(self, text: str):
        """Add raw text without indentation processing"""
        self._lines.append(text)

    def indent(self):
        """Increase indentation"""
        self._indent += 1

    def dedent(self):
        """Decrease indentation"""
        if self._indent > 0:
            self._indent -= 1

    def block(self, header: str, footer: str = '}'):
        """Context manager for code blocks"""
        return _BlockContext(self, header, footer)

    def output(self) -> str:
        """Get generated code as string"""
        return '\n'.join(self._lines)

    def clear(self):
        """Clear all generated code"""
        self._lines.clear()
        self._indent = 0


class _BlockContext:
    """Context manager for indented code blocks"""

    def __init__(self, gen: CodeGen, header: str, footer: str):
        self._gen = gen
        self._header = header
        self._footer = footer

    def __enter__(self):
        self._gen.line(self._header)
        self._gen.indent()
        return self

    def __exit__(self, *args):
        self._gen.dedent()
        self._gen.line(self._footer)


def as_pascal_case(name: str, prefix: str) -> str:
    """Convert C name to PascalCase, removing prefix

    Examples:
        sg_begin_pass -> BeginPass
        sgl_end -> End
        sg_buffer -> Buffer
    """
    parts = name.lower().split('_')
    start = 1 if parts and parts[0] + '_' == prefix else 0
    result = ''
    for part in parts[start:]:
        if part and part != 't':  # Skip empty and 't' suffix
            result += part.capitalize()
    return result


def as_snake_case(name: str, prefix: str) -> str:
    """Convert C name to snake_case, removing prefix

    Examples:
        sg_begin_pass -> begin_pass
        SG_LOADACTION_CLEAR -> loadaction_clear
    """
    result = name.lower()
    if result.startswith(prefix):
        result = result[len(prefix):]
    return result


def get_type_prefix(type_name: str, all_prefixes: list[str]) -> Optional[str]:
    """Get the original prefix for a type name

    Examples:
        sg_buffer -> sg_
        sapp_event -> sapp_
    """
    for prefix in all_prefixes:
        if type_name.startswith(prefix):
            return prefix
    return None


def is_int_type(type_str: str) -> bool:
    """Check if type is an integer type"""
    return type_str in [
        'int', 'char',
        'int8_t', 'uint8_t',
        'int16_t', 'uint16_t',
        'int32_t', 'uint32_t',
        'int64_t', 'uint64_t',
        'size_t', 'uintptr_t', 'intptr_t',
    ]


def is_float_type(type_str: str) -> bool:
    """Check if type is a float type"""
    return type_str in ['float', 'double']


def is_prim_type(type_str: str) -> bool:
    """Check if type is a primitive type"""
    return type_str == 'bool' or is_int_type(type_str) or is_float_type(type_str)


def is_string_ptr(type_str: str) -> bool:
    """Check if type is a C string"""
    return type_str == 'const char *'


def is_void_ptr(type_str: str) -> bool:
    """Check if type is void*"""
    return type_str == 'void *'


def is_const_void_ptr(type_str: str) -> bool:
    """Check if type is const void*"""
    return type_str == 'const void *'


def is_func_ptr(type_str: str) -> bool:
    """Check if type is a function pointer"""
    return '(*)' in type_str


def is_1d_array_type(type_str: str) -> bool:
    """Check if type is a 1D array"""
    import re
    return re.match(r"^(?:const )?\w*\s*\*?\[\d*\]$", type_str) is not None


def is_2d_array_type(type_str: str) -> bool:
    """Check if type is a 2D array"""
    import re
    return re.match(r"^(?:const )?\w*\s*\*?\[\d*\]\[\d*\]$", type_str) is not None


def extract_array_type(type_str: str) -> str:
    """Extract base type from array type"""
    return type_str[:type_str.index('[')].strip()


def extract_array_sizes(type_str: str) -> list[int]:
    """Extract array dimensions"""
    import re
    return [int(m) for m in re.findall(r'\[(\d+)\]', type_str)]


def extract_ptr_type(type_str: str) -> str:
    """Extract pointed-to type from pointer type"""
    # "const sg_buffer *" -> "sg_buffer"
    # "sg_buffer *" -> "sg_buffer"
    tokens = type_str.replace('*', '').split()
    if tokens[0] == 'const':
        return tokens[1] if len(tokens) > 1 else ''
    return tokens[0]


def normalize_ptr_type(type_str: str) -> str:
    """Normalize pointer type spacing"""
    return type_str.replace(' *', '*').replace('* ', '*')


def parse_func_ptr(field_type: str) -> tuple[str, list[str]]:
    """Parse function pointer type

    Returns (return_type, args_list)
    Example: "void (*)(const sapp_event *)" -> ("void", ["const sapp_event *"])
    """
    if '(*)' not in field_type:
        return '', []
    result_type = field_type[:field_type.index('(*)')].strip()
    args_str = field_type[field_type.index('(*)')+4:-1]
    args = [arg.strip() for arg in args_str.split(',') if arg.strip() and arg.strip() != 'void']
    return result_type, args
