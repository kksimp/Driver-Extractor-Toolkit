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
    $SummaryFile = Join-Path $DeviceFolder "DriverSummary.txt"
    $InstallCMD = Join-Path $DeviceFolder "InstallDriver.cmd"
    $ZipFile = Join-Path $DeviceFolder "DriverBackup.zip"

    # Start clean so a re-capture never mixes files from an older driver
    # version, or leaves an old installer behind if this export fails.
    foreach ($OldItem in $DriverFilesFolder, $InstallCMD, $ZipFile) {
        if (Test-Path -LiteralPath $OldItem) {
            Remove-Item -LiteralPath $OldItem -Recurse -Force
        }
    }

    New-Item -ItemType Directory -Path $DeviceFolder -Force | Out-Null
    New-Item -ItemType Directory -Path $DriverFilesFolder -Force | Out-Null

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

    # Nothing to install (built-in driver, or no driver yet): keep the
    # device info only, without an empty installer and ZIP.
    if ($ExportError) {

        Remove-Item -LiteralPath $DriverFilesFolder -Recurse -Force

        Write-Host ""
        Write-Host "Device Info Saved (no driver files to export)"
        Write-Host "Output Folder:"
        Write-Host $DeviceFolder
        Write-Host ""

        return
    }

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

# Device scans are slow (Windows device queries can take a second or more
# each), so capture runs them in a background runspace and keeps the screen
# free to respond to key presses. Queries are batched to keep scans short.
$DeviceScanScript = {

    param(
        $Baseline,
        [bool]$USBOnly,
        $UsbCache
    )

    function Get-PropertyMap {

        param(
            [string[]]$Ids,
            [string]$KeyName
        )

        $Map = @{}

        if ($Ids.Count -eq 0) {
            return $Map
        }

        foreach ($Property in Get-PnpDeviceProperty -InstanceId $Ids -KeyName $KeyName -ErrorAction SilentlyContinue) {
            $Map[$Property.InstanceId] = $Property.Data
        }

        return $Map
    }

    $Present = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue)

    $New = @($Present | Where-Object {
        !$Baseline.ContainsKey($_.InstanceId)
    })

    if ($USBOnly) {

        # Walk up the device tree (one batched lookup per level) so child
        # devices of a USB device, such as COM ports and HID interfaces,
        # count as USB too. Results are cached between scans.
        $Ancestor = @{}

        foreach ($Device in $New) {
            if (!$UsbCache.ContainsKey($Device.InstanceId)) {
                $Ancestor[$Device.InstanceId] = $Device.InstanceId
            }
        }

        for ($Depth = 0; $Depth -lt 6 -and $Ancestor.Count -gt 0; $Depth++) {

            foreach ($Id in @($Ancestor.Keys)) {
                if ($Ancestor[$Id] -match '^USB') {
                    $UsbCache[$Id] = $true
                    $Ancestor.Remove($Id)
                }
            }

            $Parents = Get-PropertyMap @($Ancestor.Values | Select-Object -Unique) 'DEVPKEY_Device_Parent'

            foreach ($Id in @($Ancestor.Keys)) {
                if ($Parents[$Ancestor[$Id]]) {
                    $Ancestor[$Id] = $Parents[$Ancestor[$Id]]
                }
                else {
                    $UsbCache[$Id] = $false
                    $Ancestor.Remove($Id)
                }
            }
        }

        foreach ($Id in $Ancestor.Keys) {
            $UsbCache[$Id] = $false
        }

        $New = @($New | Where-Object {
            $UsbCache[$_.InstanceId]
        })
    }

    $InfPaths = Get-PropertyMap @($New | ForEach-Object { $_.InstanceId }) 'DEVPKEY_Device_DriverInfPath'

    $Devices = foreach ($Device in $New) {

        $INF = $InfPaths[$Device.InstanceId]

        $Label = if (!$INF) {
            "no driver yet"
        }
        elseif ($INF -match '^oem\d+\.inf$') {
            "$INF, third-party"
        }
        else {
            "$INF, built-in Windows driver"
        }

        [PSCustomObject]@{
            Device = $Device
            Label  = $Label
        }
    }

    [PSCustomObject]@{
        PresentIds = @($Present | ForEach-Object { $_.InstanceId })
        Devices    = @($Devices)
    }
}

# One background runspace is reused for the whole session
$DeviceScanner = $null
$DeviceScanPending = $null

function Start-DeviceScan {

    param(
        [hashtable]$Baseline,
        [bool]$USBOnly,
        $UsbCache
    )

    if (!$script:DeviceScanner) {
        $script:DeviceScanner = [powershell]::Create()
        $script:DeviceScanner.Runspace = [runspacefactory]::CreateRunspace()
        $script:DeviceScanner.Runspace.Open()
    }

    $script:DeviceScanner.Commands.Clear()

    [void]$script:DeviceScanner.AddScript($DeviceScanScript).
        AddArgument($Baseline.Clone()).
        AddArgument($USBOnly).
        AddArgument($UsbCache)

    $script:DeviceScanPending = $script:DeviceScanner.BeginInvoke()
}

function Receive-DeviceScan {

    # Returns the scan result, or $null if the scan failed
    $Pending = $script:DeviceScanPending
    $script:DeviceScanPending = $null

    try {
        return ($script:DeviceScanner.EndInvoke($Pending) | Select-Object -Last 1)
    }
    catch {
        return $null
    }
}

function Get-SelectionIndexes {

    # Turns "1" or "1,3" into zero-based indexes. Returns an empty list and
    # prints a warning if anything is out of range or not a number.
    param(
        [string]$Text,
        [int]$Max
    )

    $Indexes = @()

    foreach ($Part in ($Text -split ',')) {

        $Number = 0

        if (![int]::TryParse($Part.Trim(), [ref]$Number) -or $Number -lt 1 -or $Number -gt $Max) {
            Write-Host ""
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
    $SelectPrompt = "Select device(s), e.g. 1 or 1,3 (Q = main menu): "

    Clear-Host
    Write-Host "Taking a snapshot of connected devices..."

    # A scan left running by a previous capture has stale results; discard it
    if ($script:DeviceScanPending) {
        Receive-DeviceScan | Out-Null
    }

    # Everything present now is ignored. A device that is unplugged while
    # watching drops out of this baseline, so plugging it back in counts as new.
    $Baseline = @{}

    foreach ($Device in Get-PnpDevice -PresentOnly) {
        $Baseline[$Device.InstanceId] = $true
    }

    $UsbCache = [hashtable]::Synchronized(@{})
    $Order = @()
    $NewDevices = @()
    $Labels = @()
    $Indexes = @()
    $Typed = ""
    $LastScreen = $null
    $NextScan = Get-Date

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

        if (!$script:DeviceScanPending -and (Get-Date) -ge $NextScan) {
            Start-DeviceScan $Baseline $USBOnly $UsbCache
        }

        if ($script:DeviceScanPending -and $script:DeviceScanPending.IsCompleted) {

            $Result = Receive-DeviceScan
            $NextScan = (Get-Date).AddSeconds(1)

            # An empty device list means the scan failed; keep the old results
            if ($Result -and $Result.PresentIds.Count -gt 0) {

                $PresentIds = @{}

                foreach ($Id in $Result.PresentIds) {
                    $PresentIds[$Id] = $true
                }

                foreach ($Id in @($Baseline.Keys)) {
                    if (!$PresentIds.ContainsKey($Id)) {
                        $Baseline.Remove($Id)
                    }
                }

                # Keep devices in the order they first appeared, so the
                # numbers don't shift while someone is typing a selection.
                $Found = @{}

                foreach ($Entry in $Result.Devices) {
                    $Found[$Entry.Device.InstanceId] = $Entry
                }

                $Order = @($Order | Where-Object { $Found.ContainsKey($_) })

                foreach ($Entry in $Result.Devices) {
                    if ($Order -notcontains $Entry.Device.InstanceId) {
                        $Order += $Entry.Device.InstanceId
                    }
                }

                $NewDevices = @($Order | ForEach-Object { $Found[$_].Device })
                $Labels = @($Order | ForEach-Object { $Found[$_].Label })
            }
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

            $Lines += "$($i+1). $DisplayName  [$($Labels[$i])]"
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
            Write-Host "Wait until the device you want shows its driver, then type its number."
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

                if ($Lines.Count -eq 0) {
                    Write-Host "[Q] Return to main menu" -ForegroundColor Cyan
                }
                else {
                    # Re-show anything already typed after a redraw
                    Write-Host $SelectPrompt -ForegroundColor Cyan -NoNewline
                    Write-Host $Typed -NoNewline
                }
            }

            $LastScreen = $Screen
        }

        if ($LiveKeys) {

            if (![Console]::KeyAvailable) {
                Start-Sleep -Milliseconds 100
                continue
            }

            $KeyInfo = [Console]::ReadKey($true)

            if ($KeyInfo.Key -eq 'Q' -or $KeyInfo.Key -eq 'Escape') {
                # Any scan still running finishes in the background and is
                # discarded by the next capture, so leaving is instant.
                return
            }

            # Nothing to select until a device shows up
            if ($NewDevices.Count -eq 0) {
                continue
            }

            if ($KeyInfo.Key -eq 'Backspace') {
                if ($Typed.Length -gt 0) {
                    $Typed = $Typed.Substring(0, $Typed.Length - 1)
                    Write-Host "`b `b" -NoNewline
                }
                continue
            }

            if ($KeyInfo.KeyChar -match '[0-9, ]') {
                $Typed += $KeyInfo.KeyChar
                Write-Host $KeyInfo.KeyChar -NoNewline
                continue
            }

            if ($KeyInfo.Key -ne 'Enter' -or !$Typed.Trim()) {
                continue
            }

            $Answer = $Typed
            $Typed = ""
        }
        else {

            $Answer = Read-Host "Type device number(s), e.g. 1 or 1,3. Press Enter to refresh, Q = main menu"
            $LastScreen = $null

            if ($Answer -match '^\s*q') {
                return
            }

            if (!$Answer.Trim() -or $NewDevices.Count -eq 0) {
                continue
            }
        }

        $Indexes = @(Get-SelectionIndexes $Answer $NewDevices.Count)

        if ($Indexes.Count -gt 0) {
            Write-Host ""
            break
        }

        # Invalid input: pause briefly, then go back to watching
        Start-Sleep -Seconds 2
        $LastScreen = $null
    }

    $Selected = @($Indexes | ForEach-Object { $NewDevices[$_] })

    foreach ($SelectedDevice in $Selected) {

        Write-Host ""
        Write-Host "Capturing $($SelectedDevice.FriendlyName)..."

        $DriverInfo = Get-SignedDriverInfo $SelectedDevice.InstanceId

        Export-DriverPackage $SelectedDevice $DriverInfo
    }

    Pause-Toolkit
}

function Install-Driver {

    Clear-Host

    # Skip info-only captures (built-in drivers), which have nothing to install
    $Drivers = @(Get-ChildItem -LiteralPath $DriversRoot -Directory | Where-Object {
        Test-Path -LiteralPath (Join-Path $_.FullName "DriverFiles")
    })

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

        if (!(Test-Path -LiteralPath (Join-Path $Folder.FullName "DriverFiles"))) {
            Write-Host "   Info only (no driver files)" -ForegroundColor DarkGray
        }

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
