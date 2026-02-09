namespace Generator;

/// <summary>
/// ModuleSpec → ModuleSpec の変換層
/// モジュール固有のドメイン概念を、CBindingGen が消費する生成指示に展開する
/// </summary>
public static class SpecTransform
{
    /// <summary>
    /// IsHandleType を ExtraMetamethods に展開する
    /// </summary>
    public static ModuleSpec ExpandHandleTypes(ModuleSpec spec)
    {
        return spec with
        {
            Structs = spec.Structs.Select(s => s.IsHandleType
                ? s with
                {
                    ExtraMetamethods =
                    [
                        new MetamethodSpec("__eq", "memcmp_eq"),
                        new MetamethodSpec("__tostring", "hex_tostring"),
                    ]
                }
                : s).ToList()
        };
    }
}
