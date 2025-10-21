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

Enable-IntuneAutoEnroll
Set-DefenderExclusions

