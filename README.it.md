# WinTech Toolkit

[English](README.md) · **Italiano**

> **Beta (0.9.1-beta).** Funziona ed è stato provato, ma non è finito: provalo prima con la
> **modalità Simulazione** attiva e [segnala i problemi](https://github.com/SlaKy03/WinTechToolkit/issues).
> Molte azioni modificano il sistema (eliminano profili, disinstallano programmi, modificano
> il registro). **Usalo a tuo rischio**, vedi [LICENSE](LICENSE).
>
> Nota: l'interfaccia del programma è per ora **solo in inglese**. Questo file è la guida in italiano.

Diagnostica, riparazione e manutenzione di Windows 10/11 in un'unica finestra, pensata per chi
fa assistenza tecnica: help desk, sistemisti, tecnici di laboratorio o chi si occupa dei PC di
casa e dell'ufficio.

Integrità di sistema (DISM/SFC), analisi di schermate blu e crash, pulizia dei profili utente,
disinstallazioni con rimozione dei residui, Windows Update, Office e Teams, credenziali,
stampanti, rete e dominio, anche su PC remoti.

Usa **Windows PowerShell 5.1**, già presente in Windows: non installa nulla.

## Avvio

**Senza scaricare niente** (PowerShell, anche non da amministratore):

```powershell
irm https://raw.githubusercontent.com/SlaKy03/WinTechToolkit/main/start.ps1 | iex
```

**Eseguibile**: scarica `WinTechToolkit.exe` dalla pagina
[Releases](https://github.com/SlaKy03/WinTechToolkit/releases/latest). All'avvio cerca l'ultima
versione su GitHub e la verifica con il file SHA-256 pubblicato; senza rete, se la verifica
fallisce o con `WinTechToolkit.exe /offline`, usa la versione incorporata. I file estratti per
l'esecuzione vengono cancellati alla chiusura.

**Dagli script**: scarica `WinTechToolkit.zip`, estrai e fai doppio clic su
`Start-WinTechToolkit.cmd` (oppure `powershell -ExecutionPolicy Bypass -File .\WinTechToolkit.ps1`).
Funziona anche da una condivisione di rete.

In tutti i casi il toolkit chiede i privilegi di amministratore (UAC).

### Sulla fiducia

Il programma gira da amministratore, quindi leggi quello che esegui: tutto il sorgente è in
questo repository. Il launcher e `start.ps1` verificano il download con il file `.sha256`
pubblicato nella stessa release. Questo protegge da download corrotti o manomessi, ma non da
chi prendesse il controllo dell'account GitHub; per questo l'`.exe` **non è ancora firmato**:
SmartScreen e alcuni antivirus possono segnalarlo. Nel dubbio usa lo zip e leggi prima gli script.

## Sezioni

| Gruppo | Sezione | Cosa fa |
|---|---|---|
| Diagnostics | **Dashboard** | PC e seriale, Windows e build, uptime e riavvio in sospeso, stabilità a 7 giorni, disco, RAM, rete, BitLocker/Secure Boot/TPM; azioni rapide |
| | **System** | Inventario completo, report HTML da allegare al ticket, punto di ripristino, report batteria, 16 console di Windows |
| | **Events and logs** | Diagnosi automatica (BSOD con codice e causa probabile, arresti imprevisti, crash con modulo ed eccezione, disco, hardware, Windows Update, servizi, rete e dominio) e 14 categorie consultabili |
| Repair | **Integrity and disks** | DISM CheckHealth/ScanHealth/RestoreHealth (anche da ISO con `/LimitAccess`), SFC con riepilogo da CBS.log, stato SMART, CHKDSK, diagnostica memoria, repository WMI |
| | **Windows Update** | Ricerca e installazione degli aggiornamenti (anche ignorando WSUS), driver, cronologia con codici di errore, reset dei componenti |
| | **Cleanup** | Analisi dello spazio recuperabile e pulizia di temp, cache di Windows Update, Ottimizzazione recapito, cestino, dump, cache dei browser, WinSxS |
| Users | **User profiles** | Ultimo utilizzo reale e dimensione, profili TEMP e `.bak`, cartelle orfane, selezione dei profili inutilizzati, eliminazione completa, riparazione del profilo temporaneo |
| | **Credentials and access** | Gestione credenziali dell'utente connesso, ticket Kerberos (utente e computer), membri di Administrators, Remote Desktop Users e Users |
| | **Office and Teams** | Riparazione rapida/online e aggiornamento di Office, cache di Teams, accesso e licenza di Microsoft 365, file .ost, Outlook in modalità provvisoria, reset di OneDrive |
| Software | **Programs and leftovers** | Disinstallazione silenziosa (MSI, Inno Setup, NSIS) e ricerca dei residui: cartelle, registro, servizi, attività, collegamenti |
| | **Startup and tasks** | Programmi all'avvio di tutti gli utenti e attività pianificate, con disattivazione reversibile |
| Network | **Network and domain** | Schede di rete, rilascio/rinnovo IP, DNS, test di connettività e di porta, reset Winsock, gpupdate, gpresult, trust del dominio, ora |
| | **Printers** | Code e stato, pagina di prova, collegamento di stampanti condivise (per tutti o per un utente), rimozione di stampanti e driver inutilizzati, spooler |
| | **Remote computer** | Le stesse funzioni su un altro PC via WinRM, senza installare nulla sul PC remoto |

I nomi delle sezioni sono quelli dell'interfaccia (in inglese). Le azioni che riguardano
l'utente (credenziali, Kerberos, OneDrive, accesso a Office) vengono eseguite **nella sessione
dell'utente connesso**, anche se il toolkit gira con un altro account amministratore.

## Interfaccia

- Tema scuro e chiaro (palette Catppuccin Mocha/Latte), menu laterale comprimibile.
- I dati delle sezioni vengono caricati in background all'avvio: aprendo una sezione sono già pronti.
- Le operazioni lunghe non bloccano la finestra; se ne avvii una mentre un'altra è in corso, viene messa in coda.
- **Modalità simulazione** (interruttore *Simulation*): le operazioni che modificano il sistema vengono solo descritte nel registro attività.
- Clic destro sulle tabelle per aprire cartelle e chiavi di registro, copiare percorsi, cercare sul web.

| Scorciatoia | Azione |
|---|---|
| `Ctrl+1` … `Ctrl+9` | Vai alla sezione |
| `F5` | Aggiorna la sezione |
| `Ctrl+F` | Cerca (Programmi, Eventi) |
| `Ctrl+L` | Mostra/nascondi il registro attività |

## Sicurezza

- Conferma esplicita prima di ogni eliminazione, con l'elenco di cosa verrà rimosso.
- Backup `.reg` di ogni chiave eliminata in `C:\ProgramData\WinTechToolkit\Backup\`.
- Profili caricati, di sistema e dell'account in uso non vengono mai eliminati; nomi generici
  o di sistema (Microsoft, Windows, Common Files...) non vengono mai proposti come residui.
- Log giornaliero per computer in `C:\ProgramData\WinTechToolkit\Logs\`, report in `...\Report\`.

## Uso da console

Tutte le funzioni sono in un modulo utilizzabile anche senza interfaccia:

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

Elenco completo: `Get-Command -Module WinTechToolkit`.

## Limiti noti

- Gli HKCU degli utenti non connessi non vengono analizzati per i residui.
- Le app dello Store (Appx/MSIX) non compaiono nell'elenco dei programmi.
- Gli uninstaller EXE senza switch silenzioso riconosciuto si avviano in modalità interattiva.
- `gpupdate` applica i criteri utente all'account che esegue il toolkit.
- L'exe non è firmato (vedi "Sulla fiducia").
- L'interfaccia è solo in inglese, per ora.

Per struttura del progetto, build e pubblicazione delle release vedi il [README in inglese](README.md).

## Licenza

[MIT](LICENSE)
