using Generator;

namespace Generator.Tests;

public class PipelineTests
{
    // ===== String Helpers =====

    [Theory]
    [InlineData("sapp_desc", "Desc")]
    [InlineData("sapp_event_type", "EventType")]
    [InlineData("width", "Width")]
    [InlineData("", "")]
    public void ToPascalCase_ConvertsCorrectly(string input, string expected)
    {
        var result = Pipeline.ToPascalCase(Pipeline.StripPrefix(input, "sapp_"));
        Assert.Equal(expected, result);
    }

    [Theory]
    [InlineData("sapp_desc", "sapp_", "desc")]
    [InlineData("sapp_event_type", "sapp_", "event_type")]
    [InlineData("other", "sapp_", "other")]
    public void StripPrefix_StripsCorrectly(string input, string prefix, string expected)
    {
        Assert.Equal(expected, Pipeline.StripPrefix(input, prefix));
    }

    // ===== ToSnakeCase =====

    [Theory]
    [InlineData("ShowDemoWindow", "show_demo_window")]
    [InlineData("GetID", "get_id")]
    [InlineData("Begin", "begin")]
    [InlineData("End", "end")]
    [InlineData("BeginChild", "begin_child")]
    [InlineData("SetCursorPos", "set_cursor_pos")]
    [InlineData("World_Step", "world_step")]
    [InlineData("Body_GetPosition", "body_get_position")]
    [InlineData("CreateWorld", "create_world")]
    [InlineData("", "")]
    public void ToSnakeCase_ConvertsCorrectly(string input, string expected)
    {
        Assert.Equal(expected, Pipeline.ToSnakeCase(input));
    }

    // ===== EnumItemName =====

    [Theory]
    [InlineData("SAPP_EVENTTYPE_INVALID", "sapp_event_type", "sapp_", "INVALID")]
    [InlineData("SAPP_EVENTTYPE_KEY_DOWN", "sapp_event_type", "sapp_", "KEY_DOWN")]
    public void EnumItemName_StripsPrefix(string itemName, string enumName, string prefix, string expected)
    {
        Assert.Equal(expected, Pipeline.EnumItemName(itemName, enumName, prefix));
    }
}
