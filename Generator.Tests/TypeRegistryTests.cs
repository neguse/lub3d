using Generator.ClangAst;

namespace Generator.Tests;

public class TypeRegistryTests
{
    private const string TestJson = """
    {
      "module": "app",
      "prefix": "sapp_",
      "dep_prefixes": ["slog_"],
      "decls": [
        {
          "kind": "struct",
          "name": "sapp_desc",
          "fields": [
            { "name": "width", "type": "int" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "func",
          "name": "sapp_run",
          "type": "void (const sapp_desc *)",
          "params": [
            { "name": "desc", "type": "const sapp_desc *" }
          ],
          "is_dep": false,
          "dep_prefix": null
        },
        {
          "kind": "enum",
          "name": "sapp_event_type",
          "items": [
            { "name": "SAPP_EVENTTYPE_INVALID" }
          ],
          "is_dep": false,
          "dep_prefix": null
        }
      ]
    }
    """;

    [Fact]
    public void Load_ReturnsTypeRegistry()
    {
        var reg = TypeRegistry.FromJson(TestJson);
        Assert.NotNull(reg);
    }

    [Fact]
    public void ModuleName_ReturnsCorrectValue()
    {
        var reg = TypeRegistry.FromJson(TestJson);
        Assert.Equal("app", reg.ModuleName);
    }

    [Fact]
    public void Prefix_ReturnsCorrectValue()
    {
        var reg = TypeRegistry.FromJson(TestJson);
        Assert.Equal("sapp_", reg.Prefix);
    }

    [Fact]
    public void Indexer_ReturnsStruct()
    {
        var reg = TypeRegistry.FromJson(TestJson);
        var decl = reg["sapp_desc"];
        Assert.IsType<Structs>(decl);
        Assert.Equal("sapp_desc", ((Structs)decl).Name);
    }

    [Fact]
    public void Indexer_ReturnsFunc()
    {
        var reg = TypeRegistry.FromJson(TestJson);
        var decl = reg["sapp_run"];
        Assert.IsType<Funcs>(decl);
        Assert.Equal("sapp_run", ((Funcs)decl).Name);
    }

    [Fact]
    public void Indexer_ReturnsEnum()
    {
        var reg = TypeRegistry.FromJson(TestJson);
        var decl = reg["sapp_event_type"];
        Assert.IsType<Enums>(decl);
        Assert.Equal("sapp_event_type", ((Enums)decl).Name);
    }

    [Fact]
    public void Indexer_ThrowsForUnknownName()
    {
        var reg = TypeRegistry.FromJson(TestJson);
        Assert.Throws<KeyNotFoundException>(() => { _ = reg["unknown"]; });
    }

    [Fact]
    public void GetStruct_ReturnsStruct()
    {
        var reg = TypeRegistry.FromJson(TestJson);
        var s = reg.GetStruct("sapp_desc");
        Assert.Equal("sapp_desc", s.Name);
    }

    [Fact]
    public void GetFunc_ReturnsFunc()
    {
        var reg = TypeRegistry.FromJson(TestJson);
        var f = reg.GetFunc("sapp_run");
        Assert.Equal("sapp_run", f.Name);
    }

    [Fact]
    public void GetEnum_ReturnsEnum()
    {
        var reg = TypeRegistry.FromJson(TestJson);
        var e = reg.GetEnum("sapp_event_type");
        Assert.Equal("sapp_event_type", e.Name);
    }
}
