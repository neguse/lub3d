int _count = {self}->count;
        const b2Vec2* _pts = {self}->points;
        if (_pts == NULL) { lua_pushnil(L); } else {
            lua_createtable(L, _count, 0);
            for (int _i = 0; _i < _count; _i++) {
                lua_createtable(L, 2, 0);
                lua_pushnumber(L, _pts[_i].x); lua_rawseti(L, -2, 1);
                lua_pushnumber(L, _pts[_i].y); lua_rawseti(L, -2, 2);
                lua_rawseti(L, -2, _i + 1);
            }
        }
---SETTER---
int _n = (int)lua_rawlen(L, {value_idx});
        b2Vec2* _pts = (b2Vec2*)lua_newuserdatauv(L, sizeof(b2Vec2) * (_n > 0 ? _n : 1), 0);
        for (int _i = 0; _i < _n; _i++) {
            lua_rawgeti(L, {value_idx}, _i + 1);
            lua_rawgeti(L, -1, 1); _pts[_i].x = (float)lua_tonumber(L, -1); lua_pop(L, 1);
            lua_rawgeti(L, -1, 2); _pts[_i].y = (float)lua_tonumber(L, -1); lua_pop(L, 1);
            lua_pop(L, 1);
        }
        lua_setiuservalue(L, 1, 2);
        {self}->points = _pts;
        {self}->count = _n
