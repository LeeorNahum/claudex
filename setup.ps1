param([switch] $UpdateProxy, [string] $Version)
$ErrorActionPreference = 'Stop'
& "$PSScriptRoot\build.ps1" -Version $Version
$install = Join-Path $env:USERPROFILE '.local\share\claudex'
$bin = Join-Path $env:USERPROFILE '.local\bin'
New-Item -ItemType Directory -Force -Path $install, $bin | Out-Null
$proxy = Join-Path $install 'cli-proxy-api.exe'
if ($UpdateProxy -or !(Test-Path -LiteralPath $proxy)) {
    $release = Invoke-RestMethod 'https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest'
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'aarch64' } else { 'amd64' }
    $asset = @($release.assets | Where-Object name -Like "*_windows_$arch.zip")
    if ($asset.Count -ne 1) { throw 'No matching CLIProxyAPI release asset.' }
    $scratch = Join-Path $install ('.update-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $scratch | Out-Null
    try {
        $archive = Join-Path $scratch 'proxy.zip'
        Invoke-WebRequest $asset[0].browser_download_url -OutFile $archive -UseBasicParsing
        Invoke-WebRequest ($release.assets | Where-Object name -EQ 'checksums.txt').browser_download_url -UseBasicParsing -OutFile "$scratch\checksums.txt"
        $checksums = [IO.File]::ReadAllText("$scratch\checksums.txt")
        $expected = @($checksums -split "`n" | Where-Object { $_ -match ([regex]::Escape($asset[0].name) + '\s*$') })
        if ($expected.Count -ne 1 -or ($expected[0] -split '\s+')[0] -ine (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash) { throw 'CLIProxyAPI checksum verification failed.' }
        Expand-Archive -LiteralPath $archive -DestinationPath "$scratch\extracted"
        $newProxy = Join-Path $scratch 'extracted\cli-proxy-api.exe'
        if (!(Test-Path -LiteralPath $newProxy)) { throw 'Proxy executable is missing from the verified archive.' }
        Get-CimInstance Win32_Process -Filter "name='cli-proxy-api.exe'" | Where-Object { $_.ExecutablePath -ieq $proxy } | ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction Stop }
        if (Test-Path -LiteralPath $proxy) { Copy-Item -LiteralPath $proxy -Destination "$proxy.backup-$([guid]::NewGuid().ToString('N'))" }
        Copy-Item -LiteralPath $newProxy -Destination $proxy -Force
        Write-Output "Installed CLIProxyAPI $($release.tag_name), SHA256 verified."
    }
    finally {
        $resolved = [IO.Path]::GetFullPath($scratch)
        if (!$resolved.StartsWith([IO.Path]::GetFullPath($install) + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected update directory.' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
$tokenPath = Join-Path $install 'claudex-token.txt'
if (!(Test-Path -LiteralPath $tokenPath)) {
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    [IO.File]::WriteAllText($tokenPath, (-join ($bytes | ForEach-Object { $_.ToString('x2') })))
}
$configPath = Join-Path $install 'config.yaml'
if (!(Test-Path -LiteralPath $configPath)) {
    $token = [IO.File]::ReadAllText($tokenPath).Trim()
    [IO.File]::WriteAllText($configPath, "host: `"127.0.0.1`"`nport: 8317`nauth-dir: 'auth'`napi-keys:`n  - `"$token`"`ndebug: false`n")
}
$config = [IO.File]::ReadAllText($configPath)
$original = $config
if ($config -notmatch '(?m)^request-retry:') { $config += "`nrequest-retry: 3`n" }
if ($config -notmatch '(?m)^logging-to-file:') { $config += "`nlogging-to-file: true`n" }
if ($config -notmatch '(?m)^oauth-excluded-models:') {
    $config += "`noauth-excluded-models:`n  codex:`n    - 'gpt-5.3*'`n    - 'gpt-5.4*'`n    - 'gpt-5.5*'`n    - 'gpt-image*'`n    - 'codex-auto-review'`n"
}
if ($config -notmatch '(?m)^oauth-model-alias:') {
    $config += "`noauth-model-alias:`n  codex:`n    - name: 'gpt-5.6-luna'`n      alias: 'background-summaries'`n      fork: true`n"
}
if ($config -ne $original) {
    Copy-Item -LiteralPath $configPath -Destination "$configPath.backup-$([guid]::NewGuid().ToString('N'))"
    [IO.File]::WriteAllText($configPath, $config)
}
foreach ($directory in $install, $bin) {
    Copy-Item -LiteralPath "$PSScriptRoot\dist\claudex.exe", "$PSScriptRoot\claudex.cmd" -Destination $directory -Force
}
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\claudex.exe'
New-Item -Path $key -Force | Out-Null
Set-Item -LiteralPath $key -Value "$bin\claudex.exe"
$paths = @([Environment]::GetEnvironmentVariable('Path', 'User') -split ';' | Where-Object { $_.Trim() })
if (!($paths | Where-Object { $_.Trim().Trim('"').TrimEnd('\') -ieq $bin })) { [Environment]::SetEnvironmentVariable('Path', (($paths + $bin) -join ';'), 'User') }
Write-Output "Installed claudex in $install. Default model: gpt-6-astra."
Write-Output 'Run claudex from Explorer, cmd, or PowerShell. Existing tokens and provider logins are preserved.'
Write-Output "For a new installation, run: & '$proxy' -codex-login"
