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

$installRoot = Join-Path $tempRoot "Vita SDK bootstrap installed $([guid]::NewGuid())"
& (Join-Path $vdpmCheckout 'bootstrap-vitasdk.ps1') `
	-ArchivePath $archive -Sha256 $digest -InstallDirectory $installRoot
if ($LASTEXITCODE -ne 0) { throw 'bootstrap-vitasdk.ps1 failed' }

& (Join-Path $installRoot 'bin/vdpm.exe') --help | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'vdpm self-test failed' }

& (Join-Path $installRoot 'share/vdpm/msys/usr/bin/pacman.exe') --version | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'pacman self-test failed' }

& (Join-Path $installRoot 'bin/arm-vita-eabi-gcc.exe') --version
if ($LASTEXITCODE -ne 0) { throw 'compiler self-test failed' }

$pkgconf = Join-Path $installRoot 'bin/pkgconf.exe'
$pkgConfig = Join-Path $installRoot 'bin/arm-vita-eabi-pkg-config.exe'
foreach ($tool in @($pkgconf, $pkgConfig)) {
	if (-not (Test-Path -PathType Leaf $tool)) {
		throw "pkg-config tool is missing: $tool"
	}
}

$probeDirectory = Join-Path $installRoot 'arm-vita-eabi/lib/pkgconfig'
New-Item -ItemType Directory -Force -Path $probeDirectory | Out-Null
$probeFile = Join-Path $probeDirectory 'vitasdk-wrapper-probe.pc'
@'
prefix=${VITASDK}/arm-vita-eabi
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: vitasdk-wrapper-probe
Description: VitaSDK pkg-config frontend smoke test
Version: 1.0
Libs: -L${libdir} -lprobe
Cflags: -I${includedir}/probe
'@ | Set-Content -NoNewline -Encoding utf8 $probeFile

$hostMetadata = Join-Path $tempRoot "host-pkgconfig-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $hostMetadata | Out-Null
@'
Name: vitasdk-wrapper-probe
Description: Host package that must not be selected
Version: 9.9
Libs: -lhost-contamination
'@ | Set-Content -NoNewline -Encoding utf8 (Join-Path $hostMetadata 'vitasdk-wrapper-probe.pc')

$env:VITASDK = Join-Path $tempRoot 'wrong sdk root'
$env:PKG_CONFIG_DIR = $hostMetadata
$env:PKG_CONFIG_PATH = $hostMetadata
$env:PKG_CONFIG_SYSROOT_DIR = $hostMetadata
$env:PKG_CONFIG_LIBDIR = $hostMetadata
$version = (& $pkgConfig --modversion vitasdk-wrapper-probe | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $version -ne '1.0') {
	throw "pkg-config frontend selected version '$version' instead of the Vita package"
}

$cmakeProject = Join-Path $tempRoot "pkgconfig-cmake-project-$([guid]::NewGuid())"
$cmakeBuild = Join-Path $tempRoot "pkgconfig-cmake-build-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $cmakeProject | Out-Null
@'
cmake_minimum_required(VERSION 3.16)
project(vitasdk_pkgconfig_probe NONE)
find_package(PkgConfig REQUIRED)
pkg_check_modules(PROBE REQUIRED IMPORTED_TARGET vitasdk-wrapper-probe)
if(NOT PROBE_VERSION STREQUAL "1.0")
    message(FATAL_ERROR "unexpected probe version: ${PROBE_VERSION}")
endif()
'@ | Set-Content -NoNewline -Encoding utf8 (Join-Path $cmakeProject 'CMakeLists.txt')
$env:VITASDK = $installRoot
& cmake -S $cmakeProject -B $cmakeBuild `
	"-DCMAKE_TOOLCHAIN_FILE=$(Join-Path $installRoot 'share/vita.toolchain.cmake')"
if ($LASTEXITCODE -ne 0) { throw 'native Windows CMake could not use the Vita pkg-config frontend' }

Write-Host "Windows bootstrap smoke test passed for $windowsHost"
