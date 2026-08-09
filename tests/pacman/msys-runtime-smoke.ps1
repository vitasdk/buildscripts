param(
    [string]$WorkDirectory = (Join-Path $env:TEMP "vitasdk-msys-pacman-smoke")
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$pacmanUrl = "https://mirror.msys2.org/msys/x86_64/pacman-6.1.0-25-x86_64.pkg.tar.zst"
$pacmanSha256 = "cb375279a44b37f646dbe834b440c233fddbacb97d6173e5c7d91362717c970f"
$runtimeUrl = "https://mirror.msys2.org/msys/x86_64/msys2-runtime-3.6.10-1-x86_64.pkg.tar.zst"
$runtimeSha256 = "0b68543d295aa52e6c16ede2d7d6113eff9bf8fa4876f140eb624b0cf33e0253"

function Get-MixedPath([string]$Path) {
    return $Path.Replace("\", "/")
}

function Assert-Sha256([string]$Path, [string]$Expected) {
    $actual = (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
    if ($actual -ne $Expected) {
        throw "SHA-256 mismatch for ${Path}: expected ${Expected}, got ${actual}"
    }
}

function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "${Program} exited with status ${LASTEXITCODE}"
    }
}

if (Test-Path $WorkDirectory) {
    Remove-Item -Recurse -Force $WorkDirectory
}

$downloads = Join-Path $WorkDirectory "downloads"
$extract = Join-Path $WorkDirectory "extract"
$sdkRoot = Join-Path $WorkDirectory "sdk"
$pacmanBin = Join-Path $sdkRoot "usr/bin"
$dbPath = Join-Path $sdkRoot "var/lib/pacman"
$cachePath = Join-Path $sdkRoot "var/cache/pacman/pkg"
$logPath = Join-Path $sdkRoot "var/log/pacman.log"
$configPath = Join-Path $sdkRoot "etc/pacman.conf"
$packageRoot = Join-Path $WorkDirectory "package"
$packagePath = Join-Path $WorkDirectory "vitasdk-msys-probe-1.0-1-any.pkg.tar.xz"

@(
    $downloads,
    $extract,
    $pacmanBin,
    $dbPath,
    $cachePath,
    (Split-Path $logPath),
    (Split-Path $configPath),
    (Join-Path $packageRoot "arm-vita-eabi/include")
) | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }

$pacmanArchive = Join-Path $downloads "pacman.pkg.tar.zst"
$runtimeArchive = Join-Path $downloads "runtime.pkg.tar.zst"
Invoke-WebRequest -Uri $pacmanUrl -OutFile $pacmanArchive
Invoke-WebRequest -Uri $runtimeUrl -OutFile $runtimeArchive
Assert-Sha256 $pacmanArchive $pacmanSha256
Assert-Sha256 $runtimeArchive $runtimeSha256

Invoke-Checked "tar.exe" @(
    "-xf", $pacmanArchive, "-C", $extract, "usr/bin/pacman.exe"
)
Invoke-Checked "tar.exe" @(
    "-xf", $runtimeArchive, "-C", $extract, "usr/bin/msys-2.0.dll"
)
Copy-Item (Join-Path $extract "usr/bin/pacman.exe") $pacmanBin
Copy-Item (Join-Path $extract "usr/bin/msys-2.0.dll") $pacmanBin

$runtimeFiles = @(Get-ChildItem -File $pacmanBin)
if ($runtimeFiles.Count -ne 2) {
    throw "minimal runtime contains unexpected files"
}

[IO.File]::WriteAllText($configPath, @"
[options]
Architecture = auto
SigLevel = Never
CheckSpace
"@)

[IO.File]::WriteAllText((Join-Path $packageRoot ".PKGINFO"), @"
pkgname = vitasdk-msys-probe
pkgbase = vitasdk-msys-probe
pkgver = 1.0-1
pkgdesc = VitaSDK MSYS runtime smoke package
builddate = 0
packager = VitaSDK CI
size = 6
arch = any
license = MIT
"@)
[IO.File]::WriteAllText(
    (Join-Path $packageRoot "arm-vita-eabi/include/msys-probe.h"),
    "probe`n"
)
Invoke-Checked "tar.exe" @(
    "-cJf", $packagePath,
    "-C", $packageRoot,
    ".PKGINFO", "arm-vita-eabi/include/msys-probe.h"
)

$pacman = Join-Path $pacmanBin "pacman.exe"
$commonArguments = @(
    "--config", (Get-MixedPath $configPath),
    "--root", "$(Get-MixedPath $sdkRoot)/",
    "--dbpath", "$(Get-MixedPath $dbPath)/",
    "--cachedir", "$(Get-MixedPath $cachePath)/",
    "--logfile", (Get-MixedPath $logPath)
)

# Exclude Git for Windows and any preinstalled MSYS2 tree from DLL lookup.
$savedPath = $env:PATH
$env:PATH = "${env:SystemRoot}\System32;${env:SystemRoot}"
try {
    Invoke-Checked $pacman @("--version")
    Invoke-Checked $pacman @(
        $commonArguments + @(
            "--upgrade", "--noscriptlet", "--noconfirm", (Get-MixedPath $packagePath)
        )
    )
    Invoke-Checked $pacman @($commonArguments + @("--query", "vitasdk-msys-probe"))

    $installedFile = Join-Path $sdkRoot "arm-vita-eabi/include/msys-probe.h"
    if (-not (Test-Path $installedFile)) {
        throw "package payload was not installed"
    }

    Invoke-Checked $pacman @(
        $commonArguments + @(
            "--remove", "--noscriptlet", "--noconfirm", "vitasdk-msys-probe"
        )
    )
    if (Test-Path $installedFile) {
        throw "package payload remains after removal"
    }
}
finally {
    $env:PATH = $savedPath
}

Write-Host "MSYS pacman two-file runtime smoke test passed"
