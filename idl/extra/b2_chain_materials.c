int _count = {self}->materialCount;
        const b2SurfaceMaterial* _mats = {self}->materials;
        if (_mats == NULL) { lua_pushnil(L); } else {
            lua_createtable(L, _count, 0);
            for (int _i = 0; _i < _count; _i++) {
                b2SurfaceMaterial* _ud = (b2SurfaceMaterial*)lua_newuserdatauv(L, sizeof(b2SurfaceMaterial), 1);
                *_ud = _mats[_i];
                luaL_setmetatable(L, "b2d.SurfaceMaterial");
                lua_rawseti(L, -2, _i + 1);
            }
        }
---SETTER---
int _n = (int)lua_rawlen(L, {value_idx});
        b2SurfaceMaterial* _mats = (b2SurfaceMaterial*)lua_newuserdatauv(L, sizeof(b2SurfaceMaterial) * (_n > 0 ? _n : 1), 0);
        for (int _i = 0; _i < _n; _i++) {
            lua_rawgeti(L, {value_idx}, _i + 1);
            b2SurfaceMaterial* _src = (b2SurfaceMaterial*)luaL_checkudata(L, -1, "b2d.SurfaceMaterial");
            _mats[_i] = *_src;
            lua_pop(L, 1);
        }
        lua_setiuservalue(L, 1, 3);
        {self}->materials = _mats;
        {self}->materialCount = _n
