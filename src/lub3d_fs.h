/*
 * lub3d_fs.h - Unified file system module for lub3d
 *
 * Lua API: require("lub3d.fs")
 *   fs.read(path)        -- read entire file (string or nil)
 *   fs.write(path, data) -- write file (true/false)
 *   fs.mtime(path)       -- modification time (integer or nil)
 *   fs.exists(path)      -- existence check (boolean)
 *   fs.dir(path)         -- directory listing (iterator or nil)
 */
#ifndef LUB3D_FS_H
#define LUB3D_FS_H

#include <lua.h>
#include <stddef.h>

/* Lua module opener */
int luaopen_lub3d_fs(lua_State *L);

/* Optional pack data lookup. If set, fs.read/fs.exists will check pack
 * data before falling back to the filesystem.
 * Returns pointer to data and sets *out_size, or NULL if not found. */
typedef const unsigned char *(*lub3d_fs_pack_find_fn)(const char *path, unsigned int *out_size);
extern lub3d_fs_pack_find_fn lub3d_fs_pack_find;

#ifdef __EMSCRIPTEN__
/* Fetch file via synchronous XHR. Caller must free() the returned buffer. */
char *lub3d_fs_fetch_file(const char *url, size_t *out_len);
#endif

#endif /* LUB3D_FS_H */
