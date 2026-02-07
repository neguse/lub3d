using System.Diagnostics;

namespace Generator.ClangAst;

/// <summary>
/// deps submodule の GitHub リンクを構築する
/// </summary>
public class SourceLink
{
    private readonly string? _fileUrl;

    private SourceLink(string? fileUrl)
    {
        _fileUrl = fileUrl;
    }

    /// <summary>
    /// deps 配下の submodule から SourceLink を構築する。
    /// headerRelativePath は deps dir からの相対パス (e.g. "sokol/sokol_app.h")
    /// </summary>
    public static SourceLink FromHeader(string depsDir, string headerRelativePath)
    {
        // headerRelativePath = "sokol/sokol_app.h" → submodule = "sokol"
        var parts = headerRelativePath.Replace('\\', '/').Split('/');
        var submoduleName = parts[0];
        var submoduleDir = Path.Combine(depsDir, submoduleName);

        var remoteUrl = RunGit(submoduleDir, "remote", "get-url", "origin");
        var commitHash = RunGit(submoduleDir, "rev-parse", "HEAD");

        if (remoteUrl == null || commitHash == null)
            return new SourceLink(null);

        // https://github.com/floooh/sokol.git → https://github.com/floooh/sokol
        var baseUrl = remoteUrl.TrimEnd('/');
        if (baseUrl.EndsWith(".git"))
            baseUrl = baseUrl[..^4];

        // submodule からのヘッダ相対パス (e.g. "sokol_app.h" or "util/sokol_gl.h")
        var headerInSubmodule = string.Join('/', parts[1..]);

        return new SourceLink($"{baseUrl}/blob/{commitHash}/{headerInSubmodule}");
    }

    /// <summary>
    /// 行番号から GitHub リンクを生成する
    /// </summary>
    public string? GetLink(int line)
    {
        return _fileUrl != null ? $"{_fileUrl}#L{line}" : null;
    }

    private static string? RunGit(string workingDir, params string[] args)
    {
        if (!Directory.Exists(workingDir)) return null;

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "git",
                WorkingDirectory = workingDir,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            foreach (var arg in args)
                psi.ArgumentList.Add(arg);

            using var proc = Process.Start(psi);
            if (proc == null) return null;
            var output = proc.StandardOutput.ReadToEnd().Trim();
            proc.WaitForExit();
            return proc.ExitCode == 0 ? output : null;
        }
        catch
        {
            return null;
        }
    }
}
