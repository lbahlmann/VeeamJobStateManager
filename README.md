# Veeam Job State Manager

**Save, disable, and restore Veeam Backup job states during updates/upgrades.**

A PowerShell GUI tool that solves a common problem: before a Veeam update, all jobs must be disabled. After the update, you need to know exactly which jobs were enabled before -- and which were already disabled. This tool saves the complete job state, disables everything, and restores the original state after the update.

> Developed by [badata GmbH](https://www.badata.de) -- IT-Systemhaus aus Verden/Aller

## The Problem

When updating Veeam Backup & Replication, all backup jobs must be stopped and disabled. Customers with many jobs have a mix of enabled and disabled jobs. If you disable everything for the update, you lose track of which jobs were active before.

**Common workarounds fail:**
- Manually noting which jobs are enabled? Error-prone with 20+ jobs
- `Get-VBRJob | Disable-VBRJob`? No way to restore the original state
- Veeam's built-in "Maintenance Mode"? Only applies to SOBR extents, not jobs

## The Solution

![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue) ![Veeam](https://img.shields.io/badge/Veeam-v9--v12.3-green) ![License](https://img.shields.io/badge/License-MIT-yellow)

A single-file PowerShell script with a WPF GUI (Dark Theme) and three actions:

1. **SAVE** -- Document the current state of all jobs as JSON
2. **DISABLE ALL** -- Auto-save + disable all enabled jobs
3. **RESTORE** -- Restore the exact original state from a saved JSON file

```
1. Start VeeamJobManager_v1.2.0.ps1  (opens GUI)
2. Click SAVE                         --> saves job state to JSON
3. Click DISABLE ALL                  --> auto-saves + disables all active jobs
4. ... perform Veeam update ...
5. Click RESTORE                      --> restores original state
```

## Supported Job Types

The tool covers **all common Veeam job types** -- not just `Get-VBRJob`:

| Job Type | Cmdlet | Description |
|---|---|---|
| VBRJob | `Get-VBRJob` | VMware/Hyper-V Backup, Replication, File Copy |
| VBRTapeJob | `Get-VBRTapeJob` | Backup to Tape, File to Tape |
| VBRSureBackupJob | `Get-VBRSureBackupJob` | SureBackup (v12+, fallback to `Get-VSBJob`) |
| VBRBackupCopyJob | `Get-VBRBackupCopyJob` | Backup Copy (separate cmdlet since v12) |
| VBRComputerBackupJob | `Get-VBRComputerBackupJob` | Veeam Agent Backup |
| VBRComputerBackupCopyJob | `Get-VBRComputerBackupCopyJob` | Agent Backup Copy |
| VBRUnstructuredBackupJob | `Get-VBRUnstructuredBackupJob` | NAS/File Share Backup |
| VBRCDPPolicy | `Get-VBRCDPPolicy` | Continuous Data Protection |
| VBRPluginJob | `Get-VBRPluginJob` | Enterprise Apps (Oracle RMAN, SAP HANA) |

Missing cmdlets are detected automatically and skipped gracefully. The tool works across Veeam versions without configuration.

## Features

- **WPF GUI** with Dark Theme (Catppuccin color scheme)
- **Running job detection**: Offers to wait for active jobs to finish, then auto-disables them. UI stays responsive during wait (timer-based, 10s interval).
- **Abort detection**: If you close the window while waiting for running jobs, the state is saved as "Aborted". On next start, you get a warning with recovery instructions.
- **State file management**: Dropdown to select from multiple saved states, sorted by date
- **Persistent log file**: All actions logged to `VeeamJobManager_<FQDN>.log` with individual job details
- **Server validation**: Warns if restoring a state file from a different server
- **Single-file deployment**: One `.ps1` file, no installation, no dependencies beyond Veeam PowerShell

## Quick Start

```powershell
# Run directly on the Veeam Backup & Replication Server as Administrator
.\VeeamJobManager_v1.2.0.ps1
```

If execution policy blocks the script:
```powershell
powershell -ExecutionPolicy Bypass -File .\VeeamJobManager_v1.2.0.ps1
```

## Requirements

- Windows PowerShell 5.1+
- Veeam Backup & Replication Server (run directly on the server)
- Administrator privileges
- Veeam PowerShell Module (v11+) or Snap-in (v9/v10) -- auto-detected

## Compatibility

| Veeam Version | Module/Snap-in | Status |
|---|---|---|
| v9, v10 | PSSnapin (VeeamPSSnapIn) | Supported |
| v11 | PowerShell Module | Supported |
| v12 -- v12.3 | PowerShell Module | Supported + extended job types |

## Known Quirks

- **Tape Jobs**: Veeam has no `Disable-VBRTapeJob` / `Enable-VBRTapeJob` cmdlets. The tool uses `Disable-VBRJob` / `Enable-VBRJob` which work for tape jobs too.
- **Backup Copy Jobs**: Since Veeam v12, backup copy jobs have their own cmdlet (`Get-VBRBackupCopyJob`). In older versions they are included in `Get-VBRJob`. The tool handles both.
- **NAS Backup Jobs**: The cmdlet name changed from `Get-VBRNASBackupJob` (v10/v11) to `Get-VBRUnstructuredBackupJob` (v12+). The tool tries both automatically.

## State File Format

State files are saved as JSON in the script directory:

```
VeeamJobState_<FQDN>_<yyyy-MM-dd_HHmm>.json
```

```json
{
  "SavedAt": "2026-03-20 10:21:54",
  "ServerName": "veeam-srv.domain.local",
  "JobCount": 21,
  "Status": "Complete",
  "Jobs": [
    {
      "Name": "Daily Backup",
      "Id": "...",
      "Type": "Hyper-V Backup",
      "IsEnabled": true,
      "JobKind": "VBRJob"
    }
  ]
}
```

## License

MIT License -- see [LICENSE](LICENSE)

## Author

**Lars Bahlmann**
[badata GmbH](https://www.badata.de) -- IT-Systemhaus aus Verden/Aller

---

*If you find this tool useful, consider giving it a star and sharing it with fellow Veeam admins.*
