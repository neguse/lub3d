using Generator.ClangAst;

namespace Generator.Modules.Jolt;

/// <summary>
/// Jolt Physics Lua binding module.
/// C++ binding is hand-written in src/jolt_lua.cpp.
/// This module generates LuaCATS annotations only (no C code generation).
/// </summary>
public class JoltModule : IModule
{
    public string ModuleName => "jolt";
    public string Prefix => "jolt_";

    // Multi-return helper types (LuaCATS only)
    private static readonly BindingType Vec3Return = new BindingType.Custom(
        "void", "number, number, number", null, null, null, null);

    private static readonly BindingType QuatReturn = new BindingType.Custom(
        "void", "number, number, number, number", null, null, null, null);

    private static readonly BindingType WorldType = new BindingType.Struct(
        "JoltWorld", "jolt.World", "jolt.World");

    public ModuleSpec BuildSpec(TypeRegistry reg, Dictionary<string, string> prefixToModule, SourceLink? sourceLink = null)
    {
        // World methods
        var worldMethods = new List<MethodBinding>
        {
            new("l_jolt_set_gravity", "set_gravity",
                [new ParamBinding("x", new BindingType.Float()),
                 new ParamBinding("y", new BindingType.Float()),
                 new ParamBinding("z", new BindingType.Float())],
                new BindingType.Void(), null),

            new("l_jolt_get_gravity", "get_gravity",
                [], Vec3Return, null),

            new("l_jolt_update", "update",
                [new ParamBinding("dt", new BindingType.Float()),
                 new ParamBinding("collision_steps", new BindingType.Int(), IsOptional: true)],
                new BindingType.Int(), null),

            new("l_jolt_optimize", "optimize",
                [], new BindingType.Void(), null),

            new("l_jolt_create_box", "create_box",
                [new ParamBinding("hx", new BindingType.Float()),
                 new ParamBinding("hy", new BindingType.Float()),
                 new ParamBinding("hz", new BindingType.Float()),
                 new ParamBinding("x", new BindingType.Float()),
                 new ParamBinding("y", new BindingType.Float()),
                 new ParamBinding("z", new BindingType.Float()),
                 new ParamBinding("motion_type", new BindingType.Int(), IsOptional: true)],
                new BindingType.Int(), null),

            new("l_jolt_create_sphere", "create_sphere",
                [new ParamBinding("radius", new BindingType.Float()),
                 new ParamBinding("x", new BindingType.Float()),
                 new ParamBinding("y", new BindingType.Float()),
                 new ParamBinding("z", new BindingType.Float()),
                 new ParamBinding("motion_type", new BindingType.Int(), IsOptional: true)],
                new BindingType.Int(), null),

            new("l_jolt_remove_body", "remove_body",
                [new ParamBinding("id", new BindingType.Int())],
                new BindingType.Void(), null),

            new("l_jolt_get_position", "get_position",
                [new ParamBinding("id", new BindingType.Int())],
                Vec3Return, null),

            new("l_jolt_get_rotation", "get_rotation",
                [new ParamBinding("id", new BindingType.Int())],
                QuatReturn, null),

            new("l_jolt_set_velocity", "set_linear_velocity",
                [new ParamBinding("id", new BindingType.Int()),
                 new ParamBinding("vx", new BindingType.Float()),
                 new ParamBinding("vy", new BindingType.Float()),
                 new ParamBinding("vz", new BindingType.Float())],
                new BindingType.Void(), null),

            new("l_jolt_add_impulse", "add_impulse",
                [new ParamBinding("id", new BindingType.Int()),
                 new ParamBinding("ix", new BindingType.Float()),
                 new ParamBinding("iy", new BindingType.Float()),
                 new ParamBinding("iz", new BindingType.Float())],
                new BindingType.Void(), null),

            new("l_jolt_is_active", "is_active",
                [new ParamBinding("id", new BindingType.Int())],
                new BindingType.Bool(), null),

            new("l_jolt_body_count", "body_count",
                [], new BindingType.Int(), null),
        };

        var opaqueTypes = new List<OpaqueTypeBinding>
        {
            new("JoltWorld", "World", "jolt.World", "jolt.World",
                null, // InitFunc — handled via ExtraLuaFuncs for param annotations
                "l_jolt_world_destroy", // UninitFunc — generates destroy annotation
                null, null,
                worldMethods, null),
        };

        // Module-level functions (for LuaCATS annotations)
        var extraLuaFuncs = new List<FuncBinding>
        {
            new("l_jolt_world_new", "init",
                [new ParamBinding("max_bodies", new BindingType.Int(), IsOptional: true),
                 new ParamBinding("max_body_pairs", new BindingType.Int(), IsOptional: true),
                 new ParamBinding("max_contact_constraints", new BindingType.Int(), IsOptional: true)],
                WorldType, null),
        };

        return new ModuleSpec(
            ModuleName, Prefix,
            CIncludes: [],
            ExtraCCode: null,
            Structs: [],
            Funcs: [],
            Enums: [],
            ExtraLuaRegs: [("init", "l_jolt_world_new")],
            OpaqueTypes: opaqueTypes,
            IsCpp: true,
            ExtraLuaFuncs: extraLuaFuncs);
    }

    public string GenerateC(TypeRegistry reg, Dictionary<string, string> prefixToModule)
    {
        // C++ binding is hand-written in src/jolt_lua.cpp
        return "";
    }

    public string GenerateLua(TypeRegistry reg, Dictionary<string, string> prefixToModule, SourceLink? sourceLink = null)
    {
        var spec = BuildSpec(reg, prefixToModule, sourceLink);
        var sb = LuaCats.LuaCatsGen.Header(spec.ModuleName);

        // World class with methods
        var ot = spec.OpaqueTypes[0];
        sb += $"---@class {ot.LuaClassName}\n";
        sb += $"---@field destroy fun(self: {ot.LuaClassName})\n";
        foreach (var m in ot.Methods)
        {
            var selfParam = $"self: {ot.LuaClassName}";
            var otherParams = string.Join(", ", m.Params.Select(p =>
            {
                var name = p.IsOptional ? p.Name + "?" : p.Name;
                var type = LuaCats.LuaCatsGen.ToLuaCatsType(p.Type);
                return $"{name}: {TypeToString(type)}";
            }));
            var allParams = string.IsNullOrEmpty(otherParams)
                ? selfParam : $"{selfParam}, {otherParams}";

            var ret = m.ReturnType is BindingType.Void ? "" : $": {TypeToString(LuaCats.LuaCatsGen.ToLuaCatsType(m.ReturnType))}";
            sb += $"---@field {m.LuaName} fun({allParams}){ret}\n";
        }
        sb += "\n";

        // Module class
        var moduleFields = new List<string>();

        // init function
        var initFunc = spec.ExtraLuaFuncs[0];
        var initParams = string.Join(", ", initFunc.Params.Select(p =>
        {
            var name = p.IsOptional ? p.Name + "?" : p.Name;
            var type = LuaCats.LuaCatsGen.ToLuaCatsType(p.Type);
            return $"{name}: {TypeToString(type)}";
        }));
        var initRet = TypeToString(LuaCats.LuaCatsGen.ToLuaCatsType(initFunc.ReturnType));
        moduleFields.Add($"---@field init fun({initParams}): {initRet}");

        // Motion type constants
        moduleFields.Add("---@field STATIC integer");
        moduleFields.Add("---@field KINEMATIC integer");
        moduleFields.Add("---@field DYNAMIC integer");

        sb += LuaCats.LuaCatsGen.ModuleClass(spec.ModuleName, moduleFields);
        sb += LuaCats.LuaCatsGen.Footer(spec.ModuleName);
        return sb;
    }

    SkipReport IModule.CollectSkips(TypeRegistry reg) => new(ModuleName, [], [], []);

    private static string TypeToString(LuaCats.Type typ) => typ switch
    {
        LuaCats.Type.Primitive(var name) => name,
        LuaCats.Type.Class(var fullName) => fullName,
        _ => "any"
    };
}
