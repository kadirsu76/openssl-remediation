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
$BaseUrl = "YOUR_GIT_RAW_URL" # e.g., https://raw.githubusercontent.com/user/repo/main\n$CsvName = "export-tvm-recommendation-related-exposed-paths.csv"\n$CryptoName = "libcrypto-3-x64.dll"\n$SslName = "libssl-3-x64.dll" 

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

# 2. Download ZIP
$ZipPath = "$TempDir\assets.zip"
if (-not (Download-File -Url $ZipUrl -Dest $ZipPath)) {
    Write-Output "CRITICAL ERROR: Failed to download ZIP file. Check Log: $LogFile"
    Stop-Transcript
    exit 1
}

# 3. Extract ZIP
try {
    Write-Host "[INFO] Extracting ZIP..."
    Expand-Archive -Path $ZipPath -DestinationPath $TempDir -Force -ErrorAction Stop
}
catch {
    Write-Output "CRITICAL ERROR: Failed to extract ZIP. Check Log: $LogFile"
    Stop-Transcript
    exit 1
}

# 4. Identify Files
# We expect these files to be inside the zip (or inside a subfolder in the zip)
# Let's find them recursively to be safe
$CsvFile = Get-ChildItem -Path $TempDir -Filter "*.csv" -Recurse | Select-Object -First 1
$CryptoFile = Get-ChildItem -Path $TempDir -Filter "libcrypto-3-x64.dll" -Recurse | Select-Object -First 1
$SslFile = Get-ChildItem -Path $TempDir -Filter "libssl-3-x64.dll" -Recurse | Select-Object -First 1

if (-not $CsvFile -or -not $CryptoFile -or -not $SslFile) {
    Write-Output "CRITICAL ERROR: Missing files in ZIP. Check Log: $LogFile"
    Write-Error "Files found in temp: $(Get-ChildItem $TempDir -Recurse | Select-Object -ExpandProperty Name)"
    Stop-Transcript
    exit 1
}

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
    if ($fileName -ne "libcrypto-3-x64.dll" -and $fileName -ne "libssl-3-x64.dll") { continue }

    # If file doesn't exist, skip
    if (-not (Test-Path $targetPath)) { continue }

    $countForUpdate++
    
    # Determine Source
    $replacementSource = if ($fileName -eq "libcrypto-3-x64.dll") { $CryptoFile.FullName } else { $SslFile.FullName }

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

Write-Host "[INFO] Process Completed."
Stop-Transcript

# SINGLE LINE OUTPUT to Intune
if ($countFailed -gt 0) {
    $failMsg = "FAILED: $countFailed (Paths: " + ($failedPaths -join ", ") + ")"
    Write-Output "TOTAL: $countForUpdate | SUCCESS: $countSuccess | $failMsg"
}
else {
    Write-Output "COMPLIANT | TOTAL: $countForUpdate | ALL SUCCESSFUL"
}

exit 0
