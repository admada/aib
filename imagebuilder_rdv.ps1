<#
.SYNOPSIS
  AVD Image Builder Script (imagebuilder_rdv.ps1)
  Converts the provided JSON config into sequential PowerShell tasks.
#>

# Ensure working folder exists
$avdPath = "C:\AVDImage"
if (-not (Test-Path $avdPath)) {
    New-Item -ItemType Directory -Path $avdPath | Out-Null
}

function Download-AVDScript {
    param (
        [string]$Uri,
        [string]$Destination
    )
    Write-Host "Downloading $Uri to $Destination"
    Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing
}

function Run-AVDScript {
    param (
        [string]$Command
    )
    Write-Host "Running: $Command"
    Invoke-Expression $Command
}

function Run-WindowsUpdate {
    Write-Host "Installing Windows Updates..."
    Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot
}

function Run-WindowsRestart {
    param (
        [string]$Timeout = "1m"
    )
    Write-Host "Restarting Windows in $Timeout..."
    Start-Sleep -Seconds ([System.Management.Automation.LanguagePrimitives]::ConvertTo($Timeout,[timespan])).TotalSeconds
    Restart-Computer -Force
}

# --- Sequence starts here ---

# Install Language Packs
Download-AVDScript -Uri "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/InstallLanguagePacks.ps1" -Destination "$avdPath\installLanguagePacks.ps1"
Run-AVDScript "C:\AVDImage\installLanguagePacks.ps1 -LanguageList 'Dutch (Netherlands)'"
Run-WindowsUpdate
Run-WindowsRestart -Timeout "10m"

# Set Default Language
Download-AVDScript -Uri "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/SetDefaultLang.ps1" -Destination "$avdPath\setDefaultLanguage.ps1"
Run-AVDScript "C:\AVDImage\setDefaultLanguage.ps1 -Language 'Dutch (Netherlands)'"
Run-WindowsUpdate
Run-WindowsRestart -Timeout "5m"

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
Run-WindowsUpdate
Run-WindowsRestart

# Remove Appx Packages
Download-AVDScript -Uri "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/RemoveAppxPackages.ps1" -Destination "$avdPath\removeAppxPackages.ps1"
Run-AVDScript "C:\AVDImage\removeAppxPackages.ps1 -AppxPackages 'Microsoft.XboxApp','Microsoft.ZuneVideo','Microsoft.ZuneMusic','Microsoft.YourPhone','Microsoft.XboxSpeechToTextOverlay','Microsoft.XboxIdentityProvider','Microsoft.XboxGamingOverlay','Microsoft.XboxGameOverlay','Microsoft.Xbox.TCUI','Microsoft.WindowsTerminal','Microsoft.WindowsSoundRecorder','Microsoft.WindowsMaps','Microsoft.WindowsFeedbackHub','Microsoft.windowscommunicationsapps','Microsoft.WindowsCamera','Microsoft.WindowsCalculator','Microsoft.WindowsAlarms','Microsoft.Windows.Photos','Microsoft.Todos','Microsoft.SkypeApp','Microsoft.ScreenSketch','Microsoft.PowerAutomateDesktop','Microsoft.People','Microsoft.MSPaint','Microsoft.MicrosoftStickyNotes','Microsoft.MicrosoftSolitaireCollection','Microsoft.Office.OneNote','Microsoft.MicrosoftOfficeHub','Microsoft.Getstarted','Microsoft.GamingApp','Microsoft.BingWeather','Microsoft.GetHelp','Microsoft.BingNews','Clipchamp.Clipchamp'"
Run-WindowsUpdate
Run-WindowsRestart
