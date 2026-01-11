#-------------------------------------------------------------------------------
#   Generate an intermediate representation of a clang AST dump.
#   Extended from sokol/bindgen/gen_ir.py for C++ and ImGui support.
#-------------------------------------------------------------------------------
import re, json, sys, subprocess
from collections import defaultdict

def is_api_decl(decl, prefix):
    if 'name' in decl:
        return decl['name'].startswith(prefix)
    elif decl['kind'] == 'EnumDecl':
        # an anonymous enum, check if the items start with the prefix
        first = get_first_non_comment(decl['inner'])
        return first['name'].lower().startswith(prefix)
    else:
        return False

def get_first_non_comment(items):
    return next(i for i in items if i['kind'] != 'FullComment')

def strip_comments(items):
    return [i for i in items if i['kind'] != 'FullComment']

def extract_comment(comment, source):
    return source[comment['range']['begin']['offset']:comment['range']['end']['offset']+1].rstrip()

def is_dep_decl(decl, dep_prefixes):
    for prefix in dep_prefixes:
        if is_api_decl(decl, prefix):
            return True
    return False

def dep_prefix(decl, dep_prefixes):
    for prefix in dep_prefixes:
        if is_api_decl(decl, prefix):
            return prefix
    return None

def filter_types(str):
    return str.replace('_Bool', 'bool')

def parse_struct(decl, source):
    outp = {}
    outp['kind'] = 'struct'
    outp['name'] = decl['name']
    outp['fields'] = []
    if 'inner' not in decl:
        return outp
    for item_decl in decl['inner']:
        if item_decl['kind'] == 'FullComment':
            outp['comment'] = extract_comment(item_decl, source)
            continue
        if item_decl['kind'] != 'FieldDecl':
            # Skip non-field members in C++ structs (methods, etc.)
            continue
        item = {}
        if 'name' in item_decl:
            item['name'] = item_decl['name']
        item['type'] = filter_types(item_decl['type']['qualType'])
        outp['fields'].append(item)
    return outp

def find_constant_value(node):
    """Recursively find ConstantExpr with evaluated value."""
    if node.get('kind') == 'ConstantExpr' and 'value' in node:
        return node['value']
    for child in node.get('inner', []):
        val = find_constant_value(child)
        if val is not None:
            return val
    return None

def parse_enum(decl, source):
    outp = {}
    if 'name' in decl:
        outp['kind'] = 'enum'
        outp['name'] = decl['name']
        needs_value = False
    else:
        outp['kind'] = 'consts'
        needs_value = True
    outp['items'] = []
    if 'inner' not in decl:
        return outp
    next_value = 0  # Track auto-increment for enums without explicit values
    for item_decl in decl['inner']:
        if item_decl['kind'] == 'FullComment':
            outp['comment'] = extract_comment(item_decl, source)
            continue
        if item_decl['kind'] == 'EnumConstantDecl':
            item = {}
            item['name'] = item_decl['name']
            # Find evaluated value from ConstantExpr (handles ImplicitCastExpr wrapper)
            value = find_constant_value(item_decl)
            if value is not None:
                item['value'] = value
                next_value = int(value) + 1
            else:
                # Auto-increment for enums without explicit value
                item['value'] = str(next_value)
                next_value += 1
            if needs_value and 'value' not in item:
                continue  # Skip anonymous enum items without explicit value
            outp['items'].append(item)
    return outp

def has_default_value(param):
    """Check if a parameter has a default value in clang AST."""
    if 'inner' not in param:
        return False
    # Look for default argument expressions
    for child in param['inner']:
        kind = child.get('kind', '')
        # Various expression types that indicate default values
        if kind in ['IntegerLiteral', 'FloatingLiteral', 'CXXNullPtrLiteralExpr',
                    'ImplicitCastExpr', 'CXXDefaultArgExpr', 'CXXConstructExpr',
                    'DeclRefExpr', 'UnaryOperator', 'CStyleCastExpr',
                    'CXXMemberCallExpr', 'CallExpr', 'CXXFunctionalCastExpr',
                    'MaterializeTemporaryExpr', 'ExprWithCleanups']:
            return True
    return False

def is_vararg_func(decl):
    """Check if function has variadic arguments (va_list or ...)."""
    type_str = decl['type']['qualType']
    if '...' in type_str:
        return True
    if 'va_list' in type_str:
        return True
    return False

def is_out_param(param_type):
    """Check if parameter type is an output parameter (non-const pointer)."""
    t = param_type.strip()
    # const pointers are not out params
    if t.startswith('const '):
        return False
    # Check if it's a pointer (but not const char*)
    if t.endswith('*') and t != 'const char *':
        return True
    return False

def parse_func(decl, source):
    outp = {}
    outp['kind'] = 'func'
    outp['name'] = decl['name']
    outp['type'] = filter_types(decl['type']['qualType'])
    outp['params'] = []

    # Check for variadic function
    if is_vararg_func(decl):
        outp['is_vararg'] = True

    if 'inner' in decl:
        for param in decl['inner']:
            if param['kind'] == 'FullComment':
                outp['comment'] = extract_comment(param, source)
                continue
            if param['kind'] != 'ParmVarDecl':
                # Skip non-parameter children
                continue
            outp_param = {}
            if 'name' in param:
                outp_param['name'] = param['name']
            else:
                outp_param['name'] = ''  # Anonymous parameter
            outp_param['type'] = filter_types(param['type']['qualType'])

            # Check for default value
            if has_default_value(param):
                outp_param['has_default'] = True

            # Check if it's an output parameter
            if is_out_param(outp_param['type']):
                outp_param['is_out'] = True

            outp['params'].append(outp_param)
    return outp

def parse_decl(decl, source):
    kind = decl['kind']
    if kind == 'RecordDecl':
        return parse_struct(decl, source)
    elif kind == 'CXXRecordDecl':
        # C++ struct/class
        return parse_struct(decl, source)
    elif kind == 'EnumDecl':
        return parse_enum(decl, source)
    elif kind == 'FunctionDecl':
        return parse_func(decl, source)
    elif kind == 'CXXMethodDecl':
        # C++ method - skip for now (we handle free functions in namespace)
        return None
    else:
        return None

def extract_namespace_funcs(namespace_decl, source, func_prefix=''):
    """Extract function declarations from a namespace."""
    funcs = []
    if 'inner' not in namespace_decl:
        return funcs

    for decl in namespace_decl['inner']:
        if decl['kind'] == 'FunctionDecl':
            # Check if it has IMGUI_API (visibility attribute or similar)
            func = parse_func(decl, source)
            if func:
                func['namespace'] = namespace_decl.get('name', '')
                funcs.append(func)
    return funcs

def clang(csrc_path, with_comments=False, cpp_mode=False, include_paths=None):
    """Run clang to get AST dump."""
    if cpp_mode:
        cmd = ['clang++', '-std=c++17']
    else:
        cmd = ['clang']

    cmd.extend(['-Xclang', '-ast-dump=json', '-c', csrc_path])

    if include_paths:
        for path in include_paths:
            cmd.extend(['-I', path])

    if with_comments:
        cmd.append('-fparse-all-comments')

    # Add flags to handle ImGui
    if cpp_mode:
        cmd.extend([
            '-DIMGUI_DISABLE_OBSOLETE_FUNCTIONS',
            '-DIMGUI_DISABLE_OBSOLETE_KEYIO',
        ])

    return subprocess.check_output(cmd)

def gen(header_path, source_path, module, main_prefix, dep_prefixes,
        with_comments=False, cpp_mode=False, namespace=None, include_paths=None):
    """Generate IR from header file."""
    ast = clang(source_path, with_comments=with_comments, cpp_mode=cpp_mode, include_paths=include_paths)
    inp = json.loads(ast)
    outp = {}
    outp['module'] = module
    outp['prefix'] = main_prefix
    outp['dep_prefixes'] = dep_prefixes
    outp['cpp_mode'] = cpp_mode
    if namespace:
        outp['namespace'] = namespace
    outp['decls'] = []

    # Track function overloads
    func_counts = defaultdict(int)

    with open(header_path, mode='r', newline='') as f:
        source = f.read()
        first_comment = re.search(r"/\*(.*?)\*/", source, re.S)
        if first_comment and "Project URL" in first_comment.group(1):
            outp['comment'] = first_comment.group(1)

        for decl in inp['inner']:
            # Handle namespace (e.g., ImGui namespace)
            if decl['kind'] == 'NamespaceDecl' and namespace and decl.get('name') == namespace:
                funcs = extract_namespace_funcs(decl, source)
                for func in funcs:
                    func_name = func['name']
                    func['overload_index'] = func_counts[func_name]
                    func_counts[func_name] += 1
                    outp['decls'].append(func)
                continue

            # Handle top-level declarations (structs, enums, etc.)
            is_dep = is_dep_decl(decl, dep_prefixes)
            if is_api_decl(decl, main_prefix) or is_dep:
                outp_decl = parse_decl(decl, source)
                if outp_decl is not None:
                    outp_decl['is_dep'] = is_dep
                    outp_decl['dep_prefix'] = dep_prefix(decl, dep_prefixes)
                    outp['decls'].append(outp_decl)

    # Second pass: assign overload indices for non-namespace functions
    for decl in outp['decls']:
        if decl['kind'] == 'func' and 'overload_index' not in decl:
            func_name = decl['name']
            decl['overload_index'] = func_counts[func_name]
            func_counts[func_name] += 1

    # Mark functions that have overloads
    for decl in outp['decls']:
        if decl['kind'] == 'func':
            func_name = decl['name']
            if func_counts[func_name] > 1:
                decl['has_overloads'] = True

    with open(f'{module}.json', 'w') as f:
        f.write(json.dumps(outp, indent=2))
    return outp

def gen_imgui(imgui_h_path, output_name='imgui'):
    """Generate IR specifically for ImGui."""
    # Create a simple source file that includes imgui.h
    import tempfile
    import os

    # Make paths absolute for clang to find from temp directory
    imgui_h_path = os.path.abspath(imgui_h_path)
    imgui_dir = os.path.dirname(imgui_h_path)

    # Create temporary source file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.cpp', delete=False) as f:
        f.write(f'#include "{imgui_h_path}"\n')
        temp_src = f.name

    try:
        outp = gen(
            header_path=imgui_h_path,
            source_path=temp_src,
            module=output_name,
            main_prefix='Im',  # ImVec2, ImVec4, ImGui*, etc.
            dep_prefixes=[],
            with_comments=True,
            cpp_mode=True,
            namespace='ImGui',
            include_paths=[imgui_dir]
        )
        return outp
    finally:
        os.unlink(temp_src)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: gen_ir_imgui.py <imgui.h path> [output_name]")
        sys.exit(1)

    imgui_h = sys.argv[1]
    output_name = sys.argv[2] if len(sys.argv) > 2 else 'imgui'

    ir = gen_imgui(imgui_h, output_name)
    print(f"Generated {output_name}.json with {len(ir['decls'])} declarations")
