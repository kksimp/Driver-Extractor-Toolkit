# Driver-Extractor-Toolkit.ps1
# Run as Administrator from Windows PowerShell 5.1 or PowerShell 7+

#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$DriversRoot = Join-Path $PSScriptRoot "Drivers"

if (!(Test-Path -LiteralPath $DriversRoot)) {
    New-Item -ItemType Directory -Path $DriversRoot -Force | Out-Null
}

function Pause-Toolkit {
    Write-Host ""
    Read-Host "Press Enter to continue" | Out-Null
}

function Get-SafeName {
    param([string]$Name)

    # Strip characters that are invalid in folder names, plus [ ] which
    # PowerShell treats as wildcards. Windows also ignores trailing dots/spaces.
    return ($Name -replace '[\\/:*?"<>|\[\]]', '_').Trim().TrimEnd('.')
}

function Read-Selection {

    param(
        [string]$Prompt,
        [int]$Max
    )

    $Selection = Read-Host $Prompt
    $Number = 0

    if (![int]::TryParse($Selection, [ref]$Number) -or $Number -lt 1 -or $Number -gt $Max) {
        Write-Host "Invalid selection." -ForegroundColor Yellow
        return $null
    }

    return $Number - 1
}

function Get-SignedDriverInfo {

    param([string]$InstanceId)

    # WQL string literals need backslashes and single quotes escaped
    $Escaped = $InstanceId.Replace('\', '\\').Replace("'", "\'")

    Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceID = '$Escaped'" |
        Select-Object -First 1
}

function Test-IsUsbDevice {

    param([string]$InstanceId)

    # Walk up the device tree so child devices of a USB device (COM ports,
    # HID interfaces, storage volumes, etc.) are also treated as USB.
    $Current = $InstanceId

    for ($Depth = 0; $Depth -lt 6 -and $Current; $Depth++) {

        if ($Current -match '^USB') {
            return $true
        }

        try {
            $Current = (Get-PnpDeviceProperty `
                -InstanceId $Current `
                -KeyName DEVPKEY_Device_Parent).Data
        }
        catch {
            return $false
        }
    }

    return $false
}

function Export-DriverFiles {

    param(
        [string]$INFName,
        [string]$Destination
    )

    # Third-party packages are published as oemNN.inf. Inbox drivers
    # (usb.inf, msports.inf, ...) ship with Windows and cannot be exported.
    if ($INFName -notmatch '^oem\d+\.inf$') {
        return "Inbox Windows driver ($INFName) - included with Windows, nothing to export"
    }

    Write-Host "Exporting driver package $INFName..."

    # Windows PowerShell 5.1 turns native stderr into a terminating error
    # under "Stop", so let pnputil report through its exit code instead.
    $ErrorActionPreference = "Continue"

    $Output = & pnputil.exe /export-driver $INFName $Destination 2>&1

    if ($LASTEXITCODE -ne 0) {
        return "pnputil export failed (exit code $LASTEXITCODE): $($Output -join ' ')"
    }

    return $null
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

    # Start from a clean DriverFiles folder so a re-capture never mixes
    # files from an older driver version with the new one.
    if (Test-Path -LiteralPath $DriverFilesFolder) {
        Remove-Item -LiteralPath $DriverFilesFolder -Recurse -Force
    }

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
    $Summary += "Computer Name:"
    $Summary += "$env:COMPUTERNAME"
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

        if ($HardwareIDs.Data) {

            $Summary += "-------------------------------------------"
            $Summary += "HARDWARE IDS"
            $Summary += "-------------------------------------------"

            foreach ($ID in $HardwareIDs.Data) {
                $Summary += $ID
            }

            $Summary += ""
        }
    }
    catch {}

    try {
        $CompatibleIDs = Get-PnpDeviceProperty `
            -InstanceId $Device.InstanceId `
            -KeyName DEVPKEY_Device_CompatibleIds

        if ($CompatibleIDs.Data) {

            $Summary += "-------------------------------------------"
            $Summary += "COMPATIBLE IDS"
            $Summary += "-------------------------------------------"

            foreach ($ID in $CompatibleIDs.Data) {
                $Summary += $ID
            }

            $Summary += ""
        }
    }
    catch {}

    $Summary += "-------------------------------------------"
    $Summary += "EXPORT RESULT"
    $Summary += "-------------------------------------------"
    $Summary += ""

    $ExportError = if ($DriverInfo.InfName) {
        Export-DriverFiles $DriverInfo.InfName $DriverFilesFolder
    }
    else {
        "No driver is installed for this device yet"
    }

    if ($ExportError) {
        Write-Host $ExportError -ForegroundColor Yellow
        $Summary += "Driver Files Exported: NO"
        $Summary += $ExportError
    }
    else {
        $Summary += "Driver Files Exported: YES"
    }

    $Summary | Out-File -LiteralPath $SummaryFile -Encoding UTF8

    $InstallCMD = Join-Path $DeviceFolder "InstallDriver.cmd"

    # %~dp0 is the folder the .cmd lives in, so this works when launched via
    # "Run as administrator" (which starts in C:\Windows\System32).
@'
@echo off
net session >nul 2>&1
if errorlevel 1 (
    echo This script must be run as Administrator.
    echo Right-click InstallDriver.cmd and choose "Run as administrator".
    pause
    exit /b 1
)
echo Installing Driver...
pnputil /add-driver "%~dp0DriverFiles\*.inf" /subdirs /install
pause
'@ | Out-File -LiteralPath $InstallCMD -Encoding ASCII

    $ZipFile = Join-Path $DeviceFolder "DriverBackup.zip"

    if (Test-Path -LiteralPath $ZipFile) {
        Remove-Item -LiteralPath $ZipFile -Force
    }

    $ZipContents = Get-ChildItem -LiteralPath $DeviceFolder |
        Select-Object -ExpandProperty FullName

    Compress-Archive `
        -LiteralPath $ZipContents `
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
        [bool]$USBOnly = $true,
        [int]$TimeoutSeconds = 120
    )

    Clear-Host

    if ($USBOnly) {
        Write-Host "Waiting for a new USB device..."
    }
    else {
        Write-Host "Waiting for a new device..."
    }

    Write-Host "Plug the device in now. Press any key to cancel (times out after $TimeoutSeconds seconds)."

    # -PresentOnly matters: without it, Get-PnpDevice also returns devices that
    # were connected in the past, so re-plugging a known device would be missed.
    $Before = Get-PnpDevice -PresentOnly | Select-Object -ExpandProperty InstanceId

    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $NewDevices = @()

    while ((Get-Date) -lt $Deadline) {

        Start-Sleep -Seconds 2

        try {
            if ([Console]::KeyAvailable) {
                [Console]::ReadKey($true) | Out-Null
                Write-Host "Cancelled."
                Pause-Toolkit
                return
            }
        }
        catch {}

        $NewDevices = @(Get-PnpDevice -PresentOnly | Where-Object {
            $_.InstanceId -notin $Before
        })

        if ($NewDevices.Count -gt 0) {
            break
        }
    }

    if ($NewDevices.Count -gt 0) {

        # Give Windows time to finish enumerating child devices and
        # installing drivers before reading driver details.
        Write-Host "Device detected. Waiting for driver installation to settle..."
        Start-Sleep -Seconds 10

        $NewDevices = @(Get-PnpDevice -PresentOnly | Where-Object {
            $_.InstanceId -notin $Before
        })
    }

    if ($USBOnly) {
        $NewDevices = @($NewDevices | Where-Object {
            Test-IsUsbDevice $_.InstanceId
        })
    }

    if ($NewDevices.Count -eq 0) {

        Write-Host ""
        Write-Host "No new devices detected."

        Pause-Toolkit
        return
    }

    Write-Host ""
    Write-Host "New Devices Detected"
    Write-Host "--------------------"

    for ($i = 0; $i -lt $NewDevices.Count; $i++) {

        $Device = $NewDevices[$i]

        $DisplayName = if ($Device.FriendlyName) {
            $Device.FriendlyName
        }
        else {
            $Device.InstanceId
        }

        Write-Host "$($i+1). $DisplayName"
    }

    Write-Host ""

    $Index = Read-Selection "Select device" $NewDevices.Count

    if ($null -eq $Index) {
        Pause-Toolkit
        return
    }

    $SelectedDevice = $NewDevices[$Index]

    $DriverInfo = Get-SignedDriverInfo $SelectedDevice.InstanceId

    Export-DriverPackage $SelectedDevice $DriverInfo

    Pause-Toolkit
}

function Install-Driver {

    Clear-Host

    $Drivers = @(Get-ChildItem -LiteralPath $DriversRoot -Directory)

    if ($Drivers.Count -eq 0) {

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

    $Index = Read-Selection "Select package" $Drivers.Count

    if ($null -eq $Index) {
        Pause-Toolkit
        return
    }

    $Selected = $Drivers[$Index]
    $DriverFilesFolder = Join-Path $Selected.FullName "DriverFiles"

    $INFFiles = @(Get-ChildItem -LiteralPath $DriverFilesFolder -Filter *.inf -Recurse -ErrorAction SilentlyContinue)

    if ($INFFiles.Count -eq 0) {

        Write-Host ""
        Write-Host "No .inf files found in $DriverFilesFolder" -ForegroundColor Yellow
        Write-Host "This package has no exportable driver files."

        Pause-Toolkit
        return
    }

    Write-Host ""
    Write-Host "Installing Driver..."
    Write-Host ""

    & pnputil.exe /add-driver "$DriverFilesFolder\*.inf" /subdirs /install

    Write-Host ""

    switch ($LASTEXITCODE) {
        0       { Write-Host "Driver installed successfully." -ForegroundColor Green }
        3010    { Write-Host "Driver installed. A reboot is required to finish." -ForegroundColor Yellow }
        default { Write-Host "pnputil finished with exit code $LASTEXITCODE. Review the output above." -ForegroundColor Yellow }
    }

    Pause-Toolkit
}

function View-Repository {

    Clear-Host

    $Folders = @(Get-ChildItem -LiteralPath $DriversRoot -Directory)

    if ($Folders.Count -eq 0) {

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

        if (Test-Path -LiteralPath $SummaryFile) {

            $Lines = @(Get-Content -LiteralPath $SummaryFile)

            for ($i = 0; $i -lt $Lines.Count - 1; $i++) {

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

    Write-Host "Enumerating Installed Third-Party Drivers..."
    Write-Host ""

    # Only third-party (oemNN.inf) packages can be exported; inbox Windows
    # drivers would just clutter the list.
    $Drivers = @(Get-CimInstance Win32_PnPSignedDriver |
        Where-Object { $_.DeviceName -and $_.InfName -match '^oem\d+\.inf$' } |
        Sort-Object DeviceName)

    if ($Drivers.Count -eq 0) {

        Write-Host "No third-party drivers found."

        Pause-Toolkit
        return
    }

    for ($i = 0; $i -lt $Drivers.Count; $i++) {

        $Driver = $Drivers[$i]

        Write-Host "$($i+1). $($Driver.DeviceName)  [$($Driver.DriverProviderName) $($Driver.DriverVersion)]"
    }

    Write-Host ""

    $Index = Read-Selection "Select Driver" $Drivers.Count

    if ($null -eq $Index) {
        Pause-Toolkit
        return
    }

    $Driver = $Drivers[$Index]

    $PnpDevice = Get-PnpDevice -InstanceId $Driver.DeviceID -ErrorAction SilentlyContinue

    $Device = [PSCustomObject]@{
        FriendlyName = $Driver.DeviceName
        Manufacturer = $Driver.Manufacturer
        Status       = if ($PnpDevice) { $PnpDevice.Status } else { "Installed" }
        Class        = $Driver.DeviceClass
        InstanceId   = $Driver.DeviceID
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

    (Read-Host "Selection").Trim()
}

do {

    $Choice = Show-Menu

    try {
        switch ($Choice) {

            "1" { Capture-NewDevice -USBOnly $true }

            "2" { Capture-NewDevice -USBOnly $false }

            "3" { Install-Driver }

            "4" { View-Repository }

            "5" { Extract-InstalledDriver }
        }
    }
    catch {
        Write-Host ""
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Pause-Toolkit
    }

} while ($Choice -ne "6")
