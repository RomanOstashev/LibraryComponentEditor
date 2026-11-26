using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Security.Cryptography;
using System.Windows.Forms;
using LibraryComponentEditor.Setup;
using Microsoft.Win32;

internal static class Program
{
    private const string Plugin = "LibraryComponentEditor";
    private const string SdkUrl = "https://dl.rengabim.com/SDK/RengaSDK.zip";

    [STAThread]
    private static int Main(string[] args)
    {
        bool interactive = args.Length == 0;
        try
        {
            string location;
            if (interactive)
            {
                using (var dialog = new FolderBrowserDialog())
                {
                    dialog.Description = "Выберите папку установки Renga, в которой находится Renga.exe.";
                    dialog.ShowNewFolderButton = false;
                    using (var key = Registry.LocalMachine.OpenSubKey(
                        @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{AD5DA106-F1CF-453A-9E44-510164E2F932}"))
                        dialog.SelectedPath = key?.GetValue("InstallLocation") as string ?? "";
                    if (dialog.ShowDialog() != DialogResult.OK)
                        return 0;
                    location = dialog.SelectedPath;
                }
            }
            else if (args.Length == 2 && args[0] == "--install")
                location = args[1];
            else
                throw new ArgumentException("Usage: Setup.exe --install \"Renga installation directory\"");

            Install(location);
            if (interactive)
                MessageBox.Show("Плагин установлен. Запустите Renga и откройте проект.", Plugin);
            return 0;
        }
        catch (Exception error)
        {
            if (interactive)
                MessageBox.Show(error.Message, Plugin, MessageBoxButtons.OK, MessageBoxIcon.Error);
            else
                Console.Error.WriteLine(error);
            return 1;
        }
    }

    private static void Install(string location)
    {
        if (!File.Exists(Path.Combine(location, "Renga.exe")))
            throw new DirectoryNotFoundException("В выбранной папке отсутствует Renga.exe.");
        if (Process.GetProcessesByName("Renga").Length != 0)
            throw new InvalidOperationException("Закройте все окна Renga и запустите установку повторно.");

        var plugins = Path.Combine(location, "Plugins");
        var target = Path.Combine(plugins, Plugin);
        var staging = Path.Combine(plugins, Guid.NewGuid().ToString("N"));
        var backup = Path.Combine(plugins, Guid.NewGuid().ToString("N"));
        var scratch = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(scratch);
        try
        {
            try { Directory.CreateDirectory(staging); }
            catch (UnauthorizedAccessException error)
            {
                throw new InvalidOperationException(
                    "Нет доступа к папке Plugins. Если у вас есть права администратора, запустите Setup.exe от имени администратора.", error);
            }

            var zip = Path.Combine(scratch, "RengaSDK.zip");
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
            using (var client = new WebClient())
                client.DownloadFile(SdkUrl, zip);
            var tlb = Path.Combine(scratch, "RengaCOMAPI.tlb");
            using (var archive = ZipFile.OpenRead(zip))
            {
                Extract(archive, "tlb/RengaCOMAPI.tlb", tlb,
                    "0d458a600bd1543917f9c6f3618d23c1283972bf634c293bfca5f8cd39884897");
                Extract(archive, "Net/Renga.NET.PluginUtility.dll",
                    Path.Combine(staging, "Renga.NET.PluginUtility.dll"),
                    "a9d6b126f468648b5c6fa8351775380086e05f432c44259f550a72ff773f4279");
            }
            InteropImporter.Import(tlb, scratch);
            foreach (var file in Directory.GetFiles(scratch, "Interop.*.dll"))
                File.Copy(file, Path.Combine(staging, Path.GetFileName(file)));
            foreach (var name in new[] { Plugin + ".dll", Plugin + ".rndesc", "Renga.WPF.Styles.dll",
                "LICENSE", "Renga.WPF.Styles.LICENSE.txt" })
                File.Copy(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, name), Path.Combine(staging, name));

            if (Directory.Exists(target))
                Directory.Move(target, backup);
            try { Directory.Move(staging, target); }
            catch
            {
                if (Directory.Exists(backup))
                    Directory.Move(backup, target);
                throw;
            }
            Clean(backup);
        }
        finally
        {
            Clean(staging);
            Clean(scratch);
        }
    }

    private static void Clean(string directory)
    {
        if (!Directory.Exists(directory))
            return;
        try { Directory.Delete(directory, true); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private static void Extract(ZipArchive archive, string entry, string path, string expected)
    {
        var file = archive.GetEntry(entry) ?? throw new InvalidDataException("В архиве Renga SDK отсутствует " + entry);
        file.ExtractToFile(path);
        using (var hash = SHA256.Create())
        using (var input = File.OpenRead(path))
        {
            var actual = string.Concat(hash.ComputeHash(input).Select(b => b.ToString("x2")));
            if (actual != expected)
                throw new InvalidDataException("Версия файла Renga SDK не совпадает с версией для Renga 9.4.34553: " + entry);
        }
    }
}
