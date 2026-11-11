# Changelog

## Unreleased

- Checks: `Build\Test-Analyzer.ps1` runs PSScriptAnalyzer with the rules that point to real mistakes
  and checks that the code stays compatible with Windows PowerShell 5.1; it also runs on GitHub.

## 0.10.0-beta

First public release.

- **14 sections** in five groups: Diagnostics (Dashboard, System, Events and logs), Repair
  (Integrity and disks, Windows Update, Cleanup), Users (User profiles, Credentials and access,
  Office and Teams), Software (Programs and apps, Startup and tasks) and Network (Network and
  domain, Printers, Remote computer).
- **Dashboard**: the state of the PC at a glance, memory and disk activity updated every second
  with charts of the last minute, and eight quick actions.
- **Automatic diagnosis** of the event logs (BSODs with code and likely cause, unexpected
  shutdowns, crashes, disk, hardware, Windows Update, services, network and domain) and an HTML
  report to attach to a ticket.
- **Programs and Store apps**: silent uninstall with automatic cleanup of the leftovers (folders,
  registry, services, tasks, shortcuts, app data); files in use are deleted at the next restart.
- **User profiles**: real last use and size, TEMP and `.bak` profiles, orphan folders, full deletion.
- **Printers**: queues of every signed-in user, shared printer connections, unused drivers, spooler.
- User actions (credentials, Kerberos, OneDrive, Office sign-in, printers) run in the signed-in
  user's session, even when the toolkit runs under a different administrator account.
- **Safety**: confirmation with the list of what will be removed, `.reg` backup of every deleted
  key, protected profiles, system paths and personal folders, Simulation mode, daily log.
- Interface in English and Italian, dark and light theme, background loading and operation queue.
- Three ways to start it: `WinTechToolkit.exe` (updates itself from the latest release, checked
  against its SHA-256 file), `irm | iex` and the scripts zip. If a security product blocks
  PowerShell at start, the exe shows what to do instead of closing silently.
- User guide in English and Italian (`docs/`), also opened from About > User guide.
- PowerShell module usable from the console without the interface.
