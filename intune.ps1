# ===== Strict mode & TLS =====
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ===== Paths & transcript =====
$avdPath = 'C:\AVDImage'
if (-not (Test-Path $avdPath)) {
    New-Item -ItemType Directory -Path $avdPath | Out-Null
}
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logFile  = "$avdPath\imagebuilder_$timestamp.log"
Start-Transcript -Path $logFile -Append

function Write-Stage {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ('-'*80)
    Write-Host "[AIB] $Message"
    Write-Host ('-'*80)
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

function write-urls {
    Write-Stage "Configuring Intune Auto-enrollment uri's"
    try {
 $key = 'SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo\*'
$keyinfo = Get-Item "HKLM:\$key"
$url = $keyinfo.name
$url = $url.Split("\")[-1]
$path = "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo\\$url"

New-ItemProperty -LiteralPath $path -Name 'MdmEnrollmentUrl' -Value 'https://enrollment.manage.microsoft.com/enrollmentserver/discovery.svc' -PropertyType String -Force -ea SilentlyContinue;
New-ItemProperty -LiteralPath $path  -Name 'MdmTermsOfUseUrl' -Value 'https://portal.manage.microsoft.com/TermsofUse.aspx' -PropertyType String -Force -ea SilentlyContinue;
New-ItemProperty -LiteralPath $path -Name 'MdmComplianceUrl' -Value 'https://portal.manage.microsoft.com/?portalAction=Compliance' -PropertyType String -Force -ea SilentlyContinue;

    }
    catch {
    Write-Warning "Url writing failed: $($_.Exception.Message)"
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


try {
Write-Stage "Starting AVD image customization"

# 1) Intune Auto Enrollment
Enable-IntuneAutoEnroll
Start-Sleep -Seconds 3

# 2) Intune Auto Enrollment
write-urls
Start-Sleep -Seconds 3

# 3) Set defender excludes
Set-DefenderExclusions
Start-Sleep -Seconds 3

}
finally {
    Stop-Transcript
    Write-Host "Transcript saved to $logFile"
}


