"""
Function binding generation module

Generates wrapper functions for C functions.
"""

from typing import TYPE_CHECKING

from .codegen import CodeGen, is_int_type, is_float_type, is_string_ptr, is_void_ptr, is_const_void_ptr

if TYPE_CHECKING:
    from .ir import IR, FuncInfo
    from .types import TypeConverter


class FuncGenerator:
    """Generates function wrapper bindings"""

    # Modules that need SOKOL_DUMMY_BACKEND support
    DUMMY_BACKEND_PREFIXES = ['sapp_', 'sglue_', 'saudio_']

    # Special dummy return values for specific functions
    DUMMY_SPECIAL_RETURNS = {
        'sglue_environment': '''(sg_environment){
            .defaults = {
                .color_format = SG_PIXELFORMAT_RGBA8,
                .depth_format = SG_PIXELFORMAT_DEPTH_STENCIL,
                .sample_count = 1,
            },
        }''',
        'sglue_swapchain': '''(sg_swapchain){
            .width = 640,
            .height = 480,
            .sample_count = 1,
            .color_format = SG_PIXELFORMAT_RGBA8,
            .depth_format = SG_PIXELFORMAT_DEPTH_STENCIL,
        }''',
        'sapp_width': '640',
        'sapp_height': '480',
        'sapp_widthf': '640.0f',
        'sapp_heightf': '480.0f',
        'sapp_dpi_scale': '1.0f',
        'sapp_frame_duration': '1.0/60.0',
    }

    def __init__(self, ir: 'IR', type_conv: 'TypeConverter', prefix: str):
        self.ir = ir
        self.type_conv = type_conv
        self.prefix = prefix

    def generate(self, func: 'FuncInfo', gen: CodeGen):
        """Generate wrapper for a function"""
        func_name = func.name
        result_type = func.return_type
        needs_dummy = self.prefix in self.DUMMY_BACKEND_PREFIXES

        gen.line(f'static int l_{func_name}(lua_State *L) {{')
        gen.indent()

        if needs_dummy:
            gen.line('#ifdef SOKOL_DUMMY_BACKEND')
            self._gen_dummy_impl(func, gen)
            gen.line('#else')

        # Get parameters from Lua stack
        for i, param in enumerate(func.params):
            to_code = self.type_conv.lua_to_c(param.type, i + 1, param.name, self.prefix)
            gen.line(to_code)

        # Call the C function
        args_str = ', '.join(p.name for p in func.params)
        if result_type == 'void':
            gen.line(f'{func_name}({args_str});')
            gen.line('return 0;')
        else:
            gen.line(f'{result_type} result = {func_name}({args_str});')
            push_code = self.type_conv.c_to_lua(result_type, 'result', self.prefix)
            if push_code:
                gen.line(push_code)
                gen.line('return 1;')
            else:
                gen.line('return 0;')

        if needs_dummy:
            gen.line('#endif')

        gen.dedent()
        gen.line('}')
        gen.line()

    def _gen_dummy_impl(self, func: 'FuncInfo', gen: CodeGen):
        """Generate dummy backend implementation"""
        func_name = func.name
        result_type = func.return_type

        gen.line('(void)L; /* unused in dummy mode */')

        if result_type == 'void':
            gen.line('return 0;')
        else:
            # Check for special return value first
            if func_name in self.DUMMY_SPECIAL_RETURNS:
                dummy_val = self.DUMMY_SPECIAL_RETURNS[func_name]
            else:
                dummy_val = self._get_dummy_return_value(result_type)
            gen.line(f'{result_type} result = {dummy_val};')
            push_code = self.type_conv.c_to_lua(result_type, 'result', self.prefix)
            if push_code:
                gen.line(push_code)
                gen.line('return 1;')
            else:
                gen.line('return 0;')

    def _get_dummy_return_value(self, result_type: str) -> str:
        """Get a dummy return value for SOKOL_DUMMY_BACKEND"""
        if result_type == 'void':
            return ''
        elif result_type == 'bool':
            return 'false'
        elif is_int_type(result_type):
            return '0'
        elif is_float_type(result_type):
            return '0.0f' if result_type == 'float' else '0.0'
        elif is_string_ptr(result_type):
            return '""'
        elif self.ir.is_struct_type(result_type):
            return f'({result_type}){{0}}'
        elif self.ir.is_enum_type(result_type):
            return '0'
        elif is_void_ptr(result_type) or is_const_void_ptr(result_type):
            return 'NULL'
        else:
            return '0'
