# SPDX-License-Identifier: GPL-3.0-only
"""Parse bounded gdbus output using GLib itself, without eval or regex rewriting."""
import ctypes as C
import ctypes.util
import json
import sys


def parse_gvariant(text):
    data = text.encode('utf-8')
    if len(data) > 1024*1024:
        raise ValueError('GVariant reply too large')
    libname = ctypes.util.find_library('glib-2.0')
    if not libname:
        raise RuntimeError('GLib unavailable')
    lib = C.CDLL(libname)
    def bind(name, result, args):
        fn = getattr(lib, name)
        fn.restype, fn.argtypes = result, args
        return fn
    parse = bind('g_variant_parse', C.c_void_p,
                 [C.c_void_p, C.c_char_p, C.c_void_p, C.c_void_p, C.POINTER(C.c_void_p)])
    unref = bind('g_variant_unref', None, [C.c_void_p])
    error_free = bind('g_error_free', None, [C.c_void_p])
    typename = bind('g_variant_get_type_string', C.c_char_p, [C.c_void_p])
    children = bind('g_variant_n_children', C.c_size_t, [C.c_void_p])
    child = bind('g_variant_get_child_value', C.c_void_p, [C.c_void_p, C.c_size_t])
    variant = bind('g_variant_get_variant', C.c_void_p, [C.c_void_p])
    string = bind('g_variant_get_string', C.c_char_p, [C.c_void_p, C.c_void_p])
    numeric = {}
    for key, name, result in [('b','boolean',C.c_int),('i','int32',C.c_int32),
                              ('u','uint32',C.c_uint32),('x','int64',C.c_int64),
                              ('t','uint64',C.c_uint64),('n','int16',C.c_int16),
                              ('q','uint16',C.c_uint16),('y','byte',C.c_ubyte),
                              ('d','double',C.c_double),('h','handle',C.c_int32)]:
        numeric[key] = bind('g_variant_get_'+name, result, [C.c_void_p])
    error = C.c_void_p()
    root = parse(None, data, None, None, C.byref(error))
    if not root:
        if error.value:
            error_free(error)
        raise ValueError('Invalid GVariant reply')
    budget = [10000]
    def read(value, depth=0):
        budget[0] -= 1
        if depth > 12 or budget[0] < 0:
            raise ValueError('GVariant nesting or node count limit')
        kind = typename(value).decode('ascii')
        if kind in ['s', 'o', 'g']:
            return string(value, None).decode('utf-8')
        if kind in numeric:
            result = numeric[kind](value)
            return bool(result) if kind == 'b' else result
        if kind == 'v':
            inner = variant(value)
            try:
                return read(inner, depth+1)
            finally:
                unref(inner)
        if kind.startswith(('a', '(', '{')):
            count = children(value)
            if count > 2048:
                raise ValueError('Too many GVariant children')
            rows = []
            for index in range(count):
                inner = child(value, index)
                try:
                    rows.append(read(inner, depth+1))
                finally:
                    unref(inner)
            if kind.startswith('a{'):
                result = dict(rows)
                if len(result) != len(rows):
                    raise ValueError('Duplicate dictionary keys')
                return result
            return rows
        raise ValueError('Unsupported GVariant type '+kind)
    try:
        return read(root)
    finally:
        unref(root)


if __name__ == '__main__':
    print(json.dumps(parse_gvariant(sys.stdin.read(1024*1024+1)), ensure_ascii=False))
