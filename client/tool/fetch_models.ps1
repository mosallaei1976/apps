[CmdletBinding()]
param(
    [string]$PinsPath = (Join-Path $PSScriptRoot 'model_pins.json'),
    [string]$ManifestPath = (Join-Path $PSScriptRoot '..\assets\models\manifest.json'),
    [string]$CacheDir = (Join-Path $env:TEMP 'persian-transcriber-models'),
    [switch]$Download,
    [switch]$WriteManifest
)

$ErrorActionPreference = 'Stop'

function Get-PinnedSourceUrl {
    param($Upstream, [string]$File)
    return "https://huggingface.co/$($Upstream.repository)/resolve/$($Upstream.revision)/$File"
}

function Assert-Artifact {
    param([string]$Path, [long]$ExpectedLength, [string]$ExpectedSha256)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing artifact: $Path. Re-run with -Download."
    }
    $actualLength = (Get-Item -LiteralPath $Path).Length
    if ($actualLength -ne $ExpectedLength) {
        throw "Size mismatch for ${Path}: expected $ExpectedLength bytes, found $actualLength."
    }
    $actualSha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSha256 -ne $ExpectedSha256.ToLowerInvariant()) {
        throw "SHA-256 mismatch for ${Path}: expected $ExpectedSha256, found $actualSha256."
    }
}

if (-not (Test-Path -LiteralPath $PinsPath -PathType Leaf)) {
    throw "Pin file not found: $PinsPath"
}

$pins = Get-Content -LiteralPath $PinsPath -Raw | ConvertFrom-Json
if ($pins.schemaVersion -ne 1) {
    throw "Unsupported pin schemaVersion: $($pins.schemaVersion)"
}
if (-not $Download -and -not $WriteManifest) {
    Write-Host 'Nothing to do. Pass -Download to fetch artifacts and/or -WriteManifest to regenerate the manifest.'
    exit 0
}

New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null

$verified = @()
foreach ($model in $pins.models) {
    $source = Get-PinnedSourceUrl -Upstream $pins.upstream -File $model.file
    $target = Join-Path $CacheDir $model.file

    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        if (-not $Download) {
            throw "Artifact is not cached: $target. Re-run with -Download."
        }
        $partial = "$target.partial"
        if (Test-Path -LiteralPath $partial) {
            Remove-Item -LiteralPath $partial -Force
        }
        Write-Host "Downloading $($model.id) from $source"
        Invoke-WebRequest -Uri $source -OutFile $partial -UseBasicParsing
        Move-Item -LiteralPath $partial -Destination $target -Force
    }

    Assert-Artifact -Path $target -ExpectedLength ([long]$model.byteLength) -ExpectedSha256 $model.sha256
    Write-Host "Verified $($model.id): $($model.byteLength) bytes, sha256=$($model.sha256)"
    $verified += $model
}

if ($WriteManifest) {
    $lines = @(
        '{',
        '  "schemaVersion": 1,',
        '  "models": ['
    )
    for ($index = 0; $index -lt $verified.Count; $index++) {
        $model = $verified[$index]
        $lines += '    {'
        $lines += "      `"id`": $($model.id | ConvertTo-Json -Compress),"
        $lines += "      `"tier`": $($model.tier | ConvertTo-Json -Compress),"
        $lines += "      `"family`": $($model.family | ConvertTo-Json -Compress),"
        $lines += "      `"quantization`": $($model.quantization | ConvertTo-Json -Compress),"
        $lines += "      `"version`": $($model.version | ConvertTo-Json -Compress),"
        $lines += "      `"byteLength`": $([long]$model.byteLength),"
        $lines += "      `"sha256`": $($model.sha256.ToLowerInvariant() | ConvertTo-Json -Compress),"
        $source = Get-PinnedSourceUrl -Upstream $pins.upstream -File $model.file
        $lines += "      `"source`": $($source | ConvertTo-Json -Compress),"
        $lines += "      `"license`": $($model.license | ConvertTo-Json -Compress),"
        $engines = ConvertTo-Json -InputObject @($model.engines) -Compress -Depth 3
        $lines += "      `"engines`": $engines"
        if ($index -lt $verified.Count - 1) {
            $lines += '    },'
        } else {
            $lines += '    }'
        }
    }
    $lines += '  ]'
    $lines += '}'
    $json = $lines -join "`n"
    $resolved = [System.IO.Path]::GetFullPath($ManifestPath)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolved) | Out-Null
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($resolved, "$json`n", $utf8NoBom)
    Write-Host "Wrote manifest: $resolved"
}
