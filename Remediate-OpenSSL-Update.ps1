<#
.SYNOPSIS
    Intune Remediation Script for OpenSSL DLL Update.
    Downloads a ZIP file from a Git repository, extracts assets, and replaces vulnerable DLLs.
    
    OUTPUT: Returns a SINGLE LINE text string summarizing the results (Total, Success, Failed).
    LOGGING: Detailed log saved to C:\Temp\OpenSSL_Update_Log.txt
    CONTEXT: Must be run as SYSTEM (Administrator).

.NOTES
    IMPORTANT: You must update $BaseUrl to point to your raw Git repository location.
#>

# ==========================================
# CONFIGURATION
# ==========================================
$BaseUrl = "https://raw.githubusercontent.com/kadirsu76/openssl-remediation/main"
$CsvName = "export-tvm-recommendation-related-exposed-paths.csv"
$CryptoName = "libcrypto-3-x64.dll"
$SslName = "libssl-3-x64.dll"
$Crypto3Name = "libcrypto-3.dll"
$Ssl3Name = "libssl-3.dll"
$CryptoZmName = "libcrypto-3-zm.dll"
$SslZmName = "libssl-3-zm.dll" 

$RegistryPath = "HKLM:\SOFTWARE\OpenSSLRemediation"
$TempDir = "$env:TEMP\OpenSSLRemediation"
$LogDir = "C:\Temp"
$LogFile = "$LogDir\OpenSSL_Update_Log.txt"

# ==========================================
# SETUP LOGGING
# ==========================================
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
Start-Transcript -Path $LogFile -Append -IncludeInvocationHeader

Write-Host "[INFO] Script Started: $(Get-Date)"
Write-Host "[INFO] Running as user: $env:USERNAME"

# ==========================================
# HELPER FUNCTIONS
# ==========================================
function Download-File {
    param([string]$Url, [string]$Dest)
    try {
        Write-Host "[INFO] Downloading $Url to $Dest..."
        Invoke-WebRequest -Uri $Url -OutFile $Dest -ErrorAction Stop
        return $true
    }
    catch {
        Write-Error "[ERROR] Failed to download $Url. Error: $_"
        return $false
    }
}

# ==========================================
# EXECUTION
# ==========================================

# 1. Prepare Temp Directory
Write-Host "[INFO] Cleaning/Creating Temp Directory: $TempDir"
if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -Path $TempDir -ItemType Directory -Force | Out-Null

# 2. Download Assets
$CsvPath = "$TempDir\$CsvName"
$CryptoPath = "$TempDir\$CryptoName"
$SslPath = "$TempDir\$SslName"
$Crypto3Path = "$TempDir\$Crypto3Name"
$Ssl3Path = "$TempDir\$Ssl3Name"
$CryptoZmPath = "$TempDir\$CryptoZmName"
$SslZmPath = "$TempDir\$SslZmName"

$downloadErrors = 0

if (-not (Download-File -Url "$BaseUrl/$CsvName" -Dest $CsvPath)) { $downloadErrors++ }
if (-not (Download-File -Url "$BaseUrl/$CryptoName" -Dest $CryptoPath)) { $downloadErrors++ }
if (-not (Download-File -Url "$BaseUrl/$SslName" -Dest $SslPath)) { $downloadErrors++ }
if (-not (Download-File -Url "$BaseUrl/$Crypto3Name" -Dest $Crypto3Path)) { $downloadErrors++ }
if (-not (Download-File -Url "$BaseUrl/$Ssl3Name" -Dest $Ssl3Path)) { $downloadErrors++ }
if (-not (Download-File -Url "$BaseUrl/$CryptoZmName" -Dest $CryptoZmPath)) { $downloadErrors++ }
if (-not (Download-File -Url "$BaseUrl/$SslZmName" -Dest $SslZmPath)) { $downloadErrors++ }

if ($downloadErrors -gt 0) {
    Write-Output "CRITICAL ERROR: Failed to download one or more assets. Check Log: $LogFile"
    Stop-Transcript
    exit 1
}

# 3. Verify Files exist (Redundant check but good for safety)
if (-not (Test-Path $CsvPath) -or -not (Test-Path $CryptoPath) -or -not (Test-Path $SslPath) -or -not (Test-Path $Crypto3Path) -or -not (Test-Path $Ssl3Path) -or -not (Test-Path $CryptoZmPath) -or -not (Test-Path $SslZmPath)) {
    Write-Output "CRITICAL ERROR: Missing files in Temp. Check Log: $LogFile"
    Stop-Transcript
    exit 1
}

# Map to variables expected by processing logic
$CsvFile = Get-Item $CsvPath
$CryptoFile = Get-Item $CryptoPath
$SslFile = Get-Item $SslPath
$Crypto3File = Get-Item $Crypto3Path
$Ssl3File = Get-Item $Ssl3Path
$CryptoZmFile = Get-Item $CryptoZmPath
$SslZmFile = Get-Item $SslZmPath

# 4. Process Replacements
try {
    Write-Host "[INFO] Reading CSV: $($CsvFile.FullName)"
    $csvData = Get-Content -Path $CsvFile.FullName | Select-Object -Skip 1 | ConvertFrom-Csv
}
catch {
    Write-Output "CRITICAL ERROR: Failed to read CSV. Check Log."
    Stop-Transcript
    exit 1
}

$countForUpdate = 0
$countSuccess = 0
$countFailed = 0
$failedPaths = @()

foreach ($row in $csvData) {
    if (-not $row.Path) { continue }

    $targetPath = $row.Path.Trim()
    $fileName = Split-Path $targetPath -Leaf

    # Only process target DLLs
    $validFiles = @("libcrypto-3-x64.dll", "libssl-3-x64.dll", "libcrypto-3.dll", "libssl-3.dll", "libcrypto-3-zm.dll", "libssl-3-zm.dll")
    if ($validFiles -notcontains $fileName) { continue }

    # If file doesn't exist, skip
    if (-not (Test-Path $targetPath)) { continue }

    $countForUpdate++
    
    # Determine Source
    $replacementSource = $null
    switch ($fileName) {
        "libcrypto-3-x64.dll" { $replacementSource = $CryptoFile.FullName }
        "libssl-3-x64.dll" { $replacementSource = $SslFile.FullName }
        "libcrypto-3.dll" { $replacementSource = $Crypto3File.FullName }
        "libssl-3.dll" { $replacementSource = $Ssl3File.FullName }
        "libcrypto-3-zm.dll" { $replacementSource = $CryptoZmFile.FullName }
        "libssl-3-zm.dll" { $replacementSource = $SslZmFile.FullName }
    }

    Write-Host "[INFO] Updating: $targetPath"
    
    # Perform Replacement
    try {
        # Method 1: Direct Copy
        Copy-Item -Path $replacementSource -Destination $targetPath -Force -ErrorAction Stop
        $countSuccess++
        Write-Host "   -> SUCCESS" -ForegroundColor Green
    }
    catch {
        # Method 2: Rename and Copy (Locked files)
        try {
            Write-Host "   -> LOCKED. Attempting rename..." -NoNewline
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $backupPath = "$targetPath.$timestamp.old"
            Rename-Item -Path $targetPath -NewName $backupPath -Force -ErrorAction Stop
            Copy-Item -Path $replacementSource -Destination $targetPath -Force -ErrorAction Stop
            $countSuccess++
            Write-Host " SUCCESS (Renamed)" -ForegroundColor Green
        }
        catch {
            $countFailed++
            $failedPaths += $targetPath
            Write-Host " FAILED. Error: $_" -ForegroundColor Red
        }
    }
}

# 5. Finalize & Summary Output
# Write registry key
if (-not (Test-Path $RegistryPath)) { New-Item -Path "HKLM:\SOFTWARE" -Name "OpenSSLRemediation" -Force | Out-Null }
New-ItemProperty -Path $RegistryPath -Name "LastRun" -Value (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") -PropertyType String -Force | Out-Null

Write-Host "[INFO] Cleaning up Temp Directory..."
Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue

# Prepare Output Message
$finalOutput = ""
if ($countFailed -gt 0) {
    $failMsg = "FAILED: $countFailed (Paths: " + ($failedPaths -join ", ") + ")"
    $finalOutput = "TOTAL: $countForUpdate | SUCCESS: $countSuccess | $failMsg"
}
else {
    $finalOutput = "COMPLIANT | TOTAL: $countForUpdate | ALL SUCCESSFUL"
}

# Log to Transcript
Write-Host "[RESULT] $finalOutput"

Write-Host "[INFO] Process Completed."
Stop-Transcript

# SINGLE LINE OUTPUT to Intune (Standard Output)
Write-Output $finalOutput

exit 0
