<#
.SYNOPSIS
  AVD Image Builder Script (imagebuilder.ps1)

#>

# Ensure working folder exists
$avdPath = "C:\AVDImage"
if (-not (Test-Path $avdPath)) {
    New-Item -ItemType Directory -Path $avdPath | Out-Null
}

# Setup transcript logging
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile   = Join-Path $avdPath "imagebuilder_$timestamp.log"
Start-Transcript -Path $logFile -Append

function Download-AVDScript {
    param (
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Destination
    )
    Write-Host "Downloading $Uri to $Destination"
    Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing
}

function Run-AVDScript {
    param (
        [Parameter(Mandatory)][string]$Command
    )
    Write-Host "Running: $Command"
    Invoke-Expression $Command
}

function Run-WindowsUpdate {
    Write-Host "Installing Windows Updates..."
    try {
        Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot -ErrorAction Stop
    } catch {
        Write-Warning "Windows Update module not available. Please ensure PSWindowsUpdate is installed."
    }
}

function Run-WindowsRestart {
    param (
        [string]$Timeout = "1m"
    )
    Write-Host "Restarting Windows in $Timeout..."
    Start-Sleep -Seconds ([System.Management.Automation.LanguagePrimitives]::ConvertTo($Timeout,[timespan])).TotalSeconds
    Restart-Computer -Force
}

function Cleanup-DownloadedScripts {
    param (
        [string[]]$Files
    )
    Write-Host "Starting cleanup of downloaded helper scripts..."
    $selfPath = $null
    try { $selfPath = (Resolve-Path -ErrorAction SilentlyContinue $PSCommandPath).Path } catch {}

    foreach ($f in $Files) {
        try {
            if (Test-Path $f) {
                $resolved = (Resolve-Path $f).Path
                if ($selfPath -and ($resolved -ieq $selfPath)) {
                    Write-Host "Skipping self script: $resolved"
                    continue
                }
                Write-Host "Removing $resolved"
                Remove-Item -Path $resolved -Force -ErrorAction Stop
            } else {
                Write-Host "Not found (skip): $f"
            }
        } catch {
            Write-Warning "Failed to remove '$f': $($_.Exception.Message)"
        }
    }
    Write-Host "Cleanup complete."
}

# Track the helper scripts we download so we can remove them later
$DownloadedHelpers = @(
    Join-Path $avdPath "installLanguagePacks.ps1",
    Join-Path $avdPath "setDefaultLanguage.ps1",
    Join-Path $avdPath "multiMediaRedirection.ps1",
    Join-Path $avdPath "windowsOptimization.ps1",
    Join-Path $avdPath "removeAppxPackages.ps1"
)

# --- Sequence starts here ---
try {
    # Install Language Packs
    Download-AVDScript -Uri "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/InstallLanguagePacks.ps1" -Destination "$avdPath\installLanguagePacks.ps1"
    Run-AVDScript "C:\AVDImage\installLanguagePacks.ps1 -LanguageList 'Dutch (Netherlands)'"
    Run-WindowsRestart -Timeout "10m"

    # Set Default Language
    Download-AVDScript -Uri "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/SetDefaultLang.ps1" -Destination "$avdPath\setDefaultLanguage.ps1"
    Run-AVDScript "C:\AVDImage\setDefaultLanguage.ps1 -Language 'Dutch (Netherlands)'"

    # TimeZone Redirection
    Run-AVDScript "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/TimezoneRedirection.ps1' | Invoke-Expression"

    # Disable Storage Sense
    Run-AVDScript "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/DisableStorageSense.ps1' | Invoke-Expression"

    # Configure RDP Shortpath
    Run-AVDScript "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/RDPShortpath.ps1' | Invoke-Expression"

    # MultiMedia Redirection
    Download-AVDScript -Uri "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/MultiMediaRedirection.ps1" -Destination "$avdPath\multiMediaRedirection.ps1"
    Run-AVDScript "C:\AVDImage\multiMediaRedirection.ps1 -VCRedistributableLink 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -EnableEdge 'true' -EnableChrome 'true'"

    # Windows Optimization
    Download-AVDScript -Uri "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/WindowsOptimization.ps1" -Destination "$avdPath\windowsOptimization.ps1"
    Run-AVDScript "C:\AVDImage\windowsOptimization.ps1 -Optimizations 'WindowsMediaPlayer','ScheduledTasks','DefaultUserSettings','Autologgers','Services','NetworkOptimizations','LGPO','DiskCleanup','Edge','RemoveLegacyIE','RemoveOneDrive'"


    # Remove Appx Packages
    Download-AVDScript -Uri "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/RemoveAppxPackages.ps1" -Destination "$avdPath\removeAppxPackages.ps1"
    Run-AVDScript "C:\AVDImage\removeAppxPackages.ps1 -AppxPackages 'Microsoft.XboxApp','Microsoft.ZuneVideo','Microsoft.ZuneMusic','Microsoft.YourPhone','Microsoft.XboxSpeechToTextOverlay','Microsoft.XboxIdentityProvider','Microsoft.XboxGamingOverlay','Microsoft.XboxGameOverlay','Microsoft.Xbox.TCUI','Microsoft.WindowsTerminal','Microsoft.WindowsSoundRecorder','Microsoft.WindowsMaps','Microsoft.WindowsFeedbackHub','Microsoft.windowscommunicationsapps','Microsoft.WindowsCamera','Microsoft.WindowsCalculator','Microsoft.WindowsAlarms','Microsoft.Windows.Photos','Microsoft.Todos','Microsoft.SkypeApp','Microsoft.ScreenSketch','Microsoft.PowerAutomateDesktop','Microsoft.People','Microsoft.MSPaint','Microsoft.MicrosoftStickyNotes','Microsoft.MicrosoftSolitaireCollection','Microsoft.Office.OneNote','Microsoft.MicrosoftOfficeHub','Microsoft.Getstarted','Microsoft.GamingApp','Microsoft.BingWeather','Microsoft.GetHelp','Microsoft.BingNews','Clipchamp.Clipchamp'"
    Run-WindowsUpdate
    Run-WindowsRestart -Timeout "5m"
}
finally {
    # Cleanup downloaded helper scripts (logged in transcript)
    Cleanup-DownloadedScripts -Files $DownloadedHelpers

    Stop-Transcript
    Write-Host "Transcript saved to $logFile"
}
