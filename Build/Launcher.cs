// WinTech Toolkit launcher.
//
// Holds the scripts in an embedded zip archive (resource "payload.zip").
// On start it tries to download the latest release from GitHub and checks it against the
// published SHA-256 file. If there is no network, the repository is not configured, the
// download cannot be verified, or /offline is passed, the embedded copy is used instead.
// The scripts are extracted to a temporary folder that is deleted when the toolkit window closes.
//
// Built by Build.ps1 with the .NET Framework 4 csc (C# 5 syntax).

using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

static class Launcher
{
    const string ProductName = "WinTech Toolkit";
    const string MainScript = "WinTechToolkit.ps1";
    const string ReleaseAsset = "WinTechToolkit.zip";
    const string TempPrefix = "WinTechToolkit_";

    [STAThread]
    static int Main(string[] args)
    {
        bool offline = false;
        foreach (string a in args)
        {
            string x = a.TrimStart('/', '-').ToLowerInvariant();
            if (x == "offline") offline = true;
        }

        RemoveStaleFolders();
        string work = Path.Combine(Path.GetTempPath(), TempPrefix + Guid.NewGuid().ToString("N").Substring(0, 10));
        try
        {
            Directory.CreateDirectory(work);
            byte[] embedded = ReadEmbeddedPayload();
            string repository = GetRepository(embedded);

            string source = "embedded";
            string note = null;
            if (!offline && repository != null && TryDownloadLatest(repository, work, out note)) source = "online (latest release)";
            else
            {
                ExtractZip(embedded, work);
                if (!offline && repository != null && note != null) source = "embedded (" + note + ")";
            }

            string script = Path.Combine(work, MainScript);
            if (!File.Exists(script)) throw new FileNotFoundException(MainScript + " not found in the package.");
            return RunPowerShell(script, source);
        }
        catch (Exception ex)
        {
            MessageBox.Show("Unable to start " + ProductName + ":\n\n" + ex.Message, ProductName, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally
        {
            DeleteFolder(work);
        }
    }

    static byte[] ReadEmbeddedPayload()
    {
        using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
        {
            if (s == null) throw new InvalidOperationException("Embedded package missing: rebuild with Build.ps1.");
            using (MemoryStream ms = new MemoryStream())
            {
                s.CopyTo(ms);
                return ms.ToArray();
            }
        }
    }

    // "Repository" in app.json, formatted as owner/name; null if not configured
    static string GetRepository(byte[] zipBytes)
    {
        try
        {
            using (ZipArchive zip = new ZipArchive(new MemoryStream(zipBytes), ZipArchiveMode.Read))
            {
                ZipArchiveEntry entry = zip.GetEntry("app.json");
                if (entry == null) return null;
                using (StreamReader r = new StreamReader(entry.Open(), Encoding.UTF8))
                {
                    Match m = Regex.Match(r.ReadToEnd(), "\"Repository\"\\s*:\\s*\"([^\"]+)\"");
                    if (!m.Success) return null;
                    string repo = m.Groups[1].Value.Trim();
                    if (repo.Length == 0 || repo.StartsWith("OWNER/", StringComparison.OrdinalIgnoreCase) || !repo.Contains("/")) return null;
                    return repo;
                }
            }
        }
        catch { return null; }
    }

    static byte[] Download(string url, int timeoutMs)
    {
        HttpWebRequest req = (HttpWebRequest)WebRequest.Create(url);
        req.UserAgent = ProductName.Replace(" ", "") + "-Launcher";
        req.Timeout = timeoutMs;
        req.ReadWriteTimeout = 15000;
        using (WebResponse resp = req.GetResponse())
        using (Stream s = resp.GetResponseStream())
        using (MemoryStream ms = new MemoryStream())
        {
            s.CopyTo(ms);
            return ms.ToArray();
        }
    }

    static bool TryDownloadLatest(string repository, string target, out string note)
    {
        note = null;
        try
        {
            // TLS 1.2 (3072): .NET 4.x on systems that are not up to date does not enable it by itself
            ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072;
            string baseUrl = "https://github.com/" + repository + "/releases/latest/download/";
            byte[] data = Download(baseUrl + ReleaseAsset, 8000);

            // The SHA-256 file published with the release must match the downloaded package
            string expected;
            try { expected = Encoding.ASCII.GetString(Download(baseUrl + ReleaseAsset + ".sha256", 8000)); }
            catch { note = "update could not be verified"; return false; }
            Match m = Regex.Match(expected, "\\b[0-9a-fA-F]{64}\\b");
            string actual;
            using (SHA256 sha = SHA256.Create()) actual = BitConverter.ToString(sha.ComputeHash(data)).Replace("-", "");
            if (!m.Success || !string.Equals(m.Value, actual, StringComparison.OrdinalIgnoreCase))
            {
                note = "update failed the integrity check";
                return false;
            }

            using (ZipArchive zip = new ZipArchive(new MemoryStream(data), ZipArchiveMode.Read))
            {
                if (zip.GetEntry(MainScript) == null) { note = "update package invalid"; return false; }
            }
            ExtractZip(data, target);
            return true;
        }
        catch
        {
            if (note == null) note = "no connection to GitHub";
            // partial package: start again from a clean folder with the embedded copy
            try { foreach (string e in Directory.GetFileSystemEntries(target)) { if (Directory.Exists(e)) Directory.Delete(e, true); else File.Delete(e); } } catch { }
            return false;
        }
    }

    static void ExtractZip(byte[] zipBytes, string target)
    {
        using (ZipArchive zip = new ZipArchive(new MemoryStream(zipBytes), ZipArchiveMode.Read))
        {
            zip.ExtractToDirectory(target);
        }
    }

    static int RunPowerShell(string script, string source)
    {
        // 64-bit PowerShell 5.1 even if the launcher runs as a 32-bit process
        string sys = Environment.Is64BitOperatingSystem && !Environment.Is64BitProcess ? "Sysnative" : "System32";
        string ps = Path.Combine(Environment.GetEnvironmentVariable("windir"), sys + @"\WindowsPowerShell\v1.0\powershell.exe");

        ProcessStartInfo psi = new ProcessStartInfo(ps, "-NoProfile -ExecutionPolicy Bypass -STA -File \"" + script + "\"");
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.System);
        psi.EnvironmentVariables["WTK_PACKAGE"] = source;
        using (Process p = Process.Start(psi))
        {
            p.WaitForExit();
            return p.ExitCode;
        }
    }

    static void DeleteFolder(string path)
    {
        for (int i = 0; i < 10 && Directory.Exists(path); i++)
        {
            try { Directory.Delete(path, true); }
            catch { Thread.Sleep(500); }
        }
    }

    // Folders left behind by interrupted sessions (PC switched off, process killed)
    static void RemoveStaleFolders()
    {
        try
        {
            foreach (string d in Directory.GetDirectories(Path.GetTempPath(), TempPrefix + "*"))
            {
                if (Directory.GetLastWriteTime(d) < DateTime.Now.AddHours(-12)) DeleteFolder(d);
            }
        }
        catch { }
    }
}
