# AVD Image Builder customization script (no reboot, no PSWindowsUpdate dependency)
# Windows PowerShell 5.1 compatible

# ===== Strict mode & TLS =====
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ===== Paths & transcript (moved away from C:\AVDImage which MS script deletes) =====
$workPath = 'C:\AIBWork'
$logPath  = 'C:\AIBLogs'

foreach ($p in @($workPath, $logPath)) {
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null }
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logFile   = "$logPath\imagebuilder_$timestamp.log"
Start-Transcript -Path $logFile -Append

function Write-Stage {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ('-'*80)
    Write-Host "[AIB] $Message"
    Write-Host ('-'*80)
}

function Download-AVDScript {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Destination
    )
    Write-Stage "Downloading: $Uri -> $Destination"
    Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing
    if (-not (Test-Path -LiteralPath $Destination)) {
        throw "Download failed: $Destination was not created."
    }
}

function Run-AVDScript {
    param([Parameter(Mandatory)][string]$CommandLine)
    Write-Stage "Running: $CommandLine"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $CommandLine
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE : $CommandLine"
    }
}

function Enable-IntuneAutoEnroll {
    Write-Stage "Configuring Intune Auto-enrollment (MDM)"
    try {
        $mdmKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM'
        if (-not (Test-Path $mdmKey)) { New-Item -Path $mdmKey -Force | Out-Null }
        New-ItemProperty -Path $mdmKey -Name AutoEnrollMDM -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $mdmKey -Name UseAADDeviceCredentials -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $mdmKey -Name UseDeviceCredentials     -Value 1 -PropertyType DWord -Force | Out-Null

        # Kick device enroller on first boot
        $action  = New-ScheduledTaskAction -Execute "$env:windir\system32\deviceenroller.exe" -Argument "/c /AutoEnrollMDMUsingAADDeviceCredential"
        $trigger = New-ScheduledTaskTrigger -At (Get-Date).AddMinutes(1) -Once
        Register-ScheduledTask -TaskName "TriggerEnrollment" -User "SYSTEM" -Action $action -Trigger $trigger -RunLevel Highest -Force | Out-Null
    }
    catch {
        Write-Warning "MDM enrollment config failed: $($_.Exception.Message)"
    }
}

function Set-DefenderExclusions {
    Write-Stage "Adding Microsoft Defender exclusions for FSLogix"
    try {
        $paths = @(
            "$env:ProgramFiles\FSLogix\Apps\frxdrv.sys",
            "$env:ProgramFiles\FSLogix\Apps\frxdrvvt.sys",
            "$env:ProgramFiles\FSLogix\Apps\frxccd.sys",
            "$env:ProgramData\FSLogix\Cache\*.VHD",
            "$env:ProgramData\FSLogix\Cache\*.VHDX",
            "$env:ProgramData\FSLogix\Proxy\*.VHD",
            "$env:ProgramData\FSLogix\Proxy\*.VHDX",
            "$env:TEMP\*.VHD",
            "$env:TEMP\*.VHDX",
            "$env:WINDIR\TEMP\*.VHD",
            "$env:WINDIR\TEMP\*.VHDX"
        )
        $procs = @(
            "$env:ProgramFiles\FSLogix\Apps\frxccd.exe",
            "$env:ProgramFiles\FSLogix\Apps\frxccds.exe",
            "$env:ProgramFiles\FSLogix\Apps\frxsvc.exe"
        )
        foreach ($p in $paths) { Add-MpPreference -ExclusionPath $p -ErrorAction SilentlyContinue }
        foreach ($p in $procs) { Add-MpPreference -ExclusionProcess $p -ErrorAction SilentlyContinue }
    }
    catch {
        Write-Warning "Defender exclusions failed: $($_.Exception.Message)"
    }
}

function SysprepVmModeFix {
    Write-Stage "Patching Sysprep command in C:\DeprovisioningScript.ps1 to use /mode:vm"
    try {
        $file = 'C:\DeprovisioningScript.ps1'
        if (Test-Path $file) {
            $content = Get-Content -LiteralPath $file -Raw
            $patched = $content -replace 'Sysprep.exe\s+/oobe\s+/generalize\s+/quiet\s+/quit','Sysprep.exe /oobe /generalize /quit /mode:vm'
            if ($patched -ne $content) {
                $patched | Set-Content -LiteralPath $file -Encoding UTF8
            }
        }
    }
    catch {
        Write-Warning "Sysprep patch failed: $($_.Exception.Message)"
    }
}

function Cleanup-DownloadedScripts {
    param([string[]]$Files)
    Write-Stage "Cleaning up helper scripts"
    foreach ($f in $Files) {
        try { if (Test-Path $f) { Remove-Item -LiteralPath $f -Force -ErrorAction Stop } }
        catch { Write-Warning "Cleanup failed for $f : $($_.Exception.Message)" }
    }
}

# ===== Official AVD helper script URLs (Azure RDS repo) =====
$urls = @{
    InstallLanguagePacks = "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/InstallLanguagePacks.ps1"
    SetDefaultLang       = "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/SetDefaultLang.ps1"
    TimezoneRedirect     = "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/TimezoneRedirection.ps1"
    DisableStorageSense  = "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/DisableStorageSense.ps1"
    RDPShortpath         = "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/RDPShortpath.ps1"
    MultiMediaRedirect   = "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/MultiMediaRedirection.ps1"
    WindowsOptimization  = "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/WindowsOptimization.ps1"
    RemoveAppx           = "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/RemoveAppxPackages.ps1"
}

# ===== Destination paths (strings only) =====
$paths = @{
    InstallLanguagePacks = "$workPath\InstallLanguagePacks.ps1"
    SetDefaultLang       = "$workPath\SetDefaultLang.ps1"
    TimezoneRedirect     = "$workPath\TimezoneRedirection.ps1"
    DisableStorageSense  = "$workPath\DisableStorageSense.ps1"
    RDPShortpath         = "$workPath\RDPShortpath.ps1"
    MultiMediaRedirect   = "$workPath\MultiMediaRedirection.ps1"
    WindowsOptimization  = "$workPath\WindowsOptimization.ps1"
    RemoveAppx           = "$workPath\RemoveAppxPackages.ps1"
}

# Keep a list for cleanup later
$downloadedHelpers = @(
    $paths.InstallLanguagePacks,
    $paths.SetDefaultLang,
    $paths.TimezoneRedirect,
    $paths.DisableStorageSense,
    $paths.RDPShortpath,
    $paths.MultiMediaRedirect,
    $paths.WindowsOptimization,
    $paths.RemoveAppx
)

# ===== Main sequence =====
try {
    Write-Stage "Starting AVD image customization"

    # 1) Language packs (example: Dutch (Netherlands))
    Download-AVDScript -Uri $urls.InstallLanguagePacks -Destination $paths.InstallLanguagePacks
    Run-AVDScript "`"$($paths.InstallLanguagePacks)`" -LanguageList 'Dutch (Netherlands)'"

    # Some Microsoft helper scripts delete C:\AVDImage; make sure our work folder still exists.
    if (-not (Test-Path $workPath)) {
        Write-Stage "Re-creating work folder after language pack step"
        New-Item -ItemType Directory -Path $workPath | Out-Null
    }

    # 2) Set default language
    Download-AVDScript -Uri $urls.SetDefaultLang -Destination $paths.SetDefaultLang
    Run-AVDScript "`"$($paths.SetDefaultLang)`" -Language 'Dutch (Netherlands)'"

    # 3) Timezone redirection / Storage Sense / RDP Shortpath
    Download-AVDScript -Uri $urls.TimezoneRedirect    -Destination $paths.TimezoneRedirect
    Run-AVDScript "`"$($paths.TimezoneRedirect)`""

    Download-AVDScript -Uri $urls.DisableStorageSense -Destination $paths.DisableStorageSense
    Run-AVDScript "`"$($paths.DisableStorageSense)`""

    Download-AVDScript -Uri $urls.RDPShortpath        -Destination $paths.RDPShortpath
    Run-AVDScript "`"$($paths.RDPShortpath)`""

    # 4) Multimedia redirection (Edge + Chrome + VC++ redist)
    Download-AVDScript -Uri $urls.MultiMediaRedirect  -Destination $paths.MultiMediaRedirect
    Run-AVDScript "`"$($paths.MultiMediaRedirect)`" -VCRedistributableLink 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -EnableEdge 'true' -EnableChrome 'true'"

    # 5) Windows optimization
    Download-AVDScript -Uri $urls.WindowsOptimization -Destination $paths.WindowsOptimization
    Run-AVDScript "`"$($paths.WindowsOptimization)`" -Optimizations 'WindowsMediaPlayer','ScheduledTasks','DefaultUserSettings','Autologgers','Services','NetworkOptimizations','LGPO','DiskCleanup','Edge','RemoveLegacyIE','RemoveOneDrive'"

    # 6) Remove unwanted in-box apps
    Download-AVDScript -Uri $urls.RemoveAppx -Destination $paths.RemoveAppx
    $appsToRemove = @(
        'Microsoft.XboxApp','Microsoft.ZuneVideo','Microsoft.ZuneMusic','Microsoft.YourPhone',
        'Microsoft.XboxSpeechToTextOverlay','Microsoft.XboxIdentityProvider','Microsoft.XboxGamingOverlay',
        'Microsoft.XboxGameOverlay','Microsoft.Xbox.TCUI','Microsoft.WindowsTerminal',
        'Microsoft.WindowsSoundRecorder','Microsoft.WindowsMaps','Microsoft.WindowsFeedbackHub',
        'Microsoft.windowscommunicationsapps','Microsoft.WindowsCamera','Microsoft.WindowsCalculator',
        'Microsoft.WindowsAlarms','Microsoft.Windows.Photos','Microsoft.Todos','Microsoft.SkypeApp',
        'Microsoft.ScreenSketch','Microsoft.PowerAutomateDesktop','Microsoft.People','Microsoft.MSPaint',
        'Microsoft.MicrosoftStickyNotes','Microsoft.MicrosoftSolitaireCollection','Microsoft.Office.OneNote',
        'Microsoft.MicrosoftOfficeHub','Microsoft.Getstarted','Microsoft.GamingApp','Microsoft.BingWeather',
        'Microsoft.GetHelp','Microsoft.BingNews','Clipchamp.Clipchamp'
    ) -join ','
    Run-AVDScript "`"$($paths.RemoveAppx)`" -AppxPackages '$appsToRemove'"

    # 7) Defender & Intune
    Set-DefenderExclusions
    Enable-IntuneAutoEnroll
}
finally {
    # Always do these even if a step failed
    SysprepVmModeFix
    Cleanup-DownloadedScripts -Files $downloadedHelpers
    try { Stop-Transcript } catch {}
    Write-Host "Transcript saved to $logFile"
}
