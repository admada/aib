## Set MDM key's for auto enrollment
$taskPath = "\Microsoft\Windows\Workplace Join\"
$taskName = "Automatic-Device-Join"

# Check if the task exists
$task = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue

if ($task) {
    Write-Host "Found the task. Enabling..." -ForegroundColor Cyan
    Enable-ScheduledTask -TaskPath $taskPath -TaskName $taskName
    Write-Host "Task enabled successfully." -ForegroundColor Green
} else {
    Write-Warning "Task not found. It may have been deleted or corrupted."
    Write-Host "Try repairing built-in tasks:"
    Write-Host "  Dism /Online /Cleanup-Image /RestoreHealth"
    Write-Host "  sfc /scannow"
}

Start-Sleep 10
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
