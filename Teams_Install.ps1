
$LogFile = "C:\Solvinity\Logs\teams\" + (Get-Date -UFormat "%d-%m-%Y") + ".log"
$RegCheck = 'teams'


function logging {
    Write-Verbose -Message "Start logging. . . . . " -Verbose
    Start-Transcript -Path $LogFile
    }

    if (Test-Path HKLM:\Software\Solvinity) {
        $regexist = Get-ItemProperty "HKLM:\Software\Solvinity" -Name $RegCheck -ErrorAction SilentlyContinue
    }
    else {
        if(!(Test-Path "HKLM:\Software\Solvinity")){
            New-Item HKLM:\Software\Solvinity
        }
    } 


function install_teams { 
    
    $deploy = "C:\Solvinity\Deploy"
    if (Test-Path $deploy) {
       
        Write-Host "Folder Exists"
        # Perform Delete file from folder operation
    }
    else
    {
      
        
        New-Item $deploy -ItemType Directory
        Write-Host "Folder Created successfully"
    }


    # Add registry Key
reg add "HKLM\SOFTWARE\Microsoft\Teams" /v IsWVDEnvironment /t REG_DWORD /d 1 /f
# check directory and create if missing


#Download RDCWEBRTCSvc
invoke-WebRequest -Uri https://aka.ms/msrdcwebrtcsvc/msi -OutFile "C:\Solvinity\Deploy\MsRdcWebRTCSvc_HostSetup_x64.msi"
Start-Sleep -s 5
#Download Teams 
invoke-WebRequest -Uri "https://teams.microsoft.com/downloads/desktopurl?env=production&plat=windows&arch=x64&managedInstaller=true&download=true" -OutFile "C:\Solvinity\Deploy\Teams_windows_x64.msi"
Start-Sleep -s 5


#Install MSRDCWEBTRCSVC
msiexec /i "C:\Solvinity\Deploy\MsRdcWebRTCSvc_HostSetup_x64.msi"  /n
Start-Sleep -s 10
# Install Teams
msiexec /i "C:\Solvinity\Deploy\Teams_windows_x64.msi" /l*v teamsinstall.txt ALLUSER=1 
Start-Sleep -s 10

# Add registry Key
reg add "HKLM\SOFTWARE\Solvinity" /v $RegCheck /t REG_SZ /d 1 /f

}

$regexist = Get-ItemProperty "HKLM:\Software\Solvinity" -Name $RegCheck -ErrorAction SilentlyContinue

if (-not($regexist)){

    logging
    install_teams
    Stop-Transcript
    Exit 0
} Else {
    Exit 0
}




