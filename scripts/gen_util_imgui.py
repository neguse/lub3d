# Common utility functions for ImGui bindings generation
# Extended from sokol/bindgen/gen_util.py
import re

re_1d_array = re.compile(r"^(?:const )?\w*\s*\*?\[\d*\]$")
re_2d_array = re.compile(r"^(?:const )?\w*\s*\*?\[\d*\]\[\d*\]$")

def is_1d_array_type(s):
    return re_1d_array.match(s) is not None

def is_2d_array_type(s):
    return re_2d_array.match(s) is not None

def is_array_type(s):
    return is_1d_array_type(s) or is_2d_array_type(s)

def extract_array_type(s):
    return s[:s.index('[')].strip()

def extract_array_sizes(s):
    return s[s.index('['):].replace('[', ' ').replace(']', ' ').split()

def is_string_ptr(s):
    return s == "const char *"

def is_const_void_ptr(s):
    return s == "const void *"

def is_void_ptr(s):
    return s == "void *"

def is_func_ptr(s):
    return '(*)' in s

def extract_ptr_type(s):
    tokens = s.split()
    if tokens[0] == 'const':
        return tokens[1]
    else:
        return tokens[0]

# PREFIX_BLA_BLUB to bla_blub
def as_lower_snake_case(s, prefix):
    outp = s.lower()
    if outp.startswith(prefix):
        outp = outp[len(prefix):]
    return outp

# prefix_bla_blub => blaBlub, PREFIX_BLA_BLUB => blaBlub
def as_lower_camel_case(s, prefix):
    outp = s.lower()
    if outp.startswith(prefix):
        outp = outp[len(prefix):]
    parts = outp.split('_')
    outp = parts[0]
    for part in parts[1:]:
        outp += part.capitalize()
    return outp

# ImGui-specific utilities

def is_imvec2(t):
    """Check if type is ImVec2 or const ImVec2&"""
    return 'ImVec2' in t

def is_imvec4(t):
    """Check if type is ImVec4 or const ImVec4&"""
    return 'ImVec4' in t

def is_imvec(t):
    """Check if type is ImVec2 or ImVec4"""
    return is_imvec2(t) or is_imvec4(t)

def is_bool_ptr(t):
    """Check if type is bool pointer (output parameter)"""
    return t == 'bool *'

def is_int_ptr(t):
    """Check if type is int pointer (output parameter)"""
    return t == 'int *'

def is_float_ptr(t):
    """Check if type is float pointer (output parameter)"""
    return t == 'float *'

def is_float_array(t):
    """Check if type is float array (e.g., float[3])"""
    return t.startswith('float') and '[' in t

def is_double_ptr(t):
    """Check if type is double pointer"""
    return t == 'double *'

def is_unsigned_int_ptr(t):
    """Check if type is unsigned int pointer"""
    return t == 'unsigned int *'

def is_output_ptr(t):
    """Check if type is an output pointer (non-const pointer)"""
    t = t.strip()
    if t.startswith('const '):
        return False
    return t.endswith('*') and t != 'const char *' and not is_func_ptr(t)

def is_callback_type(t):
    """Check if type is a callback function pointer"""
    return 'Callback' in t or '(*)' in t

def get_imvec_size(t):
    """Get the size of ImVec (2 or 4)"""
    if 'ImVec2' in t:
        return 2
    if 'ImVec4' in t:
        return 4
    return 0

def lua_type_for_c_type(t):
    """Map C/C++ type to Lua type for documentation"""
    t = t.strip()
    # Basic types
    if t in ['int', 'unsigned int', 'ImGuiID', 'ImU32', 'ImS32']:
        return 'integer'
    if t in ['float', 'double']:
        return 'number'
    if t in ['bool']:
        return 'boolean'
    if t == 'const char *':
        return 'string'
    if t == 'void':
        return 'nil'
    # ImGui types
    if 'ImVec2' in t:
        return 'ImVec2'
    if 'ImVec4' in t:
        return 'ImVec4'
    # Pointers
    if t == 'bool *':
        return 'boolean?'
    if t in ['int *', 'float *', 'double *']:
        return 'number?'
    # Default
    return 'any'

def generate_overload_suffix(func, all_funcs):
    """Generate a suffix for overloaded functions based on parameter types"""
    name = func['name']
    overloads = [f for f in all_funcs if f['kind'] == 'func' and f['name'] == name]

    if len(overloads) <= 1:
        return ''

    # Generate suffix based on parameter types
    params = func.get('params', [])
    if not params:
        return '_void'

    # Use first parameter's type to differentiate
    first_param = params[0]
    t = first_param['type']

    if is_string_ptr(t):
        return '_str'
    elif 'int' in t:
        return '_int'
    elif 'void *' in t or 'const void *' in t:
        return '_ptr'
    elif 'float' in t:
        return '_float'
    elif is_imvec2(t):
        return '_vec2'
    elif is_imvec4(t):
        return '_vec4'
    elif 'ImGuiID' in t:
        return '_id'
    else:
        # Use parameter count as fallback
        return f'_{len(params)}'

def should_skip_function(func):
    """Determine if a function should be skipped in binding generation"""
    name = func['name']

    # Skip variadic functions (Text, TextColored, etc. have V variants)
    if func.get('is_vararg'):
        return True

    # Skip internal functions
    if name.startswith('_'):
        return True

    # Skip deprecated functions
    if 'IMGUI_DISABLE' in func.get('comment', ''):
        return True

    # Skip functions with complex callback types we can't handle
    for param in func.get('params', []):
        t = param['type']
        # Skip functions with arbitrary callback params (except common ones)
        if is_callback_type(t) and 'ImGuiInputTextCallback' not in t:
            return True

    return False

def extract_return_type(func_type):
    """Extract return type from function type string"""
    # Function type is like "bool (const char *, bool *, int)"
    # We need to get the part before the first '('
    idx = func_type.find('(')
    if idx > 0:
        return func_type[:idx].strip()
    return func_type

def get_param_types(func):
    """Get list of parameter type strings"""
    return [p['type'] for p in func.get('params', [])]
