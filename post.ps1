param($storage, $key)
#----------------------------
# Post Deploy script
# Version: v1.0
# Date: 21-04-2023
# Owner: Andreas Daalder
# Modifyed By:
# Modify date: xx-xx-xxxx
#----------------------------


 $deploy     = "C:\Solvinity\Deploy"
 $logfiles   = 'PostConfig_Install.log',
               'ImageBuilder_Install.log'  

$logpath                = "C:\Solvinity\Logs"
if (Test-Path $logpath) {
  
    Write-Host "" $logpath " Folder Exists"
 }
else
{
      
    New-Item $logpath -ItemType Directory
    Write-Host "" $logpath " Folder Created successfully"
}

# Function to encrypt a file with a password
function Encrypt-File {
    Param(
        [string]$FilePath,
        [string]$Password
    )

    # Create a secure string from the password
    $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force

    # Generate a new encryption key from the password
    $EncryptionKey = New-Object System.Security.Cryptography.Rfc2898DeriveBytes $Password, (1..16), 1000

    # Read the contents of the file
    $Content = Get-Content $FilePath -Encoding Byte

    # Create a new AES object and encrypt the content
    $Aes = New-Object System.Security.Cryptography.AesCryptoServiceProvider
    $Aes.Key = $EncryptionKey.GetBytes(16)
    $Aes.IV = $EncryptionKey.GetBytes(16)
    $Aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $Aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7

    $Encryptor = $Aes.CreateEncryptor()
    $EncryptedContent = $Encryptor.TransformFinalBlock($Content, 0, $Content.Length)

    # Write the encrypted content to a new file
    [System.IO.File]::WriteAllBytes($FilePath + ".encrypted", $EncryptedContent)

    # Clean up the AES object
    $Aes.Dispose()
}

 Start-Transcript -Path "$($logpath)\Postconfig_Install.log" -Append -Debug

#-------------------------------------------------
# Config for FSLOGIX Cloud only 
#-------------------------------------------------

write-host "Configuring FSLogix"
$storage_path="$($storage).privatelink.file.core.windows.net"   
$profileShare="\\$($storage_path)\Fslogix"
$odfcShare="\\$($storage_path)\odfc"
$user="localhost\$($storage)"


New-Item -Path "HKLM:\SOFTWARE" -Name "FSLogix" -ErrorAction Ignore
New-Item -Path "HKLM:\SOFTWARE\FSLogix" -Name "Profiles" -ErrorAction Ignore
New-Item -Path "HKLM:\Software\Policies\Microsoft\" -Name AzureADAccount
New-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "Enabled" -Value 1 -PropertyType DWORD
New-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "VHDLocations" -Value $profileShare -force
New-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "ConcurrentUserSessions" -Value 1 -force
New-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "DeleteLocalProfileWhenVHDShouldApply" -Value 1 -force
New-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "FlipFlopProfileDirectoryName" -Value 1 -force
New-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "IsDynamic" -Value 1 -force
New-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "KeepLocalDir" -Value 0 -force
New-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "ProfileType" -Value 0 -force
New-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "SizeInMBs" -Value 10000 -force
New-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "VolumeType" -Value "VHDX" -force
New-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "AccessNetworkAsComputerObject" -Value 1 -force
New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\AzureADAccount"  -Name "LoadCredKeyFromProfile" -Value 1 -PropertyType DWORD
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters" -Name "CloudKerberosTicketRetrievalEnabled" -Value 1 -PropertyType DWORD

# ODFC (Office Data File Container) Config 
New-Item -Path "HKLM:\SOFTWARE\Policies\" -Name "FSLogix" -ErrorAction Ignore
New-Item -Path "HKLM:\SOFTWARE\Policies\FSLogix" -Name "ODFC" -ErrorAction Ignore
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\FSLogix\ODFC" -Name "Enabled" -Value 1 -PropertyType DWORD
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\FSLogix\ODFC" -Name "VHDLocations" -Value $odfcShare -force
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\FSLogix\ODFC" -Name "LockedRetryCount" -Value 3 -PropertyType DWORD
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\FSLogix\ODFC" -Name "LockedRetryInterval" -Value 15 -PropertyType DWORD
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\FSLogix\ODFC" -Name "FlipFlopProfileDirectoryName" -Value 1 -PropertyType DWORD
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\FSLogix\ODFC" -Name "ReAttachIntervalSeconds" -Value 15 -PropertyType DWORD
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\FSLogix\ODFC" -Name "IncludeTeams" -Value 1 -PropertyType DWORD
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\FSLogix\ODFC" -Name "ReAttachRetryCount" -Value 3 -PropertyType DWORD
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\FSLogix\ODFC" -Name "SizeInMBs" -Value 40000 -PropertyType DWORD
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\FSLogix\ODFC" -Name "VolumeType" -Value "VHDX" -force
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\FSLogix\ODFC" -Name "AccessNetworkAsComputerObject" -Value 1 -PropertyType DWORD
cmdkey.exe /add:$($storage_path) /user:$($user) /pass:$($key)

write-host "FSlogix config has been finished."

#-------------------------------------------------
# Install additional software using WinGet
#-------------------------------------------------

write-host "Install Additional software."

function Install-WingetApp {
    param (
        [string]$PackageIdentifier
    )
    $ResolveWingetPath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
    if ($ResolveWingetPath){
           $WingetPath = $ResolveWingetPath[-1].Path
    }

$Wingetpath = Split-Path -Path $WingetPath -Parent
cd $wingetpath

    Write-Host "Attempting to install $PackageIdentifier..."
    .\winget.exe install --exact --id $PackageIdentifier --silent --accept-source-agreements --accept-package-agreements 
}

# App identifiers for winget
$apps =       'Notepad++.Notepad++',
              'Microsoft.VisualStudioCode',
              'Microsoft.VisioViewer',
              'Microsoft.LAPS' 
# Install apps
foreach ($app in $apps) {
    Install-WingetApp -PackageIdentifier $app
    Write-Host "Try to Install $app "
}

Write-Host "Installation process completed."



    # function unInstallTeams($path) {

    #     $clientInstaller = "$($path)\Update.exe"
        
    #      try {
    #           $process = Start-Process -FilePath "$clientInstaller" -ArgumentList "--uninstall /s" -PassThru -Wait -ErrorAction STOP
      
    #           if ($process.ExitCode -ne 0)
    #       {
    #         Write-Error "UnInstallation failed with exit code  $($process.ExitCode)."
    #           }
    #       }
    #       catch {
    #           Write-Error $_.Exception.Message
    #       }
      
    #   }
      
    #   # Remove Teams Machine-Wide Installer
    #   Write-Host "Removing Teams Machine-wide Installer" -ForegroundColor Yellow
      
    #   $MachineWide = Get-WmiObject -Class Win32_Product | Where-Object{$_.Name -eq "Teams Machine-Wide Installer"}
    #   $MachineWide.Uninstall()
      
    #   # Remove Teams for Current Users
    #   $localAppData = "$($env:LOCALAPPDATA)\Microsoft\Teams"
    #   $programData = "$($env:ProgramData)\$($env:USERNAME)\Microsoft\Teams"
      
      
    #   If (Test-Path "$($localAppData)\Current\Teams.exe") 
    #   {
    #     unInstallTeams($localAppData)
          
    #   }
    #   elseif (Test-Path "$($programData)\Current\Teams.exe") {
    #     unInstallTeams($programData)
    #   }
    #   else {
    #     Write-Warning  "Teams installation not found"
    #   }




Write-Host "End of Post Config Steps . . . . . "
# Restart session host 
Stop-Transcript

# Encrypt logfiles and restart system

# ForEach ($logs in $logfiles)
# {& Encrypt-File -FilePath "$($logpath)\$($logs)" -Password $storage
#     Start-Sleep -Seconds 5
#     Remove-Item "$($logpath)\$($logs)" -Recurse -Force
#     Write-Host "" $logs " Encrypted!"
# }

if ((Test-Path -Path $deploy -ErrorAction SilentlyContinue)) {
    Remove-Item -Path $deploy -Force -Recurse -ErrorAction Continue
}
Restart-Computer -Force
