[CmdletBinding()]
param(
    [string]$NdkRoot = $env:ANDROID_NDK_HOME,
    [string]$WorkDir = (Join-Path $env:TEMP 'persian-transcriber-whisper-v1.8.2'),
    [string]$OutputDir = (Join-Path $PSScriptRoot '..\android\app\src\main\jniLibs'),
    [string]$Cmake = 'cmake',
    [string]$Ninja = 'ninja',
    [string[]]$Abis = @('arm64-v8a', 'armeabi-v7a'),
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'

$PinnedTag = 'v1.8.2'
$PinnedCommit = '4979e04f5dcaccb36057e059bbaed8a2f5288315'
$Repository = 'https://github.com/ggml-org/whisper.cpp.git'
$AndroidApi = 24
$RequiredSymbols = @(
    'whisper_context_default_params',
    'whisper_init_from_file_with_params',
    'whisper_free',
    'whisper_full_default_params',
    'whisper_full',
    'whisper_full_n_segments',
    'whisper_full_get_segment_text',
    'whisper_full_get_segment_t0',
    'whisper_full_get_segment_t1'
)

function Resolve-Tool {
    param([string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw "Required tool '$Name' was not found on PATH."
    }
    return $command.Source
}

if ([string]::IsNullOrWhiteSpace($NdkRoot)) {
    throw 'Set ANDROID_NDK_HOME or pass -NdkRoot to an installed Android NDK (r26+ recommended).'
}
$NdkRoot = [System.IO.Path]::GetFullPath($NdkRoot)
$toolchain = Join-Path $NdkRoot 'build\cmake\android.toolchain.cmake'
if (-not (Test-Path -LiteralPath $toolchain -PathType Leaf)) {
    throw "Android NDK CMake toolchain not found: $toolchain"
}

$cmakePath = Resolve-Tool $Cmake
$ninjaPath = Resolve-Tool $Ninja
$gitPath = Resolve-Tool 'git'

$hostTag = 'windows-x86_64'
$clang = Join-Path $NdkRoot "toolchains\llvm\prebuilt\$hostTag\bin\clang.exe"
$readelf = Join-Path $NdkRoot "toolchains\llvm\prebuilt\$hostTag\bin\llvm-readelf.exe"
$nm = Join-Path $NdkRoot "toolchains\llvm\prebuilt\$hostTag\bin\llvm-nm.exe"
foreach ($tool in @($clang, $readelf, $nm)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "NDK host tool not found: $tool"
    }
}

if ($Clean -and (Test-Path -LiteralPath $WorkDir)) {
    Remove-Item -LiteralPath $WorkDir -Recurse -Force
}

if (-not (Test-Path -LiteralPath (Join-Path $WorkDir '.git'))) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $WorkDir) | Out-Null
    & $gitPath clone --depth 1 --branch $PinnedTag $Repository $WorkDir
    if ($LASTEXITCODE -ne 0) { throw 'git clone failed.' }
} else {
    & $gitPath -C $WorkDir fetch --depth 1 origin "tag" $PinnedTag
    if ($LASTEXITCODE -ne 0) { throw 'git fetch failed.' }
    & $gitPath -C $WorkDir checkout --detach $PinnedTag
    if ($LASTEXITCODE -ne 0) { throw 'git checkout failed.' }
}

$head = (& $gitPath -C $WorkDir rev-parse HEAD).Trim()
if ($head -ne $PinnedCommit) {
    throw "whisper.cpp HEAD is $head, expected pinned commit $PinnedCommit."
}

$probe = Join-Path $PSScriptRoot 'abi\whisper_layout_probe.c'
$includeDir = Join-Path $WorkDir 'include'
$artifacts = @()

foreach ($abi in $Abis) {
    if ($abi -notin @('arm64-v8a', 'armeabi-v7a')) {
        throw "Unsupported ABI '$abi'. This pipeline pins arm64-v8a and armeabi-v7a."
    }
    $buildDir = Join-Path $WorkDir "build-$abi"
    if ($Clean -and (Test-Path -LiteralPath $buildDir)) {
        Remove-Item -LiteralPath $buildDir -Recurse -Force
    }

    Write-Host "Configuring whisper.cpp $PinnedTag for $abi"
    & $cmakePath -S $WorkDir -B $buildDir -G Ninja `
        "-DCMAKE_TOOLCHAIN_FILE=$toolchain" `
        "-DANDROID_ABI=$abi" `
        "-DANDROID_PLATFORM=android-$AndroidApi" `
        '-DCMAKE_BUILD_TYPE=Release' `
        '-DBUILD_SHARED_LIBS=ON' `
        '-DWHISPER_BUILD_TESTS=OFF' `
        '-DWHISPER_BUILD_EXAMPLES=OFF' `
        '-DWHISPER_BUILD_SERVER=OFF' `
        '-DGGML_NATIVE=OFF' `
        '-DGGML_OPENMP=OFF' `
        "-DCMAKE_MAKE_PROGRAM=$ninjaPath"
    if ($LASTEXITCODE -ne 0) { throw "CMake configure failed for $abi." }

    & $cmakePath --build $buildDir --target whisper --config Release
    if ($LASTEXITCODE -ne 0) { throw "CMake build failed for $abi." }

    $library = Get-ChildItem -LiteralPath $buildDir -Recurse -Filter 'libwhisper.so' -File |
        Select-Object -First 1
    if ($null -eq $library) {
        throw "libwhisper.so was not produced for $abi."
    }

    $target = if ($abi -eq 'arm64-v8a') { 'aarch64-linux-android' } else { 'armv7a-linux-androideabi' }
    $probeObject = Join-Path $buildDir 'whisper_layout_probe.o'
    & $clang "--target=$target$AndroidApi" -fPIC -I $includeDir -c $probe -o $probeObject
    if ($LASTEXITCODE -ne 0) {
        throw "whisper_full_params ABI probe failed for $abi (headers do not match the pinned layout)."
    }

    $machine = (& $readelf -h $library.FullName | Select-String -Pattern 'Machine:' | Select-Object -First 1).Line
    $expectedMachine = if ($abi -eq 'arm64-v8a') { 'AArch64' } else { 'ARM' }
    if ($machine -notmatch $expectedMachine) {
        throw "Unexpected ELF machine for $abi`: $machine"
    }

    $exports = & $nm -D --defined-only $library.FullName
    foreach ($symbol in $RequiredSymbols) {
        if (-not ($exports -match "\b$([regex]::Escape($symbol))\b")) {
            throw "libwhisper.so for $abi does not export $symbol."
        }
    }

    $abiOutput = Join-Path $OutputDir $abi
    New-Item -ItemType Directory -Force -Path $abiOutput | Out-Null
    $destination = Join-Path $abiOutput 'libwhisper.so'
    Copy-Item -LiteralPath $library.FullName -Destination $destination -Force

    $length = (Get-Item -LiteralPath $destination).Length
    $sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Host "Built $abi`: $length bytes, sha256=$sha256"
    $artifacts += [ordered]@{
        abi        = $abi
        fileName   = 'libwhisper.so'
        byteLength = [long]$length
        sha256     = $sha256
    }
}

$metadata = [ordered]@{
    schemaVersion = 1
    whisperCpp    = [ordered]@{
        tag     = $PinnedTag
        commit  = $PinnedCommit
        license = 'MIT'
    }
    artifacts     = @($artifacts)
}
$metadataPath = Join-Path $OutputDir 'whisper-artifacts.json'
$metadata | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $metadataPath -Encoding utf8
Write-Host "Wrote $metadataPath"
