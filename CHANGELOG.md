# Changelog

## Unreleased

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
