# AVD Image Builder Script (no-reboot)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Ensure working folder & transcript
$avdPath = "C:\AVDImage"
if (-not (Test-Path $avdPath)) { New-Item -ItemType Directory -Path $avdPath | Out-Null }
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $avdPath "imagebuilder_$timestamp.log"
Start-Transcript -Path $logFile -Append

function Download-AVDScript {
    param([Parameter(Mandatory)][string]$Uri,[Parameter(Mandatory)][string]$Destination)
    Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing
}
function Run-AVDScript {
    param([Parameter(Mandatory)][string]$Command)
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $Command
}

function Enable-Intune {
    $key = 'SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo\*'
    $keyinfo = Get-Item "HKLM:\$key" -ErrorAction SilentlyContinue
    if ($null -ne $keyinfo) {
        $url = ($keyinfo.Name.Split('\')[-1])
        $path = "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo\$url"
        New-ItemProperty -LiteralPath $path -Name 'MdmEnrollmentUrl' -Value 'https://enrollment.manage.microsoft.com/enrollmentserver/discovery.svc' -PropertyType String -Force -ea SilentlyContinue
        New-ItemProperty -LiteralPath $path -Name 'MdmTermsOfUseUrl' -Value 'https://portal.manage.microsoft.com/TermsofUse.aspx' -PropertyType String -Force -ea SilentlyContinue
        New-ItemProperty -LiteralPath $path -Name 'MdmComplianceUrl' -Value 'https://portal.manage.microsoft.com/?portalAction=Compliance' -PropertyType String -Force -ea SilentlyContinue
    }
    $k = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM"
    if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
    Set-ItemProperty -Path $k -Name AutoEnrollMDM -Type DWord -Value 1
    Set-ItemProperty -Path $k -Name UseAADDeviceCredentials -Type DWord -Value 1
    Set-ItemProperty -Path $k -Name UseDeviceCredentials -Type DWord -Value 1
    $triggers = @()
    $triggers += New-ScheduledTaskTrigger -At (Get-Date) -Once -RepetitionInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName "TriggerEnrollment" -Trigger $triggers -User "SYSTEM" `
        -Action (New-ScheduledTaskAction -Execute "$env:windir\system32\deviceenroller.exe" -Argument "/c /AutoEnrollMDMUsingAADDeviceCredential") -Force | Out-Null
}

function Set-Defender-Excludes {
    try {
        $filelist = @(
            "$env:ProgramFiles\FSLogix\Apps\frxdrv.sys",
            "$env:ProgramFiles\FSLogix\Apps\frxdrvvt.sys",
            "$env:ProgramFiles\FSLogix\Apps\frxccd.sys",
            "$env:TEMP\*.VHD",
            "$env:TEMP\*.VHDX",
            "$env:WINDIR\TEMP\*.VHD",
            "$env:WINDIR\TEMP\*.VHDX"
        )
        $processlist = @(
            "$env:ProgramFiles\FSLogix\Apps\frxccd.exe",
            "$env:ProgramFiles\FSLogix\Apps\frxccds.exe",
            "$env:ProgramFiles\FSLogix\Apps\frxsvc.exe"
        )
        foreach($p in $filelist){ Add-MpPreference -ExclusionPath $p }
        foreach($p in $processlist){ Add-MpPreference -ExclusionProcess $p }
        Add-MpPreference -ExclusionPath "$env:ProgramData\FSLogix\Cache\*.VHD"
        Add-MpPreference -ExclusionPath "$env:ProgramData\FSLogix\Cache\*.VHDX"
        Add-MpPreference -ExclusionPath "$env:ProgramData\FSLogix\Proxy\*.VHD"
        Add-MpPreference -ExclusionPath "$env:ProgramData\FSLogix\Proxy\*.VHDX"
    } catch {
        Write-Warning "Failed to add Defender exclusions: $($_.Exception.Message)"
    }
}

function Sysprep-Fix {
    try {
        ((Get-Content -path C:\DeprovisioningScript.ps1 -Raw) -replace 'Sysprep.exe /oobe /generalize /quiet /quit','Sysprep.exe /oobe /generalize /quit /mode:vm') |
            Set-Content -Path C:\DeprovisioningScript.ps1
    } catch {
        Write-Warning "Sysprep fix failed: $($_.Exception.Message)"
    }
}

function Cleanup-DownloadedScripts {
    param([string[]]$Files)
    foreach ($f in $Files) {
        try { if (Test-Path $f) { Remove-Item -Path $f -Force -ErrorAction Stop } } catch { }
    }
}

# --- Sequence (no reboot, no PSWindowsUpdate) ---
$DownloadedHelpers = @(
    Join-Path $avdPath "installLanguagePacks.ps1",
    Join-Path $avdPath "setDefaultLanguage.ps1",
    Join-Path $avdPath "multiMediaRedirection.ps1",
    Join-Path $avdPath "windowsOptimization.ps1",
    Join-Path $avdPath "removeAppxPackages.ps1"
)

try {
    # Language packs
    Download-AVDScript -Uri "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/InstallLanguagePacks.ps1" -Destination "$avdPath\installLanguagePacks.ps1"
    Run-AVDScript "C:\AVDImage\installLanguagePacks.ps1 -LanguageList 'Dutch (Netherlands)'"

    # Default language
    Download-AVDScript -Uri "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/SetDefaultLang.ps1" -Destination "$avdPath\setDefaultLanguage.ps1"
    Run-AVDScript "C:\AVDImage\setDefaultLanguage.ps1 -Language 'Dutch (Netherlands)'"

    # Timezone redirection / Storage Sense / RDP Shortpath (download then run)
    Download-AVDScript -Uri "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/TimezoneRedirection.ps1" -Destination "$avdPath\TimezoneRedirection.ps1"
    Run-AVDScript "C:\AVDImage\TimezoneRedirection.ps1"

    Download-AVDScript -Uri "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/DisableStorageSense.ps1" -Destination "$avdPath\DisableStorageSense.ps1"
    Run-AVDScript "C:\AVDImage\DisableStorageSense.ps1"

    Download-AVDScript -Uri "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/RDPShortpath.ps1" -Destination "$avdPath\RDPShortpath.ps1"
    Run-AVDScript "C:\AVDImage\RDPShortpath.ps1"

    # Multimedia redirection
    Download-AVDScript -Uri "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/MultiMediaRedirection.ps1" -Destination "$avdPath\multiMediaRedirection.ps1"
    Run-AVDScript "C:\AVDImage\multiMediaRedirection.ps1 -VCRedistributableLink 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -EnableEdge 'true' -EnableChrome 'true'"

    # Windows Optimization
    Download-AVDScript -Uri "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/WindowsOptimization.ps1" -Destination "$avdPath\windowsOptimization.ps1"
    Run-AVDScript "C:\AVDImage\windowsOptimization.ps1 -Optimizations 'WindowsMediaPlayer','ScheduledTasks','DefaultUserSettings','Autologgers','Services','NetworkOptimizations','LGPO','DiskCleanup','Edge','RemoveLegacyIE','RemoveOneDrive'"

    # Remove Appx
    Download-AVDScript -Uri "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/RemoveAppxPackages.ps1" -Destination "$avdPath\removeAppxPackages.ps1"
    Run-AVDScript "C:\AVDImage\removeAppxPackages.ps1 -AppxPackages 'Microsoft.XboxApp','Microsoft.ZuneVideo','Microsoft.ZuneMusic','Microsoft.YourPhone','Microsoft.XboxSpeechToTextOverlay','Microsoft.XboxIdentityProvider','Microsoft.XboxGamingOverlay','Microsoft.XboxGameOverlay','Microsoft.Xbox.TCUI','Microsoft.WindowsTerminal','Microsoft.WindowsSoundRecorder','Microsoft.WindowsMaps','Microsoft.WindowsFeedbackHub','Microsoft.windowscommunicationsapps','Microsoft.WindowsCamera','Microsoft.WindowsCalculator','Microsoft.WindowsAlarms','Microsoft.Windows.Photos','Microsoft.Todos','Microsoft.SkypeApp','Microsoft.ScreenSketch','Microsoft.PowerAutomateDesktop','Microsoft.People','Microsoft.MSPaint','Microsoft.MicrosoftStickyNotes','Microsoft.MicrosoftSolitaireCollection','Microsoft.Office.OneNote','Microsoft.MicrosoftOfficeHub','Microsoft.Getstarted','Microsoft.GamingApp','Microsoft.BingWeather','Microsoft.GetHelp','Microsoft.BingNews','Clipchamp.Clipchamp'"

    # Defender & Intune
    Set-Defender-Excludes
    Enable-Intune

} finally {
    Sysprep-Fix
    Cleanup-DownloadedScripts -Files $DownloadedHelpers
    Stop-Transcript
    Write-Host "Transcript saved to $logFile"
}
