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
| 1 | Capture New USB Device | Waits for a USB device to be plugged in, then exports its driver |
| 2 | Capture Any New Device | Same as option 1, but for any Plug and Play device |
| 3 | Install Exported Driver | Installs a driver package from the repository |
| 4 | View Driver Repository | Lists every saved driver with its version and INF |
| 5 | Extract Installed Driver | Exports the driver of a device that is already installed |
| 6 | Exit | Closes the toolkit |

### 1. Capture New USB Device

Waits for a newly connected USB device and records:

- Device name, manufacturer, class, and status
- Hardware IDs and compatible IDs
- Driver provider, version, and date
- INF name and driver service

It then exports the driver package, generates an install script, and zips everything into a portable backup.

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

- Lists every package in the repository
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

## How It Works

### Device Capture

Options 1 and 2 only capture devices that appear **after** monitoring starts. Docks, keyboards, and other peripherals that are already connected are ignored.

```text
Start monitoring
      ↓
Take a snapshot of connected devices
      ↓
Plug in the device
      ↓
Detect new devices (waits up to 2 minutes; press any key to cancel)
      ↓
Wait for Windows to finish installing the driver
      ↓
Choose a device
      ↓
Export the driver package
```

### Multiple Devices

Some hardware installs several devices at once. For example, a dock might add:

```text
Dell Dock USB Hub
Dell Dock Audio
Dell Dock Ethernet Adapter
```

The toolkit lists every new device and lets you pick the one to capture.

### Driver Export

Drivers are exported with `pnputil /export-driver`, the Microsoft-supported way to copy a package out of the Driver Store. PnPUtil maps the published name Windows gives the driver (such as `oem45.inf`) to the correct Driver Store folder and exports the full package.

Built-in Windows drivers (such as `usb.inf` or `msports.inf`) can't be exported, because they ship with Windows. When a device uses one, the summary says so and no files are exported.

### Tips

- If a capture reports **No driver is installed for this device yet**, Windows was still installing it. Wait a minute, then use option 5.
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
