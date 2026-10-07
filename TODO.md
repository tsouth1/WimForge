# TODO - WimForge (Windows OS media patching)

Last updated: 2026-10-06. This file holds the index and the **open** items only. Completed work (built steps, confirmed checks, steps 1, 3, 5, 11 and 14, and the History) is in [`TODO_DONE.md`](TODO_DONE.md).

**Build under test: `MediaRefresh_v2.4.ps1`.** It contains everything from v2.1-v2.3 (steps 1 and 3) plus the catalog download layer (step 5). The older scripts in `archive\` are kept for history only; nothing below needs them.

Where v2.4 stands:

- **Media / ISO testing scope (decision, 2026-09-28):** real testing of the refreshed media folder, the ISO, Patch boot.wim and the CA 2023 media is **paused for every OS except Windows 11 and Windows Server 2022 or later**. The Windows 10 LTSC profiles (2019, 2021 KMS, 2021 IoT) are tested for install.wim (and WinRE) only: untick the media folder for them. The code for Win10 media stays as it is (including the 1809 boot.wim fallback of 2026-09-28, which stays mock-tested only), but no real run is needed to close a step.

- **Mock test kit:** 7 suites, 668 checks, all passing on Windows PowerShell 5.1 and PowerShell 7.6 (2026-10-06).
- **Real Microsoft Update Catalog:** every built-in rule for all five profiles picks the right entry from the live catalog (2026-09-24, step 2A), confirmed by GUI dry runs of all five OSes on the build machine the same evening. Real GUI downloads (LTSC 2019, LTSC 2021 KMS, Win11 24H2) the same evening found one pruning bug, fixed (step 2A).
- **Real images and real DISM:** three complete real v2.4 servicing runs, all with gate PASSED: Win11 24H2 Enterprise on 2026-09-23 and 2026-09-25 (English only), and **LTSC 2019 with ten languages on 2026-09-25 16:15-20:30** (`LOGS\`: preflight x2 + full run; WinRE was switched off). **LTSC 2021 KMS with four languages (de-de, ja-jp, zh-cn, zh-tw) on 2026-10-05 12:42-14:54, gate PASSED** (build 10.0.19044.7727, WinRE on; see TODO_DONE.md 2B). **Win11 24H2 with es-mx on 2026-10-06 06:43-08:27, gate PASSED** - the first run with the ADK's DISM and the first Win11 run with a language, with app removal, patched boot.wim, media and a real SCCM import (see TODO_DONE.md 2B). IoT LTSC 2021 and Server 2022 have not been serviced on v2.4 yet (a v2.2 run of IoT LTSC 2021 finished with 0 verify issues on 2026-09-21, but v2.3/v2.4 changed the servicing code).

## Index

Step numbers are kept from earlier versions of this list because the script, the logs and older notes refer to them. **Done:** steps 1, 3, 5 (built into v2.4), 2 (validation, closed 2026-10-06; its open runs moved to step 6), 4 (ADK DISM, confirmed 2026-10-06), 11 (app removal, confirmed 2026-09-29) and 14 (download only what is missing, confirmed 2026-09-29) - see `TODO_DONE.md`.

| # | Step | Owner | Status |
|---|------|-------|--------|
| [6](#s6) | Upgrade-package media readiness and validation round 2 (incl. the runs carried over from step 2) | Claude + operator | **Now** |
| [7](#s7) | SCCM import: new tab, local copy to content source, import, distribute | Claude | OS image import confirmed on the real site 2026-10-06; upgrade package and console checks open |
| [8](#s8) | Hard cancel, batch queue, scheduled run | Claude | Last feature |
| [9](#s9) | Housekeeping and final documentation | Claude | Ongoing |
| [10](#s10) | Operator UX: INSTRUCTIONS.md + Instructions tab, saved settings, utility menu, Languages tab from Languages.json, colour schemes | Claude (+ operator for the inventory script) | 10c, 10e, 10f and 10d Cleanup Mountpoints built (confirm in the real GUI); 10a INSTRUCTIONS.md written and 10b Instructions tab built; 10d Image Inventory waits for the operator's script |
| [12](#s12) | Windows UEFI CA 2023 boot media: CA 2023 media + ISO alongside the standard ones (12a); bootable WinPE rescue ISO (12b) | Claude | 12a built (confirm on a real run and a real boot); 12b not started |
| [13](#s13) | Expand OS support: Windows 11 25H2, Windows 11 26H2, Windows Server 2025 | Claude + operator | 26H2 done through step 17 (real run 2026-10-01, gate PASSED); 25H2 and Server 2025 not started |
| [15](#s15) | Run configs and the command line: `-Config <file> [-Preflight]` runs without the window | Claude | Built (mock-tested + command line smoke-tested); confirm with a real elevated run |
| [17](#s17) | Adding or changing an OS without a new WimForge: release placeholder, stable folder key, Tools > New OS from existing / Rename OS / Check OS profile / Edit OS profile | Claude | Built (mock-tested, dialog tested on real WPF); confirm with a real 26H2 profile |
| [16](#s16) | Media-only run: build the media / ISO around the existing NEWWIM\install.wim, without servicing install.wim again | Claude | Built 2026-10-01 (mock-tested); confirm with a real media-only run (Win11 / Server 2022) |
| [18](#s18) | SCCM import from a WimForge server that is not the content source server: browse / connect to a UNC network path, copy over the network | Claude | Network copy, import and distribution confirmed 2026-10-06; picking the folder by browsing still to confirm |

Order of work: steps 2 and 4 are closed (2026-10-06); finish the real runs in 6, then the new features. The SCCM import (7) waits for a validated image, and hard cancel / batch queue (8) comes last because it changes how every other step is started and stopped.

---

<a id="s6"></a>
## 6. Upgrade-package media readiness and validation round 2

**Owner:** Claude + operator. **Depends on:** 2 (closed 2026-10-06; its open runs and checks are below).

- **Built 2026-09-27** (details in TODO_DONE.md): setup.exe and the boot manager files on the media come from the patched boot.wim; boot.wim is patched only for the media. Partly confirmed on the 2026-09-29 Win11 run (files replaced on the media).
- [ ] **To confirm:** boot the ISO or a USB stick made from `NEWWIM\Media` on a test machine (UEFI with Secure Boot) and start Setup. (The 2026-10-06 Win11 run built `NEWWIM\Media` with the patched boot.wim again; no ISO was ticked.)
- The engine follows Microsoft's order (LCU, cleanup, then NetFx3 and .NET CU). If a real run shows the .NET CU or the LCU missing after deployment, test the alternative order and let the validation gate (step 3) decide.
- The operator runs the second round: an OS with the downloader-fed patch set, media folder built, change log and gate checked.

### Carried over from step 2 (closed 2026-10-06)

Step 2 was closed on 2026-10-06: the catalog layer (2A) and five real servicing runs with gate PASSED - Win11 24H2 on 2026-09-23, 2026-09-25, 2026-09-29 and 2026-10-06 (with es-mx, on the ADK's DISM), LTSC 2019 with ten languages on 2026-09-25 and LTSC 2021 KMS with four languages on 2026-10-05. The record is in `TODO_DONE.md`, step 2. The items below were still open and belong to this round.

**Before any run**

- `Unblock-File` the script and run it from elevated Windows PowerShell 5.1, with the current `MediaRefresh_v2.4.ps1` from `main` copied to the server.
- **Antivirus exclusion: check it is really in place.** The v2.2 IoT 2021 run took about 3h53m. A few steps took far longer than the rest (LCU pass 1 ~46 min, LCU final ~38 min, one .NET CU ~29 min, cleanup ~24 min, against ~5-7 min per language pack). Its DISM log has 30,000+ benign `Error CSI ... Matching binary ... missing for component ... dualModeDriver` entries (Hyper-V driver components). Both point to real-time scanning fighting DISM. Confirm the exclusion covers the MediaRefresh folder including each OS's `MOUNT` subfolder, then compare the timings on the next run. **Update 2026-09-25:** the LTSC 2019 ten-language run spent 1 h 40 min in component cleanup alone - check the exclusion covers `<repository root>\<OS>\MOUNT` before the Server 2022 runs (four indexes).
- Tens of GB free. v2.4 checks this itself and archives the previous `NEWWIM` output, so nothing needs renaming by hand.
- Fill `PATCHES` with "Download patches..." (after 2A) or by hand; the SSU always goes into `PATCHES\SSU` by hand.

**Runs, in order** (full test plan in `MediaRefresh_Review_and_Roadmap.md`, section 0)

1. [ ] Preflight on Server 2022 (Win11 24H2, LTSC 2019, LTSC 2021 KMS and IoT passed preflight on 2026-09-25 / 27). Check the ISO role lines, patch counts and the `Detected indexes` line (all four indexes serviced).
   - **Index selection, confirmed 2026-09-27:** LTSC 2019 has one index; KMS [1] Enterprise LTSC / [2] Enterprise N LTSC - build **index 1**; IoT [1] Enterprise LTSC / [2] IoT Enterprise LTSC - build **index 2, always**; Win11 24H2 has 10 indexes - build **index 3** (Enterprise) only; Server 2022 has 4 indexes - **all** serviced. The built-in IoT profile had `preferredIndex = 1` (used only when no image name matches, but then it would have fallen back to the non-IoT edition) - **fixed to 2**. A run also WARNs now when the edition name matches an index other than the profile's `preferredIndex`. 4 new checks on the real layouts (test kit 339).
   - **Action for the operator:** the build machine's `Profiles\Win10_IoT_Enterprise_LTSC_2021.json` still has `"preferredIndex": 1` - set it to 2, or delete the file and press Reload profiles to regenerate it.
2. [ ] LTSC 2021 KMS with all ten languages.
3. [ ] Server 2022 (English only, four indexes). Confirm WinRE is serviced once and the same winre.wim is reused for every index.
4. [ ] IoT LTSC 2021 (repeat on v2.4).

- On a real console, confirm that clicking in the console no longer pauses the run (Quick Edit fix) and that the window stays responsive during mount and patch.
- After each run, put `MediaRefresh_*.log`, `DISM_*.log` and the `ChangeLog_*` files from `LOGS` into `C:\MEDIAPATCHING\LOGS\` (never into the repository). The `VERIFY` lines are the evidence that the LCU and languages are really in the image.

**Done when:** each OS produces an install.wim whose VERIFY lines show the expected RollupFix, languages and fonts, the validation gate says PASSED, and there is no crash or hang.

**Feature checks still open (tick off during the runs)**

- [ ] A `Profiles` folder with five JSON files appears beside the script on first start; the OS list, the support-date line under it and "Reload profiles" work. An edited file applies to the next run, and a broken file is reported and skipped.
- [ ] The preflight log shows the `Profile:`, `Support ends`, `... order:` and `Free space on ...` lines, and packages are applied in the logged order.
- [ ] The free-space estimate is neither too strict nor too loose (otherwise tune `minFreeGB`, or set `spaceCheck` to `warn`).
- [ ] The header shows the OS and a phase that matches the log throughout a run ("Servicing install.wim (index N of M)" on Server), then Done, Failed or Cancelled.
- [ ] Section B (derived dates, hotfix list, appx inventory) is worth reading on real data, or needs trimming. **Partly done 2026-09-25:** the staged-appx list included `Deleted` and `Merged`, which are Windows' housekeeping folders under WindowsApps, not packages; only folders named like packages (`<Name>_<Version>_...`) are listed now (`Test-AppxPackageFolder`). Still to judge: whether the rest of Section B is worth reading.

**Profile data and catalog**

- [ ] (Still open 2026-10-06: the Win11 run logs `Support end date not set in the profile.`) Fill in the Win11 24H2 and Server 2022 end-of-support dates from the Microsoft lifecycle pages (the `endOfSupport` key in the JSON files; the built-in profiles in the script can be updated at the same time).
- [ ] **1809 Setup DU:** the newest one is from 2025-11. Setup DUs for 1809 are released less often than Safe OS DUs, so this is expected, but worth a glance at the catalog before relying on it.

<a id="s7"></a>
## 7. SCCM import: new tab, local copy to content source, import, distribute

**Owner:** Claude. **Depends on:** 1 (dated output), 3 (change log for the image comment, validation gate so a failed image is never imported), 5 (a current image), 6 for the upgrade-package path.

**Built 2026-09-27** (SCCM tab, Connect, check-then-confirm import, run record, distribution - details in TODO_DONE.md). Mock-tested only.

- [x] **OS image import confirmed 2026-10-06** (`SccmImport_20261006_082743.log`, right after the Win11 24H2 run): install.wim (7.2 GB) copied to a dated folder on the content source share, imported as OS image `Windows 11 Enterprise 24H2 202610`, package ID returned, distribution to one distribution point started. **Still to check in the console:** source path, version = build (10.0.26100.9457), and that the distribution finished.
- [ ] **To confirm on the real site:** an upgrade package from a run with the media folder. If a cmdlet or parameter behaves differently on this CM version, the `SccmImport_*.log` shows the exact error.

**Done when:** the tab validates its fields, the name is pre-filled and follows the OS selection, the picker returns a usable UNC source path, the local copy lands in the chosen folder, and a finished image that passed the validation gate is imported from a `\\<SCCM-SOURCE-SERVER>\...` path and distributed to the chosen DP or DP group as the chosen package type.

<a id="s8"></a>
## 8. Hard cancel, batch queue, scheduled run

**Owner:** Claude. **Depends on:** 3, 5, 7 (they define what one OS run is).

- **Hard cancel:** stop a running DISM call, then clean up (discard/unmount any live image, clear mount folders, dismount ISOs). Cancel today works at the next safe point between operations. The start-up stale-mount cleanup is the safety net for anything orphaned.
- **ISO mount hygiene (2026-09-22):** two related fixes, small enough to do independently of the rest of this step. The first (detect ISOs already mounted at start, `Clear-StaleIsoMounts`) is built - see TODO_DONE.md.
  - **Keep ISOs mounted until the completion dialog is dismissed.** Today `Invoke-MediaRefresh` dismounts every ISO it mounted in its own `finally` block, so they are gone before the completion dialog even appears. Change this so a **successful** run leaves its ISOs mounted, hands their paths back to the GUI (the background-run result), and the GUI dismounts them only after the user clicks OK on the completion dialog (Dism cmdlets are available on the main thread too, since the module is imported at start-up). A **failed or cancelled** run should keep dismounting immediately in the engine's `finally`, as a safety net — there is no guaranteed "OK click" to hang cleanup on when the run didn't finish normally. Decide whether Preflight's own completion dialog gets the same treatment for consistency, or dismounts right away since it never touched an image.
- **Batch queue:** tick several OS profiles and process them one after another, one change log each, a summary at the end, the phase line showing "OS 2 of 3", and cancel semantics that make sense (skip this OS / stop all).
- **Scheduled run** (later): a monthly unattended run after Patch Tuesday with a summary file or email.

<a id="s9"></a>
## 9. Housekeeping and final documentation

**Owner:** Claude. **Ongoing.**

- Keep `MediaRefresh_Review_and_Roadmap.md` and this file in step with the script; update the roadmap as steps close.
- Check WimWizard's licence before reusing any of its code (steps 5 and 7).
- Version numbering: v2.4 is the build under test; once the step 6 runs pass it becomes the first tested release with a clean version number (and ideally a file name without the version, with older builds left in `archive\`). Default repository root settled 2026-09-28: the script's own folder until one is saved (no fixed drive letter).
- Minor code items from the review: rename the `$matches` variable; make OS display names match the project list.
- Operator guide: superseded by step 10's `INSTRUCTIONS.md` (folders, ISO roles, preflight first, where logs and change logs land, plus a full GUI walkthrough) rather than a separate write-up here.

<a id="s10"></a>
## 10. Operator UX: INSTRUCTIONS.md + Instructions tab, saved settings, utility menu, Languages tab

Built (details in TODO_DONE.md): 10a `INSTRUCTIONS.md`, 10b Instructions tab, 10c Save settings / Reset to defaults, 10d Tools menu with Cleanup Mountpoints, 10e Languages tab from `Languages.json`, 10f General Settings tab with colour schemes. 10d "Clear Settings" was dropped (2026-09-27).

**Still open**

- [ ] **10a:** the operator to read `INSTRUCTIONS.md` through on the build machine; keep it in step with the GUI as features are added.
- [ ] **10b** **To confirm in the real GUI:** open the Instructions tab, scroll through, switch colour schemes, edit `INSTRUCTIONS.md` and press Reload.
- [ ] **10c** **To confirm in the real GUI:** tick / untick a few boxes and languages for one OS, press Save settings (log: "Settings for <OS> saved to ...\Settings\<folder>.json"), switch to another OS and back, restart the tool - the choices come back; press Reset to defaults and confirm.
- [ ] **10d Cleanup Mountpoints** **To confirm in the real GUI (elevated):** with nothing mounted, Tools > Cleanup Mountpoints says there is nothing to clean up. Then mount one of the OS's ISOs by hand (double-click it in Explorer), run it again: the ISO is listed, and on Yes it is dismounted.
- [ ] **10e** **To confirm in the real GUI:** start the tool, open the Languages tab: 20 entries as `Full name - code`, `Profiles\Languages.json` created beside the profile files, the selected OS's defaults pre-selected; untick one, run a Preflight, and check the log's `Languages:` line lists codes.
- [ ] **10e** **New languages not yet in any run:** ca-es, cs-cz, hu-hu, pl-pl, pt-pt, ro-ro, ru-ru, sk-sk, sv-se, tr-tr. The preflight shows whether each OS's Language Pack ISO has `Microsoft-Windows-Client-Language-Pack_x64_<code>.cab` for them (it names any that are missing). ca-es: no evidence so far that its file name differs on any ISO - an earlier note assumed it might, from general knowledge that Catalan was a Language Interface Pack on some Windows 10 releases; nothing in the operator's ISOs or logs shows that. Check it with the first preflight that selects it.
- [ ] **10f** **To confirm in the real GUI:** open General Settings, try each scheme (all tabs, including the OS drop-down list and the Languages selection), leave one selected, restart the tool - it comes back; check the Log colours on a Preflight.
- [ ] **10d Image Inventory** **Image Inventory** — opens a file picker for an arbitrary image file (a WIM, an ESD, or an index within one — the operator to confirm exactly what the picker should target), then runs an inventory script against it and shows/saves a complete inventory: enabled optional features, installed languages, installed KBs, and whatever else the script reports. **The operator is providing this script.**
  - **This is the same request as the "inventory script" noted under step 3b** ("Input from the operator: the inventory script he offered; use it as the starting point for the data collection") — that script became the basis for Section B of the per-run change log (the finished image's packages/capabilities/features/appx/hotfixes, built in v2.3). This menu item is the **on-demand, any-image** version of the same idea: instead of only running automatically against the image a servicing run just produced, it runs against whatever image file the operator points it at, on request. Once the operator's script is in hand, prefer reusing step 3b's data model and HTML/CSV writer (`Write-ChangeLog`'s row/column shape) for the output rather than inventing a second report format, so an ad-hoc inventory and a run's Section B look and read the same way.

**Done when:** `INSTRUCTIONS.md` exists and covers the folder layout, every GUI control, and exactly where each log type lands; the Instructions tab renders it as formatted Markdown (headings/lists/bold actually look like headings/lists/bold, not a wall of `#`/`-`/`**` characters); pressing "Save settings" stores the selected OS's choices in `Settings\<folder>.json` and they reappear whenever that OS is selected, including after a restart and after the Profiles folder is regenerated; and the menu's two actions both work without requiring a full servicing run — Cleanup Mountpoints can be built and mock-tested now, Image Inventory once the operator's script arrives. 10e: the Languages tab lists exactly the entries of `Profiles\Languages.json` as "full name - code", created from the built-in list when missing, and each profile's defaults are pre-selected from it.

<a id="s12"></a>
## 12. Windows UEFI CA 2023 boot media: 12a OS media and ISO (built), 12b WinPE rescue ISO

<a id="s12a"></a>
### 12a. CA 2023 media and ISO, alongside the standard media - built 2026-09-27; confirm on a real run

**Built** (details in TODO_DONE.md): option "Also build CA 2023 media alongside it", `NEWWIM\Media_CA2023` and a `_CA2023` ISO with the CA 2023 boot files from the patched boot.wim, embedded signature verified.

- [ ] **To confirm on a real run:** tick media, ISO, Patch boot.wim and CA 2023 for Windows 11 24H2 and Server 2022 (1809 and 21H2 media testing is paused, 2026-09-28) - the EX folders should be in every patched boot.wim; the log shows `VERIFY CA 2023 media: bootx64.efi is signed by CN=Windows UEFI CA 2023`. Boot the `_CA2023` ISO (or a USB made from `Media_CA2023`) on a UEFI PC with Secure Boot on whose DB has the 2023 certificate - check with `[System.Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI db).bytes) -match 'Windows UEFI CA 2023'` (KB5025885) - and start Setup. Ideally also on a PC with the PCA 2011 revocation applied: the CA 2023 media boots, the standard media does not.
- [ ] **The installed OS** (deployed from install.wim): Setup / the task sequence writes the PCA 2011 boot manager to the EFI partition until Windows' Secure Boot servicing replaces it. KB5025885's command for the CA 2023 boot manager is `bcdboot c:\windows /f UEFI /s <ESP> /bootex` - a candidate step for the SCCM task sequence (after Apply Operating System), not an image change. To decide with the operator.
- [ ] **SCCM boot images / PXE**: built from the ADK by Configuration Manager, outside WimForge. Research item: what the CM / ADK version in use does for CA 2023 boot images.

<a id="s12b"></a>
### 12b. Bootable WinPE recovery/rescue ISO (ADK-based, 2023 UEFI CA signed)

**Owner:** Claude. **Depends on:** 4 (the ADK-vs-host-DISM decision settles which ADK tooling is already in play; this step needs the ADK's `copype`/WinPE tooling regardless of what that decision picks for regular servicing). **2026-09-22: clarified scope.**

This is a **separate deliverable from the per-OS WinRE servicing already built** (the WinRE step in `Service-InstallIndex`/`Service-WinRe` patches the recovery partition that ships *inside* each serviced `install.wim`). This new item is a **standalone, bootable troubleshooting/recovery ISO**, built independently of any specific OS profile:

- **Base:** the ADK's own WinPE (`copype amd64 <dest>` / `winpe.wim` from the installed Windows ADK + WinPE add-on), not an OS ISO's WinRE. Confirm the ADK version installed on the build host is recent enough to matter for the next point.
- **Signing:** the recovery ISO's boot components must chain to the **2023 Windows UEFI CA** rather than the older 2011 one, for Secure Boot trust going forward. **Largely answered by 12a (2026-09-27):** no self-signing - patch the ADK's `winpe.wim` with a 2024-04 or later LCU, then apply the same swaps from its `Windows\Boot\EFI_EX`, `FONTS_EX`, `DVD_EX` (`Save-Boot2023Files` + `Set-Media2023BootFiles` work on any media folder, so a `copype` folder is fine), build the ISO with `efisys_ex.bin`, and verify with `Get-EmbeddedSignerIssuer`. Still to check: whether the installed ADK's WinPE media tooling already offers this (e.g. a `/bootex` switch on `MakeWinPEMedia`; not confirmed), and which ADK / WinPE add-on version is on the build host.
- **Contents:** beyond the bare ADK WinPE base, decide with the operator what tools/drivers/scripts should be baked into the recovery image (storage/network drivers for the target hardware, diagnostic tools, etc.) — open question, not yet scoped.
- **Build/output:** likely reuses the same `oscdimg`-based ISO-building code already used for the regular media/ISO path (step 6/`Build-Iso`), pointed at the WinPE working folder instead of a serviced OS media folder. Output location and naming convention TBD (a dedicated folder outside the per-OS `MediaRefresh\<OS>\` structure, since this isn't tied to any one OS).

**Done when:** a bootable WinPE-based recovery ISO can be built from the ADK on demand, its boot components are confirmed to chain to the 2023 UEFI CA, and it boots and passes Secure Boot on a representative target machine.

<a id="s13"></a>
## 13. Expand OS support: Windows 11 25H2, Windows 11 26H2, Windows Server 2025

**Owner:** Claude + operator. **Depends on:** 1 (profile schema/folder conventions) and 5 (acquisition layer - each new OS needs its own `catalogSearch` rules). Added 2026-09-22, requested by the operator.

- **DISM (from step 4, closed 2026-10-06):** runs use the ADK's DISM when it is installed; the server has 10.0.26100.9457. 25H2 / 26H2 and Server 2025 are newer than the Server 2022 host, so the preflight's `ADK DISM <version>; image <version>` line must show an ADK at least as new as each new image (no "older than the image" WARN) - update the ADK on the server first if it does not.
- **Windows 11 26H2 - done through step 17 (2026-10-07 review).** The operator made the profile with Tools > New OS from existing and ran it for real on 2026-10-01 (gate PASSED, build 26300.9457, apps removed, boot.wim and media built; see TODO_DONE.md History). What is left for 26H2 is in step 17 (Check OS profile and the catalog title question) and the DISM point below.
- [ ] **26H2 and the ADK's DISM (found 2026-10-07):** that run (15:58-16:39) came before the ADK DISM change (16:56 the same day), so it used Windows' own DISM 10.0.20348. The next 26H2 run will use the ADK's DISM 10.0.26100.9457, which is **older than the 26H2 image (26300)** - the preflight will WARN. Either install a newer ADK on the server (one at least as new as 26300, if Microsoft has released one) or accept the WARN and compare the result with the 2026-10-01 run; if that run fails, the DISM is the first suspect.
- **Still to do here:** Windows 11 25H2 and Windows Server 2025 (bullets below). 25H2 can be made the same way as 26H2 (New OS from existing); Server 2025 needs its own catalog titles checked.

Add these three OSes to the set the tool services, alongside the existing five (LTSC 2019, LTSC 2021 IoT, LTSC 2021 KMS, Win11 24H2, Server 2022).

- **New profile per OS.** Same shape as the existing five: `folder` (and the matching `MediaRefresh\<folder>\{ISO,LOGS,MOUNT,OLDWIM,NEWWIM,PATCHES,TEMP,WINPE,WINRE,WORKING}` tree), `editionRegex`/`preferredIndex` (or `serviceAllIndexes` for Server), `lpPattern`, `defaultLanguages`, `endOfSupport`, and a `catalogSearch` block (LCU/NetCU/SafeOS/SetupDU search strings). Like the current five, treat every search string as best-effort until spot-checked against the real catalog - not assumed correct on the first try.
- **Windows 11 25H2 and 26H2.** Confirm current release/servicing status and exact catalog title conventions before building the profile - Microsoft Update Catalog title text for a newer release can differ from the 24H2 pattern already in use, and 26H2 in particular should be confirmed as actually released and catalog-searchable before relying on it. Decide whether 25H2/26H2 are meant to replace the 24H2 profile over time or run alongside it as separate profiles - affects whether the 24H2 profile is retired later.
- **Windows Server 2025.** Likely follows the same `serviceAllIndexes = true` / every-index-patched-and-recombined pattern as Server 2022, with the Server language pack pattern (`Microsoft-Windows-Server-Language-Pack_x64_{0}.cab`). Confirm the LCU/NetCU/SafeOS/SetupDU catalog title conventions for 2025 specifically rather than assuming they match 2022's wording.
- **Source media.** The operator supplies the OS ISO (and FOD/language ISO where relevant) for each new OS in its `ISO\` folder, same as the existing five - nothing here can be built without the source media in hand.
- **.NET CU check.** While building these, check how each ships its .NET CU. For 1809 it is one combined catalog entry that downloads one file per .NET version (step 5, "Real catalog facts"); a rule's `search` also accepts an array of terms if a product needs more than one entry.

**Done when:** a profile exists for each of the three OSes (built-in or added the same way the operator can add any custom OS profile), the servicing engine runs against each with no code changes beyond the profile files, and at least one real (or dry-run) catalog search per OS confirms the search strings actually return the right update.


<a id="s15"></a>
## 15. Run configs and the command line (2026-09-28) - built; confirm with a real elevated run

**Built** (details in TODO_DONE.md): Tools > Save run config..., `MediaRefresh_v2.4.ps1 -Config <file> [-Preflight]`, exit codes 0 / 1 / 2 / 3.

- [ ] **To confirm:** a real elevated `-Config` run (and a preflight) on the build machine.

---

<a id="s16"></a>
## 16. Build the media from an existing install.wim (media-only run)

**Owner:** Claude. **Asked 2026-09-28.** **Status:** built 2026-10-01 (mock-tested); confirm with a real media-only run on Windows 11 or Server 2022.

**Built** (details in TODO_DONE.md): option `ReuseInstall` - "Use the existing NEWWIM\install.wim instead (media-only run)".

- [ ] **Done when:** a real media-only run on the Windows 11 24H2 or Server 2022 folder builds the media (and ISO) from the install.wim of the last passing run in well under an hour, and the full run is unchanged (Win10 media testing is paused, 2026-09-28).
---

<a id="s17"></a>
## 17. Adding or changing an OS without a new WimForge (2026-09-30) - built; confirm with a real 26H2 profile

**Built** (details in TODO_DONE.md): release placeholder `{version}`, folder as the stable key, Tools > New OS from existing / Rename OS / Check OS profile / Edit OS profile / Open Profiles folder. New OS from existing used for real for the 2026-10-01 26H2 run.

- [ ] **To confirm on the build machine:** New OS from existing for Windows 11 26H2 with its ISO, then Check OS profile - does the catalog title 26H2 updates under their own release name? If not, the searches keep the 24H2 / 25H2 wording (as for 25H2 today).
- [ ] **Windows 10 Enterprise 22H2 (`Win10_Enterprise_x64`, new OS, 2026-10-07) - first run FAILED.** Made from the LTSC 2019 profile; OS ISO `SW_DVD9_Win_Pro_10_22H2.38_64BIT_English_Pro_Ent_EDU_N_MLF` (base 10.0.19045.6456, ten editions) plus the 2004-family Language Pack and FOD ISOs; English only; ADK DISM 10.0.26100.9457. Download patches fetched LCU KB5129236 (2026-09, out-of-band; the same KB as LTSC 2021), .NET CU KB5126046 (3.5 and 4.8) and Safe OS DU KB5067017 (2025-10). Run 12:18-13:00: 15 apps removed, WinRE serviced (servicing stack from the LCU + Safe OS DU), then the LCU on install.wim failed after 34 minutes with `0x80073713` ("An error occurred applying the Unattend.xml file from the .msu package"); the image was discarded, nothing was written to `NEWWIM`.
  - **Wrong edition:** the profile kept LTSC 2019's edition pattern `^Windows 10 (IoT )?Enterprise LTSC( 2019)?$`, so nothing matched and the run fell back to **index 1, Windows 10 Education** (WARN in the preflight and the run). **Action for the operator:** Tools > Edit OS profile for this OS: `editionRegex` `(?i)^Windows 10 Enterprise$` and `preferredIndex` 3, then Read apps from the ISO again (the app list was read from Education). Also `lpPattern` / `defaultLanguages` / `endOfSupport` came from LTSC 2019 - the support line already reads "Support ended 2025-10-14", so that was set.
  - **Why the LCU failed (DISM log):** the commit failed in the LCU's **Extended Security Updates advanced installer** (`ExtendedSecurityUpdatesAI.dll`, component `Microsoft-Windows-Security-SPP-Component-ExtendedSecurityUpdatesAI`, first install, error `0x80070659` = the installation was rejected), which rolled back the whole RollupFix 19041.7727. Windows 10 22H2 (non-LTSC) left support on 2025-10-14, so its 2026 LCUs are ESU updates; the same KB installed into LTSC 2021 KMS on 2026-10-05 because LTSC 2021 is still supported. Most likely the ESU installer refuses this edition / image without ESU eligibility; not yet ruled out: the Education edition (wrong index) and the ADK's DISM (the KMS run used Windows' own DISM).
  - **Next:** fix the edition (above) and re-run. If it fails the same way, the 22H2 image needs ESU handling (check whether the organisation has Windows 10 ESU, and what Microsoft documents for adding ESU LCUs to an offline image) - Claude to research; a run with Windows' own DISM would rule out the ADK (there is no switch for it yet; Claude can add one).
  - **Not affected:** WinRE took the servicing stack and the Safe OS DU without error. Other DISM `Error` lines are the usual noise.
- **Not built (idea 8):** a full profile editor tab - hold until the tools above prove not to be enough.

---

<a id="s18"></a>
## 18. SCCM import when WimForge does not run on the content source server - built; confirm with a real import

**Owner:** Claude. **Asked 2026-10-01.** **Status:** built 2026-10-01 (mock-tested); confirm with a real import from the new server.

**Built** (details in TODO_DONE.md): UNC content source on any server, mapped drives resolved, Shares... dialog, reach / write / free-space checks, robocopy.

- [x] **Copy over the network, import and distribute confirmed 2026-10-06** (Win11 24H2): WimForge on the build server (`J:\WimForge`) copied install.wim with robocopy to `\\<SCCM-SOURCE-SERVER>\OS\...` (7.2 GB in 14 s, 330 GB free reported), imported it from that UNC path and started the distribution. The log does not show whether the folder was picked by browsing or typed.
- [ ] **Done when:** from a WimForge server that is not the content source server, the SCCM tab can pick a folder on the site server's share by browsing, the plan shows the UNC path and its checks, and a real import copies the image over the network, imports it from that UNC path and distributes it.
