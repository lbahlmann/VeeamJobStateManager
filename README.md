# Veeam Job State Manager

**Job-Zustände sichern, deaktivieren und wiederherstellen bei Veeam Updates/Upgrades.**

Ein PowerShell-GUI-Tool, das ein häufiges Problem löst: Vor einem Veeam-Update müssen alle Jobs deaktiviert sein. Nach dem Update weiß man nicht mehr, welche Jobs vorher aktiv waren und welche bereits deaktiviert. Dieses Tool sichert den kompletten Job-Zustand, deaktiviert alles und stellt den Originalzustand nach dem Update exakt wieder her.

> Entwickelt von [badata GmbH](https://www.badata.de) -- IT-Systemhaus aus Verden/Aller

![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue) ![Veeam](https://img.shields.io/badge/Veeam-v9--v12.3-green) ![License](https://img.shields.io/badge/License-MIT-yellow)

## Das Problem

Bei einem Veeam-Update müssen alle Backup-Jobs gestoppt und deaktiviert sein. Kunden mit vielen Jobs haben einen Mix aus aktivierten und deaktivierten Jobs. Wenn man für das Update pauschal alle Jobs deaktiviert, ist danach nicht mehr nachvollziehbar, welche aktiv waren.

**Gängige Workarounds funktionieren nicht:**
- Manuell notieren welche Jobs aktiv sind? Fehleranfällig bei 20+ Jobs
- `Get-VBRJob | Disable-VBRJob`? Kein Weg den Originalzustand wiederherzustellen
- Veeams eingebauter "Maintenance Mode"? Gilt nur für SOBR-Extents, nicht für Jobs

## Die Lösung

Ein einzelnes PowerShell-Script mit WPF-GUI (Dark Theme) und drei Aktionen:

1. **SAVE** -- Aktuellen Zustand aller Jobs als JSON dokumentieren
2. **DISABLE ALL** -- Automatisch sichern + alle aktiven Jobs deaktivieren
3. **RESTORE** -- Originalzustand exakt aus gespeicherter JSON-Datei wiederherstellen

```
1. VeeamJobManager_v1.2.0.ps1 starten  (öffnet GUI)
2. SAVE klicken                         --> sichert Job-Zustand als JSON
3. DISABLE ALL klicken                  --> sichert nochmal + deaktiviert alle aktiven Jobs
4. ... Veeam Update durchführen ...
5. RESTORE klicken                      --> stellt Originalzustand wieder her
```

## Unterstützte Job-Typen

Das Tool deckt **alle gängigen Veeam Job-Typen** ab -- nicht nur `Get-VBRJob`:

| Job-Typ | Cmdlet | Beschreibung |
|---|---|---|
| VBRJob | `Get-VBRJob` | VMware/Hyper-V Backup, Replication, File Copy |
| VBRTapeJob | `Get-VBRTapeJob` | Backup to Tape, File to Tape |
| VBRSureBackupJob | `Get-VBRSureBackupJob` | SureBackup (v12+, Fallback auf `Get-VSBJob`) |
| VBRBackupCopyJob | `Get-VBRBackupCopyJob` | Backup Copy (ab v12 separates Cmdlet) |
| VBRComputerBackupJob | `Get-VBRComputerBackupJob` | Veeam Agent Backup |
| VBRComputerBackupCopyJob | `Get-VBRComputerBackupCopyJob` | Agent Backup Copy |
| VBRUnstructuredBackupJob | `Get-VBRUnstructuredBackupJob` | NAS/File Share Backup |
| VBRCDPPolicy | `Get-VBRCDPPolicy` | Continuous Data Protection |
| VBRPluginJob | `Get-VBRPluginJob` | Enterprise Apps (Oracle RMAN, SAP HANA) |

Fehlende Cmdlets werden automatisch erkannt und übersprungen. Das Tool funktioniert über alle Veeam-Versionen hinweg ohne Konfiguration.

## Features

- **WPF-GUI** mit Dark Theme (Catppuccin Farbschema)
- **Erkennung laufender Jobs**: Bietet an auf aktive Jobs zu warten und deaktiviert sie automatisch nach Abschluss. Die UI bleibt während des Wartens bedienbar (Timer-basiert, 10s Intervall).
- **Abbruch-Erkennung**: Wird das Fenster während des Wartens geschlossen, wird der Status als "Aborted" gespeichert. Beim nächsten Start erscheint eine Warnung mit Handlungsempfehlung.
- **State-Datei-Verwaltung**: Dropdown zur Auswahl zwischen verschiedenen Sicherungen, sortiert nach Datum
- **Persistente Log-Datei**: Alle Aktionen werden in `VeeamJobManager_<FQDN>.log` mit Einzeljob-Details protokolliert
- **Server-Validierung**: Warnung wenn eine State-Datei von einem anderen Server wiederhergestellt wird
- **Single-File Deployment**: Eine `.ps1` Datei, keine Installation, keine Abhängigkeiten außer Veeam PowerShell

## Schnellstart

```powershell
# Direkt auf dem Veeam Backup & Replication Server als Administrator ausführen
.\VeeamJobManager_v1.2.0.ps1
```

Falls die Execution Policy das Starten verhindert:
```powershell
powershell -ExecutionPolicy Bypass -File .\VeeamJobManager_v1.2.0.ps1
```

## Voraussetzungen

- Windows PowerShell 5.1+
- Veeam Backup & Replication Server (direkt auf dem Server ausführen)
- Administrator-Rechte
- Veeam PowerShell Modul (v11+) oder Snap-in (v9/v10) -- wird automatisch erkannt

## Kompatibilität

| Veeam Version | Modul/Snap-in | Status |
|---|---|---|
| v9, v10 | PSSnapin (VeeamPSSnapIn) | Unterstützt |
| v11 | PowerShell Modul | Unterstützt |
| v12 -- v12.3 | PowerShell Modul | Unterstützt + erweiterte Job-Typen |

## Bekannte Besonderheiten

- **Tape-Jobs**: Veeam bietet keine `Disable-VBRTapeJob` / `Enable-VBRTapeJob` Cmdlets. Das Tool nutzt `Disable-VBRJob` / `Enable-VBRJob`, die auch für Tape-Jobs funktionieren.
- **Backup Copy Jobs**: Ab Veeam v12 haben Backup Copy Jobs ein eigenes Cmdlet (`Get-VBRBackupCopyJob`). In älteren Versionen sind sie in `Get-VBRJob` enthalten. Das Tool unterstützt beide Varianten.
- **NAS Backup Jobs**: Der Cmdlet-Name änderte sich von `Get-VBRNASBackupJob` (v10/v11) zu `Get-VBRUnstructuredBackupJob` (v12+). Das Tool versucht automatisch beide.

## State-Datei Format

State-Dateien werden als JSON im Script-Verzeichnis gespeichert:

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

## Lizenz

MIT License -- siehe [LICENSE](LICENSE)

## Autor

**Lars Bahlmann**
[badata GmbH](https://www.badata.de) -- IT-Systemhaus aus Verden/Aller

---

*Wenn dir dieses Tool weiterhilft, freue ich mich über einen Stern und eine Empfehlung an Veeam-Kollegen.*

---

# English

**Save, disable, and restore Veeam Backup job states during updates/upgrades.**

A PowerShell GUI tool that solves a common problem: before a Veeam update, all jobs must be disabled. After the update, you need to know exactly which jobs were enabled before -- and which were already disabled. This tool saves the complete job state, disables everything, and restores the original state after the update.

## The Problem

When updating Veeam Backup & Replication, all backup jobs must be stopped and disabled. Customers with many jobs have a mix of enabled and disabled jobs. If you disable everything for the update, you lose track of which jobs were active before.

**Common workarounds fail:**
- Manually noting which jobs are enabled? Error-prone with 20+ jobs
- `Get-VBRJob | Disable-VBRJob`? No way to restore the original state
- Veeam's built-in "Maintenance Mode"? Only applies to SOBR extents, not jobs

## The Solution

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

## License

MIT License -- see [LICENSE](LICENSE)

## Author

**Lars Bahlmann**
[badata GmbH](https://www.badata.de) -- IT-Systemhaus aus Verden/Aller
