Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (& git rev-parse --show-toplevel).Trim()
if (-not $repoRoot) {
	throw "Unable to detect git repository root."
}

Push-Location $repoRoot
try {
	& git config core.hooksPath .githooks
	Write-Output "Configured git hooks path: .githooks"
	Write-Output "Hooks are now active for this repository."
} finally {
	Pop-Location
}
