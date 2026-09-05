using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

internal static class Claudex
{
    internal const string DefaultModel = "gpt-6-astra";
    private const string Endpoint = "http://127.0.0.1:8317";

    private static int Main(string[] args)
    {
        bool hold = OwnsConsole();
        int code = 1;
        try { code = Run(args); }
        catch (Exception error) { Console.Error.WriteLine("claudex: " + error.Message); }
        if (hold)
        {
            Console.WriteLine("Agent exited. Press any key to close this window.");
            try { Console.ReadKey(true); } catch (InvalidOperationException) { }
        }
        return code;
    }

    private static int Run(string[] args)
    {
        if (!string.Equals(Path.GetFileNameWithoutExtension(typeof(Claudex).Assembly.Location), "claudex", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Keep the claudex.exe filename to prevent recursion.");
        string cwd = Directory.GetCurrentDirectory();
        string raw = RawTail();
        string model = DefaultModel;
        int positional = args.Length > 0 && args[0] == "--dangerously-skip-permissions" ? 1 : 0;
        bool consume = positional < args.Length && IsModel(args[positional]);
        if (consume)
        {
            model = args[positional];
            if (IsNative(model)) throw new ArgumentException("Native Claude models belong to plain claude. Run claude --model " + model);
        }
        bool explicitModel = false;
        for (int i = 0; i < args.Length && args[i] != "--"; i++)
        {
            if (args[i] == "--model")
            {
                if (++i == args.Length || args[i].Length == 0) throw new ArgumentException("--model needs a canonical model id.");
                model = args[i];
                explicitModel = true;
            }
            else if (args[i].StartsWith("--model=", StringComparison.Ordinal))
            {
                model = args[i].Substring(8);
                if (model.Length == 0) throw new ArgumentException("--model needs a canonical model id.");
                explicitModel = true;
            }
        }
        if (IsNative(model)) throw new ArgumentException("Native Claude models belong to plain claude. Run claude --model " + model);
        if (consume) raw = RemoveToken(raw, positional);
        if (!explicitModel) raw = " --model " + Quote(model) + raw;

        string data = Path.Combine(Environment.GetEnvironmentVariable("USERPROFILE"), @".local\share\claudex");
        foreach (string file in new string[] { "cli-proxy-api.exe", "config.yaml", "claudex-token.txt" })
            if (!File.Exists(Path.Combine(data, file))) throw new FileNotFoundException("Not set up yet. Run setup.cmd first.");
        string token = File.ReadAllText(Path.Combine(data, "claudex-token.txt")).Trim();
        HashSet<string> catalog = Catalog(token);
        if (catalog == null)
        {
            // Only the proxy uses its install directory. The agent keeps the caller's cwd.
            var start = new ProcessStartInfo(Path.Combine(data, "cli-proxy-api.exe"), "-config " + Quote(Path.Combine(data, "config.yaml")));
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.WorkingDirectory = data;
            using (Process proxy = Process.Start(start)) { }
            for (int i = 0; i < 30 && catalog == null; i++) { Thread.Sleep(1000); catalog = Catalog(token); }
        }
        if (catalog == null) throw new InvalidOperationException("The local proxy did not become ready. Check the installed proxy/config and run cli-proxy-api.exe -codex-login if authentication expired.");
        string catalogId = model.EndsWith("[1m]", StringComparison.Ordinal) ? model.Substring(0, model.Length - 4) : model;
        if (!catalog.Contains(catalogId)) throw new InvalidOperationException("Model '" + model + "' is not in the live proxy catalog. Run setup.cmd -UpdateProxy and check your provider login. Available: " + string.Join(", ", catalog));

        var child = new ProcessStartInfo(ClaudePath(), raw);
        child.UseShellExecute = false;
        child.WorkingDirectory = cwd;
        foreach (string key in new string[] { "ANTHROPIC_API_KEY", "OPENAI_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_CUSTOM_MODEL_OPTION", "ANTHROPIC_CUSTOM_MODEL_OPTION_NAME", "ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION", "CLAUDE_CODE_MAX_CONTEXT_TOKENS", "CLAUDE_CODE_AUTO_COMPACT_WINDOW" }) child.EnvironmentVariables.Remove(key);
        child.EnvironmentVariables["ANTHROPIC_BASE_URL"] = Endpoint;
        child.EnvironmentVariables["ANTHROPIC_AUTH_TOKEN"] = token;
        child.EnvironmentVariables["CLAUDE_CODE_SUBAGENT_MODEL"] = model;
        child.EnvironmentVariables["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = "background-summaries";
        child.EnvironmentVariables["CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY"] = "1";
        child.EnvironmentVariables["CLAUDE_CODE_ALWAYS_ENABLE_EFFORT"] = "1";
        child.EnvironmentVariables["CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY"] = "3";
        child.EnvironmentVariables["ENABLE_TOOL_SEARCH"] = "false";
        child.EnvironmentVariables["CLAUDE_CODE_MAX_RETRIES"] = "15";
        child.EnvironmentVariables["CLAUDE_CODE_RETRY_WATCHDOG"] = "1";
        if (!catalog.Contains("k3"))
        {
            child.EnvironmentVariables["ANTHROPIC_CUSTOM_MODEL_OPTION"] = "k3";
            child.EnvironmentVariables["ANTHROPIC_CUSTOM_MODEL_OPTION_NAME"] = "Kimi K3 (not signed in)";
            child.EnvironmentVariables["ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION"] = "Run cli-proxy-api.exe -kimi-login in the claudex install directory.";
        }
        string context = model == "gpt-6-astra" ? "1050000" : model.StartsWith("gpt-5.6-", StringComparison.Ordinal) ? "372000" : model == "k3[1m]" ? "1048576" : model == "k3" || model.StartsWith("kimi-", StringComparison.Ordinal) ? "262144" : null;
        if (context != null)
        {
            child.EnvironmentVariables["CLAUDE_CODE_MAX_CONTEXT_TOKENS"] = context;
            child.EnvironmentVariables["CLAUDE_CODE_AUTO_COMPACT_WINDOW"] = context;
        }
        Console.CancelKeyPress += delegate(object sender, ConsoleCancelEventArgs e) { e.Cancel = true; };
        using (Process process = Process.Start(child)) { process.WaitForExit(); return process.ExitCode; }
    }

    private static HashSet<string> Catalog(string token)
    {
        try
        {
            var request = (HttpWebRequest)WebRequest.Create(Endpoint + "/v1/models");
            request.Proxy = null;
            request.Timeout = 1000;
            request.ReadWriteTimeout = 1000;
            request.Headers["Authorization"] = "Bearer " + token;
            using (var response = request.GetResponse())
            using (var reader = new StreamReader(response.GetResponseStream()))
            {
                var root = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(reader.ReadToEnd());
                var ids = new HashSet<string>(StringComparer.Ordinal);
                foreach (Dictionary<string, object> entry in (IEnumerable)root["data"]) ids.Add((string)entry["id"]);
                return ids;
            }
        }
        catch (WebException) { return null; }
    }

    private static bool IsNative(string value)
    {
        return value.StartsWith("claude-", StringComparison.Ordinal) || Array.IndexOf(new string[] { "sonnet", "opus", "haiku", "fable", "default", "opusplan" }, value) >= 0;
    }
    private static bool IsModel(string value)
    {
        return IsNative(value) || value.StartsWith("gpt-", StringComparison.Ordinal) || value.StartsWith("kimi-", StringComparison.Ordinal) || value == "k3" || value == "k3[1m]";
    }
    private static string ClaudePath()
    {
        foreach (string entry in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(';'))
        {
            string dir = entry.Trim().Trim('"');
            if (!(dir.StartsWith(@"\\") || (dir.Length >= 3 && char.IsLetter(dir[0]) && dir[1] == ':' && (dir[2] == '\\' || dir[2] == '/')))) continue;
            try { string file = Path.Combine(dir, "claude.exe"); if (File.Exists(file)) return file; }
            catch (ArgumentException) { }
        }
        throw new FileNotFoundException("claude.exe was not found on an absolute PATH entry. Install native Claude Code first.");
    }
    private static string RawTail()
    {
        string line = Environment.CommandLine;
        int i = 0;
        bool quoted = false;
        while (i < line.Length)
        {
            if (line[i] == '"') quoted = !quoted;
            else if (!quoted && (line[i] == ' ' || line[i] == '\t')) break;
            i++;
        }
        return line.Substring(i);
    }
    private static string RemoveToken(string raw, int index)
    {
        int i = 0;
        for (int token = 0; i < raw.Length; token++)
        {
            while (i < raw.Length && (raw[i] == ' ' || raw[i] == '\t')) i++;
            int start = i;
            bool quoted = false;
            int slashes = 0;
            while (i < raw.Length)
            {
                char c = raw[i];
                if (c == '"' && slashes % 2 == 0) quoted = !quoted;
                else if (!quoted && (c == ' ' || c == '\t')) break;
                slashes = c == '\\' ? slashes + 1 : 0;
                i++;
            }
            if (token == index) return raw.Remove(start, i - start);
        }
        throw new ArgumentException("Could not locate the positional model argument.");
    }
    private static string Quote(string value)
    {
        var result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in value)
        {
            if (c == '\\') { slashes++; continue; }
            result.Append('\\', c == '"' ? slashes * 2 + 1 : slashes);
            result.Append(c);
            slashes = 0;
        }
        return result.Append('\\', slashes * 2).Append('"').ToString();
    }
    [DllImport("kernel32.dll")] private static extern uint GetConsoleProcessList(uint[] processes, uint count);
    [DllImport("kernel32.dll")] private static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
    private static bool OwnsConsole()
    {
        try { return !Console.IsInputRedirected && GetConsoleProcessList(new uint[2], 2) == 1 && IsWindowVisible(GetConsoleWindow()); }
        catch { return false; }
    }
}
