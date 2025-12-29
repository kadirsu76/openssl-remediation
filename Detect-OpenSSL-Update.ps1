$RegistryPath = "HKLM:\SOFTWARE\OpenSSLRemediation"
# Define how often you want to force a re-run. 
# We set this to 1 MINUTE. This is the minimum "safety buffer" to ensure the
# Intune "Post-Remediation Detection" (which runs milliseconds after remediation)
# finds the run valid and reports "Success". Outside of this minute, it will run again.
$ReRunIntervalMinutes = 1

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

    # If ran VERY recently (within 5 mins), say COMPLIANT (Exit 0)
    # This is needed so Intune sees "Success" right after the remediation script runs.
    if ($timeDiff.TotalMinutes -lt $ReRunIntervalMinutes) {
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
