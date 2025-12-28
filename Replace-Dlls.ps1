<#
.SYNOPSIS
    Replaces outdated OpenSSL DLLs with new versions based on a CSV report.

.DESCRIPTION
    This script reads a CSV file containing paths to outdated DLLs (libcrypto-3-x64.dll and libssl-3-x64.dll).
    It iterates through the list and replaces each file with the new versions provided.
    
    IMPORTANT: Run this script as Administrator.
    
.PARAMETER CsvPath
    Path to the 'export-tvm-recommendation-related-exposed-paths.csv' file. Defaults to current directory.

.PARAMETER LibCryptoPath
    Path to the new 'libcrypto-3-x64.dll' file. Defaults to current directory.

.PARAMETER LibSslPath
    Path to the new 'libssl-3-x64.dll' file. Defaults to current directory.

.EXAMPLE
    .\Replace-Dlls.ps1
    Running without arguments assumes files are in the current directory.
#>

param(
    [string]$CsvPath = "$PSScriptRoot\export-tvm-recommendation-related-exposed-paths.csv",
    [string]$LibCryptoPath = "$PSScriptRoot\libcrypto-3-x64.dll",
    [string]$LibSslPath = "$PSScriptRoot\libssl-3-x64.dll"
)

# Ensure new DLLs exist
if (-not (Test-Path $LibCryptoPath)) {
    Write-Error "Error: New libcrypto DLL not found at $LibCryptoPath"
    exit 1
}
if (-not (Test-Path $LibSslPath)) {
    Write-Error "Error: New libssl DLL not found at $LibSslPath"
    exit 1
}

# Import CSV
# The provided CSV has metadata on line 1, headers on line 2. 
# We skip the first line (Select-Object -Skip 1) then ConvertFrom-Csv.
if (-not (Test-Path $CsvPath)) {
    Write-Error "Error: CSV file not found at $CsvPath"
    exit 1
}

Write-Host "Reading CSV from $CsvPath..." -ForegroundColor Cyan
$csvData = Get-Content -Path $CsvPath | Select-Object -Skip 1 | ConvertFrom-Csv

foreach ($row in $csvData) {
    if (-not $row.Path) { continue }

    $targetPath = $row.Path.Trim()
    $fileName = Split-Path $targetPath -Leaf

    Write-Host "Processing: $targetPath" -NoNewline
    
    # Check existence FIRST for all paths as requested
    if (-not (Test-Path $targetPath)) {
        Write-Host " [NOT FOUND]" -ForegroundColor DarkGray
        continue
    }

    # Determine which replacement file to use
    $replacementSource = $null
    if ($fileName -eq "libcrypto-3-x64.dll") {
        $replacementSource = $LibCryptoPath
    }
    elseif ($fileName -eq "libssl-3-x64.dll") {
        $replacementSource = $LibSslPath
    }
    else {
        Write-Host " [SKIPPED - NOT TARGET DLL]" -ForegroundColor Yellow
        continue
    }

    # If we are here, path exists and is a target DLL. Proceed with replacement.
    $success = $false
        
    # Method 1: Direct Force Copy
    try {
        Copy-Item -Path $replacementSource -Destination $targetPath -Force -ErrorAction Stop
        Write-Host " [SUCCESS]" -ForegroundColor Green
        $success = $true
    }
    catch {
        # Method 2: Rename and Copy (if file is locked)
        Write-Host " [LOCKED] - Attempting rename..." -NoNewline -ForegroundColor Yellow
        
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupPath = "$targetPath.$timestamp.old"
        
        try {
            # Try to rename the locked file
            Rename-Item -Path $targetPath -NewName $backupPath -Force -ErrorAction Stop
            
            # If rename worked, copy the new file in
            Copy-Item -Path $replacementSource -Destination $targetPath -Force -ErrorAction Stop
            
            Write-Host " [SUCCESS (Renamed old file)]" -ForegroundColor Green
            $success = $true
        }
        catch {
            Write-Host " [FAILED]" -ForegroundColor Red
            Write-Error "  Could not replace file even after rename attempt. Error: $_"
        }
    }
}

Write-Host "Operation completed." -ForegroundColor Cyan
