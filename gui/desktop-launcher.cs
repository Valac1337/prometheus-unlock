// SPDX-License-Identifier: GPL-2.0-only
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("Prometheus Unlock")]
[assembly: AssemblyDescription("Windows launcher for the experimental Prometheus Unlock workflow")]
[assembly: AssemblyVersion("0.2.0.0")]
[assembly: AssemblyFileVersion("0.2.0.0")]
internal static class DesktopLauncher {
    [STAThread]
    private static int Main(string[] args) {
        bool check = args.Length == 1 && args[0] == "--check";
        bool smoke = args.Length == 1 && args[0] == "--smoke-test";
        try {
            if (args.Length != 0 && !check && !smoke)
                throw new ArgumentException("Supported options: --check, --smoke-test");
            string root = AppDomain.CurrentDomain.BaseDirectory;
            foreach (string relative in new[] {"Install.ps1", "Launch.ps1", "gui/app.py", "gui/desktop.ps1", "SOURCE-FILES.json"})
                if (!File.Exists(Path.Combine(root, relative)))
                    throw new IOException("Extract the complete Windows ZIP first. Keep the EXE beside Install.ps1 and the gui folder. Missing: " + relative);
            if (check) return 0;
            string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32/WindowsPowerShell/v1.0/powershell.exe");
#if SETUP
            string mode = "Setup";
#else
            string mode = "Launch";
#endif
            if (smoke) mode = "SmokeTest";
            var start = new ProcessStartInfo(powershell);
            start.WorkingDirectory = root;
            start.UseShellExecute = false;
            start.CreateNoWindow = mode != "Setup";
            start.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + Path.Combine(root, "gui/desktop.ps1") + "\" -Mode " + mode;
            using (Process process = Process.Start(start)) {
                process.WaitForExit();
                if (process.ExitCode != 0 && !smoke)
                    MessageBox.Show("The operation stopped (exit " + process.ExitCode + "). Run Setup.exe and review INSTALL.md. No successful unlock is implied by opening the application.", "Prometheus Unlock", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return process.ExitCode;
            }
        } catch (Exception error) {
            if (!check && !smoke)
                MessageBox.Show(error.Message, "Prometheus Unlock", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
