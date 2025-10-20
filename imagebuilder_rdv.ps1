<#
.SYNOPSIS
  AVD Image Builder Script (imagebuilder_rdv.ps1)

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

function Enable-Intune {
Write-Host "Enable Intune setting"
$key = 'SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo\*'
$keyinfo = Get-Item "HKLM:\$key"
$url = $keyinfo.name
$url = $url.Split("\")[-1]
$path = "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo\\$url"

New-ItemProperty -LiteralPath $path -Name 'MdmEnrollmentUrl' -Value 'https://enrollment.manage.microsoft.com/enrollmentserver/discovery.svc' -PropertyType String -Force -ea SilentlyContinue;
New-ItemProperty -LiteralPath $path  -Name 'MdmTermsOfUseUrl' -Value 'https://portal.manage.microsoft.com/TermsofUse.aspx' -PropertyType String -Force -ea SilentlyContinue;
New-ItemProperty -LiteralPath $path -Name 'MdmComplianceUrl' -Value 'https://portal.manage.microsoft.com/?portalAction=Compliance' -PropertyType String -Force -ea SilentlyContinue;
Start-Sleep 5

# Make sure the MDM keys are set for device-based enrollment
$k = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM"
if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
Set-ItemProperty -Path $k -Name AutoEnrollMDM -Type DWord -Value 1
Set-ItemProperty -Path $k -Name UseAADDeviceCredentials -Type DWord -Value 1
Set-ItemProperty -Path $k -Name UseDeviceCredentials -Type DWord -Value 1

# Add ScheduledTaskTrigger
$triggers = @()
$triggers += New-ScheduledTaskTrigger -At (get-date) -Once -RepetitionInterval (New-TimeSpan -Minutes 1)
$User = "SYSTEM"
$Action = New-ScheduledTaskAction -Execute "%windir%\system32\deviceenroller.exe" -Argument "/c /AutoEnrollMDMUsingAADDeviceCredential"
$Null = Register-ScheduledTask -TaskName "TriggerEnrollment" -Trigger $triggers -User $User -Action $Action -Force

}

function Set-Defender-Excludes {
try {
     $filelist = `
  "%ProgramFiles%\FSLogix\Apps\frxdrv.sys", `
  "%ProgramFiles%\FSLogix\Apps\frxdrvvt.sys", `
  "%ProgramFiles%\FSLogix\Apps\frxccd.sys", `
  "%TEMP%\*.VHD", `
  "%TEMP%\*.VHDX", `
  "%Windir%\TEMP\*.VHD", `
  "%Windir%\TEMP\*.VHDX" `

    $processlist = `
    "%ProgramFiles%\FSLogix\Apps\frxccd.exe", `
    "%ProgramFiles%\FSLogix\Apps\frxccds.exe", `
    "%ProgramFiles%\FSLogix\Apps\frxsvc.exe"

    Foreach($item in $filelist){
        Add-MpPreference -ExclusionPath $item}
    Foreach($item in $processlist){
        Add-MpPreference -ExclusionProcess $item}


    Add-MpPreference -ExclusionPath "%ProgramData%\FSLogix\Cache\*.VHD"
    Add-MpPreference -ExclusionPath "%ProgramData%\FSLogix\Cache\*.VHDX"
    Add-MpPreference -ExclusionPath "%ProgramData%\FSLogix\Proxy\*.VHD"
    Add-MpPreference -ExclusionPath "%ProgramData%\FSLogix\Proxy\*.VHDX"
}
catch {
     Write-Host "AVD AIB Customization - Install FSLogix : Exception occurred while adding exclusions for Microsoft Defender"
     Write-Host $PSItem.Exception
}

Write-Host "Finished adding exclusions for Microsoft Defender"

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
    Join-Path $avdPath "removeAppxPackages.ps1",
    
    
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
    
    # Defender Excludes
    Set-Defender-Excludes
    
    # Set Intune settings
    Enable-Intune
    
    # Run-WindowsUpdate ## Disabled updates
    Run-WindowsRestart -Timeout "5m"
}
finally {
    
    # Cleanup downloaded helper scripts (logged in transcript)
    Cleanup-DownloadedScripts -Files $DownloadedHelpers
    # Execute sysprep 
    Write-host "Execute Systprep, sealing image"
    Run-AVDScript "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/AdminSysPrep.ps1' | Invoke-Expression"
    Stop-Transcript
    Write-Host "Transcript saved to $logFile"
}
