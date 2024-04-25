#----------------------------
# ImageBuilder Deploy script
# Version: v1.0
# Date: 25-05-2023
# Owner: Andreas Daalder
# Modifyed By:
# Modify date: xx-xx-xxxx
#----------------------------


#-------------------------------------------------
# Install Software via WinGet
#-------------------------------------------------

$WinGetApps = @( 
              "Adobe.Acrobat.Reader.64-bit",
              "DominikReichl.KeePass",
	      "Mozilla.Firefox"
)

###################################################              
$logs   = "C:\Solvinity\Logs"
$deploy = "C:\Solvinity\Deploy"

if (Test-Path $deploy) {
   
    Write-Host "" $deploy " Folder Exists"
 
}
else
{
      
    New-Item $deploy -ItemType Directory
    Write-Host "" $deploy " Folder Created successfully"
}

if (Test-Path $logs) {
   
    Write-Host "" $logs " Folder Exists"
 
}
else
{
      
    New-Item $logs -ItemType Directory
    Write-Host "" $logs " Folder Created successfully"
}

Start-Transcript -Path "C:\Solvinity\Logs\ImageBuilder_Install.log" -Append


#Create temp folder
New-Item -Path 'C:\Temp' -ItemType Directory -Force | Out-Null


## Install WinGet

Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
Install-Script -Name winget-install -Force
winget-install.ps1 -Force

# Function to install a package using winget
function Install-WingetApp {
    param (
        [string]$PackageIdentifier
    )
    
    Write-Host "Attempting to install $PackageIdentifier..."
    winget install --id $PackageIdentifier --silent --accept-source-agreements --accept-package-agreements --scope=machine --force
}

# Install apps
foreach ($app in $WinGetApps) {
    Install-WingetApp -PackageIdentifier $app
    Write-Host "Installation process $app."
}

Write-Host "Installation WinGet process completed."


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



#######################################
#     Install FSLogix                 #
#######################################

$FSLogixInstaller        = "https://aka.ms/fslogix_download"  
$LocalAVDpath            = "C:\Solvinity\Deploy\"
$FSInstaller             = 'FSLogixAppsSetup.zip'
$templateFilePathFolder  = "C:\AVDImage"


#################################
#    Download FSLogix           #
#################################
Write-Host "AVD AIB Customization - Install FSLogix : Downloading FSLogix from URI: $FSLogixInstaller"
Invoke-WebRequest -Uri $FSLogixInstaller -OutFile "$LocalAVDpath$FSInstaller"


##############################
#  Prep for FSLogix Install  #
##############################
Write-Host "AVD AIB Customization - Install FSLogix : Unzipping FSLogix installer"
Expand-Archive `
    -LiteralPath "C:\Solvinity\Deploy\$FSInstaller" `
    -DestinationPath "$LocalAVDpath\FSLogix" `
    -Force `
    -Verbose
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Set-Location $LocalAVDpath 
Write-Host "AVD AIB Customization - Install FSLogix : UnZip of FSLogix complete"


#########################
#    FSLogix Install    #
#########################
Write-Host "AVD AIB Customization - Install FSLogix : Starting to install FSLogix"
$fslogix_deploy_status = Start-Process `
    -FilePath "$LocalAVDpath\FSLogix\x64\Release\FSLogixAppsSetup.exe" `
    -ArgumentList "/install /quiet /norestart" `
    -Wait `
    -Passthru

#Reference: https://learn.microsoft.com/en-us/azure/architecture/example-scenario/wvd/windows-virtual-desktop-fslogix#add-exclusions-for-microsoft-defender-for-cloud-by-using-powershell
Write-Host "AVD AIB Customization - Install FSLogix : Adding exclusions for Microsoft Defender"

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

Write-Host "AVD AIB Customization - Install FSLogix : Finished adding exclusions for Microsoft Defender"

#Cleanup
if ((Test-Path -Path $templateFilePathFolder -ErrorAction SilentlyContinue)) {
    Remove-Item -Path $templateFilePathFolder -Force -Recurse -ErrorAction Continue
}

###################
#  END FSLOGIX    #
###################

####### Multi media redirection ########
$scripturl_mmr = 'https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2023-05-16/MultiMediaRedirection.ps1'
$mmr_script    = Invoke-WebRequest -uri $scripturl_mmr -OutFile 'C:\Solvinity\Deploy\mmr.ps1'
$mmr = & "C:\Solvinity\Deploy\mmr.ps1" -VCRedistributableLink "https://aka.ms/vs/17/release/vc_redist.x64.exe" -EnableEdge "true" -EnableChrome "true"

####### Language Packs ########
$scripturl_lp      = 'https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2023-05-16/InstallLanguagePacks.ps1'
$languagep_script    = Invoke-WebRequest -uri $scripturl_lp -OutFile 'C:\Solvinity\Deploy\installLanguagePacks.ps1'
$lp = & "C:\Solvinity\Deploy\installLanguagePacks.ps1" -LanguageList "Dutch (Netherlands)"

####### Set default Language ########
$scripturl_dl      = 'https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2023-05-16/SetDefaultLang.ps1'
$dlanguage_script    = Invoke-WebRequest -uri $scripturl_dl -OutFile 'C:\Solvinity\Deploy\setDefaultLanguage.ps1'
$dl = & "C:\Solvinity\Deploy\setDefaultLanguage.ps1" -Language "Dutch (Netherlands)" 


######## Host Optimalization #########
$scripturl_vdot = 'https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2023-05-16/WindowsOptimization.ps1'
$scripturl_appx = 'https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2023-05-16/RemoveAppxPackages.ps1'

$optimize_script = Invoke-WebRequest -uri $scripturl_vdot -OutFile 'C:\Solvinity\Deploy\vdot.ps1'
$optimize = & "C:\Solvinity\Deploy\vdot.ps1" -Optimizations "WindowsMediaPlayer","ScheduledTasks","DefaultUserSettings","Autologgers","Services","NetworkOptimizations","LGPO","DiskCleanup","Edge","RemoveLegacyIE"

$appx_script = Invoke-WebRequest -uri $scripturl_appx -OutFile 'C:\Solvinity\Deploy\remove_appx.ps1'
$remove = & "C:\Solvinity\Deploy\remove_appx.ps1" -AppxPackages "Microsoft.BingNews","Microsoft.BingWeather","Microsoft.GamingApp","Microsoft.GetHelp","Microsoft.Getstarted","Microsoft.MicrosoftOfficeHub","Microsoft.MicrosoftSolitaireCollection","Microsoft.People","Microsoft.PowerAutomateDesktop","Microsoft.ScreenSketch","Microsoft.SkypeApp","Microsoft.Todos","Microsoft.WindowsAlarms","Microsoft.WindowsCamera","Microsoft.windowscommunicationsapps","Microsoft.WindowsFeedbackHub","Microsoft.WindowsMaps","Microsoft.WindowsSoundRecorder","Microsoft.WindowsTerminal","Microsoft.Xbox.TCUI","Microsoft.XboxGameOverlay","Microsoft.XboxGamingOverlay","Microsoft.XboxIdentityProvider","Microsoft.XboxSpeechToTextOverlay","Microsoft.YourPhone","Microsoft.ZuneMusic","Microsoft.ZuneVideo","Microsoft.XboxApp","Microsoft.Windowsstore"


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

#######################################
#    Disable Storage Sense            #
#######################################

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
Write-Host "***Starting AVD AIB CUSTOMIZER PHASE: Disable Storage Sense Start -  $((Get-Date).ToUniversalTime()) "

$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense"
$registryKey = "AllowStorageSenseGlobal"
$registryValue = "0"

$registryPathWin11 = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense"

IF(!(Test-Path $registryPath)) {
    New-Item -Path $registryPath -Force
}

IF(!(Test-Path $registryPathWin11)) {
    New-Item -Path $registryPathWin11 -Force
}

Set-RegKey -registryPath $registryPath -registryKey $registryKey -registryValue $registryValue
Set-RegKey -registryPath $registryPathWin11 -registryKey $registryKey -registryValue $registryValue

$stopwatch.Stop()
$elapsedTime = $stopwatch.Elapsed
Write-Host "*** AVD AIB CUSTOMIZER PHASE: Disable Storage Sense - Exit Code: $LASTEXITCODE ***"
Write-Host "*** Ending AVD AIB CUSTOMIZER PHASE: Disable Storage Sense - Time taken: $elapsedTime "

function Set-RegKey($registryPath, $registryKey, $registryValue) {
    try {
         Write-Host "*** AVD AIB CUSTOMIZER PHASE ***  Disable Storage Sense - Setting  $registryKey with value $registryValue ***"
         New-ItemProperty -Path $registryPath -Name $registryKey -Value $registryValue -PropertyType DWORD -Force -ErrorAction Stop
    }
    catch {
         Write-Host "*** AVD AIB CUSTOMIZER PHASE ***   Disable Storage Sense  - Cannot add the registry key  $registryKey *** : [$($_.Exception.Message)]"
    }
 }



Write-Host "Cleaning up temp files. . . . . "

# if ((Test-Path -Path $deploy -ErrorAction SilentlyContinue)) {
#     Remove-Item -Path $deploy -Force -Recurse -ErrorAction Continue
# }


Stop-Transcript
