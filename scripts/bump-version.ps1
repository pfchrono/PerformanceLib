param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("major", "small", "auto")]
    [string]$ChangeType,

    [string]$TocPath = "PerformanceLib.toc",

    [switch]$UseStagedChanges
)

if (-not (Test-Path -LiteralPath $TocPath)) {
    Write-Error "TOC file not found: $TocPath"
    exit 1
}

$lines = Get-Content -LiteralPath $TocPath
$versionLineIndex = -1
$currentVersion = $null

for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^##\s*Version:\s*(.+)\s*$') {
        $versionLineIndex = $i
        $currentVersion = $Matches[1].Trim()
        break
    }
}

if ($versionLineIndex -lt 0) {
    Write-Error "No version line found in $TocPath"
    exit 1
}

$majorX = 0
$smallX = 0

if ($currentVersion -match '^1\.(\d+)\.(\d+)\.(\d{5,6})$') {
    $majorX = [int]$Matches[1]
    $smallX = [int]$Matches[2]
}

function Get-ChangeStats {
    param(
        [switch]$Staged
    )
    $args = @("diff")
    if ($Staged) {
        $args += "--cached"
    }
    $args += @("--numstat", "--", ".", ":(exclude)PerformanceLib.toc")

    $output = & git @args
    if ($LASTEXITCODE -ne 0) {
        return [pscustomobject]@{
            FileCount = 0
            LineCount = 0
        }
    }

    $files = 0
    $lines = 0
    foreach ($line in $output) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        $parts = $line -split "`t"
        if ($parts.Count -lt 3) {
            continue
        }
        $add = 0
        $del = 0
        if ($parts[0] -ne "-") {
            [void][int]::TryParse($parts[0], [ref]$add)
        }
        if ($parts[1] -ne "-") {
            [void][int]::TryParse($parts[1], [ref]$del)
        }
        $files++
        $lines += ($add + $del)
    }

    return [pscustomobject]@{
        FileCount = $files
        LineCount = $lines
    }
}

if ($ChangeType -eq "auto") {
    $stats = Get-ChangeStats -Staged:$UseStagedChanges
    if (($stats.FileCount -le 0) -and ($stats.LineCount -le 0)) {
        Write-Output "No changes detected (excluding TOC). Version unchanged: $currentVersion"
        exit 0
    }

    $fileThreshold = 20
    $lineThreshold = 1000
    if ($env:PERFLIB_MAJOR_FILE_THRESHOLD) {
        [void][int]::TryParse($env:PERFLIB_MAJOR_FILE_THRESHOLD, [ref]$fileThreshold)
    }
    if ($env:PERFLIB_MAJOR_LINE_THRESHOLD) {
        [void][int]::TryParse($env:PERFLIB_MAJOR_LINE_THRESHOLD, [ref]$lineThreshold)
    }

    if (($stats.FileCount -ge $fileThreshold) -or ($stats.LineCount -ge $lineThreshold)) {
        $ChangeType = "major"
    } else {
        $ChangeType = "small"
    }
}

switch ($ChangeType) {
    "major" {
        $majorX++
        $smallX = 0
    }
    "small" {
        $smallX++
    }
}

$mdyy = (Get-Date).ToString("Mddyy")
$newVersion = "1.$majorX.$smallX.$mdyy"
$lines[$versionLineIndex] = "## Version: $newVersion"
Set-Content -LiteralPath $TocPath -Value $lines -Encoding UTF8

Write-Output "Version updated ($ChangeType): $currentVersion -> $newVersion"
