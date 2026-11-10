[CmdletBinding()]
param(
    [string]$NdkRoot = $env:ANDROID_NDK_HOME,
    [string]$ArtifactsDir = (Join-Path $PSScriptRoot '..\android\app\src\main\jniLibs')
)

$ErrorActionPreference = 'Stop'

$metadataPath = Join-Path $ArtifactsDir 'whisper-artifacts.json'
if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
    throw "Artifact metadata not found: $metadataPath. Run build_whisper_android.ps1 first."
}

$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
if ($metadata.whisperCpp.tag -ne 'v1.8.2' -or
    $metadata.whisperCpp.commit -ne '4979e04f5dcaccb36057e059bbaed8a2f5288315') {
    throw 'Artifact metadata is not pinned to whisper.cpp v1.8.2.'
}

$readelf = $null
if (-not [string]::IsNullOrWhiteSpace($NdkRoot)) {
    $readelf = Join-Path $NdkRoot 'toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe'
    if (-not (Test-Path -LiteralPath $readelf -PathType Leaf)) {
        throw "llvm-readelf not found under NDK: $readelf"
    }
}

foreach ($artifact in $metadata.artifacts) {
    $path = Join-Path (Join-Path $ArtifactsDir $artifact.abi) $artifact.fileName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing artifact: $path"
    }
    $length = (Get-Item -LiteralPath $path).Length
    if ($length -ne [long]$artifact.byteLength) {
        throw "Size mismatch for $path`: expected $($artifact.byteLength), found $length."
    }
    $sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($sha256 -ne $artifact.sha256.ToLowerInvariant()) {
        throw "SHA-256 mismatch for $path`: expected $($artifact.sha256), found $sha256."
    }
    if ($readelf) {
        $expected = if ($artifact.abi -eq 'arm64-v8a') { 'AArch64' } else { 'ARM' }
        $machine = (& $readelf -h $path | Select-String -Pattern 'Machine:' | Select-Object -First 1).Line
        if ($machine -notmatch $expected) {
            throw "Unexpected ELF machine for $path`: $machine"
        }
    }
    Write-Host "Verified $($artifact.abi): $length bytes, sha256=$sha256"
}

Write-Host 'All whisper.cpp Android artifacts match the pinned metadata.'
