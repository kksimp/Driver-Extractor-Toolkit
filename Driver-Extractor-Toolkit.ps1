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

function Get-DriverLabel {

    param([string]$InstanceId)

    try {
        $INF = (Get-PnpDeviceProperty `
            -InstanceId $InstanceId `
            -KeyName DEVPKEY_Device_DriverInfPath).Data
    }
    catch {
        $INF = $null
    }

    if (!$INF) {
        return "no driver yet"
    }

    if ($INF -match '^oem\d+\.inf$') {
        return "$INF, third-party"
    }

    return "$INF, built-in Windows driver"
}

function Read-MultiSelection {

    param(
        [string]$Prompt,
        [int]$Max
    )

    $Indexes = @()

    foreach ($Part in ((Read-Host $Prompt) -split ',')) {

        $Number = 0

        if (![int]::TryParse($Part.Trim(), [ref]$Number) -or $Number -lt 1 -or $Number -gt $Max) {
            Write-Host "Invalid selection: '$($Part.Trim())'" -ForegroundColor Yellow
            return @()
        }

        if ($Indexes -notcontains ($Number - 1)) {
            $Indexes += $Number - 1
        }
    }

    return $Indexes
}

function Capture-NewDevice {

    param(
        [bool]$USBOnly = $true
    )

    $Title = if ($USBOnly) { "CAPTURE NEW USB DEVICE" } else { "CAPTURE ANY NEW DEVICE" }

    # Everything present now is ignored. A device that is unplugged while
    # watching drops out of this baseline, so plugging it back in counts as new.
    $Baseline = @{}

    foreach ($Device in Get-PnpDevice -PresentOnly) {
        $Baseline[$Device.InstanceId] = $true
    }

    $UsbCache = @{}
    $LastScreen = $null

    # [Console]::KeyAvailable does not work in the PowerShell ISE, so fall
    # back to Read-Host prompts there.
    $LiveKeys = $true

    try {
        while ([Console]::KeyAvailable) {
            [Console]::ReadKey($true) | Out-Null
        }
    }
    catch {
        $LiveKeys = $false
    }

    while ($true) {

        $Present = @(Get-PnpDevice -PresentOnly)
        $PresentIds = @{}

        foreach ($Device in $Present) {
            $PresentIds[$Device.InstanceId] = $true
        }

        foreach ($Id in @($Baseline.Keys)) {
            if (!$PresentIds.ContainsKey($Id)) {
                $Baseline.Remove($Id)
            }
        }

        $NewDevices = @($Present | Where-Object {
            !$Baseline.ContainsKey($_.InstanceId)
        })

        if ($USBOnly) {
            $NewDevices = @($NewDevices | Where-Object {
                if (!$UsbCache.ContainsKey($_.InstanceId)) {
                    $UsbCache[$_.InstanceId] = Test-IsUsbDevice $_.InstanceId
                }
                $UsbCache[$_.InstanceId]
            })
        }

        $Lines = @()

        for ($i = 0; $i -lt $NewDevices.Count; $i++) {

            $Device = $NewDevices[$i]

            $DisplayName = if ($Device.FriendlyName) {
                $Device.FriendlyName
            }
            else {
                $Device.InstanceId
            }

            $Lines += "$($i+1). $DisplayName  [$(Get-DriverLabel $Device.InstanceId)]"
        }

        # Only redraw when something changed, so the screen doesn't flicker
        $Screen = $Lines -join "`n"

        if ($Screen -ne $LastScreen) {

            Clear-Host

            Write-Host "========================================="
            Write-Host " $Title"
            Write-Host "========================================="
            Write-Host ""
            Write-Host "Plug in the device now. If it is already plugged in, unplug it and plug it back in."
            Write-Host "Wait until the device you want shows its driver, then press Enter to select it."
            Write-Host ""

            if ($Lines.Count -eq 0) {
                Write-Host "Watching for new devices..." -ForegroundColor Cyan
            }
            else {
                Write-Host "New Devices Detected"
                Write-Host "--------------------"

                foreach ($Line in $Lines) {
                    Write-Host $Line
                }
            }

            Write-Host ""

            if ($LiveKeys) {
                Write-Host "[Enter] Select device    [Q] Return to main menu" -ForegroundColor Cyan
            }

            $LastScreen = $Screen
        }

        $Action = $null

        if ($LiveKeys) {

            # Listen for keys for ~2 seconds, then refresh the device list
            $Until = (Get-Date).AddSeconds(2)

            while (!$Action -and (Get-Date) -lt $Until) {

                if ([Console]::KeyAvailable) {

                    $Key = [Console]::ReadKey($true).Key

                    if ($Key -eq 'Q' -or $Key -eq 'Escape') {
                        $Action = "Quit"
                    }
                    elseif ($Key -eq 'Enter') {
                        $Action = "Select"
                    }
                }
                else {
                    Start-Sleep -Milliseconds 100
                }
            }
        }
        else {

            $Answer = Read-Host "Press Enter to refresh, S to select a device, Q to return to main menu"

            if ($Answer -match '^\s*q') {
                $Action = "Quit"
            }
            elseif ($Answer -match '^\s*s') {
                $Action = "Select"
            }

            $LastScreen = $null
        }

        if ($Action -eq "Quit") {
            return
        }

        if ($Action -eq "Select") {

            if ($NewDevices.Count -eq 0) {
                continue
            }

            Write-Host ""

            $Indexes = @(Read-MultiSelection "Select device(s), e.g. 1 or 1,3" $NewDevices.Count)

            if ($Indexes.Count -gt 0) {
                break
            }

            # Invalid input: pause briefly, then go back to watching
            Start-Sleep -Seconds 2
            $LastScreen = $null
        }
    }

    foreach ($Index in $Indexes) {

        $SelectedDevice = $NewDevices[$Index]

        $DriverInfo = Get-SignedDriverInfo $SelectedDevice.InstanceId

        Export-DriverPackage $SelectedDevice $DriverInfo
    }

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
