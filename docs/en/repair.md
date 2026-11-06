# Repair

[Guide](README.md) · [Italiano](../it/repair.md)

Functions that change the system: try them first with **Simulation** on. Long operations
(DISM, SFC) can be stopped with **Stop** in the status bar: the programs they started are
terminated.

## Integrity and disks

| Button | Command | What it is for |
|---|---|---|
| CheckHealth | `DISM /Online /Cleanup-Image /CheckHealth` | Quick check of the corruption flags of the component store (seconds) |
| ScanHealth | `DISM /Online /Cleanup-Image /ScanHealth` | Deep scan of the component store (minutes), repairs nothing |
| RestoreHealth | `DISM /Online /Cleanup-Image /RestoreHealth` | Repairs the Windows image downloading the files from Windows Update. With **/LimitAccess** and a source (mounted ISO, `install.wim`) it works without Internet or with WSUS |
| SFC /scannow | `sfc /scannow` | Checks and repairs the protected Windows files |
| Full repair | RestoreHealth, then SFC | The standard sequence when Windows files are damaged (30-60 minutes) |
| SFC details | Reads `CBS.log` | Extracts the `[SR]` lines: which files were repaired or could not be |
| Disk health (SMART) | Storage cmdlets | Health status, temperature, wear and errors of the physical disks |
| Online CHKDSK | `chkdsk C: /scan` | Checks the file system without a restart |
| CHKDSK at restart | `fsutil dirty set C:` | Schedules `chkdsk /F` on the system volume at the next restart |
| Memory diagnostic | `mdsched.exe` | RAM test at the next restart (Windows asks when) |
| Verify repository | `winmgmt /verifyrepository` | Checks the WMI repository (inventory, scripts or consoles not working) |
| Repair repository | `winmgmt /salvagerepository` | Repairs the WMI repository |

## Windows Update

The updates are searched and installed through the Windows Update agent (the same API as
Settings), so the toolkit also shows the error code when something fails.

| Button / switch | What it does | Changes the system |
|---|---|---|
| Search for updates | Updates not installed yet, with KB, category, severity, size | No |
| Directly from Microsoft | Searches Microsoft Update instead of the company WSUS server | No |
| Include drivers | Also lists driver updates | No |
| Install selected / Install all | Downloads and installs; the log says if a restart is needed | Yes |
| Background scan | `UsoClient StartScan`: like "Check for updates" in Settings | No |
| Reset components | Stops the Windows Update services, renames `SoftwareDistribution` and `catroot2` (they are created again) and starts the services. For updates stuck or always failing | Yes |
| History | The last installations with the result and the error code | No |

## Cleanup

Select what to clean, press **Analyze recoverable space** to see how much space you get back
(nothing is deleted), then **Run cleanup**. **Select recommended** ticks the safe items.

| Item | What is emptied |
|---|---|
| Windows temporary files | `C:\Windows\Temp` |
| Temporary files of all users | `AppData\Local\Temp` of every profile |
| Windows Update download cache | `C:\Windows\SoftwareDistribution\Download` |
| Delivery Optimization cache | Peer-to-peer update cache |
| Recycle Bin | Of all users and all volumes |
| Crash dumps and error reports | `MEMORY.DMP`, minidumps, LiveKernelReports, WER reports (also per user) |
| Browser cache | Cache of Edge, Chrome and Firefox (bookmarks, passwords and history are kept) |
| WinSxS component store | `DISM /Online /Cleanup-Image /StartComponentCleanup` (old versions of the updates) |

Files in use are skipped. The toolkit never deletes its own files while it is running (with the
exe or `irm` it runs from a temporary folder).
