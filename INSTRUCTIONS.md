# WimForge - operator guide

WimForge builds updated Windows images for Configuration Manager (SCCM) deployment. For each operating system it takes the Microsoft ISO, adds the latest updates (and, where wanted, extra languages), cleans and verifies the result, and writes an import-ready `install.wim`. It can also build a refreshed installation media folder and ISO, for OS Upgrade Packages or for booting a PC from USB or ISO.

This guide covers the folders WimForge expects, every part of the window, the recommended order of work, and where every log and report is written.

## Before you start

- **Run it elevated in Windows PowerShell 5.1.** Right-click Windows PowerShell and choose "Run as administrator". The script refuses to start without administrator rights.
- **Unblock the script once** after copying it to the build machine: `Unblock-File .\MediaRefresh_v2.4.ps1`
- **Start it** from its own folder: `.\MediaRefresh_v2.4.ps1`. The window opens; the console behind it can be minimised but must stay open.
- **Windows ADK Deployment Tools** are needed only to build an ISO (WimForge uses the ADK's `oscdimg.exe`).
- **Internet access** is needed only for "Download patches...": it installs the MSCatalogLTS PowerShell module for the current user the first time, and searches catalog.update.microsoft.com.
- **Free disk space:** roughly three times the size of the source image plus 6 GB, plus one ISO's size for the media folder and another for each ISO. The preflight check works out the figure and tells you.
- **Antivirus exclusion:** exclude the repository root, including every `<OS>\MOUNT` folder, from real-time scanning. Without it DISM steps such as component cleanup can take hours instead of minutes.
- **Use an NTFS drive** for the repository root. Images cannot be mounted on ReFS.

## Folder layout

Everything lives under one **repository root** (the default is `F:\mediaRefresh`; change it on the Source and targets tab). Inside it there is one folder per operating system:

- `Win10_Enterprise_LTSC_2019` - Windows 10 Enterprise LTSC 2019 (IoT)
- `Win10_IoT_Enterprise_LTSC_2021` - Windows 10 IoT Enterprise LTSC 2021
- `Win10_Enterprise_LTSC_2021_KMS` - Windows 10 Enterprise LTSC 2021 (KMS)
- `Win11_Enterprise_24H2` - Windows 11 Enterprise 24H2
- `Windows_Server_2022` - Windows Server 2022

WimForge creates the sub-folders of an OS folder the first time that OS is run:

- `ISO` - put the ISOs here (see below).
- `PATCHES` - the updates, one sub-folder per kind:
  - `PATCHES\SSU` - the servicing stack update, **always placed by hand** (LTSC 2019: KB5005112; LTSC 2021 IoT and KMS: `ssu-19041.3562-x64.msu`). WimForge never downloads into or deletes from this folder.
  - `PATCHES\LCU` - the latest cumulative update. On Windows 11 24H2 this folder may also hold a checkpoint update; that is expected (see "Updates and features").
  - `PATCHES\NETCU` - the .NET Framework cumulative update (one or two files).
  - `PATCHES\SAFEOSDU` - the Safe OS Dynamic Update, used for WinRE.
  - `PATCHES\SETUPDU` - the Setup Dynamic Update, used for the refreshed media.
- `NEWWIM` - the finished output (see "What a run produces").
- `LOGS` - every log and change log for this OS (see "Where the logs are").
- `ProvisionedApps.json` - the app list shown on the Apps tab, read from the ISO. Safe to delete; it is read again.
- `OLDWIM`, `WORKING`, `TEMP`, `MOUNT`, `WINRE`, `WINPE` - WimForge's own working folders. Leave them alone; they are cleared at the start of every run.

**The ISO folder.** Put one ISO of each kind in it; the file names do not matter, because WimForge recognises each ISO by what is inside it:

- the **OS ISO** (always needed);
- the **Language Pack ISO** (only when languages are added);
- the **Features on Demand (FOD) ISO(s)** (only when languages are added; a second FOD ISO is fine and is used as an extra source).

Windows 11 24H2 and Server 2022 are built English-only and need only the OS ISO. Get fresh Microsoft ISOs each servicing cycle.

**Beside the script** WimForge keeps two folders of its own:

- `Profiles` - one JSON file per operating system (edition, language pack pattern, catalog search rules, end-of-support date, ...) and `Languages.json` (the list on the Languages tab). They are written from the built-in defaults the first time. Edit a file and press "Reload profiles" to use the change; a broken file is reported in the log and skipped. To go back to the built-in defaults, delete the file (or the whole folder) and press "Reload profiles".
- `Settings` - the choices saved with "Save settings" (one file per OS) and `General.json` (the repository root and the colour scheme).

## Recommended order of work

1. **Select the operating system** on the Source and targets tab.
2. **Fill PATCHES:** press "Download patches...", check the list it shows, and confirm. Put the SSU into `PATCHES\SSU` by hand (LTSC 2019 and LTSC 2021 only).
3. **Run a preflight:** tick "Preflight check only" and press "Start refresh". It takes about a minute and changes nothing. In the log, check the ISO roles, the patch counts, the language packs and the `Selected client image index` line.
4. **Run the real build:** untick "Preflight check only", choose the outputs, updates, languages and the apps to remove (Apps tab), and press "Start refresh". A run takes one to four hours depending on the OS and the number of languages.
5. **Check the result:** the completion message, the `VALIDATION GATE` line at the end of the log, and the change log (see below).
6. **Import into SCCM** the `install.wim` from `NEWWIM` (or use the `Media` folder for an OS Upgrade Package).

Press "Save settings" once the ticks and languages for an OS are how you want them; they come back every time that OS is selected.

## The window

### Header

- **Left:** the tool name.
- **Right:** the operating system being worked on and the current phase (for example "Servicing install.wim (index 1)", then "Done", "Failed" or "Cancelled"). While nothing runs it shows the selected OS and "Idle".
- **Tools** (top right): a menu with maintenance tools - see "Tools menu".

### Source and targets tab

- **Repository root** - the folder that holds the OS folders.
- **Operating system** - the OS to work on. The line under it shows the profile file in use and the end-of-support date (in red when support ends within 180 days or has ended).
- **Download patches...** - searches the Microsoft Update Catalog for the selected OS and every ticked update kind (LCU, .NET CU, Safe OS DU, Setup DU). It always shows what it found first (title, KB, release date, and for the LCU whether it is the Patch Tuesday or an out-of-band release) and downloads only after you confirm. Older files of the same kind are then removed from that PATCHES folder. `PATCHES\SSU` is never touched.
- **Reload profiles** - re-reads the files in `Profiles`.

**Outputs:**

- **Preflight check only** - checks ISOs, patch folders, language packs, edition and free space in about a minute; changes nothing.
- **Create updated install.wim** - the main output.
- **Service embedded WinRE** - patches the recovery environment inside the image once and reuses it for every index. WinRE gets the servicing stack from the LCU (the log says "LCU (servicing stack only)"; the rest of the LCU does not apply to WinRE) and the Safe OS Dynamic Update.
- **Verify the final install.wim** - mounts the result read-only, logs its version, and checks that the cumulative update, the language packs and their fonts are really installed. Needed for the validation gate and for the full change log.
- **Create refreshed media folder** - a complete installation media folder in `NEWWIM\Media`, for an OS Upgrade Package, a bootable USB stick or the ISO. It carries the new `install.wim` and the Setup Dynamic Update.
  - **Patch boot.wim** - available when the media folder or the ISO is built, ticked by default. Patches the WinPE and Setup images in `boot.wim`, and copies `setup.exe`, `setuphost.exe` and the boot manager files from the patched `boot.wim` onto the media, so the media boots and installs with up-to-date files. SCCM task sequences and upgrade packages do not use this `boot.wim`; it matters only when a PC is booted from the media, ISO or USB.
    - **Also build CA 2023 media alongside it** - available when Patch boot.wim is ticked. Builds a second copy, `NEWWIM\Media_CA2023` (and a `_CA2023` ISO), whose boot manager is signed by the newer "Windows UEFI CA 2023" certificate. It boots only on PCs whose firmware already trusts that certificate; the standard media is still built for all others. The log line `VERIFY CA 2023 media` confirms the signature.
- **Also build an ISO from that media** - builds `UpdatedMedia_<date>.iso` in `NEWWIM` (needs the Windows ADK).

### Updates and features tab

- **Servicing Stack Update**, **Latest Cumulative Update**, **Safe OS Dynamic Update**, **.NET Cumulative Update**, **Setup Dynamic Update** - which PATCHES folders are used. A ticked folder that is empty is logged and skipped, except the LCU (and the SSU on LTSC 2019 and LTSC 2021), which stop the run so an unpatched image is never produced by accident.
- **Enable .NET Framework 3.5** - from the OS ISO's `sources\sxs`.
- Windows 11 24H2 only: when `PATCHES\LCU` holds the LCU and its checkpoint update, only the LCU is installed and DISM takes what it needs from the checkpoint in the same folder (Microsoft's method). Keep both files in that folder and nothing else.

### Languages tab

- Tick the languages to add. Each entry shows the full name and the code (for example `German (Germany) - de-de`). The list comes from `Profiles\Languages.json`.
- Languages go into `install.wim` only. WinRE and `boot.wim` stay English-only.
- Each language needs its language pack on the Language Pack ISO and its language features on the FOD ISO. The preflight names any that are missing.
- Leave all unticked for English only. The ticks follow the selected OS (its saved settings, or the profile's defaults).

### Apps tab

- Lists the **provisioned apps** of the selected edition (the apps every new user gets, such as Clipchamp or Xbox apps on Windows 11). Tick the apps to remove; they are removed from `install.wim` as the very first servicing step, before WinRE, updates and languages.
- **Remove the ticked apps** - untick to keep the ticks but skip removal for a run.
- **Read apps from the ISO** - mounts the edition from the OS ISO read-only (about a minute) and fills the list. Changes nothing. A preflight also reads the list when there is none yet or the ISO has changed, and every run refreshes it. The line above the list says which ISO and edition it came from.
- Press **Save settings** to keep the ticks for this OS. Ticks are kept by app name, so they carry over to newer ISOs. A ticked app that is not in the current list stays on it, marked, and is skipped (logged) if the image does not have it.
- After the run, **Verify** checks that every ticked app is really gone; a leftover fails the validation gate. Each removal is a row in the change log.
- Windows Server has no provisioned consumer apps, so the tab is greyed out for it.

### Log tab

- Every line the run writes, with the time and a level: `[INFO]`, `[WARN]` or `[ERROR]`.
- With a colour scheme other than Default, warnings, errors and success lines (such as `VALIDATION GATE: PASSED`) are shown in their own colours.
- The same lines are written to the log file in `LOGS` (see below), so nothing is lost when the window is closed.

### Instructions tab

- This guide, formatted. The line at the top shows which `INSTRUCTIONS.md` was read (the one beside the script).
- **Reload** - reads the file again, for example after editing it; no restart needed.

### General Settings tab

- **Color scheme** - Default (the original look) or one of four dark schemes. The choice applies at once and is remembered for the next start. The tab shows the scheme's palette and a preview of the log colours.

### Bottom bar

- **Status line and progress bar** - the current step and the elapsed time.
- **Save settings** - saves the ticks and languages for the selected OS (and the repository root). They are applied whenever that OS is selected, also after a restart.
- **Reset to defaults** - after a confirmation, deletes the selected OS's saved settings and restores the defaults.
- **Start refresh** - starts the run with the current choices.
- **Cancel** - stops the run at the next safe point. A DISM operation that is already running must finish first, so cancelling can take a few minutes. The window cannot be closed while a run is active.

## Tools menu

- **Cleanup Mountpoints...** - use it after a crash, a forced restart or a cancelled run, or when an ISO was left mounted. It looks under the whole repository root (every OS folder) and lists what it finds: images still mounted, ISOs still mounted from any ISO folder, and mount folders with leftover files. Nothing is changed until you confirm. Then it discards the mounted images (changes in them are lost - never use it while a run is active), clears broken mount points, dismounts the ISOs and empties the leftover folders. Anything it cannot release is listed; restarting the build machine usually frees it. Images mounted outside the repository root are listed but never touched.

Every run also does a smaller version of this for its own OS folder at the start: stray mounts are discarded and ISOs of that OS still mounted are dismounted, with a WARN in the log.

## What a run produces

Everything goes to `<repository root>\<OS folder>\NEWWIM`:

- `install.wim` - the updated image to import into SCCM. Client operating systems have one index (the configured edition); Windows Server 2022 keeps all four.
- `Media` - the refreshed media folder (when ticked).
- `Media_CA2023` - the CA 2023 media folder (when ticked).
- `UpdatedMedia_<date>.iso` and `UpdatedMedia_CA2023_<date>.iso` - the ISOs (when ticked).
- `ChangeLog_<OS>_<build>_<date>.html` and `.csv` - a copy of the change log.
- `Archive\<date>` - the previous run's output, moved here before new output is written. The newest three archives are kept (`keepArchives` in the profile).

## Where the logs are

For each operating system, in `<repository root>\<OS folder>\LOGS`:

- `MediaRefresh_<yyyyMMdd_HHmmss>.log` - the run log: the same lines as the Log tab. Written by servicing runs, preflights and "Download patches...".
- `DISM_<yyyyMMdd_HHmmss>.log` - DISM's own detailed log for the same run. Look here when a package fails to install.
- `ChangeLog_<OS>_<build>_<yyyyMMdd_HHmmss>.html` and `.csv` - the change log for the image (also copied to `NEWWIM`).

For the Tools menu, in `<repository root>\LOGS`:

- `MountCleanup_<yyyyMMdd_HHmmss>.log` - what Cleanup Mountpoints did.

When asking for help with a run, send the `MediaRefresh_*`, `DISM_*` and `ChangeLog_*` files of that run.

## Validation gate and change log

**The validation gate** is the verdict at the end of a run with "Verify" ticked:

- `VALIDATION GATE: PASSED` - the cumulative update, the selected language packs and their fonts are all installed in every index.
- `VALIDATION GATE: FAILED` - at least one check failed; the `VERIFY` lines above it say which. The image is still written, but the completion message warns and the change log is marked FAILED. Do not import it until the cause is understood.
- `Skipped` - Verify was not ticked, or the run was a preflight.

**The change log** (HTML to read, CSV for Excel) describes the finished image:

- **Header** - OS, build before and after, every source ISO, edition and index, languages, and the gate result.
- **Section A** - everything this run changed, each with the time it succeeded: SSU, LCU, language packs, fonts and features, Safe OS DU, .NET, WinRE, cleanup, and the media files.
- **Section B** - the finished image's full inventory: packages, capabilities, enabled features, apps and hotfixes. Written only when Verify is ticked.

## Troubleshooting

- **"PATCHES\LCU is empty"** - download the patches or put the LCU in `PATCHES\LCU`, or untick Latest Cumulative Update.
- **"This OS needs its servicing stack update in PATCHES\SSU"** - put the SSU in by hand (see "Folder layout").
- **A language pack is missing** - the Language Pack ISO in the ISO folder does not have it. Untick the language or use the right ISO.
- **"Not enough free disk space"** - free space on the repository drive, or build fewer outputs at once. The message names the profile setting (`minFreeGB`, `spaceCheck`) if the estimate needs tuning.
- **The run stops with a mount error, or a folder "cannot be cleared because an image is still mounted"** - use Tools > Cleanup Mountpoints, then start again.
- **"CA 2023 media was not created"** - the `boot.wim` did not carry the CA 2023 boot files (they come with the April 2024 or later cumulative update). The standard media and `install.wim` are fine.
- **A step takes far longer than usual** (component cleanup over half an hour) - check the antivirus exclusion for the repository root and its `MOUNT` folders.
- **Support-end warning in red** - the OS is within 180 days of the end of support; plan its replacement.
