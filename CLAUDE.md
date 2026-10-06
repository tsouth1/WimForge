# CLAUDE.md - WimForge (C:\MEDIAPATCHING)

Read this first; rescan the repo only when something here is missing or looks stale (then update this file).

## What it is

WimForge: offline DISM servicing of Windows OS media (install.wim, WinRE, boot.wim, media folder, ISO, CA 2023 media)
for SCCM/ConfigMgr OSD, plus catalog downloads (MSCatalogLTS) and SCCM import. Single-file PowerShell 5.1 WPF GUI app.
The user is "the operator" in the docs; Claude does the code, the operator does real runs on the build server.

## Files

| Path | What |
|---|---|
| `MediaRefresh_v2.4.ps1` | **The only script under development** (~4,800 lines). Tool version is **2.5.0** (`$script:ToolVersion`, line ~186); the file keeps the v2.4 name on purpose (docs, run configs, scheduled tasks). |
| `TODO.md` | Index + **open** items only, by step number (2, 4, 6-10, 12, 13, 15-18). |
| `TODO_DONE.md` | Completed items moved out of TODO.md (build details, confirmed checks, steps 1/3/5/11/14, History). Add finished work here and a dated History line. |
| `INSTRUCTIONS.md` | Operator guide; also rendered by the GUI's Instructions tab. Only headings, lists, bold, italic, code, links - **no tables** (the tab's small Markdown renderer). Keep it in step with GUI changes. |
| `README.md` | GitHub readme + screenshots (`images\`). Status section quotes the test-kit check count. |
| `Languages.json` | Reference language list (repo copy); runtime copy is `Profiles\Languages.json`, also built into the script (`Get-BuiltInLanguageData`, a test keeps them equal). |
| `MediaRefresh_Review_and_Roadmap.md` | Original review/roadmap; section 0 = real-image test plan. |
| `archive\` | v2_original, v2.1-v2.3 and old notes - history only, never edit. |
| `Make2023BootableMedia.ps1` | Microsoft's script, local reference for step 12a; **gitignored, never commit**. |
| `Profiles\`, `Settings\`, `Configs\` | Runtime, per machine, gitignored (OS profile JSON, saved GUI settings, run configs). |

## Script layout (`MediaRefresh_v2.4.ps1`)

- `#Requires -Version 5.1 -RunAsAdministrator`; `param([string]$Config, [switch]$Preflight)`; `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`.
- Regions: `#region BOOTSTRAP` (~143-165), `#region ENGINE` (~167-3603), command-line branch between ENGINE and GUI, `#region GUI` (~3613-end; XAML inline, background runspace for runs).
- **Keep the `#region ENGINE` / `#endregion ENGINE` markers** - the test kit extracts the engine text between them.
- Must run on **Windows PowerShell 5.1** (no PS7-only syntax; typed array params need an empty default under StrictMode).
- Command line: `MediaRefresh_v2.4.ps1 -Config <file> [-Preflight]`; exit codes 0 ok, 1 failed/bad config, 2 gate FAILED, 3 SCCM import failed.
- Patch classes `$script:ProfileClasses` (line ~202: SSU, LCU, NetCU, SafeOS, SetupDU); saved/run-config option names `$script:SettingOptionNames` (line ~602); defaults `$script:OptionDefaults` (line ~3470; a test keeps them equal to the window's).
- Header `.NOTES` holds the version changelog; bump it with notable changes.

## Logs

- **`C:\MEDIAPATCHING\LOGS\`** - where the operator drops run logs from the build server for Claude to read (usually zipped: `DISM_*.zip`, `*.7z`). Gitignored; **never commit logs** (`*.log`, `*.zip`, `*.7z` are ignored).
- On the build server, per OS: `<repository root>\<OS folder>\LOGS\` - `MediaRefresh_<time>.log` (run log), `DISM_<time>.log` (DISM's own), `ChangeLog_<OS>_<build>_<time>.html/.csv` (also copied to `NEWWIM\`), `SccmImport_<time>.log`. `MountCleanup_<time>.log` lands in `<repository root>\LOGS\`.
- Evidence of success in a run log: `VERIFY` lines and `VALIDATION GATE: PASSED`.

## Tests (`testkit\`)

- Mock-based; no real images/DISM. Run from `testkit\`:
  - `powershell.exe -NoProfile -ExecutionPolicy Bypass -File run_all.ps1` (5.1, what the tool runs on), and/or `pwsh -NoProfile -File run_all.ps1`.
  - Single suite: run that `.ps1` the same way. Suites: `parse`, `xaml`, `harness`, `e2e` (E1-E32), `runner`, `profiles` (P-numbered), `acquisition` (A-numbered). `lint.ps1` / `lint2.ps1` need PSScriptAnalyzer (not in run_all).
  - `$env:MR_SCRIPT` = path of another script copy to test. `mocks.ps1` is shared, dot-sourced.
- Last known total: **664 checks, 7 suites, all passing** (2026-10-01). When adding a feature, add checks and update the count in TODO_DONE.md History, README.md and `testkit\README_TESTKIT.md`.
- Scratch output folders (`testkit\e2e`, `ptest`, `rt`, `tst*`, `acq`, `engine_only.ps1`) are gitignored and recreated each run.
- Avast on this PC can quarantine new test scripts (see memory) - a vanished `.ps1` is likely the Virus Chest.

## Working folder layout (build server, per OS)

`<repository root>\<OS folder>\{ISO, LOGS, MOUNT, OLDWIM, NEWWIM, PATCHES\{SSU,LCU,NETCU,SAFEOSDU,SETUPDU}, TEMP, WINPE, WINRE, WORKING}`.
Default repository root = the script's own folder until one is saved (`Settings\General.json`). `PATCHES\SSU` is always manual.
`NEWWIM\RunResult.json` = run record (used by SCCM import and media-only runs). The build server runs WimForge from `J:\WimForge` (since 2026-10-01).

## OS profiles

Five built-ins: Win10 Enterprise LTSC 2019 (1809), Win10 Enterprise LTSC 2021 KMS and IoT Enterprise LTSC 2021 (21H2/19041),
Win11 Enterprise 24H2, Windows Server 2022 (all indexes). 26H2 added on the server via Tools > New OS from existing.
Real media/ISO testing only for Win11 and Server 2022+; Win10 LTSC = install.wim (+WinRE) only.

## Conventions

- Docs style: plain British-ish English, dated entries (`2026-10-06`), "the operator" not names; no real server/domain names in tracked files (use `<SCCM-SOURCE-SERVER>`, contoso.com).
- Files use CRLF line endings.
- Commit only when asked; branch is `main`.
