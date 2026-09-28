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

Everything lives under one **repository root** (until you save one, the default is the folder the script is in, on whatever drive that is; change it on the Source and Targets tab and press Save settings to keep it). Inside it there is one folder per operating system:

- `Win10_Enterprise_LTSC_2019` - Windows 10 Enterprise LTSC 2019 (IoT)
- `Win10_IoT_Enterprise_LTSC_2021` - Windows 10 IoT Enterprise LTSC 2021
- `Win10_Enterprise_LTSC_2021_KMS` - Windows 10 Enterprise LTSC 2021 (KMS)
- `Win11_Enterprise_24H2` - Windows 11 Enterprise 24H2
- `Windows_Server_2022` - Windows Server 2022

WimForge creates the sub-folders of an OS folder the first time that OS is run:

- `ISO` - put the ISOs here (see below).
- `PATCHES` - the updates, one sub-folder per kind:
  - `PATCHES\SSU` - the servicing stack update, **always placed by hand** (LTSC 2019: KB5005112; LTSC 2021 IoT and KMS: `ssu-19041.3562-x64.msu`). WimForge never downloads into or deletes from this folder.
  - `PATCHES\LCU` - the latest cumulative update. On Windows 11 24H2 this folder may also hold a checkpoint update; that is expected (see "Updates and Features").
  - `PATCHES\NETCU` - the .NET Framework cumulative update (one or two files).
  - `PATCHES\SAFEOSDU` - the Safe OS Dynamic Update, used for WinRE.
  - `PATCHES\SETUPDU` - the Setup Dynamic Update, used for the refreshed media.
- `NEWWIM` - the finished output (see "What a run produces").
- `LOGS` - every log and change log for this OS (see "Where the logs are").
- `OLDWIM`, `WORKING`, `TEMP`, `MOUNT`, `WINRE`, `WINPE` - WimForge's own working folders. Leave them alone; they are cleared at the start of every run.

**The ISO folder.** Put one ISO of each kind in it; the file names do not matter, because WimForge recognises each ISO by what is inside it:

- the **OS ISO** (always needed);
- the **Language Pack ISO** (only when languages are added);
- the **Features on Demand (FOD) ISO(s)** (only when languages are added; a second FOD ISO is fine and is used as an extra source).

Windows 11 24H2 and Server 2022 are built English-only and need only the OS ISO. Get fresh Microsoft ISOs each servicing cycle.

**Beside the script** WimForge keeps two folders of its own:

- `Profiles` - one JSON file per operating system (edition, language pack pattern, catalog search rules, end-of-support date, ...) and `Languages.json` (the list on the Languages tab). They are written from the built-in defaults the first time. Edit a file and press "Reload profiles" to use the change; a broken file is reported in the log and skipped. Existing files are never changed by WimForge. To go back to the built-in version of one OS, delete its file and press "Reload profiles": a fresh copy is written (the other files are not touched). To take an OS off the list, rename its file to `<name>.json.disabled`.
- `Settings` - the choices saved with "Save settings" (one file per OS) and `General.json` (the repository root and the colour scheme).
- `Profiles\Apps` - the Apps tab's app list per OS (`<OS>_Appx.json`), read once from the ISO. Kept when the profile files are regenerated; delete one to have it read again.

## Recommended order of work

1. **Select the operating system** on the Source and Targets tab.
2. **Fill PATCHES:** press "Download patches...", check the list it shows, and confirm. Put the SSU into `PATCHES\SSU` by hand (LTSC 2019 and LTSC 2021 only).
3. **Run a preflight:** tick "Preflight check only" and press "Start refresh". It takes about a minute and changes nothing. In the log, check the ISO roles, the patch counts, the language packs and the `Selected client image index` line.
4. **Run the real build:** untick "Preflight check only", choose the outputs, updates, languages and the apps to remove (Apps tab), and press "Start refresh". A run takes one to four hours depending on the OS and the number of languages.
5. **Check the result:** the completion message, the `VALIDATION GATE` line at the end of the log, and the change log (see below).
6. **Import into SCCM** from the SCCM tab (Full OS image or Upgrade package), or tick "Import after the run finishes" there before step 4.

Press "Save settings" once the ticks and languages for an OS are how you want them; they come back every time that OS is selected.

## The window

### Header

- **Left:** the tool name.
- **Right:** the operating system being worked on and the current phase (for example "Servicing install.wim (index 1)", then "Done", "Failed" or "Cancelled"). While nothing runs it shows the selected OS and "Idle".
- **Tools** (top right): a menu with maintenance tools - see "Tools menu".

### Source and Targets tab

- **Repository root** - the folder that holds the OS folders.
- **Operating system** - the OS to work on. The line under it shows the profile file in use and the end-of-support date (in red when support ends within 180 days or has ended).
- **Download patches...** - searches the Microsoft Update Catalog for the selected OS and every ticked update kind (LCU, .NET CU, Safe OS DU, Setup DU). It always shows what it found first (title, KB, release date, and for the LCU whether it is the Patch Tuesday or an out-of-band release) and downloads only after you confirm - and only what is not already there: each line says "already in PATCHES\..." or "will be downloaded", and when everything is present you are told PATCHES is up to date and nothing is downloaded. Older files of the same kind are then removed from that PATCHES folder. `PATCHES\SSU` is never touched. Each folder keeps a small `_downloads.json` that remembers which files each catalog entry produced (an entry is downloaded again if one of its files is missing or has changed size).
- **Reload profiles** - re-reads the files in `Profiles`.

**Outputs:**

- **Preflight check only** - checks ISOs, patch folders, language packs, edition and free space in about a minute; changes nothing.
- **Create updated install.wim** - the main output.
- **Service embedded WinRE** - patches the recovery environment inside the image once and reuses it for every index. WinRE gets the servicing stack from the LCU and the Safe OS Dynamic Update. When the LCU .msu carries its own servicing stack (an `SSU-*.cab` inside, as the Windows 10 1809 LCUs now do), only that cab is extracted and added (the log says "servicing stack from <LCU file>"); otherwise the .msu is added and the log says "LCU (servicing stack only)". The rest of the LCU never goes into WinRE.
- **Verify the final install.wim** - mounts the result read-only, logs its version, and checks that the cumulative update, the language packs and their fonts are really installed. Needed for the validation gate and for the full change log.
- **Create refreshed media folder** - a complete installation media folder in `NEWWIM\Media`, for an OS Upgrade Package, a bootable USB stick or the ISO. It carries the new `install.wim` and the Setup Dynamic Update. The options below it are available only while it is ticked.
  - **Also build an ISO from that media** - builds `UpdatedMedia_<date>.iso` in `NEWWIM` (needs the Windows ADK).
  - **Patch boot.wim** - ticked by default. Patches the WinPE and Setup images in `boot.wim`, and copies `setup.exe`, `setuphost.exe` and the boot manager files from the patched `boot.wim` onto the media, so the media boots and installs with up-to-date files. SCCM task sequences and upgrade packages do not use this `boot.wim`; it matters only when a PC is booted from the media, ISO or USB. When the LCU .msu carries its own servicing stack, `boot.wim` gets it in two steps (the servicing stack cab, then the update cab; the log says "in two steps"), because the Windows 10 1809 `boot.wim` rejects both at once. The 1809 `boot.wim` cannot take the cumulative update at all (its images lack files the update needs; DISM error 0x8007371b): WimForge then mounts that image again and gives it the servicing stack only, as WinRE gets, and the log and change log say the LCU was not applied to `boot.wim`. The media is still built, but its `setup.exe` and boot manager files are the original ones, and no CA 2023 media can be made for 1809. If `boot.wim` or the media fails for any other reason, the finished `install.wim`, the change log and the run record are kept (the run still ends in an error and no media or ISO is built), so the image can be imported.
    - **Also build CA 2023 media alongside it** - available when Patch boot.wim is ticked. Builds a second copy, `NEWWIM\Media_CA2023` (and a `_CA2023` ISO), whose boot manager is signed by the newer "Windows UEFI CA 2023" certificate. It boots only on PCs whose firmware already trusts that certificate; the standard media is still built for all others. The log line `VERIFY CA 2023 media` confirms the signature.
### Updates and Features tab

- **Servicing Stack Update**, **Latest Cumulative Update**, **Safe OS Dynamic Update**, **.NET Cumulative Update**, **Setup Dynamic Update** - which PATCHES folders are used. A ticked folder that is empty is logged and skipped, except the LCU (and the SSU on LTSC 2019 and LTSC 2021), which stop the run so an unpatched image is never produced by accident.
  - About the LCU on Windows 11 24H2: when `PATCHES\LCU` holds the LCU and its checkpoint update, only the LCU is installed and DISM takes what it needs from the checkpoint in the same folder (Microsoft's method). Keep both files in that folder and nothing else.
- **Download the latest patches before the run** - off by default. Ticked: the run first searches the catalog, like "Download patches...", and downloads only the ticked updates that are not in PATCHES yet (a preflight only checks and says what the run would download). If the catalog cannot be reached, the run carries on with the patches already in the folders and logs a warning. Unticked: the run uses the patches already in the folders. Saved per OS.
- **Enable .NET Framework 3.5** - available for **every** operating system (on Windows Server 2022 it is enabled in all four indexes). Its files always come from the **OS ISO's own `sources\sxs` folder**, never from Windows Update. It is enabled after the component cleanup and before the .NET cumulative update, so the .NET CU also updates it. A preflight stops with a clear message if the OS ISO has no `sources\sxs`. The tick is saved per OS.

### Languages tab

- Tick the languages to add. Each entry shows the full name and the code (for example `German (Germany) - de-de`). The list comes from `Profiles\Languages.json`.
- Languages go into `install.wim` only. WinRE and `boot.wim` stay English-only.
- Each language needs its language pack on the Language Pack ISO and its language features on the FOD ISO. The preflight names any that are missing.
- Leave all unticked for English only. The ticks follow the selected OS (its saved settings, or the profile's defaults).

### Apps tab

- Lists the **provisioned apps** of the selected edition (the apps every new user gets, such as Clipchamp or Xbox apps on Windows 11). Tick the apps to remove; they are removed from `install.wim` as the very first servicing step, before WinRE, updates and languages.
- **Remove the ticked apps** - untick to keep the ticks but skip removal for a run.
- **Read apps from the ISO** - mounts only the OS ISO, then the edition read-only, and fills the list; usually a few minutes (mostly mounting and discarding the image), with each step shown in the status line. Changes nothing. The LTSC editions have no provisioned apps, so their list is empty. One scan per OS: the list is kept in `Profiles\Apps\<OS>_Appx.json` and fills the tab whenever that OS is selected. A preflight reads it again only when there is none yet or the OS ISO has changed (a new ISO - even under the same file name - may add or remove apps); a real run never changes it. The line above the list says which ISO and edition it came from, and points it out when the ISO in the folder has changed since.
- Press **Save settings** to keep the ticks for this OS. Ticks are kept by app name, so they carry over to newer ISOs. A ticked app that is not in the current list stays on it, marked, and is skipped (logged) if the image does not have it.
- After the run, **Verify** checks that every ticked app is really gone; a leftover fails the validation gate. Each removal is a row in the change log.
- Windows Server has no provisioned consumer apps, so the tab is greyed out for it.

### SCCM tab

Imports the latest finished run of the selected OS into Configuration Manager. Needs the Configuration Manager console on the build machine and rights on the site.

- **Site server** - the site server's name (FQDN). **Connect** checks the console module and the site, reads the site code, and fills the pick list with the site's distribution points and groups. It usually takes up to a minute (loading the console's PowerShell module is the slow part); the status line shows each step.
- **Distribute to** - a distribution point or a distribution point group; type the name, or pick it from the list after Connect.
- **Content source folder** - a folder on this server inside a shared folder (**Browse...** to pick it). The line under it shows the UNC path Configuration Manager imports from. Each import creates a new sub-folder named after the image; nothing already there is overwritten.
- **Image name** - the OS name with the month (`yyyyMM`), following the selected OS; type another name if wanted (50 characters at most), **Reset** to go back. If an image of that name already exists, the new one gets " (2)", " (3)", ...; the existing one is never changed.
- **Package type** - **Full OS image** (the `install.wim`, for task sequences) or **Upgrade package** (the whole refreshed media folder, for in-place upgrades; the run must have built the media folder).
- **Import after the run finishes** - starts the import straight after a successful run, without a confirmation. An image whose validation gate FAILED is not imported.
- **Import into SCCM...** - checks everything first (the run, the gate, the folder and share, free space, the site and the name) and shows exactly what it will do; nothing changes until you confirm. It then copies the image, creates the OS image or upgrade package, and starts the content distribution (follow it in the console under Monitoring > Distribution Status).
- The line under the button shows the latest run for this OS: build, validation gate and time. **A run whose validation gate FAILED is never imported.**
- Save settings keeps the site server and target (for every OS), and the content folder, package type and a typed image name (per OS).

### Log tab

- Every line the run writes, with the time and a level: `[INFO]`, `[WARN]` or `[ERROR]`.
- With a colour scheme other than Default, warnings, errors and success lines (such as `VALIDATION GATE: PASSED`) are shown in their own colours.
- The same lines are written to the log file in `LOGS` (see below), so nothing is lost when the window is closed.

### Instructions tab

- This guide, formatted. `INSTRUCTIONS.md` is read from the script's folder, or else from the repository root. The line at the top shows which file was read, or where it was looked for.
- **Reload** - reads the file again, for example after editing it; no restart needed, and it works during a run. Opening the tab also re-reads the file when it has appeared or changed. (Reload profiles, next to the OS list, does not touch this guide.)

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

## Running without the window (command line)

Every choice in the window can be saved as a **run config** (a JSON file) and run later without the window - for example from Task Scheduler after Patch Tuesday.

1. In the window, select the OS and set everything up (outputs, updates, languages, apps, SCCM).
2. **Tools > Save run config...** saves it, by default to `Configs\<OS>_run.json` beside the script.
3. Run it from an **elevated** Windows PowerShell 5.1:
   - `.\MediaRefresh_v2.4.ps1 -Config .\Configs\Win10_IoT_Enterprise_LTSC_2021_run.json`
   - add `-Preflight` for a check only (nothing is changed), whatever the config says.

- The run writes the usual `LOGS` files and prints its log to the console.
- **Exit codes:** `0` success; `1` failed (including a bad config); `2` finished, but the validation gate FAILED; `3` the run succeeded but the SCCM import the config asks for failed.
- **SCCM:** when "Import after the run finishes" was ticked on the SCCM tab, the config imports straight after a successful run - without a confirmation - and never when the validation gate FAILED.
- **Editing a config by hand:** option names are the same as in the window's saved settings (`Install`, `WinRE`, `NetFx3`, `AutoDownload`, ...). A missing option takes the window's default; a missing `languages` list takes the OS profile's default languages (an empty list means English only). A misspelled option, an unknown OS or language, or a value that is not `true` / `false` stops the run with a message naming every problem - a typo never quietly changes a run.
## What a run produces

Everything goes to `<repository root>\<OS folder>\NEWWIM`:

- `install.wim` - the updated image to import into SCCM. Client operating systems have one index (the configured edition); Windows Server 2022 keeps all four.
- `Media` - the refreshed media folder (when ticked).
- `Media_CA2023` - the CA 2023 media folder (when ticked).
- `UpdatedMedia_<date>.iso` and `UpdatedMedia_CA2023_<date>.iso` - the ISOs (when ticked).
- `ChangeLog_<OS>_<build>_<date>.html` and `.csv` - a copy of the change log.
- `RunResult.json` - the record of the run (build, validation gate, outputs) that the SCCM import works from.
- `Archive\<date>` - the previous run's output, moved here before new output is written. The newest three archives are kept (`keepArchives` in the profile).

## Where the logs are

For each operating system, in `<repository root>\<OS folder>\LOGS`:

- `MediaRefresh_<yyyyMMdd_HHmmss>.log` - the run log: the same lines as the Log tab. Written by servicing runs, preflights and "Download patches...".
- `DISM_<yyyyMMdd_HHmmss>.log` - DISM's own detailed log for the same run. Look here when a package fails to install.
- `ChangeLog_<OS>_<build>_<yyyyMMdd_HHmmss>.html` and `.csv` - the change log for the image (also copied to `NEWWIM`).
- `SccmImport_<yyyyMMdd_HHmmss>.log` - what an SCCM import did (copy, import, distribution).

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
- **SCCM: "The Configuration Manager console is not installed"** - install the console on the build machine; the import uses its PowerShell module.
- **SCCM: "not inside a shared folder on this server"** - Configuration Manager reads the content over the network, so the content source folder must be inside a share. Share it (or a parent folder).
- **SCCM: "Refused: ... FAILED its validation gate"** - fix what the VERIFY lines report, run again, then import.
- **A step takes far longer than usual** (component cleanup over half an hour) - check the antivirus exclusion for the repository root and its `MOUNT` folders.
- **Support-end warning in red** - the OS is within 180 days of the end of support; plan its replacement.
