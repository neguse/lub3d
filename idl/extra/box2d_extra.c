/* Serial task system for single-threaded Box2D */
static void b2d_enqueue_task(b2TaskCallback* task, int32_t itemCount,
    int32_t minRange, void* taskContext, void* userContext)
{
    (void)userContext;
    task(0, itemCount, 0, taskContext);
}

static void b2d_finish_task(void* userTask, void* userContext)
{
    (void)userTask;
    (void)userContext;
}

/* Manifold accessors for PreSolve callback */
static int l_b2d_manifold_point_count(lua_State *L) {
    b2Manifold* m = (b2Manifold*)lua_touserdata(L, 1);
    lua_pushinteger(L, m->pointCount);
    return 1;
}
static int l_b2d_manifold_point(lua_State *L) {
    b2Manifold* m = (b2Manifold*)lua_touserdata(L, 1);
    int i = (int)luaL_checkinteger(L, 2) - 1;
    lua_newtable(L);
    lua_pushnumber(L, m->points[i].point.x); lua_rawseti(L, -2, 1);
    lua_pushnumber(L, m->points[i].point.y); lua_rawseti(L, -2, 2);
    return 1;
}
static int l_b2d_manifold_normal(lua_State *L) {
    b2Manifold* m = (b2Manifold*)lua_touserdata(L, 1);
    lua_newtable(L);
    lua_pushnumber(L, m->normal.x); lua_rawseti(L, -2, 1);
    lua_pushnumber(L, m->normal.y); lua_rawseti(L, -2, 2);
    return 1;
}

/* Friction callback (no void* context — manual trampoline) */
static lua_State* _friction_cb_L = NULL;
static int _friction_cb_ref = LUA_NOREF;

static float b2d_friction_trampoline(float frictionA, int matIdA, float frictionB, int matIdB) {
    if (!_friction_cb_L || _friction_cb_ref == LUA_NOREF)
        return frictionA * frictionB;
    lua_rawgeti(_friction_cb_L, LUA_REGISTRYINDEX, _friction_cb_ref);
    lua_pushnumber(_friction_cb_L, frictionA);
    lua_pushinteger(_friction_cb_L, matIdA);
    lua_pushnumber(_friction_cb_L, frictionB);
    lua_pushinteger(_friction_cb_L, matIdB);
    lua_call(_friction_cb_L, 4, 1);
    float r = (float)lua_tonumber(_friction_cb_L, -1);
    lua_pop(_friction_cb_L, 1);
    return r;
}

static int l_b2d_world_set_friction_callback(lua_State *L) {
    b2WorldId worldId = *(b2WorldId*)luaL_checkudata(L, 1, "b2d.WorldId");
    if (lua_isnil(L, 2) || lua_isnone(L, 2)) {
        if (_friction_cb_ref != LUA_NOREF) {
            luaL_unref(L, LUA_REGISTRYINDEX, _friction_cb_ref);
            _friction_cb_ref = LUA_NOREF; _friction_cb_L = NULL;
        }
        b2World_SetFrictionCallback(worldId, NULL);
    } else {
        luaL_checktype(L, 2, LUA_TFUNCTION);
        if (_friction_cb_ref != LUA_NOREF)
            luaL_unref(L, LUA_REGISTRYINDEX, _friction_cb_ref);
        lua_pushvalue(L, 2);
        _friction_cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        _friction_cb_L = L;
        b2World_SetFrictionCallback(worldId, b2d_friction_trampoline);
    }
    return 0;
}

/* Restitution callback (no void* context — manual trampoline) */
static lua_State* _restitution_cb_L = NULL;
static int _restitution_cb_ref = LUA_NOREF;

static float b2d_restitution_trampoline(float restitutionA, int matIdA, float restitutionB, int matIdB) {
    if (!_restitution_cb_L || _restitution_cb_ref == LUA_NOREF)
        return restitutionA > restitutionB ? restitutionA : restitutionB;
    lua_rawgeti(_restitution_cb_L, LUA_REGISTRYINDEX, _restitution_cb_ref);
    lua_pushnumber(_restitution_cb_L, restitutionA);
    lua_pushinteger(_restitution_cb_L, matIdA);
    lua_pushnumber(_restitution_cb_L, restitutionB);
    lua_pushinteger(_restitution_cb_L, matIdB);
    lua_call(_restitution_cb_L, 4, 1);
    float r = (float)lua_tonumber(_restitution_cb_L, -1);
    lua_pop(_restitution_cb_L, 1);
    return r;
}

static int l_b2d_world_set_restitution_callback(lua_State *L) {
    b2WorldId worldId = *(b2WorldId*)luaL_checkudata(L, 1, "b2d.WorldId");
    if (lua_isnil(L, 2) || lua_isnone(L, 2)) {
        if (_restitution_cb_ref != LUA_NOREF) {
            luaL_unref(L, LUA_REGISTRYINDEX, _restitution_cb_ref);
            _restitution_cb_ref = LUA_NOREF; _restitution_cb_L = NULL;
        }
        b2World_SetRestitutionCallback(worldId, NULL);
    } else {
        luaL_checktype(L, 2, LUA_TFUNCTION);
        if (_restitution_cb_ref != LUA_NOREF)
            luaL_unref(L, LUA_REGISTRYINDEX, _restitution_cb_ref);
        lua_pushvalue(L, 2);
        _restitution_cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        _restitution_cb_L = L;
        b2World_SetRestitutionCallback(worldId, b2d_restitution_trampoline);
    }
    return 0;
}

/* CollideMover callback trampoline (immediate — valid only during call) */
static lua_State* _collide_mover_cb_L = NULL;
static int _collide_mover_cb_ref = LUA_NOREF;

static bool b2d_collide_mover_trampoline(b2ShapeId shapeId, const b2PlaneResult* plane, void* context) {
    (void)context;
    if (!_collide_mover_cb_L || _collide_mover_cb_ref == LUA_NOREF) return false;
    lua_rawgeti(_collide_mover_cb_L, LUA_REGISTRYINDEX, _collide_mover_cb_ref);
    b2ShapeId* sid = (b2ShapeId*)lua_newuserdatauv(_collide_mover_cb_L, sizeof(b2ShapeId), 1);
    *sid = shapeId;
    luaL_setmetatable(_collide_mover_cb_L, "b2d.ShapeId");
    b2PlaneResult* pr = (b2PlaneResult*)lua_newuserdatauv(_collide_mover_cb_L, sizeof(b2PlaneResult), 1);
    *pr = *plane;
    luaL_setmetatable(_collide_mover_cb_L, "b2d.PlaneResult");
    lua_call(_collide_mover_cb_L, 2, 1);
    bool r = lua_toboolean(_collide_mover_cb_L, -1);
    lua_pop(_collide_mover_cb_L, 1);
    return r;
}

static int l_b2d_world_collide_mover(lua_State *L) {
    b2WorldId worldId = *(b2WorldId*)luaL_checkudata(L, 1, "b2d.WorldId");
    const b2Capsule* mover = (const b2Capsule*)luaL_checkudata(L, 2, "b2d.Capsule");
    b2QueryFilter filter = *(b2QueryFilter*)luaL_checkudata(L, 3, "b2d.QueryFilter");
    luaL_checktype(L, 4, LUA_TFUNCTION);
    lua_pushvalue(L, 4);
    _collide_mover_cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    _collide_mover_cb_L = L;
    b2World_CollideMover(worldId, mover, filter, b2d_collide_mover_trampoline, NULL);
    luaL_unref(L, LUA_REGISTRYINDEX, _collide_mover_cb_ref);
    _collide_mover_cb_ref = LUA_NOREF;
    _collide_mover_cb_L = NULL;
    return 0;
}

/* b2ClipVector wrapper (takes array of b2CollisionPlane userdata) */
static int l_b2d_clip_vector(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    b2Vec2 vector;
    lua_rawgeti(L, 1, 1); vector.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);
    lua_rawgeti(L, 1, 2); vector.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);
    luaL_checktype(L, 2, LUA_TTABLE);
    int count = (int)lua_rawlen(L, 2);
    b2CollisionPlane planes[64];
    luaL_argcheck(L, count <= 64, 2, "too many planes (max 64)");
    for (int i = 0; i < count; i++) {
        lua_rawgeti(L, 2, i + 1);
        b2CollisionPlane* p = (b2CollisionPlane*)luaL_checkudata(L, -1, "b2d.CollisionPlane");
        planes[i] = *p;
        lua_pop(L, 1);
    }
    b2Vec2 result = b2ClipVector(vector, planes, count);
    lua_newtable(L);
    lua_pushnumber(L, result.x); lua_rawseti(L, -2, 1);
    lua_pushnumber(L, result.y); lua_rawseti(L, -2, 2);
    return 1;
}

/* b2SolvePlanes wrapper (takes array of b2CollisionPlane userdata, mutates push field) */
static int l_b2d_solve_planes(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    b2Vec2 targetDelta;
    lua_rawgeti(L, 1, 1); targetDelta.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);
    lua_rawgeti(L, 1, 2); targetDelta.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);
    luaL_checktype(L, 2, LUA_TTABLE);
    int count = (int)lua_rawlen(L, 2);
    b2CollisionPlane planes[64];
    luaL_argcheck(L, count <= 64, 2, "too many planes (max 64)");
    for (int i = 0; i < count; i++) {
        lua_rawgeti(L, 2, i + 1);
        b2CollisionPlane* p = (b2CollisionPlane*)luaL_checkudata(L, -1, "b2d.CollisionPlane");
        planes[i] = *p;
        lua_pop(L, 1);
    }
    b2PlaneSolverResult result = b2SolvePlanes(targetDelta, planes, count);
    for (int i = 0; i < count; i++) {
        lua_rawgeti(L, 2, i + 1);
        b2CollisionPlane* p = (b2CollisionPlane*)lua_touserdata(L, -1);
        *p = planes[i];
        lua_pop(L, 1);
    }
    b2PlaneSolverResult* ud = (b2PlaneSolverResult*)lua_newuserdatauv(L, sizeof(b2PlaneSolverResult), 1);
    *ud = result;
    luaL_setmetatable(L, "b2d.PlaneSolverResult");
    return 1;
}
