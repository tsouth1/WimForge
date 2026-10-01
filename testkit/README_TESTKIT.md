# WimForge - mock-based test kit

These checks exercise the engine without real images or a real DISM: the DISM cmdlets, ISO mounting and free-space reader are replaced by mocks, so call order, error handling, profile loading and output handling can be re-checked after every change.

**Run:** PowerShell 7 or Windows PowerShell 5.1, from this folder: `pwsh -NoProfile -File run_all.ps1`. By default every suite tests `..\MediaRefresh_v2.4.ps1`; set `$env:MR_SCRIPT` to a path to test another copy. Verified on Windows (2026-09-28): 7 suites, 646 checks, all passing under both PowerShell 7.6 and Windows PowerShell 5.1 (`powershell.exe -NoProfile -ExecutionPolicy Bypass -File run_all.ps1`; 5.1 is what the tool itself runs on). These are mock tests only; the real-image and real-catalog checks are TODO.md step 2.

| File | What it covers |
|---|---|
| parse.ps1 | Parser: 0 syntax errors |
| xaml.ps1 | XAML is well-formed; every control the script looks up exists; the Languages tab list, the Save settings / Reset buttons, the colour schemes (styles, brushes, coloured log lines), the media options, the Apps, SCCM and Instructions tabs on real WPF controls (Windows only) |
| harness.ps1 | ISO role detection, package handling, cleanup and failure paths (unit level) |
| mocks.ps1 | Shared mocks, dot-sourced by harness/e2e/profiles |
| e2e.ps1 | Whole-run scenarios E1-E31 (languages, Server multi-index, preflight, IoT edition selection, profiles through a run, archive, free space, LCU checkpoints, change log, install.wim-only languages, Cleanup Mountpoints, boot.wim and setup / boot files on the media, CA 2023 media, provisioned-app removal, SCCM import with the site mocked, .NET 3.5 source, download before the run, the command line, WinRE getting only the SSU cab from a combined LCU .msu, boot.wim getting it in two steps, a boot.wim failure keeping install.wim, the 1809 boot.wim falling back to the servicing stack only, an ISO run without the ADK stopping before any mount, Tools > Check OS profile, a run config with a root from before a move, the SCCM import to a share on another server, which DISM a run uses, the ISO build with oscdimg's blank lines and stderr) |
| runner.ps1 | The background runspace runner: queue messages, result hand-back, cancel, errors, a real preflight inside a runspace |
| profiles.ps1 | JSON profiles, order manifest, support status, archive, free-space check, the Languages tab list (Profiles\Languages.json), saved settings per OS (Settings\), colour schemes, the Instructions tab Markdown parser, the provisioned-app list and ticks, SCCM names / UNC paths / run record |
| acquisition.ps1 | Step 5 (acquisition layer): catalogSearch profile parsing/validation, search-result filtering, checkpoint-chain pruning, and a mocked Invoke-PatchAcquisition dry-run + real-download pass (never touches PATCHES\SSU) |
| lint2.ps1 | Windows PowerShell 5.1 syntax-compatibility lint (needs PSScriptAnalyzer) |
| lint.ps1 | General PSScriptAnalyzer pass (style findings such as positional parameters are known and accepted) |

Test-only conventions: tests read the engine text between `#region ENGINE` and `#endregion ENGINE`, so keep those markers. `MR_SCRIPT` selects the script under test.
