using System;
using System.Collections.Generic;
using System.IO;
using System.Web.Script.Serialization;
internal static class Probe
{
    private static int Main(string[] args)
    {
        var env = new Dictionary<string, string>();
        foreach (string key in new string[] { "CLAUDE_CODE_SUBAGENT_MODEL", "CLAUDE_CODE_MAX_CONTEXT_TOKENS", "CLAUDE_CODE_AUTO_COMPACT_WINDOW", "ANTHROPIC_BASE_URL", "ANTHROPIC_DEFAULT_HAIKU_MODEL" }) env[key] = Environment.GetEnvironmentVariable(key);
        var result = new { cwd = Directory.GetCurrentDirectory(), argv = args, env = env, credentialsCleared = Environment.GetEnvironmentVariable("ANTHROPIC_API_KEY") == null && Environment.GetEnvironmentVariable("OPENAI_API_KEY") == null && Environment.GetEnvironmentVariable("CLAUDE_CODE_OAUTH_TOKEN") == null };
        File.WriteAllText(Environment.GetEnvironmentVariable("CLAUDEX_CAPTURE"), new JavaScriptSerializer().Serialize(result));
        return 37;
    }
}
