# WinTech Toolkit

**English** · [Italiano](README.it.md)

> **Beta (0.9.1-beta).** It works and has been tested, but it is not finished: please try it
> first with **Simulation mode** on, and [report problems](https://github.com/SlaKy03/WinTechToolkit/issues).
> Many of the actions change the system (delete profiles, uninstall programs, edit the
> registry). **Use at your own risk**, see [LICENSE](LICENSE).

Diagnostics, repair and maintenance of Windows 10/11 in a single window, built for IT
support work: help desk, sysadmins, lab technicians, or anyone who looks after the PCs at
home or in the office.

System integrity (DISM/SFC), blue screen and crash analysis, user profile cleanup,
uninstalls with leftover removal, Windows Update, Office and Teams, credentials, printers,
network and domain, also on remote PCs.

It uses **Windows PowerShell 5.1**, already part of Windows: nothing to install.

## Run it

**Without downloading anything** (PowerShell, no need to be admin):

```powershell
irm https://raw.githubusercontent.com/SlaKy03/WinTechToolkit/main/start.ps1 | iex
```

**Executable**: download `WinTechToolkit.exe` from the
[Releases](https://github.com/SlaKy03/WinTechToolkit/releases/latest) page. On start it looks
for the latest version on GitHub and checks it against the published SHA-256 file; with no
network, if the check fails, or with `WinTechToolkit.exe /offline`, it uses the embedded
version. The files extracted to run it are deleted when you close it.

**From the scripts**: download `WinTechToolkit.zip`, extract it and double-click
`Start-WinTechToolkit.cmd` (or `powershell -ExecutionPolicy Bypass -File .\WinTechToolkit.ps1`).
It also works from a network share.

In every case the toolkit asks for administrator rights (UAC).

### About trust

The tool runs as administrator, so read what you run: the whole source is in this
repository. The launcher and `start.ps1` verify the download against the `.sha256` file
published with the same release. This protects against corrupted or tampered downloads,
but not against someone who takes control of the GitHub account, which is why the
`.exe` is **not code-signed yet**: SmartScreen and some antivirus programs may flag it.
If in doubt, use the zip and read the scripts first.

## Sections

| Group | Section | What it does |
|---|---|---|
| Diagnostics | **Dashboard** | PC and serial number, Windows and build, uptime and pending restart, 7-day stability, disk, RAM, network, BitLocker/Secure Boot/TPM; quick actions |
| | **System** | Full inventory, HTML report to attach to a ticket, restore point, battery report, 16 Windows consoles |
| | **Events and logs** | Automatic diagnosis (BSODs with code and likely cause, unexpected shutdowns, crashes with module and exception, disk, hardware, Windows Update, services, network and domain) and 14 browsable categories |
| Repair | **Integrity and disks** | DISM CheckHealth/ScanHealth/RestoreHealth (also from an ISO with `/LimitAccess`), SFC with a CBS.log summary, SMART status, CHKDSK, memory diagnostic, WMI repository |
| | **Windows Update** | Search and install updates (also bypassing WSUS), drivers, history with error codes, component reset |
| | **Cleanup** | Analyze recoverable space and clean temp files, Windows Update cache, Delivery Optimization, recycle bin, dumps, browser caches, WinSxS |
| Users | **User profiles** | Real last use and size, TEMP and `.bak` profiles, orphan folders, selection of unused profiles, full deletion, temporary profile repair |
| | **Credentials and access** | Credential Manager of the signed-in user, Kerberos tickets (user and computer), members of Administrators, Remote Desktop Users and Users |
| | **Office and Teams** | Quick/online repair and update of Office, Teams cache, Microsoft 365 sign-in and license, .ost files, Outlook safe mode, OneDrive reset |
| Software | **Programs and leftovers** | Silent uninstall (MSI, Inno Setup, NSIS) and search for leftovers: folders, registry, services, tasks, shortcuts |
| | **Startup and tasks** | Startup programs of all users and scheduled tasks, with reversible disabling |
| Network | **Network and domain** | Adapters, IP release/renew, DNS, connectivity and port tests, Winsock reset, gpupdate, gpresult, domain trust, time |
| | **Printers** | Queues and status, test page, connecting shared printers (for everyone or one user), removing printers and unused drivers, spooler |
| | **Remote computer** | The same functions on another PC over WinRM, nothing installed on the remote PC |

Actions that concern the user (credentials, Kerberos, OneDrive, Office sign-in) run
**in the signed-in user's session**, even if the toolkit runs under a different
administrator account.

## Interface

- Dark and light theme (Catppuccin Mocha/Latte palette), collapsible sidebar.
- The data of each section is loaded in the background at startup, so it is ready when you open it.
- Long operations do not block the window; if you start one while another is running, it is queued.
- **Simulation mode**: operations that change the system are only described in the activity log.
- Right-click the tables to open folders and registry keys, copy paths, search the web.

| Shortcut | Action |
|---|---|
| `Ctrl+1` … `Ctrl+9` | Go to section |
| `F5` | Refresh the section |
| `Ctrl+F` | Search (Programs, Events) |
| `Ctrl+L` | Show/hide the activity log |

The interface is currently **English only**. More languages are planned; contributions are welcome.

## Safety

- Explicit confirmation before every deletion, with the list of what will be removed.
- `.reg` backup of every deleted key in `C:\ProgramData\WinTechToolkit\Backup\`.
- Loaded profiles, system profiles and the account in use are never deleted; generic or
  system names (Microsoft, Windows, Common Files...) are never offered as leftovers.
- Daily log per computer in `C:\ProgramData\WinTechToolkit\Logs\`, reports in `...\Report\`.

## Use from the console

All the functions are in a module that can also be used without the interface:

```powershell
Import-Module .\Module\WinTechToolkit.psm1 -DisableNameChecking
(Get-WTProblemReport -Days 30).Report
Invoke-WTFullRepair
Get-WTUserProfile | Where-Object { $_.DaysUnused -gt 180 -and -not $_.Protected } |
    ForEach-Object { Remove-WTUserProfile -InputObject $_ -Simulate }
$p = Get-WTInstalledProgram | Where-Object DisplayName -like '*Zoom*'
Uninstall-WTProgram -Program $p -Silent
Find-WTProgramResidue -Program $p | Out-GridView -PassThru | ForEach-Object { Remove-WTResidue -InputObject $_ }
Invoke-WTRemote -ComputerName PC042 -Command Get-WTDiskHealth
```

Full list: `Get-Command -Module WinTechToolkit`.

## Project layout

```
WinTechToolkit.ps1        WPF interface: window, operation queue, runspaces
Start-WinTechToolkit.cmd  double-click launcher
start.ps1                 launch from the web (irm | iex)
app.json                  name, version and repository (used by the interface, exe and build)
UI\Styles.ps1             palette and styles
UI\Pages\*.ps1            one section per file (XAML, loading, handlers)
Module\Functions\*.ps1    module functions, split by topic
Build\Build.ps1           creates dist\WinTechToolkit.zip/.exe and their .sha256 files
Build\Launcher.cs         source of the .exe launcher
Build\Test-*.ps1          static checks and a UI run with screenshots
```

To add a section, create a new file in `UI\Pages` that calls `Register-WTPage`.
`.ps1` files must be saved as **UTF-8 with BOM** (Windows PowerShell 5.1 otherwise misreads
non-ASCII characters): `Build\Test-Toolkit.ps1 -FixBom` fixes it.

## Publishing a release

1. Update `Version` in `app.json` and `CHANGELOG.md`.
2. `git tag v0.9.0-beta && git push --tags`: GitHub Actions runs the checks, builds, and
   publishes the release with `WinTechToolkit.zip`, `WinTechToolkit.exe` and their `.sha256` files.

Do **not** mark the release as a GitHub "pre-release": `releases/latest`, which the
launcher and `start.ps1` use, ignores pre-releases.

Manual build: `powershell -ExecutionPolicy Bypass -File .\Build\Build.ps1`.

## Known limitations

- The HKCU hives of users who are not signed in are not scanned for leftovers.
- Store apps (Appx/MSIX) do not appear in the program list.
- EXE uninstallers without a recognized silent switch start in interactive mode.
- `gpupdate` applies user policies to the account running the toolkit.
- The exe is not code-signed (see "About trust").
- English only for now.

## License

[MIT](LICENSE)
