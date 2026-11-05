# Changelog

## Unreleased

- Fix: `irm ... | iex` never worked. `start.ps1` had a BOM ("term not recognized") and, once
  that was fixed, it failed the integrity check because GitHub serves the `.sha256` file as
  binary and the hash was read from a byte array. The static checks now fail if `start.ps1`
  has a BOM.
- Events: the category being shown stays highlighted instead of always "Automatic diagnosis".
- Programs: the manual leftovers search also lists folders and registry keys whose name
  contains the text (e.g. "Zoom" finds "ZoomVideoApps"), for programs uninstalled without
  the toolkit; protected and too generic names are still excluded.
- Report and diagnosis: healthy disks are no longer reported as a problem with "0 events"
  and printers show "Ready" instead of the code "0".
- Safety: `Remove-WTFolder` now refuses profile folders and their personal folders (Documents,
  Desktop, Downloads, AppData...) whoever calls it, not only the search; a whole profile is
  deleted only through the profile functions. Found by the new `Build\Test-Safety.ps1`
  (129 checks, also run on GitHub), which also covers the protected names and paths, the
  profile protections, the leftovers search and the language fallback.
- Programs and startup items: trailing spaces in the publisher and version are removed.
- Fix: after an uninstall or a cleanup of the temp folders, the next operations failed with
  "Invoke-WTCleanup / Find-WTProgramResidue / Get-WTPrinter is not recognized". When the
  toolkit runs from %TEMP% (exe or `irm | iex`) its own files could be deleted, and the
  background runspaces created later could no longer load the module. The runspaces now load
  it from the code read at startup, and the cleanups never delete the folder of the running
  toolkit or of another running copy (also with 8.3 short paths like `C:\Users\ABCDEF~1`).
- New tools: problem devices with the meaning of the error code and BitLocker recovery key
  (System), Windows Hello PIN reset (Accounts), Wi-Fi report (Network).
- **Programs and apps** (was "Programs and leftovers"): two tabs, desktop programs and
  **Microsoft Store apps**. Store apps are listed for every user with their name as shown in
  Start, size and source; they are removed for all users and, optionally, also for new users
  (removed from the Windows image), then their leftover data folders are searched. Apps that
  Windows or other apps need (Store, App Installer/winget, Windows Security, Edge, runtimes)
  are shown in grey and never removed.
- Printers: when Windows cannot load the PrintManagement module in the background ("Get-Printer
  found in the module PrintManagement, but the module could not be loaded") the module is loaded
  again a few times and the list is read from WMI as a last resort. Removing printers, queues
  and unused drivers stops with an error instead: without the printer list every driver would
  have looked unused.
- Closing the toolkit asks for a confirmation, with an option to delete its data in
  `C:\ProgramData\WinTechToolkit` (logs, reports, registry backups, settings).
- Interface: buttons, search boxes, switches, filters and counters have the same height and
  spacing on every page; the title bar is taller and aligned; the collapsed menu no longer
  shows a scroll bar that pushed the icons off centre; "Windows Hello" in Credentials and
  access is on its own line instead of next to the button.

## 0.9.2-beta

- **Italian interface**: the whole interface, messages, confirmations and logs are translated.
  The language follows Windows by default and can be changed from the title bar (the toolkit
  restarts to apply it). The ticket report stays in English. Other languages can be added
  with a new `Module\Lang\<code>.psd1` file.
- The static checks fail on missing translations, different placeholders and untranslated
  XAML texts.
- Size columns are wider so the Italian text is not cut.
- Search and text boxes: the caret no longer starts in the middle of the placeholder and the
  typed text sits next to the search icon; placeholders are fainter so they don't look typed.
- Unexpected errors in the interface no longer close the window: they are written to
  `Logs\Crash_*.txt` and shown in a message, and the app keeps working.
- App icon on the taskbar; progress on the taskbar button; when an operation of 15 seconds or
  more ends while the window is in the background, the button flashes (red if it failed) and
  a Windows notification appears.
- Window size, position, maximized state and activity log height are remembered.
- Tables: long values end with "..." and show the whole text in a tooltip; the Events
  description column keeps a minimum width; "User slaky" instead of "User PC01\slaky".
- Checks run on GitHub on every push and pull request, not only for releases.

## 0.9.1-beta

- Title bar: rounded corners, shadow and themed border on Windows 11, Snap Layouts on the
  maximize button, correct size when maximized at any scaling, title dimmed when the window
  is inactive, beta badge, shorter computer/user line (full details in the tooltip).
- New About panel with version, Windows and PowerShell info, links to the project, releases
  and issue tracker, and a "Copy info" button for bug reports.
- Network: connected adapters are listed first, then by name.
- Quick action tiles fill the whole row; the status bar text is no longer indented.
- Events: wider columns, and the description includes the error when the first line ends
  with a colon (e.g. Service Control Manager 7023).
- Programs: invalid install dates are no longer shown (e.g. "2026-20-22").
- Uptime without "0 d", wider search boxes, "1 item" instead of "1 items".
- Stop button in the status bar: stops the running operation and terminates the programs it
  started (DISM, SFC, CHKDSK...). Closing the window during an operation now offers to stop it.
- Confirmations and messages use the app theme instead of the white Windows message box.
- Queued file renames alone no longer show "Restart pending" on the Dashboard and in the reports.
- Physical disks: type, bus and health as names (e.g. "SSD NVMe - Healthy") instead of codes;
  the disk health check no longer reports healthy disks as errors when the codes are raw.
- Placeholders for the ticket report notes and the TCP port test host.

## 0.9.0-beta

First public beta. Feedback and bug reports are welcome in the
[issue tracker](https://github.com/SlaKy03/WinTechToolkit/issues).

- 14 sections: Dashboard, System, Events, Integrity, Windows Update, Cleanup, User profiles,
  Credentials and access, Office and Teams, Programs and leftovers, Startup and tasks,
  Network and domain, Printers, Remote computer.
- Simulation mode, dark and light theme, collapsible sidebar, task queue.
- `.exe` launcher with online update (SHA-256 verified) and offline fallback, and
  `irm | iex` launch.
- English interface. Other languages are planned.
