#----------------------------
# ImageBuilder Deploy script
# Version: v1.0
# Date: 17-04-2023
# Owner: Andreas Daalder
# Modifyed By:
# Modify date: xx-xx-xxxx
#----------------------------


#-------------------------------------------------
# Install Software via WinGet
#-------------------------------------------------

$WinGetApps = 'Google.Chrome.Beta',
              'Adobe.Acrobat.Reader.64-bit',
              'DominikReichl.KeePass',
		          'Mozilla.Firefox'

###################################################              

$deploy = "C:\Solvinity\Deploy"
if (Test-Path $deploy) {
   
    Write-Host "" $deploy " Folder Exists"
 
}
else
{
      
    New-Item $deploy -ItemType Directory
    Write-Host "" $deploy " Folder Created successfully"
}


Start-Transcript -Path "C:\Solvinity\Logs\"+ (get-date -format 'ddMMyyyy') + '_Install.log' -Append


#Create temp folder
New-Item -Path 'C:\Temp' -ItemType Directory -Force | Out-Null


## Install WinGet

#Set-ExecutionPolicy RemoteSigned
$MyLink = "https://github.com/microsoft/winget-cli/releases/download/v1.4.10173/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"

Write-Host "Winget is being downloaded"

Invoke-WebRequest -Uri $MyLink -OutFile "C:\Solvinity\Deploy\WinGet.msixbundle"
Write-Host "Winget installer downloaded, launching installer."
$localFolderPath = "C:\Solvinity\Deploy"
$localPackage = "C:\Solvinity\Deploy\WinGet.msixbundle"

DISM.EXE /Online /Add-ProvisionedAppxPackage /PackagePath:$localPackage /SkipLicense

## End installation WinGet

## Start installation of Applications

 $winget_exe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
      if ($winget_exe.count -gt 1){
          $winget_exe = $winget_exe[-1].Path
              }
              
              if (!$winget_exe){Write-Error "Winget not installed"} 
              
              
ForEach ($Apps in $WinGetApps)
{ & $winget_exe install --exact --id $Apps --silent --accept-package-agreements --accept-source-agreements --scope=machine --force
    Write-Host "" $Apps " Installed"
}


# install Teams in VDI Mode
reg add "HKLM\SOFTWARE\Microsoft\Teams" /v IsWVDEnvironment /t REG_DWORD /d 1 /f

    
#Download RDCWEBRTCSvc
invoke-WebRequest -Uri https://aka.ms/msrdcwebrtcsvc/msi -OutFile "C:\Solvinity\Deploy\MsRdcWebRTCSvc_HostSetup_x64.msi"
Start-Sleep -s 5
#Download Teams 
invoke-WebRequest -Uri "https://teams.microsoft.com/downloads/desktopurl?env=production&plat=windows&arch=x64&managedInstaller=true&download=true" -OutFile "C:\Solvinity\Deploy\Teams_windows_x64.msi"
Start-Sleep -s 5


#Install MSRDCWEBTRCSVC
msiexec /i "C:\Solvinity\Deploy\MsRdcWebRTCSvc_HostSetup_x64.msi"  /qn
Start-Sleep -s 60
# Install Teams
msiexec /i "C:\Solvinity\Deploy\Teams_windows_x64.msi" /l*v teamsinstall.txt ALLUSER=1 /qn
Start-Sleep -s 30

######## Host Optimalization ##

# Variables
$verbosePreference = 'Continue'
$vdot = 'https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/archive/refs/heads/main.zip' 
$apppackages = 'https://github.com/admada/aib/raw/main/AppxPackages.json'
$vdot_location = 'c:\Optimize' 
$vdot_location_zip = 'c:\Optimize\vdot.zip'
$apppackages_location = 'C:\Optimize\AppxPackages.json'

# Enable TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Clear screen
Clear

# Create Folder
$checkdir = Test-Path -Path $vdot_location
if ($checkdir -eq $false){
    Write-Verbose "Creating '$vdot_location' folder"
    New-Item -Path 'c:\' -Name 'Optimize' -ItemType 'directory' | Out-Null
}
else {
    Write-Verbose "Folder '$vdot_location' already exists."
}

# Download VDOT
Write-Verbose "Download VDOT" 
Invoke-WebRequest -Uri $vdot -OutFile $vdot_location_zip

# Expand Archive
Write-Verbose "Expand Archive" 
Expand-Archive $vdot_location_zip -DestinationPath $vdot_location -Verbose -Force

# Remove Archive
Write-Verbose "Remove Archive" 
Remove-Item $vdot_location_zip

# Download AppPackages
Write-Verbose "Download Apppackages.json APPX file" 
Invoke-WebRequest -Uri $apppackages -OutFile $apppackages_location

# Copy the AppPackage file to all versions
Write-Verbose "Copy Apppackages.json to all configurationfiles folders" 
Copy-Item $apppackages_location -Destination 'C:\Optimize\Virtual-Desktop-Optimization-Tool-main\1909\ConfigurationFiles\AppxPackages.json'
Copy-Item $apppackages_location -Destination 'C:\Optimize\Virtual-Desktop-Optimization-Tool-main\2004\ConfigurationFiles\AppxPackages.json'
Copy-Item $apppackages_location -Destination 'C:\Optimize\Virtual-Desktop-Optimization-Tool-main\2009\ConfigurationFiles\AppxPackages.json'

# Unblock all files
Write-Verbose "Unblock all files" 
dir $vdot_location -Recurse | Unblock-File

# Change folder to VDOT
Write-Verbose "Change folder to VDOT location" 
$vdot_folder = $vdot_location + '\Virtual-Desktop-Optimization-Tool-main' 
cd $vdot_folder

Write-Verbose "Run VDOT" 
Set-ExecutionPolicy -ExecutionPolicy bypass -Scope Process -Force
./Windows_VDOT.ps1 -Optimizations All -AdvancedOptimizations All -Verbose -AcceptEULA 

# Sleep 5 seconds
sleep 5

# Remove folder
Write-Verbose "Remove Optimize folder" 
cd \
Remove-Item $vdot_location -Recurse -Force


## Enable RDP Shortpath

$WinstationsKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations'
if(Test-Path $WinstationsKey){
    New-ItemProperty -Path $WinstationsKey -Name 'fUseUdpPortRedirector' -ErrorAction:SilentlyContinue -PropertyType:dword -Value 1 -Force
    New-ItemProperty -Path $WinstationsKey -Name 'UdpPortNumber' -ErrorAction:SilentlyContinue -PropertyType:dword -Value 3390 -Force
    New-ItemProperty -Path $WinstationsKey -Name 'ICEControl' -ErrorAction:SilentlyContinue -PropertyType:dword -Value 2 -Force

    # RDP FPS optimization
    New-ItemProperty -Path $WinstationsKey -Name 'DWMFRAMEINTERVAL' -ErrorAction:SilentlyContinue -PropertyType:dword -Value 15 -Force
}

New-NetFirewallRule -DisplayName 'Remote Desktop - Shortpath (UDP-In)'  -Action Allow -Description 'Inbound rule for the Remote Desktop service to allow RDP traffic. [UDP 3390]' -Group '@FirewallAPI.dll,-28752' -Name 'RemoteDesktop-UserMode-In-Shortpath-UDP'  -PolicyStore PersistentStore -Profile Domain, Private -Service TermService -Protocol udp -LocalPort 3390 -Program '%SystemRoot%\system32\svchost.exe' -Enabled:True
New-NetQosPolicy -Name "RDP Shortpath for managed networks" -AppPathNameMatchCondition "svchost.exe" -IPProtocolMatchCondition UDP -IPSrcPortStartMatchCondition 3390 -IPSrcPortEndMatchCondition 3390 -DSCPAction 46 -NetworkProfile All

#Sysprep fix, remove delay Windows installer
try {
    ((Get-Content -path C:\DeprovisioningScript.ps1 -Raw) -replace 'Sysprep.exe /oobe /generalize /quiet /quit', 'Sysprep.exe /oobe /generalize /quit /mode:vm' ) | Set-Content -Path C:\DeprovisioningScript.ps1
    Write-Host "Sysprep Mode:VM fix applied"
}
catch {
    $ErrorMessage = $_.Exception.message
    Write-Host "Error updating script: $ErrorMessage"
}

## Set Time Zone   

Set-TimeZone -Name "W. Europe Standard Time" -PassThru

Write-Host "Cleaning up temp files. . . . . "

Remove-Item $deploy -Recurse -Force

Stop-Transcript
