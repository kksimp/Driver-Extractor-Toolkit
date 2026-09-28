# Driver Extractor Toolkit

A portable PowerShell utility for capturing, backing up, organizing, and reinstalling Windows drivers.

Built for IT technicians who deal with hard-to-find drivers: printers, scanners, USB serial adapters, dealership diagnostic equipment, label printers, specialty USB devices, legacy hardware, and anything else that can be difficult or impossible to find again later.

## Contents

- [Quick Start](#quick-start)
- [Menu Options](#menu-options)
- [Repository Structure](#repository-structure)
- [Output Files](#output-files)
- [How It Works](#how-it-works)
- [Requirements](#requirements)
- [Use Cases](#use-cases)
- [Roadmap](#roadmap)
- [License](#license)

## Quick Start

1. Download `Driver-Extractor-Toolkit.ps1` into its own folder (a USB stick or network share works well).
2. If the file came from the internet, unblock it:

   ```powershell
   Unblock-File .\Driver-Extractor-Toolkit.ps1
   ```

3. Open PowerShell **as Administrator** and run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Driver-Extractor-Toolkit.ps1
   ```

A `Drivers` folder is created next to the script the first time it runs. Every captured driver is saved there.

## Menu Options

| # | Option | What it does |
|---|--------|--------------|
| 1 | Capture New USB Device | Watches for USB devices being plugged in, then exports the drivers you pick |
| 2 | Capture Any New Device | Same as option 1, but for any Plug and Play device |
| 3 | Install Exported Driver | Installs a driver package from the repository |
| 4 | View Driver Repository | Lists every saved driver with its version and INF |
| 5 | Extract Installed Driver | Exports the driver of a device that is already installed |
| 6 | Exit | Closes the toolkit |

### 1. Capture New USB Device

Watches for newly connected USB devices. There is no time limit: the screen updates live as devices appear, showing each device's driver status. When the device you want shows its driver, just type its number and press **Enter**. Pick several at once with commas (for example `1,3`). Press **Q** at any time to return to the main menu.

Devices keep their numbers while you watch: a newly detected device is always added to the bottom of the list.

```text
=========================================
 CAPTURE NEW USB DEVICE
=========================================

New Devices Detected
--------------------
1. USB Serial Converter  [oem45.inf, third-party]
2. USB Serial Port (COM3)  [oem46.inf, third-party]

Select device(s), e.g. 1 or 1,3 (Q = main menu): 2
```

For each selected device it records:

- Device name, manufacturer, class, and status
- Hardware IDs and compatible IDs
- Driver provider, version, and date
- INF name and driver service

It then exports the driver package, generates an install script, and zips everything into a portable backup. If the device uses a built-in Windows driver, only the device information is saved (see [Info-Only Captures](#info-only-captures)).

Child devices created by a USB device (for example the COM port of a USB serial adapter, or the HID interface of a scanner) are also listed, so you can capture the exact device whose driver you need.

### 2. Capture Any New Device

Works like option 1 but watches all Plug and Play devices, not only USB. Use it for:

- PCI and PCIe cards
- Bluetooth adapters
- Docking stations
- Network and graphics adapters
- Unknown devices

### 3. Install Exported Driver

Installs a saved driver on the current machine.

- Lists every package that has driver files (info-only captures are skipped)
- Installs with Microsoft PnPUtil
- Supports packages that contain multiple INF files
- Reports success, failure, or a required reboot

### 4. View Driver Repository

Shows a quick inventory of saved drivers:

```text
1. USB Serial Converter
   Version: 2.12.36.4
   INF: oem45.inf

2. Zebra Printer
   Version: 8.6.5.0
   INF: oem112.inf

3. USB Mass Storage Device
   Version: 10.0.22621.1
   INF: usbstor.inf
   Info only (no driver files)
```

### 5. Extract Installed Driver

Exports the driver of a device that is already installed. It lists third-party drivers only, since built-in Windows drivers already ship with every copy of Windows.

Useful when:

- The hardware is no longer available
- The device is built into the system
- You want to preserve drivers before rebuilding a computer
- Vendor downloads are no longer available

## Repository Structure

```text
Driver Extractor Toolkit
├── Driver-Extractor-Toolkit.ps1
└── Drivers
    ├── Zebra Printer
    │   ├── DriverSummary.txt
    │   ├── InstallDriver.cmd
    │   ├── DriverBackup.zip
    │   └── DriverFiles\
    └── USB Serial Converter
        ├── DriverSummary.txt
        ├── InstallDriver.cmd
        ├── DriverBackup.zip
        └── DriverFiles\
```

## Output Files

Each captured driver gets its own folder containing the files below.

### DriverSummary.txt

A plain-text record of the device and its driver:

| Field | Field |
|-------|-------|
| Capture Date | Driver Provider |
| Computer Name | Driver Version |
| Device Name | Driver Date |
| Manufacturer | INF Name |
| Status | Service Name |
| Class | Hardware IDs |
| Instance ID | Compatible IDs |

It ends with an export result saying whether the driver files were exported, and why not if they weren't.

Example:

```text
===========================================
 DRIVER CAPTURE SUMMARY
===========================================

Capture Date:
9/28/2026 09:15 AM

Device Name:
USB Serial Converter

Manufacturer:
FTDI

Status:
OK

Class:
USB

Instance ID:
USB\VID_0403&PID_6001\A50285BI

-------------------------------------------
DRIVER DETAILS
-------------------------------------------

Driver Provider:
FTDI

Driver Version:
2.12.36.4

Driver Date:
3/15/2024

INF:
oem45.inf

Service:
FTDIBUS

-------------------------------------------
HARDWARE IDS
-------------------------------------------
USB\VID_0403&PID_6001&REV_0600
USB\VID_0403&PID_6001

-------------------------------------------
EXPORT RESULT
-------------------------------------------

Driver Files Exported: YES
```

### DriverFiles

The complete driver package, exported from the Windows Driver Store with `pnputil /export-driver`. It typically contains:

```text
*.inf    Setup information file
*.sys    Driver binaries
*.cat    Signed catalog file
*.dll    Supporting libraries
```

### InstallDriver.cmd

A generated install script. Right-click it and choose **Run as administrator** to install the driver on another machine without the toolkit.

```bat
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
```

### DriverBackup.zip

A portable archive containing:

```text
DriverSummary.txt
InstallDriver.cmd
DriverFiles\
```

Copy it to a network share, OneDrive, a technician toolkit, or long-term storage. Extract it anywhere and run `InstallDriver.cmd` to install.

### Info-Only Captures

When a device uses a built-in Windows driver, or has no driver installed yet, there is nothing to install. The toolkit still saves `DriverSummary.txt` with the device details and hardware IDs, but skips `DriverFiles`, `InstallDriver.cmd`, and `DriverBackup.zip`.

```text
Drivers
└── USB Mass Storage Device
    └── DriverSummary.txt
```

The hardware IDs in the summary are still useful for tracking down a vendor driver later.

## How It Works

### Device Capture

Options 1 and 2 only capture devices that appear **after** monitoring starts. Docks, keyboards, and other peripherals that are already connected are ignored. If the device you want is already plugged in, unplug it and plug it back in while the toolkit is watching.

```text
Start monitoring
      ↓
Take a snapshot of connected devices
      ↓
Plug in the device (as many as you like)
      ↓
New devices appear on screen with their driver status
      ↓
Wait until the driver shows
      ↓
Type the device number(s) and press Enter
      ↓
Export the driver packages
```

### Multiple Devices

Some hardware installs several devices at once. For example, a dock might add:

```text
Dell Dock USB Hub
Dell Dock Audio
Dell Dock Ethernet Adapter
```

The toolkit lists every new device and lets you pick the ones to capture.

### Driver Export

Drivers are exported with `pnputil /export-driver`, the Microsoft-supported way to copy a package out of the Driver Store. PnPUtil maps the published name Windows gives the driver (such as `oem45.inf`) to the correct Driver Store folder and exports the full package.

Built-in Windows drivers (such as `usb.inf` or `msports.inf`) can't be exported, because they ship with Windows. When a device uses one, the summary says so and no files are exported.

### Driver Status Labels

| Label | Meaning |
|-------|---------|
| `oem45.inf, third-party` | A vendor driver. This is what the toolkit exports. |
| `usbstor.inf, built-in Windows driver` | Ships with Windows. Only device info is saved. |
| `no driver yet` | Windows is still installing the driver. Keep waiting. |

### Tips

- Wait until the device shows a driver before selecting it. First-time installs, especially from Windows Update, can take a minute or more.
- USB flash drives and most keyboards and mice use built-in Windows drivers. They are good for checking that detection works, but only their device info is saved.
- Many devices create more than one entry. A USB serial adapter, for example, shows both the USB device and its COM port, often with separate drivers. Select both (such as `1,2`) to keep the full set.
- Running in the PowerShell ISE? Live key presses aren't supported there, so the capture screen asks you to type the device number(s), press Enter to refresh, or type **Q** to return instead. A regular PowerShell window is recommended.
- If Windows installs a generic driver, install the vendor driver first, then capture.
- Capturing the same device again replaces its previous export.

## Requirements

- Windows 10 (version 1607 or later) or Windows 11
- Windows PowerShell 5.1 or PowerShell 7+
- Administrator privileges

## Use Cases

| Scenario | Why it helps |
|----------|--------------|
| Enterprise IT | Archive drivers before reimaging systems |
| Help desk | Quickly preserve hard-to-find drivers from user computers |
| Printers | Capture manufacturer drivers for future deployment |
| Scanners | Archive barcode and specialty scanner drivers |
| USB serial adapters | Preserve FTDI, Prolific, and manufacturer-specific drivers |
| Automotive diagnostics | Store dealership and OEM diagnostic interface drivers |
| Industrial equipment | Preserve drivers for devices with limited manufacturer support |
| Legacy hardware | Archive drivers before vendor downloads disappear |

## Why This Exists

Finding drivers years after a device was deployed can be difficult or impossible.

Driver Extractor Toolkit builds a portable, organized driver repository directly from a working Windows installation. Rare and hard-to-find drivers become easy to archive, transfer, and reinstall on future systems.

## Roadmap

Possible future improvements:

- Search drivers by VID/PID
- Tag driver packages
- Export and import the whole repository
- CSV inventory reports
- Automatic driver verification
- Device Manager screenshot capture
- Deduplicate driver packages
- Silent installation mode
- Driver package integrity validation

## License

Use, modify, and distribute as needed.

No warranty is provided. Test all driver installations in line with your organization's change management and deployment policies.
