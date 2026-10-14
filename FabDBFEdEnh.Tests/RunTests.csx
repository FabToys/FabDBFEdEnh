// Runs the FabDBFEdEnh unit tests with vstest.console.exe (found through vswhere, no PATH needed).
//
//   csi.exe FabDBFEdEnh.Tests\RunTests.csx [path-to-FabDBFEdEnh.Tests.dll] [pause]
//   "pause" waits for a key at the end, so a console window opened by an IDE stays readable.
//
// Without an argument the most recently built FabDBFEdEnh.Tests.dll is tested
// (XIde: Bin\Debug, Visual Studio: FabDBFEdEnh.Tests\bin\Debug).
// csi.exe is part of Visual Studio: ...\MSBuild\Current\Bin\Roslyn\csi.exe
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;

static string ThisFile([System.Runtime.CompilerServices.CallerFilePath] string path = "") { return path; }

static string FindVstest()
{
    var x86 = Environment.GetEnvironmentVariable("ProgramFiles(x86)");
    if (!string.IsNullOrEmpty(x86))
    {
        var vswhere = Path.Combine(x86, "Microsoft Visual Studio", "Installer", "vswhere.exe");
        if (File.Exists(vswhere))
        {
            var psi = new ProcessStartInfo(vswhere, "-latest -products * -find **\\vstest.console.exe")
            {
                UseShellExecute = false,
                RedirectStandardOutput = true,
                CreateNoWindow = true
            };
            using (var p = Process.Start(psi))
            {
                var found = p.StandardOutput.ReadToEnd()
                    .Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                    .FirstOrDefault(File.Exists);
                p.WaitForExit();
                if (found != null) return found;
            }
        }
    }
    // PATH
    var path = Environment.GetEnvironmentVariable("PATH") ?? "";
    foreach (var dir in path.Split(';'))
    {
        try
        {
            var candidate = Path.Combine(dir.Trim(), "vstest.console.exe");
            if (File.Exists(candidate)) return candidate;
        }
        catch { }
    }
    return null;
}

var here = Path.GetDirectoryName(ThisFile());          // ...\FabDBFEdEnh.Tests
var repo = Path.GetDirectoryName(here);                // repository root

bool pause = Args.Any(a => string.Equals(a, "pause", StringComparison.OrdinalIgnoreCase));
string dll = Args.FirstOrDefault(a => !string.Equals(a, "pause", StringComparison.OrdinalIgnoreCase));
if (dll == null)
{
    dll = new[]
        {
            Path.Combine(repo, "Bin", "Debug", "FabDBFEdEnh.Tests.dll"),
            Path.Combine(here, "bin", "Debug", "FabDBFEdEnh.Tests.dll")
        }
        .Where(File.Exists)
        .OrderByDescending(File.GetLastWriteTime)
        .FirstOrDefault();
}
if (dll == null || !File.Exists(dll))
{
    Console.Error.WriteLine("FabDBFEdEnh.Tests.dll not found. Build the test project first.");
    Environment.Exit(2);
}
dll = Path.GetFullPath(dll);

var vstest = FindVstest();
if (vstest == null)
{
    Console.Error.WriteLine("vstest.console.exe not found. It is part of Visual Studio (test tools) or the Build Tools.");
    Environment.Exit(2);
}

Console.WriteLine("Tests : " + dll);
Console.WriteLine("Runner: " + vstest);

var run = new ProcessStartInfo(vstest, "\"" + dll + "\" --TestAdapterPath:\"" + Path.GetDirectoryName(dll) + "\"")
{
    UseShellExecute = false
};
int code;
using (var p = Process.Start(run))
{
    p.WaitForExit();
    code = p.ExitCode;
}
Console.WriteLine(code == 0 ? "ALL TESTS PASSED" : "TESTS FAILED (exit code " + code + ")");
if (pause)
{
    Console.WriteLine("Press any key to close...");
    Console.ReadKey(true);
}
Environment.Exit(code);
