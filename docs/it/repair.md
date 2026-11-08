# Riparazione

[Guida](README.md) · [English](../en/repair.md)

Funzioni che modificano il sistema: provale prima con **Simulazione** attiva. Le operazioni lunghe
(DISM, SFC) si possono fermare con **Stop** nella barra di stato: i programmi avviati vengono
terminati.

## Integrità e dischi

| Pulsante | Comando | A cosa serve |
|---|---|---|
| CheckHealth | `DISM /Online /Cleanup-Image /CheckHealth` | Controllo rapido dei segnali di danneggiamento dell'archivio componenti (secondi) |
| ScanHealth | `DISM /Online /Cleanup-Image /ScanHealth` | Analisi approfondita dell'archivio componenti (minuti), non ripara nulla |
| RestoreHealth | `DISM /Online /Cleanup-Image /RestoreHealth` | Ripara l'immagine di Windows scaricando i file da Windows Update. Con **/LimitAccess** e un'origine (ISO montata, `install.wim`) funziona senza Internet o con WSUS |
| SFC /scannow | `sfc /scannow` | Controlla e ripara i file protetti di Windows |
| Riparazione completa | RestoreHealth, poi SFC | La sequenza classica quando i file di Windows sono danneggiati (30-60 minuti) |
| Dettagli SFC | Legge `CBS.log` | Estrae le righe `[SR]`: quali file sono stati riparati o non si sono potuti riparare |
| Stato dei dischi (SMART) | Cmdlet di archiviazione | Stato di salute, temperatura, usura ed errori dei dischi fisici |
| CHKDSK online | `chkdsk C: /scan` | Controlla il file system senza riavviare |
| CHKDSK al riavvio | `fsutil dirty set C:` | Pianifica `chkdsk /F` sul volume di sistema al prossimo riavvio |
| Diagnostica memoria | `mdsched.exe` | Test della RAM al prossimo riavvio (Windows chiede quando) |
| Verifica repository | `winmgmt /verifyrepository` | Controlla il repository WMI (inventario, script o console che non funzionano) |
| Ripara repository | `winmgmt /salvagerepository` | Ripara il repository WMI |

## Windows Update

Gli aggiornamenti si cercano e si installano tramite l'agente di Windows Update (la stessa API di
Impostazioni), così il toolkit mostra anche il codice di errore quando qualcosa non va.

| Pulsante / interruttore | Cosa fa | Modifica il sistema |
|---|---|---|
| Cerca aggiornamenti | Aggiornamenti non ancora installati, con KB, categoria, gravità, dimensione | No |
| Direttamente da Microsoft | Cerca su Microsoft Update invece che sul server WSUS aziendale | No |
| Includi driver | Elenca anche gli aggiornamenti dei driver | No |
| Installa selezionati / Installa tutti | Scarica e installa; il registro indica se serve un riavvio | Sì |
| Analisi in background | `UsoClient StartScan`: come "Verifica disponibilità aggiornamenti" in Impostazioni | No |
| Reimposta componenti | Arresta i servizi di Windows Update, rinomina `SoftwareDistribution` e `catroot2` (vengono ricreate) e riavvia i servizi. Per aggiornamenti bloccati o che falliscono sempre | Sì |
| Cronologia | Le ultime installazioni con esito e codice di errore | No |

## Pulizia

Seleziona cosa pulire, premi **Analizza lo spazio recuperabile** per vedere quanto spazio recuperi
(non si elimina nulla), poi **Esegui pulizia**. **Seleziona consigliati** spunta le voci sicure.

| Voce | Cosa viene svuotato |
|---|---|
| File temporanei di Windows | `C:\Windows\Temp` |
| File temporanei di tutti gli utenti | `AppData\Local\Temp` di ogni profilo |
| Cache dei download di Windows Update | `C:\Windows\SoftwareDistribution\Download` |
| Cache di Ottimizzazione recapito | Cache peer-to-peer degli aggiornamenti |
| Cestino | Di tutti gli utenti e di tutti i volumi |
| Dump di arresto e segnalazioni errori | `MEMORY.DMP`, minidump, LiveKernelReports, segnalazioni WER (anche per utente) |
| Cache dei browser | Cache di Edge, Chrome e Firefox (preferiti, password e cronologia restano) |
| Archivio componenti WinSxS | `DISM /Online /Cleanup-Image /StartComponentCleanup` (vecchie versioni degli aggiornamenti) |

I file in uso vengono saltati. Il toolkit non elimina mai i propri file mentre è in esecuzione
(con l'exe o con `irm` gira da una cartella temporanea).
