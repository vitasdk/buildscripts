# Windows-on-Windows bootstrap smoke test: the host triple, on-disk layout
# and vdpm frontend knowledge live here so build-sdk.yml stays generic.
param(
	[Parameter(Mandatory = $true)]
	[string]$ArtifactsDir
)

$ErrorActionPreference = 'Stop'
$windowsHost = 'x86_64-w64-mingw32'

$archives = @()
if (Test-Path $ArtifactsDir) {
	$archives = @(Get-ChildItem $ArtifactsDir -Recurse -File -Filter "vitasdk-bootstrap-$windowsHost.tar.bz2")
}
if ($archives.Count -eq 0) {
	Write-Host "no $windowsHost bootstrap artifact found under $ArtifactsDir; nothing to smoke test"
	exit 0
}
if ($archives.Count -gt 1) {
	throw "expected exactly one $windowsHost bootstrap archive, found $($archives.Count)"
}
$archive = $archives[0].FullName
$checksumFile = "$archive.sha256"
if (-not (Test-Path $checksumFile)) {
	throw "missing checksum sidecar: $checksumFile"
}
$checksum = Get-Content $checksumFile
$digest = ($checksum -split '\s+')[0]

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$componentsFile = Join-Path $repoRoot 'cmake/Components.cmake'
$vdpmTagMatch = Select-String -Path $componentsFile -Pattern '^set\(VDPM_TAG\s+([^\s)]+)' | Select-Object -First 1
if (-not $vdpmTagMatch) {
	throw "could not determine VDPM_TAG from $componentsFile"
}
$vdpmTag = $vdpmTagMatch.Matches[0].Groups[1].Value

$tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
$vdpmCheckout = Join-Path $tempRoot "vdpm-bootstrap-$([guid]::NewGuid())"
git clone --depth=1 --branch $vdpmTag https://github.com/vitasdk/vdpm.git $vdpmCheckout
if ($LASTEXITCODE -ne 0) { throw 'failed to check out the vdpm frontend' }

$installRoot = Join-Path $tempRoot "vitasdk-bootstrap-installed-$([guid]::NewGuid())"
& (Join-Path $vdpmCheckout 'bootstrap-vitasdk.ps1') `
	-ArchivePath $archive -Sha256 $digest -InstallDirectory $installRoot
if ($LASTEXITCODE -ne 0) { throw 'bootstrap-vitasdk.ps1 failed' }

& (Join-Path $installRoot 'bin/vdpm.exe') --help | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'vdpm self-test failed' }

& (Join-Path $installRoot 'share/vdpm/msys/usr/bin/pacman.exe') --version | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'pacman self-test failed' }

& (Join-Path $installRoot 'bin/arm-vita-eabi-gcc.exe') --version
if ($LASTEXITCODE -ne 0) { throw 'compiler self-test failed' }

Write-Host "Windows bootstrap smoke test passed for $windowsHost"
