namespace Generator.Modules.Sokol;

/// <summary>
/// sokol.glue モジュールの生成定義
/// </summary>
public class Glue : SokolModule
{
    public override string ModuleName => "sokol.glue";
    public override string Prefix => "sglue_";

    protected override string? ExtraCCode(ClangAst.TypeRegistry reg) => """
        #ifdef SOKOL_DUMMY_BACKEND
        sg_environment sglue_environment(void) {
            sg_environment e; memset(&e, 0, sizeof(e));
            e.defaults.color_format = SG_PIXELFORMAT_RGBA8;
            e.defaults.depth_format = SG_PIXELFORMAT_DEPTH_STENCIL;
            e.defaults.sample_count = 1;
            return e;
        }
        sg_swapchain sglue_swapchain(void) {
            sg_swapchain s; memset(&s, 0, sizeof(s));
            s.width = 640;
            s.height = 480;
            s.sample_count = 1;
            s.color_format = SG_PIXELFORMAT_RGBA8;
            s.depth_format = SG_PIXELFORMAT_DEPTH_STENCIL;
            return s;
        }
        #endif

        """;
}
