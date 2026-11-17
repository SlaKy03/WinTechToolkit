# Security policy

WinTech Toolkit runs as administrator and can delete profiles, registry keys and files, so
security reports are taken seriously.

## Supported versions

Only the latest release receives fixes. The executable and `start.ps1` always download the
latest release, so updating means starting the toolkit again.

## Reporting a vulnerability

Please **do not open a public issue** for a security problem.

Use **Security > Report a vulnerability** on the
[repository page](https://github.com/SlaKy03/WinTechToolkit/security/advisories/new): the report
stays private until a fix is published.

Useful details:

- the version (shown in the sidebar and in the About box) and how the toolkit was started
  (exe, `irm | iex`, zip);
- Windows edition and build;
- the steps to reproduce it and what happens;
- never include passwords, tokens or recovery keys.

You will get an answer within a few days. Once the fix is released, the advisory is published
and you are credited, unless you prefer otherwise.

## What counts as a vulnerability

- a way to make the toolkit delete or change something outside what the confirmation shows
  (profiles, system folders, personal folders, registry keys);
- a way to run code or gain privileges through the toolkit, its launcher or `start.ps1`
  (for example by tampering with the download or the temporary folder);
- secrets (credentials, BitLocker recovery keys) written to logs or reports.

Not vulnerabilities: the toolkit asking for administrator rights, antivirus products flagging
the unsigned executable, and actions that do exactly what their confirmation says.

## How downloads are verified

The launcher and `start.ps1` check the downloaded package against the `.sha256` file published
with the same release and start nothing if it does not match. This protects against corrupted
or tampered downloads; the executable is not code-signed yet (see "About trust" in the
[README](README.md)).
