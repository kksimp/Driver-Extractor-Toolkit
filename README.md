# Driver Extractor Toolkit

A portable PowerShell utility for capturing, backing up, organizing, and reinstalling Windows drivers.

Designed for IT technicians who regularly deal with hard-to-find drivers for printers, scanners, USB serial adapters, dealership diagnostic equipment, label printers, specialty USB devices, legacy hardware, and other devices that can be difficult or impossible to locate later.

---

## Features

### 1. Capture New USB Device

Monitors for newly connected USB devices and captures:

- Device information
- Hardware IDs
- Compatible IDs
- Driver version
- Driver provider
- Driver date
- INF file name
- Driver service information

The tool then:

- Copies the associated driver package from the Windows Driver Store
- Creates a portable installation package
- Archives everything into a ZIP file

---

### 2. Capture Any New Device

Works like USB capture but monitors all Plug-and-Play devices.

Useful for:

- PCI devices
- Bluetooth adapters
- Docking stations
- Network adapters
- Graphics adapters
- Unknown devices
- USB devices

This option is helpful when the target hardware is not technically a USB device.

---

### 3. Install Exported Driver

Installs previously exported drivers directly from the repository.

Features:

- Lists available driver packages
- Uses Microsoft PnPUtil for installation
- Supports multi-INF packages
- Works from exported DriverFiles folders

---

### 4. View Driver Repository

Provides a quick inventory of the driver repository.

Displays:

- Driver package name
- Driver version
- INF file name

Example:

```text
1. USB Serial Converter
   Version: 2.12.36.4
   INF: oem45.inf

2. Zebra Printer
   Version: 8.6.5.0
   INF: oem112.inf
```

---

### 5. Extract Installed Driver

Extracts drivers from devices already installed on the machine.

Perfect for situations where:

- The hardware is no longer available
- The device is built into the system
- You want to preserve drivers before rebuilding a computer
- Vendor downloads are unavailable

---

### 6. Exit

Closes the application.

---

# Repository Structure

```text
Driver Extractor
│
├── DriverToolkit.ps1
│
└── Drivers
    │
    ├── Zebra Printer
    │   ├── DriverSummary.txt
    │   ├── InstallDriver.cmd
    │   ├── DriverBackup.zip
    │   └── DriverFiles
    │
    └── USB Serial Converter
        ├── DriverSummary.txt
        ├── InstallDriver.cmd
        ├── DriverBackup.zip
        └── DriverFiles
```

---

# Output Files

Each exported driver package includes:

## DriverSummary.txt

Contains:

- Device Name
- Manufacturer
- Device Class
- Status
- Instance ID
- Driver Provider
- Driver Version
- Driver Date
- INF Name
- Service Name
- Hardware IDs
- Compatible IDs
- Capture Date

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
Ports

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
2024-03-15

INF:
oem45.inf

Service:
FTSER2K

-------------------------------------------
HARDWARE IDS
-------------------------------------------

USB\VID_0403&PID_6001
USB\VID_0403&PID_6001&REV_0600
```

---

## DriverFiles

Contains the exported driver package from the Windows Driver Store.

Typically includes:

```text
*.INF
*.SYS
*.CAT
DLL*Files
Supporting Files
``*

---

## InstallDriver.cmd

Autom*tically generated*installation script.

```*md
@echo off
echo Installing*Driver...
pnput*l /add-driver ".\DriverFiles**.inf" /subdirs /install
*ause
```

*--

## DriverBackup.zip

Portable *rchive containing:

```text
Driver*ummary.txt
InstallDriver.cmd
Drive*Files\
```

*his ZIP*file can be copied to network*shares, OneDrive, technician repos*tories, or archives.

---

# Techn*cal Notes

### USB*Monitoring*
The USB capture option only captu*es devices detected after monitori*g begins.

This prevents*existing dock devices and already*connected peripherals from being c*ptured accidentally.

Workflow:

`*`text
Start Monitoring
      ↓**ake Snapshot
      ↓
Plug In Devic*
      ↓*Detect New Device
      ↓
Choose*Device
      ↓*Export Driver Package
```

*--

### Multiple Device Detection
*Some hardware may install multiple*devices simultaneously.

Example:
*```text
*ell Dock USB Hub
Dell Dock Audio
D*ll Dock Ethernet Adapter
```

*he toolkit presents all newly dete*ted devices and*allows you to select which device *hould be captured.

---

# Require*ents

- Windows*10
- Windows 11
- Power*hell 5.1+
- Administrator privileg*s

---

# Recommended*Use Cases

### Enterprise*IT

Archive drivers before reimagi*g systems.

### Help Desk

Quickly*preserve*hard-to-find drivers from user com*uters.

### Printers

Capture*manufacturer*drivers*for future deployment.

### Sc*nners*
Archive barcode*scanner and specialty scanner driv*rs.

### USB Serial Adapters

Pres*rve FTDI, Prolific, and manufactur*r-specific drivers.

### Automotiv* Diagnostic Equipment

Store deale*ship and OEM diagnostic interface *rivers.

### Industrial Equipment
*Preserve drivers for devices with *imited manufacturer support.

### *egacy Hardware

Archive drivers be*ore vendor downloads disappear.

-*-

# Why This Exists

Finding driv*rs years after a device was deploy*d can be difficult or impossible.
*Driver Extractor Toolkit creates a*portable, organized driver reposit*ry directly from a working Windows*installation, making rare and hard*to-find drivers easy to archive, t*ansfer, and reinstall on future sy*tems.

---

#*Future Enhancements

Potential fut*re improvements include:

- Driver*search*by VID/PID
- Driver*package tagging
- Driver*repository export/import
- CSV*inventory*reports
- Automatic*driver verification
- Device*Manager*screenshot capture*- Driver package deduplication
- S*lent*installation*mode
- Driver package integrity va*idation

---

# License

Use, modi*y, and distribute as needed.

*o*warranty*is*provided.*Test*all*driver*installations in accordance*with your organization's change ma*agement and deployment policies.
`*``*