# Contributing

Bug reports, ideas, translations and code are welcome.

## Reporting a problem or an idea

Open an [issue](https://github.com/SlaKy03/WinTechToolkit/issues/new/choose) with the bug or
feature template. For a bug, **About > Report a problem** copies the version and system details
to paste. Never include passwords, tokens or recovery keys. Security problems follow
[SECURITY.md](SECURITY.md) instead.

## Working on the code

Nothing to install: the toolkit is Windows PowerShell 5.1 plus a small C# launcher built with the
compiler that ships with Windows. Work on the `dev` branch and open pull requests against `dev`.

```powershell
git clone https://github.com/SlaKy03/WinTechToolkit.git
cd WinTechToolkit
git checkout dev
.\Start-WinTechToolkit.cmd        # run it from the sources
```

The project layout is described in the [README](README.md#project-layout).

### Rules that keep it safe

- Every action that changes the system takes `-Simulate` and does nothing when it is set.
- Deletions go through the existing functions (`Remove-WTFolder`, `Remove-WTResidue`,
  `Remove-WTUserProfile`...): they hold the protections for profiles, system paths and personal
  folders. Do not delete with `Remove-Item` directly.
- Ask for confirmation before changing the system, listing what will be changed.
- Registry keys are backed up to `.reg` before they are deleted.
- The code must run on Windows PowerShell 5.1: no PowerShell 7 syntax.

### Files and texts

- `.ps1` files are **UTF-8 with BOM** and CRLF (`Build\Test-Toolkit.ps1 -FixBom` fixes the BOM);
  `start.ps1` has **no** BOM.
- Interface texts are written in English in the code, inside `T '...'` or `TX '...'`, and
  translated in `Module\Lang\<language>.psd1`. A new text needs its Italian translation in
  `Module\Lang\it.psd1`, with the same `{0}` placeholders.
- A change to a section also updates its page of the guide in `docs\en` and `docs\it`.

### Checks before a pull request

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build\Test-Toolkit.ps1    # syntax, XAML, controls, translations
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build\Test-Safety.ps1     # protections of the delete functions
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build\Test-Pester.ps1     # unit tests of the delete functions (Pester 5)
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build\Test-Analyzer.ps1   # PSScriptAnalyzer (Install-Module PSScriptAnalyzer)
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\Build\Test-Gui.ps1   # screenshots of every section in %TEMP%\wtsmoke
```

The first four also run on GitHub for every push and pull request. Look at the screenshots when
you change the interface, in both themes (`-Theme Light`) and languages (`-Language it`).

### Commits

Short messages in English, one topic per commit, in the style of the history
(`Network: list connected adapters first`).

## Translations

To add a language, copy `Module\Lang\it.psd1` to `Module\Lang\<code>.psd1` (for example
`de.psd1`) and translate the values, keeping the keys and the `{0}` placeholders.
`Build\Test-Toolkit.ps1` lists the missing texts and builds the window in every language.

## License

Contributions are released under the [MIT license](LICENSE) of the project.
