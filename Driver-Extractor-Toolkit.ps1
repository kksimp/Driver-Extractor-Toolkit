# DriverToolkit.ps1
# Run as Administrator

$ErrorActionPreference = "SilentlyContinue"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$DriversRoot = Join-Path $ScriptRoot "Drivers"

if (!(Test-Path $DriversRoot)) {
    New-Item -ItemType Directory -Path $DriversRoot -Force | Out-Null
}

function Pause-Toolkit {
    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Get-SafeName {
    param([string]$Name)
    return ($Name -replace '[\\/:*?"<>|]', '_')
}

function Find-DriverStoreFolder {

    param([string]$INFName)

    Get-ChildItem "C:\Windows\System32\DriverStore\FileRepository" -Directory |
        Where-Object {
            Test-Path (Join-Path $_.FullName $INFName)
        } |
        Select-Object -First 1
}

function Export-DriverPackage {

    param(
        $Device,
        $DriverInfo
    )

    $DeviceName = if ($Device.FriendlyName) {
        $Device.FriendlyName
    }
    elseif ($DriverInfo.DeviceName) {
        $DriverInfo.DeviceName
    }
    else {
        $Device.InstanceId
    }

    $SafeName = Get-SafeName $DeviceName

    $DeviceFolder = Join-Path $DriversRoot $SafeName
    $DriverFilesFolder = Join-Path $DeviceFolder "DriverFiles"

    New-Item -ItemType Directory -Path $DeviceFolder -Force | Out-Null
    New-Item -ItemType Directory -Path $DriverFilesFolder -Force | Out-Null

    $SummaryFile = Join-Path $DeviceFolder "DriverSummary.txt"

    $Summary = @()

    $Summary += "==========================================="
    $Summary += " DRIVER CAPTURE SUMMARY"
    $Summary += "==========================================="
    $Summary += ""
    $Summary += "Capture Date:"
    $Summary += "$(Get-Date)"
    $Summary += ""
    $Summary += "Device Name:"
    $Summary += "$DeviceName"
    $Summary += ""
    $Summary += "Manufacturer:"
    $Summary += "$($Device.Manufacturer)"
    $Summary += ""
    $Summary += "Status:"
    $Summary += "$($Device.Status)"
    $Summary += ""
    $Summary += "Class:"
    $Summary += "$($Device.Class)"
    $Summary += ""
    $Summary += "Instance ID:"
    $Summary += "$($Device.InstanceId)"
    $Summary += ""
    $Summary += "-------------------------------------------"
    $Summary += "DRIVER DETAILS"
    $Summary += "-------------------------------------------"
    $Summary += ""
    $Summary += "Driver Provider:"
    $Summary += "$($DriverInfo.DriverProviderName)"
    $Summary += ""
    $Summary += "Driver Version:"
    $Summary += "$($DriverInfo.DriverVersion)"
    $Summary += ""
    $Summary += "Driver Date:"
    $Summary += "$($DriverInfo.DriverDate)"
    $Summary += ""
    $Summary += "INF:"
    $Summary += "$($DriverInfo.InfName)"
    $Summary += ""
    $Summary += "Service:"
    $Summary += "$($DriverInfo.Service)"
    $Summary += ""

    try {
        $HardwareIDs = Get-PnpDeviceProperty `
            -InstanceId $Device.InstanceId `
            -KeyName DEVPKEY_Device_HardwareIds

        $Summary += "-------------------------------------------"
        $Summary += "HARDWARE IDS"
        $Summary += "-------------------------------------------"

        foreach ($ID in $HardwareIDs.Data) {
            $Summary += $ID
        }

        $Summary += ""
    }
    catch {}

    try {
        $CompatibleIDs = Get-PnpDeviceProperty `
            -InstanceId $Device.InstanceId `
            -KeyName DEVPKEY_Device_CompatibleIds

        $Summary += "-------------------------------------------"
        $Summary += "COMPATIBLE IDS"
        $Summary += "-------------------------------------------"

        foreach ($ID in $CompatibleIDs.Data) {
            $Summary += $ID
        }

        $Summary += ""
    }
    catch {}

    $Summary | Out-File $SummaryFile -Encoding UTF8

    if ($DriverInfo.InfName) {

        $DriverStoreFolder = Find-DriverStoreFolder $DriverInfo.InfName

        if ($DriverStoreFolder) {

            Write-Host "Copying Driver Files..."

            Copy-Item `
                $DriverStoreFolder.FullName `
                $DriverFilesFolder `
                -Recurse `
                -Force

            Add-Content $SummaryFile ""
            Add-Content $SummaryFile "Driver Files Exported: YES"

        }
        else {

            Add-Content $SummaryFile ""
            Add-Content $SummaryFile "Driver Files Exported: NO"
            Add-Content $SummaryFile "DriverStore Folder Not Found"
        }
    }

    $InstallCMD = Join-Path $DeviceFolder "InstallDriver.cmd"

@'
@echo off
echo Installing Driver...
pnputil /add-driver ".\DriverFiles\*.inf" /subdirs /install
pause
'@ | Out-File $InstallCMD -Encoding ASCII

    $ZipFile = Join-Path $DeviceFolder "DriverBackup.zip"

    if (Test-Path $ZipFile) {
        Remove-Item $ZipFile -Force
    }

    Compress-Archive `
        -Path "$DeviceFolder\*" `
        -DestinationPath $ZipFile `
        -Force

    Write-Host ""
    Write-Host "Capture Complete"
    Write-Host "Output Folder:"
    Write-Host $DeviceFolder
    Write-Host ""
}

function Capture-NewDevice {

    param(
        [bool]$USBOnly = $true
    )

    Clear-Host

    if ($USBOnly) {
        Write-Host "Waiting for a new USB device..."
    }
    else {
        Write-Host "Waiting for a new device..."
    }

    $Before = Get-PnpDevice | Select-Object -ExpandProperty InstanceId

    Register-WmiEvent `
        -Class Win32_DeviceChangeEvent `
        -SourceIdentifier DeviceCapture | Out-Null

    Wait-Event -SourceIdentifier DeviceCapture | Out-Null

    Start-Sleep 5

    $After = Get-PnpDevice

    $NewDevices = $After | Where-Object {
        $_.InstanceId -notin $Before
    }

    Unregister-Event DeviceCapture -ErrorAction SilentlyContinue

    if ($USBOnly) {
        $NewDevices = $NewDevices | Where-Object {
            $_.InstanceId -match '^USB'
        }
    }

    if (!$NewDevices) {

        Write-Host ""
        Write-Host "No new devices detected."

        Pause-Toolkit
        return
    }

    Write-Host ""
    Write-Host "New Devices Detected"
    Write-Host "--------------------"

    $Counter = 1

    foreach ($Device in $NewDevices) {

        $DisplayName = if ($Device.FriendlyName) {
            $Device.FriendlyName
        }
        else {
            $Device.InstanceId
        }

        Write-Host "$Counter. $DisplayName"

        $Counter++
    }

    Write-Host ""

    $Selection = Read-Host "Select device"

    $SelectedDevice = $NewDevices[[int]$Selection - 1]

    if (!$SelectedDevice) {
        return
    }

    $DriverInfo = Get-CimInstance Win32_PnPSignedDriver |
    Where-Object {
        $_.DeviceID -eq $SelectedDevice.InstanceId
    } |
    Select-Object -First 1

    Export-DriverPackage $SelectedDevice $DriverInfo

    Pause-Toolkit
}

function Install-Driver {

    Clear-Host

    $Drivers = Get-ChildItem $DriversRoot -Directory

    if (!$Drivers) {

        Write-Host "No exported drivers found."

        Pause-Toolkit
        return
    }

    Write-Host "Available Driver Packages"
    Write-Host ""

    for ($i = 0; $i -lt $Drivers.Count; $i++) {

        Write-Host "$($i+1). $($Drivers[$i].Name)"
    }

    Write-Host ""

    $Selection = Read-Host "Select package"

    $Selected = $Drivers[[int]$Selection - 1]

    if (!$Selected) {
        return
    }

    Write-Host ""
    Write-Host "Installing Driver..."
    Write-Host ""

    pnputil /add-driver "$($Selected.FullName)\DriverFiles\*.inf" /subdirs /install

    Pause-Toolkit
}

function View-Repository {

    Clear-Host

    $Folders = Get-ChildItem $DriversRoot -Directory

    if (!$Folders) {

        Write-Host "Repository Empty"

        Pause-Toolkit
        return
    }

    Write-Host "========================================="
    Write-Host " DRIVER REPOSITORY"
    Write-Host "========================================="
    Write-Host ""

    $Counter = 1

    foreach ($Folder in $Folders) {

        $SummaryFile = Join-Path $Folder.FullName "DriverSummary.txt"

        $Version = "Unknown"
        $INF = "Unknown"

        if (Test-Path $SummaryFile) {

            $Lines = Get-Content $SummaryFile

            for ($i=0; $i -lt $Lines.Count; $i++) {

                if ($Lines[$i] -eq "Driver Version:") {
                    $Version = $Lines[$i+1]
                }

                if ($Lines[$i] -eq "INF:") {
                    $INF = $Lines[$i+1]
                }
            }
        }

        Write-Host "$Counter. $($Folder.Name)"
        Write-Host "   Version: $Version"
        Write-Host "   INF: $INF"
        Write-Host ""

        $Counter++
    }

    Pause-Toolkit
}

function Extract-InstalledDriver {

    Clear-Host

    Write-Host "Enumerating Installed Drivers..."
    Write-Host ""

    $Drivers = Get-CimInstance Win32_PnPSignedDriver |
        Where-Object { $_.DeviceName } |
        Sort-Object DeviceName

    for ($i=0; $i -lt $Drivers.Count; $i++) {

        Write-Host "$($i+1). $($Drivers[$i].DeviceName)"
    }

    Write-Host ""

    $Selection = Read-Host "Select Driver"

    $Driver = $Drivers[[int]$Selection - 1]

    if (!$Driver) {
        return
    }

    $Device = [PSCustomObject]@{
        FriendlyName = $Driver.DeviceName
        Manufacturer = $Driver.Manufacturer
        Status = "Installed"
        Class = $Driver.DeviceClass
        InstanceId = $Driver.DeviceID
    }

    Export-DriverPackage $Device $Driver

    Pause-Toolkit
}

function Show-Menu {

    Clear-Host

    Write-Host ""
    Write-Host "========================================="
    Write-Host " DRIVER EXTRACTOR TOOLKIT"
    Write-Host "========================================="
    Write-Host ""
    Write-Host "1. Capture New USB Device"
    Write-Host "2. Capture Any New Device"
    Write-Host "3. Install Exported Driver"
    Write-Host "4. View Driver Repository"
    Write-Host "5. Extract Installed Driver"
    Write-Host "6. Exit"
    Write-Host ""

    Read-Host "Selection"
}

do {

    $Choice = Show-Menu

    switch ($Choice) {

        "1" { Capture-NewDevice -USBOnly $true }

        "2" { Capture-NewDevice -USBOnly $false }

        "3" { Install-Driver }

        "4" { View-Repository }

        "5" { Extract-InstalledDriver }

        "6" { break }
    }

} while ($true)