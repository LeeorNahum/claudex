param([string] $Version)
$ErrorActionPreference = 'Stop'
if (!$Version) {
    $Version = (& git -C $PSScriptRoot describe --tags --abbrev=0 2>$null) -replace '^v', ''
    if (!$Version) { throw 'Pass -Version MAJOR.MINOR.PATCH when building a source archive.' }
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Version must be MAJOR.MINOR.PATCH.' }
$compiler = "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (!(Test-Path -LiteralPath $compiler)) { $compiler = "$env:SystemRoot\Microsoft.NET\Framework\v4.0.30319\csc.exe" }
$dist = New-Item -ItemType Directory -Force -Path "$PSScriptRoot\dist"
[IO.File]::WriteAllText("$dist\Version.cs", "using System.Reflection; [assembly: AssemblyVersion(""$Version"")] [assembly: AssemblyFileVersion(""$Version"")] [assembly: AssemblyProduct(""claudex"")]")
& $compiler /nologo /target:exe /optimize+ /warnaserror+ /reference:System.Web.Extensions.dll "/out:$dist\claudex.exe" "$PSScriptRoot\claudex.cs" "$dist\Version.cs"
if ($LASTEXITCODE -ne 0) { throw 'Claudex build failed.' }
Write-Output "Built claudex $Version"
