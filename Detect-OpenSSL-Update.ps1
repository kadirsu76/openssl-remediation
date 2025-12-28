$RegistryPath = "HKLM:\SOFTWARE\OpenSSLRemediation"
# Define how often you want to force a re-run. 
# If LastRun is older than this (e.g. 12 hours), it will report "Not Detected" and run Remediation again.
$ReRunIntervalHours = 12 

try {
    # Check if we have a "LastRun" timestamp
    $regKey = Get-ItemProperty -Path $RegistryPath -ErrorAction SilentlyContinue
    
    if ($null -eq $regKey -or $null -eq $regKey.LastRun) {
        # Never ran -> Run it
        Write-Host "Not run yet. Remediation required."
        exit 1
    }

    $lastRunDate = [DateTime]$regKey.LastRun
    $timeDiff = (Get-Date) - $lastRunDate

    # If ran recently (within interval), say COMPLIANT (Exit 0)
    # This ensures Intune reports "Success" immediately after running.
    if ($timeDiff.TotalHours -lt $ReRunIntervalHours) {
        Write-Host "Compliant. Ran recently on: $($lastRunDate)"
        exit 0
    }
    else {
        # If ran long ago, say NON-COMPLIANT (Exit 1) so it runs again
        Write-Host "Old run detected ($($lastRunDate)). Re-running to enforce compliance."
        exit 1
    }
}
catch {
    Write-Host "Error during detection: $_"
    exit 1
}
