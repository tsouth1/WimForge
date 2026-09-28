#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    WimForge v2.4 - GUI offline servicing for Configuration Manager OSD WIMs.
.DESCRIPTION
    Mounts the OS ISO (plus optional Language Pack and FOD ISOs, detected by CONTENT, not file name),
    exports the configured client edition or preserves all Server indexes, services install.wim
    (and optionally WinRE / boot.wim), verifies the result, and can build a refreshed media folder
    (for OS Upgrade Packages) and an optional ISO.

    Servicing order for install.wim follows Microsoft's media Dynamic Update guidance:
      WinRE (once)  ->  SSU  ->  [LCU pass 1 -> language packs -> FODs/fonts when languages are selected]
      ->  LCU (final)  ->  component cleanup  ->  NetFx3 -> .NET CU  ->  export -> verify

.NOTES
    Version 2.4.0 (draft - mock-tested; real catalog dry runs for LTSC 2019 only; never run against real images or a real DISM yet).
      * Added: acquisition layer (step 5) - "Download patches..." searches the Microsoft Update Catalog via the
               MSCatalogLTS module using per-profile catalogSearch rules, shows a dry-run preview of what it found,
               and on confirmation downloads into PATCHES\<class> and prunes superseded files. PATCHES\SSU is never
               touched - legacy servicing-stack updates stay a manual, hand-placed file. Checkpoint-CU chains
               (Win11 24H2+/Server 2025) are looked up from a profile-supplied KB list, not derived automatically -
               open point, see TODO.md step 5. Catalog search strings shipped in the built-in profiles are
               best-effort and need spot-checking against catalog.update.microsoft.com.
      * Fixed (after Terry's real-catalog test, LTSC 2019): catalog results carry no Architecture property and the
               catalog search matches words loosely, so an x86 entry could be picked for an x64 profile. The
               architecture is now checked against the title (and each downloaded file name) instead.
      * Fixed: a catalog entry can download several files (the combined .NET CU "3.5, 4.7.2 and 4.8" for 1809,
               KB5126144, downloads KB5126043 for 3.5/4.7.2 and KB5126048 for 4.8). Every file is now kept,
               instead of only the newest one being kept and the rest pruned.
      * Fixed: a .NET CU file that does not apply to the image (the 4.8 part on an image without .NET 4.8) is
               skipped with a WARN instead of failing the whole servicing run.
      * Fixed: a catalog search with no match stopped the whole download with "The property 'Count' cannot be found"
               (Terry's first real dry run, LTSC 2019, Safe OS DU search); it is now reported as a skipped class.
      * Added: catalogSearch rules take productFilter / productExclude (regular expressions against the catalog
               Products field). The 1809 Safe OS DU is titled plain "Dynamic Update for Windows 10 Version 1809" and is
               only marked as Safe OS by its Products entry; the 1809 SafeOS/SetupDU rules now use that.
      * Changed: the built-in LCU rules have a title filter so a .NET CU or Dynamic Update released the same day can
               no longer be picked as the LCU; the 1809 .NET CU rule searches for the combined entry.
      * Fixed (live catalog check, 2026-09-24): the installed MSCatalogLTS 2.1.0.1 hides Dynamic Updates without
               -IncludeDynamic, reads one page without -AllPages and rewrites "Dynamic Update for ..." searches, so Safe OS
               and Setup DU searches could never find anything. Both switches are now passed and searches reach the
               catalog as written. A search over 100 characters (the catalog returns nothing for it) is refused when the
               profile loads. The 21H2, Server 2022 and Win11 24H2 rules were corrected from the real catalog, and
               Win11 24H2 gained a .NET CU rule.
      * Fixed: the "confirm download" dialog and the "selected" log line listed every KB twice (the catalog title
               already ends in it). Display only - each pick was always downloaded once.
      * Fixed: a real download could delete the patch it had just picked (Terry's Win11 24H2 run removed the LCU): the
               module skips a file that already exists unless -Force is passed, and the pruning kept only files new or
               re-written in the run. -Force is now passed, and pruning never removes a file whose KB was picked in the
               run unless the run also saved a file with that KB.
      * Changed: the "confirm download" dialog and "selected" log line show each pick's release date and catalog
               classification, and for the LCU whether it is the Patch Tuesday or an out-of-band release (the newest
               cumulative release is still the one picked).
      * Fixed: when PATCHES\LCU holds a checkpoint as well as the LCU (Win11 24H2+), only the target LCU (highest KB)
               is installed and the checkpoint stays in the same folder for DISM to apply where needed - Microsoft's
               method. Before, every file was added, so the checkpoint was installed directly into WinRE, install.wim
               and WinPE. A single LCU file is installed as before.
      * Fixed (Terry's 2026-09-25 Win11 change log): Section A rows show the time each step succeeded, not the time
               the log was written; the Setup DU expanded into the media is listed; Windows' housekeeping folders under
               WindowsApps ("Deleted", "Merged") are no longer listed as staged appx packages. [string[]] parameters that
               are counted default to an empty array (Windows PowerShell 5.1 throws on @($x).Count when one is unbound).
      * Fixed (Terry's 2026-09-25 LTSC 2019 run): a .NET CU part that DISM finds not applicable while still returning
               success for the .MSU (the 4.8 part on a 4.7.2 image) was logged and recorded as added; the package list
               is now compared before and after, and an unchanged list is logged as a WARN and recorded as skipped.
      * Fixed: a Features on Demand ISO without language features (1809 "FOD part 2") is recognised as an extra FOD
               source by its metadata\*CompDB* catalogue or package-identity cabs, instead of "not recognised".
      * Changed (Terry, 2026-09-26): languages go into install.wim only. WinRE and boot.wim stay English-only - the
               WinPE language step (lp.cab, WinPE component, font and speech cabs, lang.ini) is removed; WinRE and
               boot.wim are still patched.
      * Changed (Terry, 2026-09-26): the Languages tab lists Profiles\Languages.json (created from the built-in copy
               of Terry's list when missing; a bad file falls back to the built-in list) as "full name - code"; runs,
               saved choices and profile defaults use the code. A profile default not on the list is logged, not selected.
      * Added (Terry, 2026-09-27): "Save settings" and "Reset to defaults" buttons. The selected OS's checkboxes and
               languages are saved to Settings\<profile folder>.json (repository root to Settings\General.json), beside
               Profiles\, and applied whenever that OS is selected; an OS without saved settings gets the defaults.
    Version 2.2.0 (draft - test against non-production images first).
      * Added: OS profiles are JSON files in a Profiles folder beside the script (created from the built-in profiles the first
               time the folder is empty). Edit a file and press "Reload profiles"; a bad file is reported and skipped.
               New OSes need a JSON file, not a code change.
      * Added: package order manifest per profile (packageOrder) instead of plain file-name order, logged at run start.
      * Added: end-of-support date per profile; the run warns when it is past or within 180 days, and the GUI shows it.
      * Added: the previous NEWWIM output is archived to NEWWIM\Archive\<timestamp> before a run writes new output (newest 3 kept,
               keepArchives in the profile) instead of being overwritten.
      * Added: free-disk-space check in preflight and before a real run (estimate from the source WIM size; minFreeGB / spaceCheck
               in the profile).
    Version 2.1.0
      * Fixed: crash when a ticked PATCHES subfolder is empty (now skipped and logged).
      * Fixed: crash when no languages are selected (English-only OSes such as Win11 / Server 2022).
      * Fixed: language pack ISO was mis-detected as an OS ISO (roles are now detected from ISO content).
      * Fixed: language packs silently skipped ("not found on the FOD ISO"); now checked BEFORE any
               image is mounted, and the run stops early with a clear message.
      * Fixed: LCU was applied before FOD/NetFx3 and could show as missing after deployment; the final
               LCU is now applied after all languages/FODs, then cleanup, then NetFx3 + .NET CU
               (this also avoids the 0x800F0806 pending-operations cleanup failure).
      * Fixed: stale mounts are discarded before the mount folders are cleared (no more deleting into a
               live mount); mount-path checks tolerate trailing backslashes.
      * Fixed: WinRE is serviced once and reused for every index (Server 2022).
      * Fixed: ISOs are dismounted before the completion dialog is shown.
      * Added: font capabilities (ja-jp, ko-kr, zh-cn, zh-tw), Server language pack file pattern,
               lang.ini regeneration for boot.wim, DISM log in LOGS, host-vs-image DISM build warning,
               post-build verification (read-only mount), refreshed media folder for Upgrade Packages,
               default language selection per OS profile, folder-name aliases.
      * Fixed: console "hang until Enter is pressed" (Quick Edit mode pauses the script when the console
               window is clicked). Quick Edit is switched off at start-up, cmdlet progress bars are
               suppressed, and the GUI no longer writes every log line to the console.
      * Changed: several Features on Demand ISOs (or an LP ISO that also carries FODs) are all used as
               capability sources instead of stopping the run.
      * Added: "Preflight only" mode - mounts the ISOs and checks ISO roles, patch folders, language packs and
               edition selection in about a minute without touching any image. Run it before a long servicing run.
      * Fixed: the window no longer freezes ("Not Responding") during mounts and patching. The engine now runs on a
               background runspace; the window shows live log lines, progress and elapsed time, and Cancel responds at once
               (it takes effect at the next safe point between DISM operations).
      * Not yet done: MSCatalogLTS downloads, SCCM import, a hard cancel that aborts a running DISM call.
    Run on a supported Windows/ADK servicing workstation as Administrator.
    Keep one OS ISO, and (when languages are needed) one Language Pack ISO and one FOD ISO, in each ISO folder.
.PARAMETER Config
    Runs without the window, from a run config file (JSON) saved with Tools > Save run config... in the window. The run
    logs to the console and the usual LOGS files and ends with an exit code: 0 = success, 1 = failed, 2 = finished but
    the validation gate FAILED, 3 = the run succeeded but the SCCM import asked for in the config failed.
.PARAMETER Preflight
    With -Config: a preflight only (checks everything, changes nothing), whatever the config says.
.EXAMPLE
    .\MediaRefresh_v2.4.ps1 -Config .\Configs\Win10_IoT_Enterprise_LTSC_2021_run.json
.EXAMPLE
    .\MediaRefresh_v2.4.ps1 -Config .\Configs\Win10_IoT_Enterprise_LTSC_2021_run.json -Preflight
#>
param(
    [string]$Config,
    [switch]$Preflight
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region BOOTSTRAP
$ProgressPreference = 'SilentlyContinue'   # cmdlet progress bars slow servicing and write to the console
function Disable-ConsoleQuickEdit {
    # Clicking inside a console window enters Quick Edit selection mode, which blocks the next console write
    # (and so the whole script) until Enter/Esc is pressed. Clear ENABLE_QUICK_EDIT_MODE (0x40), set ENABLE_EXTENDED_FLAGS (0x80).
    try {
        Add-Type -Namespace MediaRefresh -Name ConsoleMode -ErrorAction Stop -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern System.IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetConsoleMode(System.IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleMode(System.IntPtr hConsoleHandle, uint dwMode);
'@
        $h = [MediaRefresh.ConsoleMode]::GetStdHandle(-10)
        [uint32]$mode = 0
        if ([MediaRefresh.ConsoleMode]::GetConsoleMode($h, [ref]$mode)) {
            $new = ([int64]$mode -band 4294967231) -bor 128
            [void][MediaRefresh.ConsoleMode]::SetConsoleMode($h, [uint32]$new)
        }
    } catch { }
}
Disable-ConsoleQuickEdit
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
Import-Module Dism -ErrorAction Stop
#endregion BOOTSTRAP

#region ENGINE
$script:MountedIsoPaths = [System.Collections.Generic.List[string]]::new()
$script:LogFile    = $null
$script:LogBox     = $null
$script:Progress   = $null
$script:Status     = $null
$script:Cancelled  = $false
$script:UiQueue    = $null   # set only when the engine runs on a background runspace (GUI stays responsive)
$script:Shared     = $null   # synchronized hashtable shared with the GUI thread (Cancel flag, result)
$script:DismLogArgs = @{}
$script:LastResult = $null
$script:HeaderOs    = $null   # GUI header controls (idle/foreground path); background runs send 'H' queue messages instead
$script:HeaderPhase = $null
$script:CurrentOsName = ''
$script:ChangeEvents  = [System.Collections.Generic.List[object]]::new()   # Section A: what this run changed
$script:IsoSources    = [System.Collections.Generic.List[object]]::new()   # header: OS/Language Pack/FOD ISO file names
$script:VerifyInventory  = [System.Collections.Generic.List[object]]::new()   # Section B: final-state inventory from the verify mount
$script:VerifyBuildAfter = $null
$script:BuildBefore      = $null
$script:ToolVersion      = '2.4.0'

$script:ClientLpPattern = 'Microsoft-Windows-Client-Language-Pack_x64_{0}.cab'
$script:ServerLpPattern = 'Microsoft-Windows-Server-Language-Pack_x64_{0}.cab'
# Language -> font script capability (Language.Fonts.<Script>~~~und-<SCRIPT>~0.0.1.0)
$script:LangFontScripts = @{ 'ja-jp' = 'Jpan'; 'ko-kr' = 'Kore'; 'zh-cn' = 'Hans'; 'zh-tw' = 'Hant' }
$script:DefaultLanguageSet = @('de-de','en-gb','es-es','fr-fr','it-it','ja-jp','ko-kr','pt-br','zh-cn','zh-tw')

# ---------- OS profiles ----------
# Profiles live in JSON files (Profiles folder beside the script). The five built-in profiles below are written out as files the
# first time the folder is empty, and are used as-is when no usable file exists. Client matching is name-first, index-fallback.
#   ssuRequired : the separate SSU must be present in PATCHES\SSU (legacy OSes)
#   altFolders  : other accepted folder names
#   packageOrder: per package class, wildcard file-name patterns applied in that order (rest follow in name order)
#   endOfSupport: yyyy-MM-dd or empty; the run warns when it is past or within 180 days
#   keepArchives: how many archived NEWWIM outputs to keep (0 = keep all);  minFreeGB / spaceCheck: enforce | warn | off
$script:ProfileClasses  = @('SSU', 'LCU', 'NetCU', 'SafeOS', 'SetupDU')
$script:ProfileMessages = [System.Collections.Generic.List[object]]::new()
$script:LanguagesFileName = 'Languages.json'   # Profiles\Languages.json: the Languages tab list (step 10e), not an OS profile
$script:OutputArchived  = $false

function Get-BuiltInProfileData {
    $noOrder = { [ordered]@{ SSU = @(); LCU = @(); NetCU = @(); SafeOS = @(); SetupDU = @() } }
    return @(
        [ordered]@{ schemaVersion = 1; name = 'Windows 10 Enterprise LTSC 2019 (IoT)'; sortOrder = 10; folder = 'Win10_Enterprise_LTSC_2019'; altFolders = @()
            serviceAllIndexes = $false; editionRegex = '(?i)^Windows 10 (IoT )?Enterprise LTSC( 2019)?$'; preferredIndex = 1
            lpPattern = $script:ClientLpPattern; ssuRequired = $true; defaultLanguages = $script:DefaultLanguageSet; packageOrder = (& $noOrder)
            endOfSupport = '2029-01-10'; keepArchives = 3; minFreeGB = 30; spaceCheck = 'enforce'; notes = 'Needs the 1809 Language Pack ISO for languages. SSU KB5005112 goes in PATCHES\SSU. Catalog search rules checked against the real catalog on 2026-09-24.'; catalogSearch = [ordered]@{ LCU = [ordered]@{ search = 'Cumulative Update for Windows 10 Version 1809 for x64-based Systems'; architecture = 'x64'; excludePreview = $true; buildFilter = '^\d{4}-\d{2} Cumulative Update for Windows 10 Version 1809'; checkpointKBs = @() }; NetCU = [ordered]@{ search = 'Cumulative Update for .NET Framework 3.5, 4.7.2 and 4.8 for Windows 10 Version 1809 for x64'; architecture = 'x64'; excludePreview = $true; buildFilter = '^\d{4}-\d{2} Cumulative Update for \.NET Framework 3\.5, 4\.7\.2 and 4\.8 for Windows 10 Version 1809'; checkpointKBs = @() }; SafeOS = [ordered]@{ search = 'Dynamic Update for Windows 10 Version 1809 for x64-based Systems'; architecture = 'x64'; excludePreview = $true; buildFilter = '^\d{4}-\d{2} Dynamic Update for Windows 10 Version 1809'; productFilter = 'Safe OS'; productExclude = ''; checkpointKBs = @() }; SetupDU = [ordered]@{ search = 'Dynamic Update for Windows 10 Version 1809 for x64-based Systems'; architecture = 'x64'; excludePreview = $true; buildFilter = '^\d{4}-\d{2} Dynamic Update for Windows 10 Version 1809'; productFilter = 'Dynamic Update'; productExclude = 'Safe OS'; checkpointKBs = @() } } }
        [ordered]@{ schemaVersion = 1; name = 'Windows 10 IoT Enterprise LTSC 2021'; sortOrder = 20; folder = 'Win10_IoT_Enterprise_LTSC_2021'; altFolders = @('Win10_IOT_Enterprise_LTSC_2021')
            serviceAllIndexes = $false; editionRegex = '(?i)^Windows 10 IoT Enterprise LTSC( 2021)?$'; preferredIndex = 2
            lpPattern = $script:ClientLpPattern; ssuRequired = $true; defaultLanguages = $script:DefaultLanguageSet; packageOrder = (& $noOrder)
            endOfSupport = '2032-01-14'; keepArchives = 3; minFreeGB = 30; spaceCheck = 'enforce'; notes = 'SSU ssu-19041.3562-x64.msu goes in PATCHES\SSU. Catalog search rules checked against the real catalog on 2026-09-24.'; catalogSearch = [ordered]@{ LCU = [ordered]@{ search = 'Cumulative Update for Windows 10 Version 21H2 for x64-based Systems'; architecture = 'x64'; excludePreview = $true; buildFilter = '^\d{4}-\d{2} Cumulative Update for Windows 10 Version 21H2'; checkpointKBs = @() }; NetCU = [ordered]@{ search = 'Cumulative Update for .NET Framework 3.5, 4.8 and 4.8.1 for Windows 10 Version 21H2 for x64'; architecture = 'x64'; excludePreview = $true; buildFilter = '^\d{4}-\d{2} Cumulative Update for \.NET Framework 3\.5, 4\.8 and 4\.8\.1 for Windows 10 Version 21H2'; checkpointKBs = @() }; SafeOS = [ordered]@{ search = 'Dynamic Update for Windows 10 Version 21H2 for x64-based Systems'; architecture = 'x64'; excludePreview = $true; buildFilter = '^\d{4}-\d{2} Dynamic Update for Windows 10 Version 21H2'; productFilter = 'Safe OS'; productExclude = ''; checkpointKBs = @() }; SetupDU = [ordered]@{ search = 'Dynamic Update for Windows 10 Version 21H2 for x64-based Systems'; architecture = 'x64'; excludePreview = $true; buildFilter = '^\d{4}-\d{2} Dynamic Update for Windows 10 Version 21H2'; productFilter = 'Dynamic Update'; productExclude = 'Safe OS'; checkpointKBs = @() } } }
        [ordered]@{ schemaVersion = 1; name = 'Windows 10 Enterprise LTSC 2021 (KMS)'; sortOrder = 30; folder = 'Win10_Enterprise_LTSC_2021_KMS'; altFolders = @()
            serviceAllIndexes = $false; editionRegex = '(?i)^Windows 10 Enterprise LTSC( 2021)?$'; preferredIndex = 1
            lpPattern = $script:ClientLpPattern; ssuRequired = $true; defaultLanguages = $script:DefaultLanguageSet; packageOrder = (& $noOrder)
            endOfSupport = '2027-01-13'; keepArchives = 3; minFreeGB = 30; spaceCheck = 'enforce'; notes = 'SSU ssu-19041.3562-x64.msu goes in PATCHES\SSU. Support ends 2027-01-13; plan the replacement. Catalog search rules checked against the real catalog on 2026-09-24.'; catalogSearch = [ordered]@{ LCU = [ordered]@{ search = 'Cumulative Update for Windows 10 Version 21H2 for x64-based Systems'; architecture = 'x64'; excludePreview = $true; buildFilter = '^\d{4}-\d{2} Cumulative Update for Windows 10 Version 21H2'; checkpointKBs = @() }; NetCU = [ordered]@{ search = 'Cumulative Update for .NET Framework 3.5, 4.8 and 4.8.1 for Windows 10 Version 21H2 for x64'; architecture = 'x64'; excludePreview = $true; buildFilter = '^\d{4}-\d{2} Cumulative Update for \.NET Framework 3\.5, 4\.8 and 4\.8\.1 for Windows 10 Version 21H2'; checkpointKBs = @() }; SafeOS = [ordered]@{ search = 'Dynamic Update for Windows 10 Version 21H2 for x64-based Systems'; architecture = 'x64'; excludePreview = $true; buildFilter = '^\d{4}-\d{2} Dynamic Update for Windows 10 Version 21H2'; productFilter = 'Safe OS'; productExclude = ''; checkpointKBs = @() }; SetupDU = [ordered]@{ search = 'Dynamic Update for Windows 10 Version 21H2 for x64-based Systems'; architecture = 'x64'; excludePreview = $true; buildFilter = '^\d{4}-\d{2} Dynamic Update for Windows 10 Version 21H2'; productFilter = 'Dynamic Update'; productExclude = 'Safe OS'; checkpointKBs = @() } } }
        [ordered]@{ schemaVersion = 1; name = 'Windows 11 Enterprise 24H2'; sortOrder = 40; folder = 'Win11_Enterprise_24H2'; altFolders = @('Win11Enterprise_24H2')
            serviceAllIndexes = $false; editionRegex = '(?i)^Windows 11 Enterprise$'; preferredIndex = 3
            lpPattern = $script:ClientLpPattern; ssuRequired = $false; defaultLanguages = @(); packageOrder = (& $noOrder)
            endOfSupport = ''; keepArchives = 3; minFreeGB = 30; spaceCheck = 'enforce'; notes = 'English only. Support end date not yet checked against the Microsoft lifecycle page. Catalog search rules checked against the real catalog on 2026-09-24.'; catalogSearch = [ordered]@{ LCU = [ordered]@{ search = 'Windows 11, version 24H2'; architecture = 'x64'; excludePreview = $true; buildFilter = '^\d{4}-\d{2} Cumulative Update for Windows 11,? version 24H2'; checkpointKBs = @() }; NetCU = [ordered]@{ search = 'Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11, version 24H2 for x64'; architecture = 'x64'; excludePreview = $true; buildFilter = '^\d{4}-\d{2} Cumulative Update for \.NET Framework 3\.5 and 4\.8\.1 for Windows 11,? version 24H2'; checkpointKBs = @() }; SafeOS = [ordered]@{ search = 'Safe OS Dynamic Update for Windows 11, version 24H2'; architecture = 'x64'; excludePreview = $true; buildFilter = '^\d{4}-\d{2} Safe OS Dynamic Update for Windows 11,? version 24H2'; checkpointKBs = @() }; SetupDU = [ordered]@{ search = 'Setup Dynamic Update for Windows 11, version 24H2'; architecture = 'x64'; excludePreview = $true; buildFilter = '^\d{4}-\d{2} Setup Dynamic Update for Windows 11,? version 24H2'; checkpointKBs = @() } } }
        [ordered]@{ schemaVersion = 1; name = 'Windows Server 2022'; sortOrder = 50; folder = 'Windows_Server_2022'; altFolders = @()
            serviceAllIndexes = $true; editionRegex = ''; preferredIndex = 0
            lpPattern = $script:ServerLpPattern; ssuRequired = $false; defaultLanguages = @(); packageOrder = (& $noOrder)
            endOfSupport = ''; keepArchives = 3; minFreeGB = 60; spaceCheck = 'enforce'; notes = 'Every index is serviced and recombined. English only. Support end date not yet checked. Catalog search rules checked against the real catalog on 2026-09-24.'; catalogSearch = [ordered]@{ LCU = [ordered]@{ search = 'Cumulative Update for Microsoft server operating system version 21H2'; architecture = 'x64'; excludePreview = $true; buildFilter = '^\d{4}-\d{2} Cumulative Update for Microsoft server operating system,? version 21H2'; checkpointKBs = @() }; NetCU = [ordered]@{ search = '.NET Framework 3.5, 4.8 and 4.8.1 for Microsoft server operating system version 21H2'; architecture = 'x64'; excludePreview = $true; buildFilter = '^\d{4}-\d{2} Cumulative Update for \.NET Framework 3\.5, 4\.8 and 4\.8\.1 for Microsoft server operating system,? version 21H2'; checkpointKBs = @() }; SafeOS = [ordered]@{ search = 'Dynamic Update for Microsoft server operating system version 21H2 for x64-based Systems'; architecture = 'x64'; excludePreview = $true; buildFilter = '^\d{4}-\d{2} Dynamic Update for Microsoft server operating system,? version 21H2'; productFilter = 'Safe OS'; productExclude = ''; checkpointKBs = @() }; SetupDU = [ordered]@{ search = 'Dynamic Update for Microsoft server operating system version 21H2 for x64-based Systems'; architecture = 'x64'; excludePreview = $true; buildFilter = '^\d{4}-\d{2} Dynamic Update for Microsoft server operating system,? version 21H2'; productFilter = 'Dynamic Update'; productExclude = 'Safe OS'; checkpointKBs = @() } } }
    )
}
function Get-ProfileValue {
    param($Data, [string]$Key, $Default = $null)
    if ($null -eq $Data) { return $Default }
    if ($Data -is [System.Collections.IDictionary]) { foreach ($k in $Data.Keys) { if ([string]$k -ieq $Key) { return $Data[$k] } }; return $Default }
    $prop = @($Data.PSObject.Properties | Where-Object { $_.Name -ieq $Key }) | Select-Object -First 1
    if ($prop) { return $prop.Value } else { return $Default }
}
function ConvertTo-OsProfile {
    # Validates one profile (from JSON or the built-in data) and returns the object the engine uses. Throws a plain-language message.
    param([Parameter(Mandatory)]$Data, [string]$SourceFile = '(built-in)')
    $name = ([string](Get-ProfileValue $Data 'name' '')).Trim()
    if (-not $name) { throw "'name' is missing." }
    $folder = ([string](Get-ProfileValue $Data 'folder' '')).Trim()
    if (-not $folder) { throw "'folder' is missing." }
    $all = [bool](Get-ProfileValue $Data 'serviceAllIndexes' $false)
    $regex = [string](Get-ProfileValue $Data 'editionRegex' '')
    if (-not $all) {
        if (-not $regex) { throw "'editionRegex' is required unless serviceAllIndexes is true." }
        try { [void][regex]::new($regex) } catch { throw "'editionRegex' is not a valid regular expression: $($_.Exception.Message)" }
    }
    $prefRaw = [string](Get-ProfileValue $Data 'preferredIndex' 0); [int]$pref = 0
    if (-not [int]::TryParse($prefRaw, [ref]$pref) -or $pref -lt 0) { throw "'preferredIndex' must be a whole number, 0 or more." }
    if (-not $all -and $pref -eq 0 -and -not $regex) { throw "Set 'editionRegex' or a 'preferredIndex' of 1 or more." }
    $lp = [string](Get-ProfileValue $Data 'lpPattern' $script:ClientLpPattern)
    if ($lp -notmatch '\{0\}') { throw "'lpPattern' must contain {0} where the language code goes, for example Microsoft-Windows-Client-Language-Pack_x64_{0}.cab." }
    $langs = @(@(Get-ProfileValue $Data 'defaultLanguages' @()) | Where-Object { $_ } | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
    foreach ($l in $langs) { if ($l -notmatch '^[a-z]{2,3}-[a-z0-9]{2,8}$') { throw "'defaultLanguages' contains '$l', which is not a language code such as de-de." } }
    $alt = @(@(Get-ProfileValue $Data 'altFolders' @()) | Where-Object { $_ } | ForEach-Object { ([string]$_).Trim() })
    $order = @{}
    foreach ($c in $script:ProfileClasses) { $order[$c] = @() }
    $po = Get-ProfileValue $Data 'packageOrder' $null
    if ($null -ne $po) {
        $keys = if ($po -is [System.Collections.IDictionary]) { @($po.Keys) } else { @($po.PSObject.Properties | ForEach-Object { $_.Name }) }
        foreach ($k in $keys) {
            $canon = $script:ProfileClasses | Where-Object { $_ -ieq [string]$k } | Select-Object -First 1
            if (-not $canon) { throw "'packageOrder' has an unknown class '$k'. Use: $($script:ProfileClasses -join ', ')." }
            $order[$canon] = @(@(Get-ProfileValue $po ([string]$k) @()) | Where-Object { $_ } | ForEach-Object { [string]$_ })
        }
    }
    # catalogSearch (step 5): per package class, Microsoft Update Catalog search rules. SSU is refused here - legacy
    # servicing-stack updates always stay a manual, hand-placed file (PATCHES\SSU), never a downloader target.
    $catalogSearch = @{}
    $cs = Get-ProfileValue $Data 'catalogSearch' $null
    if ($null -ne $cs) {
        $csKeys = if ($cs -is [System.Collections.IDictionary]) { @($cs.Keys) } else { @($cs.PSObject.Properties | ForEach-Object { $_.Name }) }
        foreach ($k in $csKeys) {
            $canon = $script:ProfileClasses | Where-Object { $_ -ieq [string]$k } | Select-Object -First 1
            if (-not $canon) { throw "'catalogSearch' has an unknown class '$k'. Use: $($script:ProfileClasses -join ', ')." }
            if ($canon -eq 'SSU') { throw "'catalogSearch' cannot include SSU - servicing stack updates stay manual (PATCHES\SSU)." }
            $ruleData = Get-ProfileValue $cs ([string]$k) $null
            # 'search' may be a single string or an array of strings. Most classes need only one search term, but a
            # few (notably .NET CU on Windows 10 1809, which ships parallel "3.5 and 4.7.2" / "3.5 and 4.8" updates
            # side by side) need every term searched and every match kept, not just the newest single result.
            $searchRaw = Get-ProfileValue $ruleData 'search' $null
            $searchTerms = [System.Collections.Generic.List[string]]::new()
            if ($searchRaw -is [string]) {
                $t = $searchRaw.Trim(); if ($t) { $searchTerms.Add($t) }
            } elseif ($null -ne $searchRaw) {
                foreach ($item in @($searchRaw)) { $t = ([string]$item).Trim(); if ($t) { $searchTerms.Add($t) } }
            }
            if ($searchTerms.Count -eq 0) { throw "'catalogSearch.$canon.search' is required when the class is listed." }
            # The catalog returns nothing at all for a search over 100 characters (checked 2026-09-24: 106 -> 0 results, 93 -> 41).
            foreach ($st in $searchTerms) { if ($st.Length -gt 100) { throw "'catalogSearch.$canon.search' is $($st.Length) characters; the Microsoft Update Catalog returns nothing for a search over 100 characters. Shorten it and let buildFilter match the exact title." } }
            $chainKbs = @(@(Get-ProfileValue $ruleData 'checkpointKBs' @()) | Where-Object { $_ } | ForEach-Object { ([string]$_).Trim() })
            $catalogSearch[$canon] = [ordered]@{
                search = $searchTerms[0]
                searches = @($searchTerms)
                architecture = [string](Get-ProfileValue $ruleData 'architecture' 'x64')
                excludePreview = [bool](Get-ProfileValue $ruleData 'excludePreview' $true)
                buildFilter = [string](Get-ProfileValue $ruleData 'buildFilter' '')
                productFilter = [string](Get-ProfileValue $ruleData 'productFilter' '')
                productExclude = [string](Get-ProfileValue $ruleData 'productExclude' '')
                checkpointKBs = $chainKbs
            }
            foreach ($rk in @('buildFilter', 'productFilter', 'productExclude')) {
                $rx = $catalogSearch[$canon][$rk]
                if ($rx) { try { [void][regex]::new($rx) } catch { throw "'catalogSearch.$canon.$rk' is not a valid regular expression: $($_.Exception.Message)" } }
            }
        }
    }
    $eos = ([string](Get-ProfileValue $Data 'endOfSupport' '')).Trim()
    if ($eos) {
        $dt = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($eos, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$dt)) { throw "'endOfSupport' must look like 2027-01-13 (or be empty)." }
    }
    [int]$keep = 3; if (-not [int]::TryParse([string](Get-ProfileValue $Data 'keepArchives' 3), [ref]$keep) -or $keep -lt 0) { throw "'keepArchives' must be a whole number, 0 or more." }
    [int]$minFree = 30; if (-not [int]::TryParse([string](Get-ProfileValue $Data 'minFreeGB' 30), [ref]$minFree) -or $minFree -lt 0) { throw "'minFreeGB' must be a whole number, 0 or more." }
    $sc = ([string](Get-ProfileValue $Data 'spaceCheck' 'enforce')).Trim().ToLowerInvariant()
    if (@('enforce', 'warn', 'off') -notcontains $sc) { throw "'spaceCheck' must be enforce, warn or off." }
    [int]$sort = 100; [void][int]::TryParse([string](Get-ProfileValue $Data 'sortOrder' 100), [ref]$sort)
    return [pscustomobject]@{
        Name = $name; SortOrder = $sort; Folder = $folder; AltFolders = $alt; ServiceAllIndexes = $all
        EditionRegex = $regex; PreferredIndex = $pref; LpPattern = $lp; SsuRequired = [bool](Get-ProfileValue $Data 'ssuRequired' $false)
        DefaultLanguages = $langs; PackageOrder = $order; CatalogSearch = $catalogSearch; EndOfSupport = $eos; KeepArchives = $keep; MinFreeGB = $minFree; SpaceCheck = $sc
        Notes = [string](Get-ProfileValue $Data 'notes' ''); SourceFile = $SourceFile
    }
}
function Add-ProfileMessage { param([string]$Level, [string]$Text) $script:ProfileMessages.Add([pscustomobject]@{ Level = $Level; Text = $Text }) }
function Write-ProfileMessages {
    foreach ($m in @($script:ProfileMessages)) { Write-Log $m.Text $m.Level }
    $script:ProfileMessages.Clear()
}
function Save-BuiltInProfiles {
    # Writes the built-in profile files that are missing; never touches an existing file. Skips a built-in OS that another
    # file already defines ($SkipNames) or that was switched off by renaming its file to <folder>.json.disabled.
    # Returns the names of the files written.
    param([Parameter(Mandatory)][string]$Directory, [string[]]$SkipNames = @())
    Ensure-Directory $Directory
    $written = [System.Collections.Generic.List[string]]::new()
    foreach ($d in (Get-BuiltInProfileData)) {
        $file = Join-Path $Directory ($d.folder + '.json')
        if ((Test-Path -LiteralPath $file) -or (Test-Path -LiteralPath "$file.disabled") -or (@($SkipNames) -contains $d.name)) { continue }
        [System.IO.File]::WriteAllText($file, (($d | ConvertTo-Json -Depth 6) + [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))
        $written.Add((Split-Path $file -Leaf))
    }
    return $written.ToArray()
}
function Import-OsProfiles {
    # Returns an ordered table name -> profile. Problems are collected in $script:ProfileMessages (flush with Write-ProfileMessages).
    param([string]$Directory)
    $script:ProfileMessages.Clear()
    $table = @{}
    if ($Directory) {
        try {
            # Languages.json (the Languages tab list, step 10e) lives in the same folder but is not an OS profile.
            $profileFiles = { @(Get-ChildItem -LiteralPath $Directory -Filter '*.json' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne $script:LanguagesFileName } | Sort-Object Name) }
            # Every start and every Reload: a built-in profile whose file is missing is written again (Terry, 2026-09-27),
            # so deleting one file and pressing Reload gives a fresh copy of that OS. Existing files are never changed;
            # an OS is switched off by renaming its file to <folder>.json.disabled. The OS names already defined by the
            # existing files are read first, so an OS kept under another file name is not duplicated.
            $definedNames = @(foreach ($f in @(& $profileFiles)) { try { [string](Get-ProfileValue ([System.IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json -ErrorAction Stop) 'name' '') } catch { } })
            $created = @(Save-BuiltInProfiles -Directory $Directory -SkipNames $definedNames)
            if ($created.Count -gt 0) { Add-ProfileMessage 'INFO' "Profile files created from the built-in profiles in ${Directory}: $($created -join ', ')" }
            foreach ($f in @(& $profileFiles)) {
                try {
                    $obj = [System.IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json -ErrorAction Stop
                    $p = ConvertTo-OsProfile -Data $obj -SourceFile $f.Name
                    if ($table.ContainsKey($p.Name)) { Add-ProfileMessage 'WARN' "Profile file $($f.Name) skipped: another file already defines '$($p.Name)'."; continue }
                    $table[$p.Name] = $p
                } catch { Add-ProfileMessage 'WARN' "Profile file $($f.Name) skipped: $($_.Exception.Message)" }
            }
        } catch { Add-ProfileMessage 'WARN' "Profiles folder '$Directory' could not be used: $($_.Exception.Message)" }
    }
    if ($table.Count -eq 0) {
        if ($Directory) { Add-ProfileMessage 'WARN' 'No usable profile file was found; using the built-in profiles.' }
        foreach ($d in (Get-BuiltInProfileData)) { $p = ConvertTo-OsProfile -Data $d; $table[$p.Name] = $p }
    }
    $ordered = [ordered]@{}
    foreach ($p in @($table.Values | Sort-Object SortOrder, Name)) { $ordered[$p.Name] = $p }
    return $ordered
}
$script:OsDefinitions = Import-OsProfiles   # built-ins until a Profiles folder is loaded

# ---------- language list (Languages tab, TODO step 10e) ----------
function Get-BuiltInLanguageData {
    # The languages offered on the Languages tab: Terry's Languages.json (repo root, 2026-09-26). Written to
    # Profiles\Languages.json when that file is missing; the file then wins, so the list is edited there.
    return @(
        @{ language = 'Catalan (Spain)'; code = 'ca-es' }, @{ language = 'Czech (Czech Republic)'; code = 'cs-cz' },
        @{ language = 'German (Germany)'; code = 'de-de' }, @{ language = 'English (United Kingdom)'; code = 'en-gb' },
        @{ language = 'Spanish (Spain)'; code = 'es-es' }, @{ language = 'Spanish (Mexico)'; code = 'es-mx' },
        @{ language = 'French (France)'; code = 'fr-fr' },
        @{ language = 'Hungarian (Hungary)'; code = 'hu-hu' }, @{ language = 'Italian (Italy)'; code = 'it-it' },
        @{ language = 'Japanese (Japan)'; code = 'ja-jp' }, @{ language = 'Korean (South Korea)'; code = 'ko-kr' },
        @{ language = 'Polish (Poland)'; code = 'pl-pl' }, @{ language = 'Portuguese (Brazil)'; code = 'pt-br' },
        @{ language = 'Portuguese (Portugal)'; code = 'pt-pt' }, @{ language = 'Romanian (Romania)'; code = 'ro-ro' },
        @{ language = 'Russian (Russia)'; code = 'ru-ru' }, @{ language = 'Slovak (Slovakia)'; code = 'sk-sk' },
        @{ language = 'Swedish (Sweden)'; code = 'sv-se' }, @{ language = 'Turkish (Turkey)'; code = 'tr-tr' },
        @{ language = 'Chinese (Simplified, China)'; code = 'zh-cn' }, @{ language = 'Chinese (Traditional, Taiwan)'; code = 'zh-tw' }
    )
}
function ConvertTo-LanguageList {
    # Validates Languages.json content (an array of { "language": ..., "code": ... }) and returns one object per entry
    # with Name, Code and Display ("German (Germany) - de-de"). Throws a plain-language message.
    param($Data)
    $out = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($e in @($Data | Where-Object { $null -ne $_ })) {
        $name = ([string](Get-ProfileValue $e 'language' '')).Trim()
        $code = ([string](Get-ProfileValue $e 'code' '')).Trim().ToLowerInvariant()
        if (-not $name -or -not $code) { throw "every entry needs a 'language' name and a 'code'." }
        if ($code -notmatch '^[a-z]{2,3}-[a-z0-9]{2,4}$') { throw "'$code' ($name) is not a language code like de-de." }
        if (-not $seen.Add($code)) { throw "'$code' is listed more than once." }
        $out.Add([pscustomobject]@{ Name = $name; Code = $code; Display = "$name - $code" })
    }
    if ($out.Count -eq 0) { throw 'the list is empty.' }
    return @($out)
}
function Save-BuiltInLanguages {
    # Writes the built-in list in the same one-entry-per-line style as the repo's Languages.json.
    param([Parameter(Mandatory)][string]$File)
    Ensure-Directory (Split-Path $File -Parent)
    $rows = @(Get-BuiltInLanguageData | ForEach-Object { '  { "language": ' + (ConvertTo-Json ([string]$_.language)) + ', "code": ' + (ConvertTo-Json ([string]$_.code)) + ' }' })
    $nl = [Environment]::NewLine
    [System.IO.File]::WriteAllText($File, ('[' + $nl + ($rows -join (',' + $nl)) + $nl + ']' + $nl), (New-Object System.Text.UTF8Encoding($false)))
}
function Import-LanguageList {
    # Returns the Languages tab list from <Directory>\Languages.json, creating it from the built-in list when missing.
    # A bad file is reported and the built-in list used instead - never a crash. Problems go to $script:ProfileMessages,
    # so call this after Import-OsProfiles (which clears them) and before Write-ProfileMessages.
    param([string]$Directory)
    if ($Directory) {
        $file = Join-Path $Directory $script:LanguagesFileName
        try {
            if (-not (Test-Path -LiteralPath $file)) { Save-BuiltInLanguages -File $file; Add-ProfileMessage 'INFO' "Language list created from the built-in list: $file" }
            return ConvertTo-LanguageList -Data ([System.IO.File]::ReadAllText($file) | ConvertFrom-Json -ErrorAction Stop)
        } catch { Add-ProfileMessage 'WARN' "Language list $file could not be used ($($_.Exception.Message)); using the built-in list." }
    }
    return ConvertTo-LanguageList -Data (Get-BuiltInLanguageData)
}
# ---------- saved GUI settings per OS (TODO step 10c) ----------
# Settings\<profile folder>.json holds one OS's checkboxes and ticked languages; Settings\General.json the repository
# root. Kept apart from Profiles\ on purpose: profile files get regenerated, which must not wipe saved choices.
$script:SettingOptionNames = @('Preflight', 'Install', 'Boot', 'WinRE', 'Verify', 'BuildMedia', 'BuildIso', 'Media2023', 'SSU', 'LCU', 'SafeOS', 'NetCU', 'SetupDU', 'NetFx3', 'AppRemoval', 'SccmAutoImport', 'AutoDownload')
function Get-OsSettingsFile {
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][pscustomobject]$Definition)
    return (Join-Path $Directory ($Definition.Folder + '.json'))
}
function Save-OsSettings {
    # Writes the selected OS's choices; returns the file path. Only the known option names are stored, as true/false.
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][pscustomobject]$Definition, [hashtable]$Options = @{}, [string[]]$Languages = @(), [string[]]$RemoveApps = @(), [hashtable]$Sccm = @{})
    Ensure-Directory $Directory
    $opts = [ordered]@{}
    foreach ($k in $script:SettingOptionNames) { if ($Options.ContainsKey($k)) { $opts[$k] = [bool]$Options[$k] } }
    $data = [ordered]@{
        schemaVersion = 1; os = $Definition.Name; saved = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); options = $opts
        languages = @($Languages | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() })
        removeApps = @($RemoveApps | Where-Object { $_ } | ForEach-Object { [string]$_ })   # provisioned apps ticked on the Apps tab, by DisplayName
        # SCCM tab, per OS: content source folder, package type (Image / Upgrade), and the image name only when typed by hand
        sccm = [ordered]@{ contentSource = [string]$Sccm['ContentSource']; packageType = [string]$Sccm['PackageType']; imageName = [string]$Sccm['ImageName'] }
    }
    $file = Get-OsSettingsFile -Directory $Directory -Definition $Definition
    [System.IO.File]::WriteAllText($file, (($data | ConvertTo-Json -Depth 4) + [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))
    return $file
}
function Read-OsSettings {
    # The OS's saved choices, or $null when it has none. An unusable file is reported (WARN) and ignored - never a crash.
    # Saved languages that are no longer on the Languages tab list come back in MissingLanguages, not in Languages.
    param([string]$Directory, [Parameter(Mandatory)][pscustomobject]$Definition, [object[]]$LanguageList = @())
    if (-not $Directory) { return $null }
    $file = Get-OsSettingsFile -Directory $Directory -Definition $Definition
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try {
        $obj = [System.IO.File]::ReadAllText($file) | ConvertFrom-Json -ErrorAction Stop
        $optObj = Get-ProfileValue $obj 'options' $null
        if ($null -eq $optObj) { throw "'options' is missing." }
        $opts = @{}
        foreach ($k in $script:SettingOptionNames) {
            $v = Get-ProfileValue $optObj $k $null
            if ($null -eq $v) { continue }
            if ($v -isnot [bool]) { throw "'options.$k' must be true or false." }
            $opts[$k] = $v
        }
        $codes = @(@(Get-ProfileValue $obj 'languages' @()) | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() })
        $known = @($LanguageList | ForEach-Object { $_.Code })
        $apps = @(@(Get-ProfileValue $obj 'removeApps' @()) | Where-Object { $_ } | ForEach-Object { [string]$_ })
        $sc = Get-ProfileValue $obj 'sccm' $null
        $sccm = [pscustomobject]@{ ContentSource = [string](Get-ProfileValue $sc 'contentSource' ''); PackageType = [string](Get-ProfileValue $sc 'packageType' ''); ImageName = [string](Get-ProfileValue $sc 'imageName' '') }
        return [pscustomobject]@{ File = $file; Options = $opts; Languages = @($codes | Where-Object { $known -contains $_ }); MissingLanguages = @($codes | Where-Object { $known -notcontains $_ }); RemoveApps = $apps; Sccm = $sccm }
    } catch {
        Write-Log "Saved settings $file could not be used ($($_.Exception.Message)); using the defaults." 'WARN'
        return $null
    }
}
function Remove-OsSettings {
    # Deletes the OS's saved choices; $true when there was a file.
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][pscustomobject]$Definition)
    $file = Get-OsSettingsFile -Directory $Directory -Definition $Definition
    if (-not (Test-Path -LiteralPath $file)) { return $false }
    Remove-Item -LiteralPath $file -Force -ErrorAction Stop
    return $true
}
function Save-GeneralSettings {
    # Settings\General.json holds what is shared by every OS. Only the values passed are changed; the others are kept.
    param([Parameter(Mandatory)][string]$Directory, [string]$Root, [string]$ColorScheme, [string]$SccmSiteServer, [string]$SccmTargetType, [string]$SccmTarget)
    Ensure-Directory $Directory
    $file = Join-Path $Directory 'General.json'
    $old = $null
    if (Test-Path -LiteralPath $file) { try { $old = [System.IO.File]::ReadAllText($file) | ConvertFrom-Json -ErrorAction Stop } catch { $old = $null } }
    $data = [ordered]@{
        schemaVersion = 1; saved = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        root        = $(if ($PSBoundParameters.ContainsKey('Root')) { [string]$Root } else { [string](Get-ProfileValue $old 'root' '') })
        colorScheme = $(if ($PSBoundParameters.ContainsKey('ColorScheme')) { [string]$ColorScheme } else { [string](Get-ProfileValue $old 'colorScheme' '') })
        # SCCM tab (step 7): shared by every OS
        sccmSiteServer = $(if ($PSBoundParameters.ContainsKey('SccmSiteServer')) { [string]$SccmSiteServer } else { [string](Get-ProfileValue $old 'sccmSiteServer' '') })
        sccmTargetType = $(if ($PSBoundParameters.ContainsKey('SccmTargetType')) { [string]$SccmTargetType } else { [string](Get-ProfileValue $old 'sccmTargetType' '') })
        sccmTarget     = $(if ($PSBoundParameters.ContainsKey('SccmTarget')) { [string]$SccmTarget } else { [string](Get-ProfileValue $old 'sccmTarget' '') })
    }
    [System.IO.File]::WriteAllText($file, (($data | ConvertTo-Json) + [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))
}
function Read-SccmGeneralSettings {
    # The SCCM tab's shared values from General.json (empty strings when not saved; an unusable file is a WARN).
    param([string]$Directory)
    $none = [pscustomobject]@{ SiteServer = ''; TargetType = ''; Target = '' }
    if (-not $Directory) { return $none }
    $file = Join-Path $Directory 'General.json'
    if (-not (Test-Path -LiteralPath $file)) { return $none }
    try {
        $o = [System.IO.File]::ReadAllText($file) | ConvertFrom-Json -ErrorAction Stop
        return [pscustomobject]@{ SiteServer = [string](Get-ProfileValue $o 'sccmSiteServer' ''); TargetType = [string](Get-ProfileValue $o 'sccmTargetType' ''); Target = [string](Get-ProfileValue $o 'sccmTarget' '') }
    } catch { Write-Log "Saved settings $file could not be used ($($_.Exception.Message))." 'WARN'; return $none }
}
function Read-ColorSchemeSetting {
    # The saved colour scheme name, or '' when there is none or the file is unusable (WARN).
    param([string]$Directory)
    if (-not $Directory) { return '' }
    $file = Join-Path $Directory 'General.json'
    if (-not (Test-Path -LiteralPath $file)) { return '' }
    try { return ([string](Get-ProfileValue ([System.IO.File]::ReadAllText($file) | ConvertFrom-Json -ErrorAction Stop) 'colorScheme' '')).Trim() }
    catch { Write-Log "Saved settings $file could not be used ($($_.Exception.Message))." 'WARN'; return '' }
}
function Get-ColorSchemes {
    # The colour schemes on the General Settings tab (Terry, 2026-09-27). 'Default' is the original look: the window keeps
    # the standard Windows controls and only these colours are applied. The other schemes restyle every control.
    # Palette = the colours as Terry gave them (shown as swatches); Colors = the colour used for each part of the window.
    # Colours not in a palette (light text on dark backgrounds, warning / error log colours where none was given) are
    # chosen to stay readable against that scheme's backgrounds.
    $s = [ordered]@{}
    $s['Default'] = [ordered]@{ Dark = $false
        Palette = @('Window #F4F6F8', 'Accent #0078D4', 'Muted text #555555', 'Log background #111827', 'Log text #E5E7EB')
        Colors  = [ordered]@{ WindowBg = '#F4F6F8'; PanelBg = '#FFFFFF'; ControlBg = '#FFFFFF'; Border = '#ACACAC'; Text = '#000000'; SubtleText = '#555555'; Title = '#000000'
            Accent = '#0078D4'; AccentText = '#FFFFFF'; ButtonBg = '#DDDDDD'; ButtonText = '#000000'; TabBg = '#F0F0F0'; TabSelectedText = '#000000'
            Hover = '#E5F3FB'; SelectionBg = '#CCE8FF'; SelectionText = '#000000'; InfoText = '#696969'; WarnText = '#B22222'; CodeBg = '#EEF1F4'
            LogBg = '#111827'; LogText = '#E5E7EB'; LogSuccess = '#E5E7EB'; LogWarn = '#E5E7EB'; LogError = '#E5E7EB' } }
    $s['Industrial Forge'] = [ordered]@{ Dark = $true
        Palette = @('Iron Gray #2B2B2B', 'Steel Blue #3A5F7D', 'Charcoal #1A1A1A', 'Molten Orange #FF6A00', 'Amber Glow #FFC14A')
        Colors  = [ordered]@{ WindowBg = '#2B2B2B'; PanelBg = '#1A1A1A'; ControlBg = '#2B2B2B'; Border = '#3A5F7D'; Text = '#EDEDED'; SubtleText = '#B0B0B0'; Title = '#FF6A00'
            Accent = '#FF6A00'; AccentText = '#1A1A1A'; ButtonBg = '#3A5F7D'; ButtonText = '#FFFFFF'; TabBg = '#2B2B2B'; TabSelectedText = '#FFC14A'
            Hover = '#2F4A60'; SelectionBg = '#3A5F7D'; SelectionText = '#FFFFFF'; InfoText = '#B0B0B0'; WarnText = '#FFC14A'; CodeBg = '#3A3A3A'
            LogBg = '#1A1A1A'; LogText = '#FFC14A'; LogSuccess = '#FFC14A'; LogWarn = '#FF6A00'; LogError = '#FF4D4D' } }
    $s['Modern Sysadmin'] = [ordered]@{ Dark = $true
        Palette = @('Azure Blue #0078D4', 'Graphite #3C3C3C', 'Slate #5A5A5A', 'Cloud Gray #D0D0D0', 'Lime Signal #A4E400')
        Colors  = [ordered]@{ WindowBg = '#3C3C3C'; PanelBg = '#333333'; ControlBg = '#2A2A2A'; Border = '#5A5A5A'; Text = '#D0D0D0'; SubtleText = '#A8A8A8'; Title = '#FFFFFF'
            Accent = '#0078D4'; AccentText = '#FFFFFF'; ButtonBg = '#5A5A5A'; ButtonText = '#FFFFFF'; TabBg = '#3C3C3C'; TabSelectedText = '#FFFFFF'
            Hover = '#474747'; SelectionBg = '#0078D4'; SelectionText = '#FFFFFF'; InfoText = '#A8A8A8'; WarnText = '#FFC83D'; CodeBg = '#262626'
            LogBg = '#1E1E1E'; LogText = '#D0D0D0'; LogSuccess = '#A4E400'; LogWarn = '#FFC83D'; LogError = '#FF6B6B' } }
    $s['Arcane Tech (Runic Teal)'] = [ordered]@{ Dark = $true
        Palette = @('Runic Teal #00A6A6', 'Obsidian #0F0F0F', 'Gunmetal #2F3B45', 'Deep Violet #4B2E83', 'Electrum Gold #C6A667')
        Colors  = [ordered]@{ WindowBg = '#0F0F0F'; PanelBg = '#2F3B45'; ControlBg = '#1A2229'; Border = '#4B5A67'; Text = '#E8E8E8'; SubtleText = '#A9B4BE'; Title = '#C6A667'
            Accent = '#00A6A6'; AccentText = '#0F0F0F'; ButtonBg = '#4B2E83'; ButtonText = '#FFFFFF'; TabBg = '#1A2229'; TabSelectedText = '#C6A667'
            Hover = '#3A4854'; SelectionBg = '#00A6A6'; SelectionText = '#0F0F0F'; InfoText = '#A9B4BE'; WarnText = '#C6A667'; CodeBg = '#1A2229'
            LogBg = '#0F0F0F'; LogText = '#C6A667'; LogSuccess = '#00A6A6'; LogWarn = '#FFB454'; LogError = '#FF6B6B' } }
    $s['Minimalist Forge'] = [ordered]@{ Dark = $true
        Palette = @('Blackened Steel #121212', 'Soft Gray #B8B8B8', 'Neutral Dark #2E2E2E', 'Forge Red #D7263D', 'White Heat #F2F2F2')
        Colors  = [ordered]@{ WindowBg = '#121212'; PanelBg = '#2E2E2E'; ControlBg = '#1C1C1C'; Border = '#4A4A4A'; Text = '#F2F2F2'; SubtleText = '#B8B8B8'; Title = '#F2F2F2'
            Accent = '#D7263D'; AccentText = '#F2F2F2'; ButtonBg = '#3A3A3A'; ButtonText = '#F2F2F2'; TabBg = '#1C1C1C'; TabSelectedText = '#F2F2F2'
            Hover = '#3A3A3A'; SelectionBg = '#D7263D'; SelectionText = '#F2F2F2'; InfoText = '#B8B8B8'; WarnText = '#FF6B7A'; CodeBg = '#1C1C1C'
            LogBg = '#121212'; LogText = '#B8B8B8'; LogSuccess = '#B8B8B8'; LogWarn = '#F2F2F2'; LogError = '#D7263D' } }
    return $s
}
function ConvertFrom-MarkdownBlocks {
    # The Markdown subset INSTRUCTIONS.md uses (TODO 10b), split into blocks for the Instructions tab: Heading (Level 1-6),
    # Paragraph, ListItem (Level = nesting from 2-space indents, Ordered for "1."), Code (fenced ```). Lines of a paragraph,
    # and indented continuation lines of a list item, are joined with spaces. Inline markup is left in Text.
    param([string]$Markdown)
    $blocks = [System.Collections.Generic.List[object]]::new()
    $para = $null; $inCode = $false; $code = $null
    $flush = { if ($null -ne $para) { $blocks.Add([pscustomobject]@{ Type = 'Paragraph'; Level = 0; Ordered = $false; Text = $para }); Set-Variable -Name para -Value $null -Scope 1 } }
    foreach ($line in ($Markdown -split '\r?\n')) {
        if ($inCode) {
            if ($line -match '^\s*```') { $blocks.Add([pscustomobject]@{ Type = 'Code'; Level = 0; Ordered = $false; Text = ($code -join "`n") }); $inCode = $false }
            else { $code.Add($line) }
            continue
        }
        if ($line -match '^\s*```') { & $flush; $inCode = $true; $code = [System.Collections.Generic.List[string]]::new(); continue }
        if ($line -match '^\s*$') { & $flush; continue }
        if ($line -match '^(#{1,6})\s+(.*)$') { & $flush; $blocks.Add([pscustomobject]@{ Type = 'Heading'; Level = $Matches[1].Length; Ordered = $false; Text = $Matches[2].Trim() }); continue }
        if ($line -match '^(\s*)([-*]|\d+\.)\s+(.*)$') {
            $indent = $Matches[1].Length; $marker = $Matches[2]; $itemText = $Matches[3].Trim()   # before -match below resets $Matches
            & $flush
            $blocks.Add([pscustomobject]@{ Type = 'ListItem'; Level = [int][Math]::Floor($indent / 2); Ordered = ($marker -match '^\d'); Text = $itemText })
            continue
        }
        if ($null -eq $para -and $line -match '^\s+\S' -and $blocks.Count -gt 0 -and $blocks[$blocks.Count - 1].Type -eq 'ListItem') {
            $blocks[$blocks.Count - 1].Text += ' ' + $line.Trim(); continue
        }
        $para = if ($null -eq $para) { $line.Trim() } else { $para + ' ' + $line.Trim() }
    }
    & $flush
    if ($inCode) { $blocks.Add([pscustomobject]@{ Type = 'Code'; Level = 0; Ordered = $false; Text = ($code -join "`n") }) }
    return $blocks.ToArray()
}
function Split-MarkdownInline {
    # Inline markup for the Instructions tab: **bold**, *italic*, `code`, [text](url). Returns runs of Kind Text / Bold /
    # Italic / Code / Link (Url set for links). Underscores are never markup (paths like Media_CA2023 stay as they are).
    param([string]$Text)
    $runs = [System.Collections.Generic.List[object]]::new()
    $pattern = '(`[^`]+`|\*\*[^*]+\*\*|\[[^\]]+\]\([^)\s]+\)|\*[^*\s][^*]*\*)'
    foreach ($part in [regex]::Split($Text, $pattern)) {
        if ($part -eq '') { continue }
        if ($part -match '^`([^`]+)`$') { $runs.Add([pscustomobject]@{ Kind = 'Code'; Text = $Matches[1]; Url = '' }) }
        elseif ($part -match '^\*\*([^*]+)\*\*$') { $runs.Add([pscustomobject]@{ Kind = 'Bold'; Text = $Matches[1]; Url = '' }) }
        elseif ($part -match '^\[([^\]]+)\]\(([^)\s]+)\)$') { $runs.Add([pscustomobject]@{ Kind = 'Link'; Text = $Matches[1]; Url = $Matches[2] }) }
        elseif ($part -match '^\*([^*\s][^*]*)\*$') { $runs.Add([pscustomobject]@{ Kind = 'Italic'; Text = $Matches[1]; Url = '' }) }
        else { $runs.Add([pscustomobject]@{ Kind = 'Text'; Text = $part; Url = '' }) }
    }
    return $runs.ToArray()
}
function Get-LogLineKind {
    # How the Log tab colours a line: Error, Warn, Success or Normal, from the [LEVEL] tag every log line carries.
    param([string]$Line)
    if ($Line -match '^(\d{2}:\d{2}:\d{2} )?\[ERROR\]') { return 'Error' }
    if ($Line -match '^(\d{2}:\d{2}:\d{2} )?\[(WARN|CANCELLED)\]') { return 'Warn' }
    if ($Line -match '(?i)VALIDATION GATE: PASSED|PREFLIGHT OK|completed successfully|All \d+ language packs located|\bsaved to\b') { return 'Success' }
    return 'Normal'
}
function Read-GeneralSettings {
    # The saved repository root, or '' when there is none or the file is unusable (WARN).
    param([string]$Directory)
    if (-not $Directory) { return '' }
    $file = Join-Path $Directory 'General.json'
    if (-not (Test-Path -LiteralPath $file)) { return '' }
    try { return ([string](Get-ProfileValue ([System.IO.File]::ReadAllText($file) | ConvertFrom-Json -ErrorAction Stop) 'root' '')).Trim() }
    catch { Write-Log "Saved settings $file could not be used ($($_.Exception.Message))." 'WARN'; return '' }
}
function Get-DefaultLanguageSelection {
    # A profile's defaultLanguages split into the codes that are on the Languages tab list (to pre-select) and the ones
    # that are not (reported, not selected).
    param([pscustomobject]$Definition, [object[]]$LanguageList)
    $codes = @($LanguageList | ForEach-Object { $_.Code })
    $defaults = @($Definition.DefaultLanguages | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() })
    return [pscustomobject]@{ Select = @($defaults | Where-Object { $codes -contains $_ }); Missing = @($defaults | Where-Object { $codes -notcontains $_ }) }
}

function Get-SupportStatus {
    param([Parameter(Mandatory)]$Definition, [datetime]$Now = (Get-Date))
    if (-not $Definition.EndOfSupport) { return [pscustomobject]@{ Level = 'Unknown'; Days = $null; Text = 'Support end date not set in the profile.' } }
    $d = [datetime]::ParseExact($Definition.EndOfSupport, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    $days = [int][Math]::Floor(($d.Date - $Now.Date).TotalDays)
    if ($days -lt 0) { return [pscustomobject]@{ Level = 'Past'; Days = $days; Text = "Support ended $($Definition.EndOfSupport) ($([Math]::Abs($days)) days ago)." } }
    $lvl = if ($days -le 180) { 'Soon' } else { 'OK' }
    return [pscustomobject]@{ Level = $lvl; Days = $days; Text = "Support ends $($Definition.EndOfSupport) ($days days)." }
}
function Write-SupportStatus {
    param([Parameter(Mandatory)]$Definition)
    $st = Get-SupportStatus -Definition $Definition
    $lvl = if ($st.Level -in @('Past', 'Soon')) { 'WARN' } else { 'INFO' }
    Write-Log $st.Text $lvl
}

function Get-TS { Get-Date -Format 'HH:mm:ss' }
function Write-Log {
    param([Parameter(Mandatory)][string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-TS), $Level, $Message
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 }
    if ($script:UiQueue) { $script:UiQueue.Enqueue("L`t$line") }   # background run: the GUI thread drains this queue
    elseif ($script:LogBox) {
        Add-LogText $line
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, 'Background')
    } else { Write-Host $line }   # GUI runs log to the window and file only; console writes can block (Quick Edit)
}
function Set-Progress {
    param([int]$Percent, [string]$Status)
    $pct = [Math]::Max(0, [Math]::Min(100, $Percent))
    if ($script:UiQueue) { $script:UiQueue.Enqueue("P`t$pct`t$Status"); return }
    if ($script:Progress) { $script:Progress.Value = $pct }
    if ($script:Status)   { $script:Status.Text = $Status }
    if ($script:Progress) { [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, 'Background') }
}
function Set-Phase {
    # Updates the title-bar "OS being worked on / current phase" display. $OsName is sticky for the rest of the run; pass it
    # once (Invoke-MediaRefresh does, at the top) and just -Phase after that.
    param([string]$Phase, [string]$OsName = $null)
    if ($OsName) { $script:CurrentOsName = $OsName }
    if ($script:UiQueue) { $script:UiQueue.Enqueue("H`t$($script:CurrentOsName)`t$Phase"); return }
    if ($script:HeaderOs)    { $script:HeaderOs.Text = $script:CurrentOsName }
    if ($script:HeaderPhase) { $script:HeaderPhase.Text = $Phase }
    if ($script:HeaderPhase) { [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, 'Background') }
}
function Assert-NotCancelled {
    if ($script:Cancelled -or ($script:Shared -and $script:Shared['Cancel'])) { throw 'Operation cancelled by user.' }
}
function Ensure-Directory { param([string]$Path) if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null } }
function Join-Chain {
    param([Parameter(Mandatory)][string]$Base, [Parameter(Mandatory)][string[]]$Parts)
    $p = $Base
    foreach ($part in $Parts) { $p = Join-Path $p $part }
    return $p
}
function Get-NormalizedPath {
    param([string]$Path)
    if (-not $Path) { return '' }
    return $Path.TrimEnd('\', '/').ToLowerInvariant()
}

# ---------- mount safety ----------
function Test-IsMounted {
    param([string]$Path)
    $target = Get-NormalizedPath $Path
    foreach ($m in @(Get-WindowsImage -Mounted -ErrorAction SilentlyContinue)) {
        if ((Get-NormalizedPath $m.Path) -eq $target) { return $true }
    }
    return $false
}
function Dismount-IfMounted {
    param([string]$Path)
    if (Test-IsMounted $Path) {
        try { Dismount-WindowsImage -Path $Path -Discard -ErrorAction Stop | Out-Null; Write-Log "Discarded mounted image at $Path" 'WARN' }
        catch { Write-Log "Could not discard mounted image at ${Path}: $($_.Exception.Message)" 'WARN' }
    }
}
function Test-PathUnder {
    # True when $Path is $Root or inside it, by whole folder names (F:\mr\Win11_old is not under F:\mr\Win11).
    param([string]$Path, [string]$Root)
    $p = Get-NormalizedPath $Path; $r = Get-NormalizedPath $Root
    return [bool]($r -and ($p -eq $r -or $p.StartsWith($r + '\')))
}
function Clear-StaleMounts {
    param([string]$Root)
    foreach ($m in @(Get-WindowsImage -Mounted -ErrorAction SilentlyContinue)) {
        if (Test-PathUnder $m.Path $Root) {
            Write-Log "Found stale mount $($m.Path) (status $($m.MountStatus)); discarding it." 'WARN'
            try { Dismount-WindowsImage -Path $m.Path -Discard -ErrorAction Stop | Out-Null }
            catch {
                Write-Log "Discard failed ($($_.Exception.Message)); running Clear-WindowsCorruptMountPoint." 'WARN'
                Clear-WindowsCorruptMountPoint | Out-Null
            }
        }
    }
}
function Test-IsoAttached {
    param([string]$Path)
    try { return [bool](Get-DiskImage -ImagePath $Path -ErrorAction Stop).Attached } catch { return $false }
}
function Clear-StaleIsoMounts {
    # ISOs from an OS's ISO folder that are still mounted (left by a crashed run, or mounted by hand) are dismounted
    # before a run mounts them itself (TODO step 8, ISO mount hygiene).
    param([string]$IsoFolder)
    foreach ($f in @(Get-ChildItem -LiteralPath $IsoFolder -Filter '*.iso' -File -ErrorAction SilentlyContinue)) {
        if (-not (Test-IsoAttached $f.FullName)) { continue }
        Write-Log "ISO $($f.Name) was already mounted (left by an earlier run, or mounted by hand); dismounting it." 'WARN'
        try { Dismount-DiskImage -ImagePath $f.FullName -ErrorAction Stop | Out-Null }
        catch { Write-Log "Could not dismount ISO $($f.FullName): $($_.Exception.Message)" 'WARN' }
    }
}
function Get-MountCleanupPlan {
    # What "Cleanup Mountpoints" (Tools menu) finds under the repository root: images mounted anywhere under it, mounted
    # ISOs from any <OS>\ISO folder, and MOUNT sub-folders holding leftover files while nothing is mounted there.
    # Images mounted outside the root are listed separately and never touched.
    param([Parameter(Mandatory)][string]$Root)
    $wim = @(); $other = @()
    foreach ($m in @(Get-WindowsImage -Mounted -ErrorAction SilentlyContinue)) {
        $e = [pscustomobject]@{ Path = ([string]$m.Path).TrimEnd('\'); ImagePath = [string](Get-ProfileValue $m 'ImagePath' ''); Status = [string](Get-ProfileValue $m 'MountStatus' '') }
        if (Test-PathUnder $e.Path $Root) { $wim += $e } else { $other += $e }
    }
    $isos = @(); $folders = @()
    foreach ($os in @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue)) {
        foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $os.FullName 'ISO') -Filter '*.iso' -File -ErrorAction SilentlyContinue)) {
            if (Test-IsoAttached $f.FullName) { $isos += $f.FullName }
        }
        foreach ($d in @(Get-ChildItem -LiteralPath (Join-Path $os.FullName 'MOUNT') -Directory -ErrorAction SilentlyContinue)) {
            if (@($wim | Where-Object { (Get-NormalizedPath $_.Path) -eq (Get-NormalizedPath $d.FullName) }).Count -gt 0) { continue }
            if (@(Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue | Select-Object -First 1).Count -gt 0) { $folders += $d.FullName }
        }
    }
    return [pscustomobject]@{ Root = $Root; WimMounts = @($wim); OtherWimMounts = @($other); Isos = @($isos); LeftoverFolders = @($folders); Count = ($wim.Count + $isos.Count + $folders.Count) }
}
function Invoke-MountCleanup {
    # "Cleanup Mountpoints" (Tools menu, TODO step 10d). -DryRun only reports. Otherwise: discards every image mounted
    # under the repository root (changes in it are lost), clears corrupt mount points, dismounts the ISOs and empties
    # MOUNT sub-folders left with files, then checks again. Nothing outside the repository root is touched.
    param([Parameter(Mandatory)][string]$Root, [switch]$DryRun)
    Set-Phase -OsName 'Cleanup Mountpoints' -Phase $(if ($DryRun) { 'Checking mounts' } else { 'Cleaning up mounts' })
    if (-not (Test-Path -LiteralPath $Root)) { throw "Repository root $Root does not exist." }
    $plan = Get-MountCleanupPlan -Root $Root
    Write-Log "Mount cleanup under $Root$(if ($DryRun) { ' (check only)' }): $($plan.WimMounts.Count) mounted image(s), $($plan.Isos.Count) mounted ISO(s), $($plan.LeftoverFolders.Count) mount folder(s) with leftover files."
    foreach ($m in $plan.WimMounts) { Write-Log "  Mounted image: $($m.Path) ($($m.ImagePath), status $($m.Status))" }
    foreach ($i in $plan.Isos) { Write-Log "  Mounted ISO: $i" }
    foreach ($d in $plan.LeftoverFolders) { Write-Log "  Leftover files in: $d" }
    foreach ($m in $plan.OtherWimMounts) { Write-Log "  Left alone (outside the repository root): $($m.Path)" }
    $done = [System.Collections.Generic.List[string]]::new()
    $remaining = @()
    if (-not $DryRun) {
        foreach ($m in $plan.WimMounts) {
            Assert-NotCancelled
            Write-Log "Discarding mounted image $($m.Path) (changes in it are not saved)."
            try { Dismount-WindowsImage -Path $m.Path -Discard -ErrorAction Stop | Out-Null; $done.Add("Discarded mounted image $($m.Path)") }
            catch { Write-Log "Discard failed for $($m.Path): $($_.Exception.Message)" 'WARN' }
        }
        if ($plan.WimMounts.Count -gt 0) {
            Write-Log 'Clearing corrupt mount points (DISM /Cleanup-Mountpoints).'
            try { Clear-WindowsCorruptMountPoint -ErrorAction Stop | Out-Null } catch { Write-Log "Clearing corrupt mount points failed: $($_.Exception.Message)" 'WARN' }
        }
        foreach ($i in $plan.Isos) {
            Assert-NotCancelled
            try { Dismount-DiskImage -ImagePath $i -ErrorAction Stop | Out-Null; Write-Log "Dismounted ISO $i"; $done.Add("Dismounted ISO $i") }
            catch { Write-Log "Could not dismount ISO ${i}: $($_.Exception.Message)" 'WARN' }
        }
        # Checked again: a discard can leave files behind, and a failed discard may have been cleared above.
        foreach ($d in (Get-MountCleanupPlan -Root $Root).LeftoverFolders) {
            try { Get-ChildItem -LiteralPath $d -Force | Remove-Item -Recurse -Force -ErrorAction Stop; Write-Log "Emptied $d"; $done.Add("Emptied $d") }
            catch { Write-Log "Could not empty ${d}: $($_.Exception.Message)" 'WARN' }
        }
        $after = Get-MountCleanupPlan -Root $Root
        $remaining = @(@($after.WimMounts | ForEach-Object { "Mounted image $($_.Path)" }) + @($after.Isos | ForEach-Object { "Mounted ISO $_" }) + @($after.LeftoverFolders | ForEach-Object { "Leftover files in $_" }))
        if ($remaining.Count -gt 0) { Write-Log "Mount cleanup finished; still left: $($remaining -join '; '). Restarting the build machine usually releases these; then run Cleanup Mountpoints again." 'WARN' }
        else { Write-Log "Mount cleanup completed successfully ($($done.Count) item(s) cleaned)." }
    }
    Set-Phase 'Done'
    $script:LastResult = [pscustomobject]@{ Mode = 'Cleanup'; DryRun = [bool]$DryRun; Root = $Root; Plan = $plan; Done = @($done); Remaining = @($remaining) }
    return $script:LastResult
}
function Remove-DirectoryContents {
    param([string]$Path)
    Ensure-Directory $Path
    if (Test-IsMounted $Path) { throw "Refusing to clear $Path because an image is still mounted there." }
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction Stop
}

# ---------- DISM helpers ----------
function Invoke-DismExe {
    param([Parameter(Mandatory)][string[]]$Arguments = @(), [Parameter(Mandatory)][string]$Description, [switch]$AllowPending)
    Write-Log $Description
    $all = @($Arguments)
    if ($script:DismLogArgs.ContainsKey('LogPath')) { $all += ('/LogPath:' + $script:DismLogArgs['LogPath']) }
    & dism.exe @all | ForEach-Object { if ($_ -and $_.Trim()) { Write-Log $_ } }
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        if ($AllowPending -and (($code -eq -2146498554) -or ($code -eq 0x800F0806))) {
            Write-Log "Cleanup reported CBS_E_PENDING ($code); continuing." 'WARN'
        } else { throw "$Description failed with exit code $code." }
    }
}
function Test-DismHostVersion {
    param([string]$ImageVersion)
    try {
        $cmd = Get-Command dism.exe -ErrorAction Stop
        $hostVer = [version]$cmd.Version
        $imgVer  = [version]$ImageVersion
        Write-Log "Host DISM $hostVer; image $imgVer"
        if ($imgVer.Build -gt $hostVer.Build) {
            Write-Log "Host DISM build $($hostVer.Build) is older than the image build $($imgVer.Build). Servicing may fail; use the ADK's DISM or a newer host." 'WARN'
        }
    } catch { Write-Log "Could not compare host DISM and image versions: $($_.Exception.Message)" 'WARN' }
}

# ---------- change log helpers ----------
function ConvertTo-SafeFileName { param([string]$Name) return ($Name -replace '[\\/:*?"<>|]', '_').Trim() }
function Get-KbFromName {
    param([string]$Name)
    $m = [regex]::Match([string]$Name, '(?i)KB[0-9]{6,8}')
    if ($m.Success) { return $m.Value.ToUpperInvariant() } else { return '' }
}
function Test-PatchTuesday {
    # $true for the second Tuesday of a month (Microsoft's monthly release day).
    param([datetime]$Date)
    return ($Date.DayOfWeek -eq [DayOfWeek]::Tuesday -and $Date.Day -ge 8 -and $Date.Day -le 14)
}
function Format-CatalogPick {
    # "<title> (<KB>)" for the dry-run dialog and log - but catalog titles already end in "(KBnnnnnnn)", so the KB is only
    # added when the title does not contain it (Terry, 2026-09-24: every KB was listed twice).
    # The release date and classification follow in brackets, so an out-of-band release ("Updates", mid-month) is told
    # apart from the Patch Tuesday one ("Security Updates") before anything is downloaded (Terry, 2026-09-24).
    # -Release (LCU only) names Patch Tuesday vs out-of-band from the date: Microsoft classed the September 2026 Win11
    # out-of-band LCU "Security Updates", so the classification alone does not tell them apart.
    param([string]$Title, [string]$Kb, [datetime]$Date = [datetime]::MinValue, [string]$Classification = '', [switch]$Release)
    $text = if ($Kb -and $Title -notmatch [regex]::Escape($Kb)) { "$Title ($Kb)" } else { $Title }
    $extra = @()
    if ($Date -ne [datetime]::MinValue) { $extra += 'released ' + $Date.ToString('yyyy-MM-dd') }
    if ($Release -and $Date -ne [datetime]::MinValue) { $extra += $(if (Test-PatchTuesday $Date) { 'Patch Tuesday' } else { 'out-of-band' }) }
    if ($Classification) { $extra += $Classification }
    if ($extra.Count -gt 0) { $text += ' [' + ($extra -join ', ') + ']' }
    return $text
}
function Get-EventCategory {
    # Maps an Add-Packages -Label to a Section A category, without touching every call site.
    param([string]$Label)
    switch -Regex ($Label) {
        '^SSU$'              { return 'SSU' }
        '^LCU'                { return 'LCU' }
        '^Safe OS DU$'        { return 'SafeOS' }
        '^Setup DU$'          { return 'SetupDU' }
        '^\.NET CU$'          { return 'NetCU' }
        '^language pack '     { return 'LanguagePack' }
        '^WinPE '              { return 'WinPE' }
        default                { return 'Other' }
    }
}
function Add-ChangeEvent {
    # Section A: one row per change this run actually made, with the time it succeeded.
    param([Parameter(Mandatory)][string]$Category, [Parameter(Mandatory)][string]$Item, [Parameter(Mandatory)][string]$Target, [string]$Kb = '', [string]$Detail = '')
    if (-not $script:ChangeEvents) { $script:ChangeEvents = [System.Collections.Generic.List[object]]::new() }
    $script:ChangeEvents.Add([pscustomobject]@{ Time = (Get-Date); Category = $Category; Item = $Item; Kb = $Kb; Target = $Target; Detail = $Detail })
}

# ---------- acquisition (MSCatalogLTS) - step 5 ----------
# Fills PATCHES\<class> automatically from the Microsoft Update Catalog, per the OS profile's catalogSearch rules.
# PATCHES\SSU is never touched by any function in this section - legacy servicing-stack updates stay a manual,
# hand-placed file, exactly as ConvertTo-OsProfile refuses an SSU catalogSearch rule at the profile-validation level.
function Ensure-CatalogModule {
    # Installs (CurrentUser scope) and imports MSCatalogLTS on first use. Throws a plain-language error - never a bare
    # "command not found" - when the module cannot be obtained (offline machine, blocked PowerShell Gallery, etc.).
    if (Get-Module -Name MSCatalogLTS -ListAvailable -ErrorAction SilentlyContinue) {
        Import-Module MSCatalogLTS -ErrorAction Stop
        return
    }
    Write-Log 'MSCatalogLTS module not found locally; installing from the PowerShell Gallery (CurrentUser scope).'
    try {
        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
        }
        Install-Module -Name MSCatalogLTS -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Import-Module MSCatalogLTS -ErrorAction Stop
    } catch {
        throw "Could not install the MSCatalogLTS module (needed to search and download patches automatically): $($_.Exception.Message). Install it manually (Install-Module MSCatalogLTS -Scope CurrentUser) or check network access to the PowerShell Gallery, then try again."
    }
}
function Get-BaseWimBuild {
    # Mounts the OS ISO just long enough to read the base image's build number (Get-WindowsImage .Version), then
    # dismounts. Used to fill {build}/{version} in catalogSearch strings. Returns $null (logs a WARN) rather than
    # throwing when the build cannot be determined - the search still runs, just without that substitution.
    param([Parameter(Mandatory)][string]$IsoFolder, [Parameter(Mandatory)][pscustomobject]$Definition)
    $isoFiles = @(Get-ChildItem -LiteralPath $IsoFolder -Filter '*.iso' -File -ErrorAction SilentlyContinue)
    if ($isoFiles.Count -eq 0) { Write-Log "No ISO in $IsoFolder to read the base build from." 'WARN'; return $null }
    foreach ($f in $isoFiles) {
        try {
            $drive = Mount-IsoFile $f.FullName
            $wimPath = Join-Chain $drive @('sources', 'install.wim')
            if (-not (Test-Path -LiteralPath $wimPath)) { $wimPath = Join-Chain $drive @('sources', 'install.esd') }
            if (-not (Test-Path -LiteralPath $wimPath)) { continue }
            $idx = if ($Definition.ServiceAllIndexes) { 1 } elseif ($Definition.PreferredIndex -gt 0) { $Definition.PreferredIndex } else { 1 }
            $img = Get-WindowsImage -ImagePath $wimPath -Index $idx -ErrorAction Stop
            if ($img.Version) { return [string]$img.Version }
        } catch { Write-Log "Could not read the base build from $($f.Name): $($_.Exception.Message)" 'WARN' }
        finally { Dismount-AllIso }
    }
    return $null
}
function Resolve-CatalogSearch {
    # Substitutes {build} (and the {version} alias) in a catalogSearch.search string with the base image's build
    # number. Left as literal text when no build could be determined - still a usable (just less precise) search.
    param([string]$Search, [string]$Build)
    if (-not $Search) { return $Search }
    if ($Build) { return ($Search -replace '\{build\}', $Build -replace '\{version\}', $Build) }
    return $Search
}
function Get-ArchFromText {
    # Architecture named in a catalog title or a downloaded file name ('x64', 'x86', 'arm64'), or '' when none is.
    # Catalog titles: "... for x64-based Systems", "... for x64", "... for ARM64-based Systems"; file names:
    # "windows10.0-kb5126043-x64.msu". The combined .NET CU's x86 entry names no architecture in its title at all.
    param([string]$Text)
    if ($Text -match '(?i)(?<![a-z0-9])(arm64|aarch64)(?![a-z0-9])') { return 'arm64' }
    if ($Text -match '(?i)(?<![a-z0-9])(x64|amd64)(?![a-z0-9])') { return 'x64' }
    if ($Text -match '(?i)(?<![a-z0-9])(x86|i386)(?![a-z0-9])') { return 'x86' }
    return ''
}
function Test-ArchMatch {
    # $true when $Found (from Get-ArchFromText or a result property) satisfies the rule's architecture. amd64 = x64.
    param([string]$Wanted, [string]$Found)
    $norm = { param($a) switch -Regex ([string]$a) { '(?i)^(x64|amd64)$' { 'x64' } '(?i)^(arm64|aarch64)$' { 'arm64' } '(?i)^(x86|i386)$' { 'x86' } default { ([string]$a).ToLowerInvariant() } } }
    return ((& $norm $Wanted) -eq (& $norm $Found))
}
function Test-CatalogCandidate {
    # Filters one Get-MSCatalogUpdate result against a resolved catalogSearch rule. Reads whatever property names the
    # installed module version actually exposes (via Get-ProfileValue, which is name-tolerant) instead of assuming one.
    # Architecture: real MSCatalogLTS results have no Architecture property (confirmed on Terry's machine), and the
    # catalog search matches words loosely ("for x64" in the search still returns the x86 entry), so when the result
    # has no such property the title must name the wanted architecture - a title naming none is rejected too,
    # because that is exactly how the combined .NET CU's x86 entry looks. Set architecture to '' in the profile to
    # switch the check off for a product whose titles never name one.
    param([Parameter(Mandatory)]$Result, [Parameter(Mandatory)]$Rule)
    $title = [string](Get-ProfileValue $Result 'Title' '')
    $arch = [string](Get-ProfileValue $Result 'Architecture' (Get-ProfileValue $Result 'Arch' ''))
    if (-not $arch) { $arch = Get-ArchFromText $title }
    if ($Rule.architecture -and -not (Test-ArchMatch $Rule.architecture $arch)) { return $false }
    if ($Rule.excludePreview -and $title -match '(?i)preview') { return $false }
    if ($Rule.buildFilter -and $title -notmatch $Rule.buildFilter) { return $false }
    # Products (a string such as "Windows 10, Windows 10 LTSB", or a list): some classes can only be told apart here.
    # The 1809 Safe OS DU is titled plain "Dynamic Update for Windows 10 Version 1809 ..." - its Products entry
    # "Windows Safe OS Dynamic Update" is what marks it (Terry, 2026-09-23). Read by name so a rule object without
    # these keys still works under StrictMode.
    $productFilter = [string](Get-ProfileValue $Rule 'productFilter' '')
    $productExclude = [string](Get-ProfileValue $Rule 'productExclude' '')
    if ($productFilter -or $productExclude) {
        $products = (@(Get-ProfileValue $Result 'Products' '') | ForEach-Object { [string]$_ }) -join ', '
        if ($productFilter -and $products -notmatch $productFilter) { return $false }
        if ($productExclude -and $products -match $productExclude) { return $false }
    }
    return $true
}
function Get-CatalogDate {
    param($Result)
    $raw = Get-ProfileValue $Result 'LastUpdated' (Get-ProfileValue $Result 'Date' $null)
    if (-not $raw) { return [datetime]::MinValue }
    $dt = [datetime]::MinValue
    if ([datetime]::TryParse([string]$raw, [ref]$dt)) { return $dt }
    return [datetime]::MinValue
}
function Invoke-CatalogUpdateSearch {
    # Calls Get-MSCatalogUpdate, passing -ExcludePreview/-Architecture only when the installed module version actually
    # declares them (confirmed real parameters of the MSCatalogLTS/MSCatalog family, per its source on GitHub - but the
    # exact surface can still drift between module versions, so this checks rather than assumes). Test-CatalogCandidate
    # below still re-checks everything in PowerShell as a backstop, and is what applies buildFilter either way.
    # Checked against the installed MSCatalogLTS 2.1.0.1 on Terry's PC (2026-09-24), which differs from the upstream source:
    # - every title containing "Dynamic" is dropped unless -IncludeDynamic is passed (Safe OS / Setup DU found nothing);
    # - only the first page (25 rows) is read unless -AllPages is passed (the 1809 Setup DU is well past page 1);
    # - previews are left out unless -IncludePreview is passed; there is no -ExcludePreview;
    # - a search starting with "Dynamic Update for ..." (or another update-type phrase) is rewritten by the module's
    #   "smart search" into its own "Cumulative Update for <OS>" query, which can never return a Dynamic Update.
    #   A leading space stops that parser matching, so the search reaches the catalog as written (the catalog trims it).
    param([string]$Search, [pscustomobject]$Rule)
    $cmd = Get-Command Get-MSCatalogUpdate -ErrorAction Stop
    $params = @{ Search = ' ' + $Search.Trim() }
    if ($cmd.Parameters.ContainsKey('IncludeDynamic')) { $params['IncludeDynamic'] = $true }
    if ($cmd.Parameters.ContainsKey('AllPages')) { $params['AllPages'] = $true }
    if ($Rule.excludePreview -and $cmd.Parameters.ContainsKey('ExcludePreview')) { $params['ExcludePreview'] = $true }
    if (-not $Rule.excludePreview -and $cmd.Parameters.ContainsKey('IncludePreview')) { $params['IncludePreview'] = $true }
    if ($Rule.architecture -and $cmd.Parameters.ContainsKey('Architecture')) { $params['Architecture'] = $Rule.architecture }
    return @(Get-MSCatalogUpdate @params -ErrorAction Stop)
}
function Search-CatalogCandidates {
    # Runs one catalogSearch rule through Get-MSCatalogUpdate, filters and sorts newest-first. Returns @() (with a
    # logged WARN) when nothing matches after filtering; a search/module failure still throws to the caller.
    param([Parameter(Mandatory)][pscustomobject]$Rule, [string]$Build)
    $search = Resolve-CatalogSearch -Search $Rule.search -Build $Build
    if (-not $search) { return @() }
    Write-Log "Catalog search: $search"
    $raw = @(Invoke-CatalogUpdateSearch -Search $search -Rule $Rule)
    $filtered = @($raw | Where-Object { Test-CatalogCandidate -Result $_ -Rule $Rule })
    if ($filtered.Count -eq 0) { Write-Log "No catalog results matched for '$search' after filtering ($($raw.Count) raw result(s))." 'WARN'; return @() }
    return @($filtered | Sort-Object { Get-CatalogDate $_ } -Descending)
}
function Save-CatalogCandidate {
    # Downloads one catalog result into $Destination via Save-MSCatalogUpdate and returns the full path of EVERY file
    # it produced. One catalog entry can carry several files: the combined .NET CU for 1809 ("3.5, 4.7.2 and 4.8",
    # KB5126144) downloads windows10.0-kb5126043-x64.msu (3.5/4.7.2) and windows10.0-kb5126048-x64-ndp48.msu (4.8),
    # each named after its own component KB, not the entry's KB. The real cmdlet names files from the download URL,
    # so no renaming is needed. -DownloadAll / -AcceptMultiFileUpdates / -Confirm are passed only when the installed
    # module declares them (-DownloadAll confirmed on Terry's machine); without them a multi-file entry would need
    # interactive input, which a background run can never provide. Returns $null when no new or re-written file
    # appeared; the caller then logs a WARN and leaves the folder unpruned rather than guessing which file is current.
    param([Parameter(Mandatory)]$Result, [Parameter(Mandatory)][string]$Destination)
    Ensure-Directory $Destination
    $before = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath $Destination -File -ErrorAction SilentlyContinue)) { $before[$f.Name] = $f.LastWriteTimeUtc }
    $cmd = Get-Command Save-MSCatalogUpdate -ErrorAction Stop
    $params = @{ Update = $Result; Destination = $Destination }
    if ($cmd.Parameters.ContainsKey('DownloadAll')) { $params['DownloadAll'] = $true }
    if ($cmd.Parameters.ContainsKey('AcceptMultiFileUpdates')) { $params['AcceptMultiFileUpdates'] = $true }
    if ($cmd.Parameters.ContainsKey('Confirm')) { $params['Confirm'] = $false }
    # MSCatalogLTS 2.1.0.1 skips a file that already exists unless -Force is passed. A skipped file is neither new nor
    # re-written, so it would not be recognised as this run's download and the pruning below would delete it (Terry's
    # Win11 24H2 run 2026-09-24 deleted the LCU it had just picked). Re-downloading is the price of always knowing.
    if ($cmd.Parameters.ContainsKey('Force')) { $params['Force'] = $true }
    Save-MSCatalogUpdate @params -ErrorAction Stop | Out-Null
    $after = @(Get-ChildItem -LiteralPath $Destination -File -ErrorAction SilentlyContinue)
    # New or re-written (same name, newer timestamp) files are this download's output.
    $new = @($after | Where-Object { -not $before.ContainsKey($_.Name) -or $_.LastWriteTimeUtc -gt $before[$_.Name] } | Sort-Object Name)
    if ($new.Count -gt 0) { return @($new | ForEach-Object { $_.FullName }) }
    return $null
}
function Update-PatchCache {
    # Prunes a PATCHES\<class> folder after a download: keeps $NewestFile and/or every file in $KeepFiles, plus any
    # .cab/.msu whose KB is in $KeepChain (the checkpoint chain), removes everything else superseded. $NewestFile
    # stays as the single-file form (most classes only ever download one file per run); $KeepFiles is for a class
    # with more than one search term - e.g. .NET CU on Windows 10 1809, which needs both its "3.5 and 4.7.2" and
    # "3.5 and 4.8" downloads kept side by side, not pruned down to just the newest of the two. Never called for the
    # SSU folder.
    # Safety net: $KeepKbs are the KBs picked in this run. A file with one of those KBs is never removed unless this run
    # also saved a file with the same KB (then the older copy, e.g. the long "_<hash>" name, is a true duplicate).
    param([Parameter(Mandatory)][string]$Folder, [string]$NewestFile = '', [string[]]$KeepFiles = @(), [string[]]$KeepChain = @(), [string[]]$KeepKbs = @())
    if (-not (Test-Path -LiteralPath $Folder)) { return @() }
    $keepNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($NewestFile) { [void]$keepNames.Add([System.IO.Path]::GetFileName($NewestFile)) }
    foreach ($kf in $KeepFiles) { if ($kf) { [void]$keepNames.Add([System.IO.Path]::GetFileName($kf)) } }
    $savedKbs = @($keepNames | ForEach-Object { Get-KbFromName $_ } | Where-Object { $_ })
    $pickedKbs = @($KeepKbs | Where-Object { $_ } | ForEach-Object { ([string]$_).ToUpperInvariant() })
    $removed = @()
    $exts = @('.cab', '.msu')
    foreach ($f in @(Get-ChildItem -LiteralPath $Folder -File -ErrorAction SilentlyContinue | Where-Object { $exts -contains $_.Extension.ToLowerInvariant() })) {
        if ($keepNames.Contains($f.Name)) { continue }
        $kb = Get-KbFromName $f.Name
        if ($kb -and ($KeepChain -contains $kb)) { continue }
        if ($kb -and ($pickedKbs -contains $kb) -and ($savedKbs -notcontains $kb)) {
            Write-Log "Kept $($f.Name) in $Folder - it is $kb, picked in this run, although this run did not re-write it." 'WARN'
            continue
        }
        try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $removed += $f.Name; Write-Log "Removed superseded file $($f.Name) from $Folder" }
        catch { Write-Log "Could not remove superseded file $($f.Name): $($_.Exception.Message)" 'WARN' }
    }
    return $removed
}
# ---------- "download only what is missing" (TODO step 14, Terry 2026-09-27) ----------
# Each PATCHES\<class> folder keeps _downloads.json: for every catalog entry downloaded there (by its Guid), the files it
# produced and their sizes. A pick is "already present" when every one of those files is still there at that size (an
# interrupted or replaced file counts as missing), or - when the catalog result lists its file names - when all of them
# are there. Without either, a pick is downloaded (once; from then on the record knows it). The record matters because
# one catalog entry can produce several files named after other KBs (1809 .NET CU; Win11 LCU + checkpoint).
$script:DownloadRecordName = '_downloads.json'
function Get-CatalogEntryKey {
    param($Result)
    $g = [string](Get-ProfileValue $Result 'Guid' '')
    if ($g) { return $g.ToLowerInvariant() }
    return ('title:' + [string](Get-ProfileValue $Result 'Title' ''))
}
function Read-DownloadRecord {
    param([string]$Folder)
    $table = @{}
    $file = [System.IO.Path]::Combine($Folder, $script:DownloadRecordName)
    if (-not (Test-Path -LiteralPath $file)) { return $table }
    try {
        $o = [System.IO.File]::ReadAllText($file) | ConvertFrom-Json -ErrorAction Stop
        foreach ($e in @(Get-ProfileValue $o 'entries' @())) {
            $k = [string](Get-ProfileValue $e 'key' ''); if (-not $k) { continue }
            $table[$k] = [pscustomobject]@{ Key = $k; Kb = [string](Get-ProfileValue $e 'kb' ''); Title = [string](Get-ProfileValue $e 'title' ''); Downloaded = [string](Get-ProfileValue $e 'downloaded' '')
                Files = @(@(Get-ProfileValue $e 'files' @()) | ForEach-Object { [pscustomobject]@{ Name = [string](Get-ProfileValue $_ 'name' ''); Size = [string](Get-ProfileValue $_ 'size' '') } } | Where-Object { $_.Name }) }
        }
    } catch { Write-Log "Download record $file could not be used ($($_.Exception.Message)); its patches are downloaded again." 'WARN' }
    return $table
}
function Save-DownloadRecord {
    # Writes the record, dropping entries whose files are no longer in the folder (pruned or deleted by hand).
    param([string]$Folder, [hashtable]$Record)
    if (-not (Test-Path -LiteralPath $Folder)) { return }
    $keep = @($Record.Values | Where-Object { $e = $_; @($e.Files).Count -gt 0 -and @($e.Files | Where-Object { -not (Test-Path -LiteralPath ([System.IO.Path]::Combine($Folder, $_.Name))) }).Count -eq 0 } | Sort-Object Key)
    $data = [ordered]@{ schemaVersion = 1; note = 'Written by WimForge Download patches: which files each catalog entry produced, so a repeat download can skip them.'
        entries = @($keep | ForEach-Object { [ordered]@{ key = $_.Key; kb = $_.Kb; title = $_.Title; downloaded = $_.Downloaded; files = @($_.Files | ForEach-Object { [ordered]@{ name = $_.Name; size = $_.Size } }) } }) }
    [System.IO.File]::WriteAllText([System.IO.Path]::Combine($Folder, $script:DownloadRecordName), (($data | ConvertTo-Json -Depth 5) + [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))
}
function Get-CatalogResultFileNames {
    # The file names a catalog result says it downloads, as Save-MSCatalogUpdate names them (URL leaf without the
    # "_<hash>" part). Real MSCatalogLTS 2.1.0.1 results leave FileNames empty; then this returns nothing.
    param($Result)
    $raw = @(Get-ProfileValue $Result 'FileNames' @()) | ForEach-Object { [string]$_ -split '[,;\s]+' } | Where-Object { $_ }
    return @($raw | ForEach-Object {
        $leaf = ($_ -split '[/\\]')[-1]
        $leaf -replace '_[0-9a-fA-F]{16,}(?=\.[A-Za-z0-9]+$)', ''
    } | Where-Object { $_ -match '\.(msu|cab)$' } | Select-Object -Unique)
}
function Get-PresentCatalogFiles {
    # The full paths of a picked catalog entry's files when they are ALL already in $Folder; otherwise @().
    param($Result, [Parameter(Mandatory)][string]$Folder, [hashtable]$Record = @{})
    $key = Get-CatalogEntryKey $Result
    if ($Record.ContainsKey($key)) {
        $files = @($Record[$key].Files)
        $ok = $files.Count -gt 0
        foreach ($f in $files) {
            $p = [System.IO.Path]::Combine($Folder, $f.Name)
            if (-not (Test-Path -LiteralPath $p) -or ([string](Get-Item -LiteralPath $p).Length -ne $f.Size)) { $ok = $false; break }
        }
        if ($ok) { return @($files | ForEach-Object { [System.IO.Path]::Combine($Folder, $_.Name) }) }
        return @()
    }
    $names = @(Get-CatalogResultFileNames $Result)
    if ($names.Count -gt 0) {
        $paths = @($names | ForEach-Object { [System.IO.Path]::Combine($Folder, $_) })
        if (@($paths | Where-Object { -not (Test-Path -LiteralPath $_) -or (Get-Item -LiteralPath $_).Length -eq 0 }).Count -eq 0) { return $paths }
    }
    return @()
}
function Invoke-PatchAcquisition {
    # Entry point for the "Download patches..." action. $Options.DryRun=$true only searches and reports what WOULD be
    # downloaded/kept/removed - nothing is written or deleted. See TODO.md step 5 for the open points (checkpoint-CU
    # chain discovery is profile-supplied, not derived automatically; catalog search strings need spot-checking).
    param([Parameter(Mandatory)][pscustomobject]$Options, [Parameter(Mandatory)][pscustomobject]$Definition, [Parameter(Mandatory)][hashtable]$Paths)
    $dryRun = [bool](Get-ProfileValue $Options 'DryRun' $false)
    Set-Phase -OsName $Definition.Name -Phase $(if ($dryRun) { 'Checking for updates (dry run)' } else { 'Acquiring patches' })
    Write-Log "Starting patch acquisition for $($Definition.Name)$(if ($dryRun) { ' (dry run - nothing will be downloaded or removed)' } else { '' })"
    if (-not $Definition.CatalogSearch -or $Definition.CatalogSearch.Count -eq 0) {
        throw "This profile has no 'catalogSearch' rules yet (see $($Definition.SourceFile)). Add search rules for at least one package class, or fill PATCHES manually."
    }
    Set-Progress 2 'Preparing the catalog module'
    Ensure-CatalogModule

    Set-Progress 5 'Reading the base image build'
    $build = Get-BaseWimBuild -IsoFolder $Paths.ISO -Definition $Definition
    if ($build) { Write-Log "Base image build: $build" } else { Write-Log 'Base image build could not be determined; catalog searches with {build} will use the literal placeholder text.' 'WARN' }

    $classes = @('LCU', 'NetCU', 'SafeOS', 'SetupDU')   # SSU is deliberately excluded - always manual
    $wanted = @{ LCU = [bool]$Options.LCU; NetCU = [bool]$Options.NetCU; SafeOS = [bool]$Options.SafeOS; SetupDU = [bool]$Options.SetupDU }
    $folders = [ordered]@{ LCU = 'LCU'; NetCU = 'NETCU'; SafeOS = 'SAFEOSDU'; SetupDU = 'SETUPDU' }
    $plan = [System.Collections.Generic.List[object]]::new()
    $downloaded = [System.Collections.Generic.List[object]]::new()
    $removed = [System.Collections.Generic.List[object]]::new()
    $alreadyPresent = [System.Collections.Generic.List[object]]::new()
    $skippedClasses = [System.Collections.Generic.List[string]]::new()
    $removedNow = @()
    $n = 0
    foreach ($class in $classes) {
        $n++
        Set-Progress ([int](10 + ($n / $classes.Count) * 80)) "Checking $class"
        if (-not $wanted[$class]) { continue }
        $rule = Get-ProfileValue $Definition.CatalogSearch $class $null
        if (-not $rule -or -not (Get-ProfileValue $rule 'search' '')) { $skippedClasses.Add("$class (no catalogSearch rule in the profile)"); continue }
        Assert-NotCancelled
        $searchTerms = @(@(Get-ProfileValue $rule 'searches' @()) | Where-Object { $_ })
        if ($searchTerms.Count -eq 0) { $single = [string](Get-ProfileValue $rule 'search' ''); if ($single) { $searchTerms = @($single) } }
        $ruleArch = [string](Get-ProfileValue $rule 'architecture' 'x64')
        $ruleExcludePreview = [bool](Get-ProfileValue $rule 'excludePreview' $true)
        $ruleBuildFilter = [string](Get-ProfileValue $rule 'buildFilter' '')
        $ruleProductFilter = [string](Get-ProfileValue $rule 'productFilter' '')
        $ruleProductExclude = [string](Get-ProfileValue $rule 'productExclude' '')
        $chainKbs = @(@(Get-ProfileValue $rule 'checkpointKBs' @()) | Where-Object { $_ } | ForEach-Object { ([string]$_).ToUpperInvariant() })
        if ($chainKbs.Count -gt 0) {
            Write-Log "$class checkpoint chain from the profile: $($chainKbs -join ', ') - kept alongside the downloaded file(s) when already present, not fetched separately (open point, TODO.md step 5)." 'INFO'
        }
        # Most classes have exactly one search term. A class with several (e.g. NetCU on Windows 10 1809, which needs
        # both its "3.5 and 4.7.2" and "3.5 and 4.8" updates) searches and downloads each term independently, and all
        # of this run's downloads for the class are kept together when pruning - not just the single newest.
        $classFilesKept = [System.Collections.Generic.List[string]]::new()
        $classPickedKbs = [System.Collections.Generic.List[string]]::new()
        $folder = Join-Path $Paths.Patches $folders[$class]
        $record = Read-DownloadRecord -Folder $folder
        $recordChanged = $false; $removedNow = @()
        foreach ($term in $searchTerms) {
            Assert-NotCancelled
            $ruleObj = [pscustomobject]@{ search = $term; architecture = $ruleArch; excludePreview = $ruleExcludePreview; buildFilter = $ruleBuildFilter; productFilter = $ruleProductFilter; productExclude = $ruleProductExclude }
            # @() is required: a function returning an empty array hands the caller $null, and on Windows PowerShell 5.1 a
            # single result comes back as a bare object - under StrictMode .Count on either throws (seen on Terry's first
            # real dry run, LTSC 2019, when the Safe OS DU search returned nothing).
            try { $candidates = @(Search-CatalogCandidates -Rule $ruleObj -Build $build) }
            catch { Write-Log "Catalog search failed for $class ('$term'): $($_.Exception.Message)" 'ERROR'; $skippedClasses.Add("$class (search failed for '$term': $($_.Exception.Message))"); continue }
            if ($candidates.Count -eq 0) { $skippedClasses.Add("$class (no catalog result matched '$term')"); continue }
            $best = $candidates[0]
            $title = [string](Get-ProfileValue $best 'Title' '(untitled catalog result)')
            $kb = Get-KbFromName $title
            $released = Get-CatalogDate $best; $classification = [string](Get-ProfileValue $best 'Classification' '')
            $present = @(Get-PresentCatalogFiles -Result $best -Folder $folder -Record $record)
            $plan.Add([pscustomobject]@{ Class = $class; Title = $title; Kb = $kb; Date = $released; Classification = $classification; Present = ($present.Count -gt 0); Folder = $folders[$class] })
            if ($kb) { $classPickedKbs.Add($kb) }
            Write-Log "$class`: selected '$(Format-CatalogPick -Title $title -Kb $kb -Date $released -Classification $classification -Release:($class -eq 'LCU'))'$(if ($searchTerms.Count -gt 1) { " [search: $term]" })"
            if ($present.Count -gt 0) { Write-Log "$class`: already in PATCHES\$($folders[$class]) ($(($present | ForEach-Object { Split-Path $_ -Leaf }) -join ', ')); not downloaded again." }
            elseif (-not $dryRun) { Write-Log "$class`: not in PATCHES\$($folders[$class]) yet; downloading." }
            if ($dryRun) { continue }
            if ($present.Count -gt 0) {
                # Step 14: nothing to fetch. Its files stay (the pruning below keeps them) and nothing is recorded as a download.
                foreach ($p in $present) { $classFilesKept.Add($p); $alreadyPresent.Add([pscustomobject]@{ Class = $class; File = $p; EntryKb = $kb }) }
                continue
            }

            $entryFiles = [System.Collections.Generic.List[object]]::new()
            $savedFiles = @(Save-CatalogCandidate -Result $best -Destination $folder | Where-Object { $_ })
            if ($savedFiles.Count -eq 0) { Write-Log "$class`: download reported success but no file could be located in $folder (search '$term')." 'WARN'; continue }
            if ($savedFiles.Count -gt 1) { Write-Log "$class`: catalog entry$(if ($kb) { " $kb" }) downloaded $($savedFiles.Count) files: $(($savedFiles | ForEach-Object { Split-Path $_ -Leaf }) -join ', ')" }
            foreach ($saved in $savedFiles) {
                $leaf = Split-Path $saved -Leaf
                # Backstop for the title check: never keep a file whose name says it is for another architecture.
                $fileArch = Get-ArchFromText $leaf
                if ($ruleArch -and $fileArch -and -not (Test-ArchMatch $ruleArch $fileArch)) {
                    Write-Log "$class`: removing $leaf - its name says $fileArch but the profile asks for $ruleArch." 'WARN'
                    Remove-Item -LiteralPath $saved -Force -ErrorAction SilentlyContinue
                    continue
                }
                $fileKb = Get-KbFromName $leaf
                $detail = if ($kb -and $fileKb -and $fileKb -ne $kb) { "downloaded by acquisition layer (part of catalog entry $kb)" } else { 'downloaded by acquisition layer' }
                Add-ChangeEvent -Category $class -Item $leaf -Target $folder -Kb $(if ($fileKb) { $fileKb } else { $kb }) -Detail $detail
                $downloaded.Add([pscustomobject]@{ Class = $class; File = $saved; Kb = $(if ($fileKb) { $fileKb } else { $kb }); EntryKb = $kb })
                $classFilesKept.Add($saved)
                $savedSize = (Get-Item -LiteralPath $saved).Length
                $entryFiles.Add([pscustomobject]@{ Name = $leaf; Size = [string]$savedSize })
                # Every file is named in the log (Terry, 2026-09-28: single-file entries used to leave no trace of their file).
                Write-Log ("{0}: downloaded {1} ({2:N1} MB) to PATCHES\{3}" -f $class, $leaf, ($savedSize / 1MB), $folders[$class])
            }
            # Remember what this entry produced, so the next Download patches can skip it (step 14).
            if ($entryFiles.Count -gt 0) {
                $record[(Get-CatalogEntryKey $best)] = [pscustomobject]@{ Key = (Get-CatalogEntryKey $best); Kb = $kb; Title = $title; Downloaded = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Files = @($entryFiles) }
                $recordChanged = $true
            }
        }
        if (-not $dryRun -and $classFilesKept.Count -gt 0) {
            $removedNow = Update-PatchCache -Folder $folder -KeepFiles @($classFilesKept) -KeepChain $chainKbs -KeepKbs @($classPickedKbs)
            foreach ($r in $removedNow) { $removed.Add([pscustomobject]@{ Class = $class; File = $r }) }
        }
        if (-not $dryRun -and ($recordChanged -or @($removedNow).Count -gt 0)) {
            try { Save-DownloadRecord -Folder $folder -Record $record } catch { Write-Log "The download record in $folder could not be written: $($_.Exception.Message)" 'WARN' }
        }
    }
    foreach ($s in $skippedClasses) { Write-Log "Skipped $s" 'WARN' }
    if ($plan.Count -gt 0 -and @($plan | Where-Object { -not $_.Present }).Count -eq 0) { Write-Log 'PATCHES is up to date: every detected patch is already in its folder, so nothing was downloaded.' }
    elseif (-not $dryRun) { Write-Log "Download patches: $($downloaded.Count) file(s) downloaded, $($alreadyPresent.Count) already present." }
    Set-Progress 95 'Acquisition done'
    Set-Phase 'Done'
    return [pscustomobject]@{
        Mode = 'Download'; DryRun = $dryRun; OsName = $Definition.Name; Plan = @($plan)
        Downloaded = @($downloaded); Removed = @($removed); SkippedClasses = @($skippedClasses); AlreadyPresent = @($alreadyPresent)
        UpToDate = [bool]($plan.Count -gt 0 -and @($plan | Where-Object { -not $_.Present }).Count -eq 0)
        NewWim = ''; Preflight = $false; VerifyIssues = $null; Gate = $null
    }
}

# ---------- packages ----------
function Get-PackageFiles {
    # $Order: optional wildcard file-name patterns from the profile's packageOrder. Matches are applied in pattern order,
    # everything else follows in name order.
    param([string]$Path, [string[]]$Extensions = @('.cab', '.msu'), [string[]]$Order = @())
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $files = @(Get-ChildItem -LiteralPath $Path -File -Recurse | Where-Object { $Extensions -contains $_.Extension.ToLowerInvariant() })
    $pats = @($Order | Where-Object { $_ })
    if ($pats.Count -eq 0) { return @($files | Sort-Object FullName) }
    foreach ($pat in $pats) {
        if (@($files | Where-Object { $_.Name -like $pat }).Count -eq 0) { Write-Log "Order manifest pattern '$pat' matched no file in $Path." 'WARN' }
    }
    return @($files | Sort-Object -Property @{ Expression = { $n = $_.Name; $r = $pats.Count; for ($i = 0; $i -lt $pats.Count; $i++) { if ($n -like $pats[$i]) { $r = $i; break } }; $r } }, FullName)
}
function Get-PackageSet {
    param([string]$PatchRoot, [hashtable]$Enabled, [hashtable]$Order = @{})
    $folders = [ordered]@{ LCU = 'LCU'; SSU = 'SSU'; NetCU = 'NETCU'; SafeOS = 'SAFEOSDU'; SetupDU = 'SETUPDU' }
    $set = @{}
    foreach ($k in $folders.Keys) {
        $ext = if ($k -eq 'SetupDU') { @('.cab') } else { @('.cab', '.msu') }
        $set[$k] = @( if ($Enabled[$k]) { Get-PackageFiles -Path (Join-Path $PatchRoot $folders[$k]) -Extensions $ext -Order @($Order[$k]) } )
    }
    $lcu = Resolve-LcuTarget -Files $set.LCU
    $set.LCU = $lcu.Install; $set.LcuCheckpoints = $lcu.Checkpoints
    return $set
}
function Resolve-LcuTarget {
    # Checkpoint cumulative updates (Win11 24H2+, Server 2025): Microsoft's method for offline media is to put the target
    # LCU and every earlier checkpoint .msu in one folder and add ONLY the target; DISM finds and installs the checkpoints
    # the image still needs (learn.microsoft.com "Checkpoint cumulative updates and the Microsoft Update Catalog").
    # Adding a checkpoint directly is never needed and may fail on an image already past it. So when PATCHES\LCU holds
    # more than one .msu, the one with the highest KB number is the target and the rest stay in the folder, uninstalled.
    # One file (every Win10 / Server 2022 profile) or no KB numbers to go by: unchanged, everything is installed.
    param([object[]]$Files)
    $all = @($Files | Where-Object { $_ })
    $msu = @($all | Where-Object { $_.Extension -ieq '.msu' -and (Get-KbFromName $_.Name) })
    if ($all.Count -le 1 -or $msu.Count -eq 0) { return @{ Install = $all; Checkpoints = @() } }
    $target = $msu | Sort-Object { [int64]((Get-KbFromName $_.Name) -replace '\D', '') } -Descending | Select-Object -First 1
    return @{ Install = @($target); Checkpoints = @($all | Where-Object { $_.FullName -ne $target.FullName }) }
}
function Test-PackageSet {
    param([pscustomobject]$Definition, [hashtable]$Packages, [hashtable]$Enabled, [bool]$DoWinRe, [bool]$BuildMedia)
    foreach ($k in @('SSU', 'LCU', 'NetCU', 'SafeOS', 'SetupDU')) {
        $state = if ($Enabled[$k]) { 'selected' } else { 'not selected' }
        Write-Log "$k packages: $(@($Packages[$k]).Count) ($state)"
        if (@($Packages[$k]).Count -gt 1) { Write-Log "$k order: $((@($Packages[$k]) | ForEach-Object { $_.Name }) -join ' -> ')" }
    }
    if ($Enabled.LCU -and @($Packages.LCU).Count -eq 0) { throw 'Latest Cumulative Update is selected but PATCHES\LCU is empty. Add the LCU or untick it.' }
    $cps = @($Packages['LcuCheckpoints'] | Where-Object { $_ })
    if ($Enabled.LCU -and $cps.Count -gt 0) {
        $target = @($Packages.LCU)[0]
        Write-Log "LCU: only $($target.Name) is installed; $(($cps | ForEach-Object { $_.Name }) -join ', ') stay in the folder for DISM to apply as checkpoint(s) where the image needs them. PATCHES\LCU must hold only this LCU and its checkpoints."
        foreach ($cp in $cps) {
            if ($cp.DirectoryName -ne $target.DirectoryName) { Write-Log "LCU checkpoint $($cp.Name) is not in the same folder as $($target.Name); DISM only looks beside the target. Move it next to the target." 'WARN' }
        }
    }
    if ($Enabled.SSU -and $Definition.SsuRequired -and @($Packages.SSU).Count -eq 0) { throw 'This OS needs its servicing stack update in PATCHES\SSU. Add it or untick Servicing Stack Update.' }
    if ($DoWinRe -and $Enabled.SafeOS -and @($Packages.SafeOS).Count -eq 0) { Write-Log 'WinRE servicing is on but PATCHES\SAFEOSDU is empty; WinRE will not get the Safe OS update.' 'WARN' }
    if ($BuildMedia -and $Enabled.SetupDU -and @($Packages.SetupDU).Count -eq 0) { Write-Log 'Refreshed media is requested but PATCHES\SETUPDU is empty; Setup files will not be updated.' 'WARN' }
}
function Get-PackageFingerprint {
    # One string for the mounted image's packages and their states, to tell whether an Add-WindowsPackage changed anything.
    param([string]$MountPath)
    return ((@(Get-WindowsPackage -Path $MountPath -ErrorAction Stop) | ForEach-Object { "$($_.PackageName)|$($_.PackageState)" } | Sort-Object) -join "`n")
}
function Add-Packages {
    param(
        [Parameter(Mandatory)][string]$MountPath,
        [AllowNull()][object[]]$Packages,
        [Parameter(Mandatory)][string]$Target,
        [string]$Label = 'package',
        [switch]$IgnoreCombinedLcu7007e,
        [switch]$SkipNotApplicable
    )
    $dl = $script:DismLogArgs
    $list = @($Packages | Where-Object { $_ })
    if ($list.Count -eq 0) { Write-Log "No $Label packages to add to $Target (skipped)."; return }
    foreach ($pkg in $list) {
        Assert-NotCancelled
        Write-Log "Adding $Label $($pkg.FullName) to $Target"
        try {
            # For a .MSU, DISM can decide "not applicable" (0x800f081e) internally and still return success - Terry's
            # LTSC 2019 run (2026-09-25) logged the .NET 4.8 part as added although DISM skipped it. So where skipping is
            # allowed, the image's package list is compared before and after: no change means nothing was installed.
            $before = if ($SkipNotApplicable) { Get-PackageFingerprint $MountPath } else { $null }
            Add-WindowsPackage -Path $MountPath -PackagePath $pkg.FullName @dl -ErrorAction Stop | Out-Null
            $pkgName = Split-Path $pkg.FullName -Leaf
            if ($null -ne $before -and (Get-PackageFingerprint $MountPath) -eq $before) {
                Write-Log "Skipped $Label ${pkgName}: DISM found it not applicable to $Target and installed nothing (the image's package list is unchanged)." 'WARN'
                Add-ChangeEvent -Category (Get-EventCategory $Label) -Item $pkgName -Target $Target -Kb (Get-KbFromName $pkgName) -Detail "$Label - skipped, not applicable to this image"
                continue
            }
            Add-ChangeEvent -Category (Get-EventCategory $Label) -Item $pkgName -Target $Target -Kb (Get-KbFromName $pkgName) -Detail $Label
        }
        catch {
            if ($IgnoreCombinedLcu7007e -and $_.Exception.Message -match '0x8007007e') {
                Write-Log 'Known combined-LCU error 0x8007007e encountered; continuing.' 'WARN'
            } elseif ($SkipNotApplicable -and $_.Exception.Message -match '(?i)0x800f081e|not applicable') {
                # CBS_E_NOT_APPLICABLE: e.g. the .NET 4.8 part of a combined .NET CU on an image that only has 4.7.2.
                Write-Log "Skipped $Label $(Split-Path $pkg.FullName -Leaf): not applicable to $Target (0x800f081e)." 'WARN'
                Add-ChangeEvent -Category (Get-EventCategory $Label) -Item (Split-Path $pkg.FullName -Leaf) -Target $Target -Kb (Get-KbFromName $pkg.FullName) -Detail "$Label - skipped, not applicable to this image"
            } else { throw }
        }
    }
}

# ---------- ISO handling ----------
function Mount-IsoFile {
    param([string]$ImagePath)
    Write-Log "Mounting ISO $ImagePath"
    $disk = Mount-DiskImage -ImagePath $ImagePath -PassThru -ErrorAction Stop
    $script:MountedIsoPaths.Add($ImagePath)
    $volume = $disk | Get-Volume | Where-Object DriveLetter | Select-Object -First 1
    if (-not $volume) { throw "Mounted ISO has no drive letter: $ImagePath" }
    return ($volume.DriveLetter + ':\')
}
function Dismount-AllIso {
    foreach ($path in @($script:MountedIsoPaths)) {
        try { Dismount-DiskImage -ImagePath $path -ErrorAction Stop | Out-Null; Write-Log "Dismounted ISO $path" }
        catch { Write-Log "Could not dismount ISO ${path}: $($_.Exception.Message)" 'WARN' }
    }
    $script:MountedIsoPaths.Clear()
}
function Get-IsoRoleMap {
    # $Mounted: objects with .Path (ISO file) and .Drive (mounted root). Roles come from CONTENT, not file names.
    param([object[]]$Mounted)
    $os = @(); $lp = @(); $fod = @(); $unknown = @()
    foreach ($m in @($Mounted)) {
        $root = $m.Drive
        $isOs = (Test-Path -LiteralPath (Join-Chain $root @('sources', 'install.wim'))) -or (Test-Path -LiteralPath (Join-Chain $root @('sources', 'install.esd')))
        $isLp = $false; $isFod = $false
        if (-not $isOs) {
            $isLp = [bool](Get-ChildItem -LiteralPath $root -Filter 'Microsoft-Windows-*-Language-Pack_x64_*.cab' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
            # A FOD ISO without language features (1809 "FOD part 2") still carries DISM's FOD catalogue (metadata\*CompDB*)
            # and package-identity cabs (..~31bf3856ad364e35~..); it is then an extra capability source, not "unrecognised".
            $isFod = (Test-Path -LiteralPath (Join-Path $root 'LanguagesAndOptionalFeatures')) -or
                     [bool](Get-ChildItem -LiteralPath $root -Filter 'Microsoft-Windows-LanguageFeatures-*.cab' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1) -or
                     [bool](Get-ChildItem -LiteralPath (Join-Path $root 'metadata') -Filter '*CompDB*' -File -ErrorAction SilentlyContinue | Select-Object -First 1) -or
                     [bool](Get-ChildItem -LiteralPath $root -Filter '*~31bf3856ad364e35~*.cab' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
        }
        if ($isOs)  { $os  += $m }
        if ($isLp)  { $lp  += $m }
        if ($isFod) { $fod += $m }
        if (-not ($isOs -or $isLp -or $isFod)) { $unknown += $m }
    }
    if ($os.Count -ne 1) { throw "Expected exactly one OS ISO (one containing sources\install.wim or install.esd); found $($os.Count)." }
    if ($lp.Count -gt 1) {
        # An ISO that carries language packs AND FODs is only chosen as the LP source when no LP-only ISO exists.
        $lpOnly = @($lp | Where-Object { $fod -notcontains $_ })
        if ($lpOnly.Count -eq 1) { $lp = @($lpOnly[0]) }
        else { throw "More than one Language Pack ISO found: $((@($lp | ForEach-Object { Split-Path $_.Path -Leaf })) -join ', '). Keep only one." }
    }
    $fodDrives = @($fod | ForEach-Object { $_.Drive })
    return [pscustomobject]@{
        OsDrive      = $os[0].Drive
        LpDrive      = $(if ($lp.Count) { $lp[0].Drive } else { $null })
        FodDrives    = $fodDrives
        FodDrive     = $(if ($fodDrives.Count) { $fodDrives[0] } else { $null })
        Unclassified = @($unknown | ForEach-Object { $_.Path })
    }
}
function Get-FodSource {
    # Returns one capability source folder per FOD-bearing ISO (DISM searches all of them).
    param([string[]]$FodDrives)
    $out = @()
    foreach ($d in @($FodDrives | Where-Object { $_ })) {
        $candidate = Join-Path $d 'LanguagesAndOptionalFeatures'
        if (Test-Path -LiteralPath $candidate) { $out += $candidate } else { $out += $d }
    }
    return $out
}
function Resolve-LanguagePacks {
    # Finds every requested language pack cab BEFORE any image is mounted. Throws if any are missing.
    param([string]$LpRoot, [string]$Pattern, [string[]]$Languages = @())
    $byName = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath $LpRoot -Filter '*Language-Pack_x64_*.cab' -File -Recurse -ErrorAction SilentlyContinue)) {
        $byName[$f.Name.ToLowerInvariant()] = $f.FullName
    }
    $found = @{}; $missing = @()
    foreach ($lang in @($Languages)) {
        $key = ($Pattern -f $lang).ToLowerInvariant()
        if ($byName.ContainsKey($key)) { $found[$lang] = $byName[$key] } else { $missing += $lang }
    }
    if ($missing.Count -gt 0) { throw "Language pack cab not found for: $($missing -join ', ') (looked for $($Pattern -f '<lang>') in $LpRoot). Check that the correct Language Pack ISO is in the ISO folder." }
    return $found
}

# ---------- languages ----------
function Add-OfflineLanguages {
    param([string]$MountPath, [hashtable]$LpFiles, [string[]]$FodSource = @(), [string[]]$Languages = @(), [string]$Target)
    $dl = $script:DismLogArgs
    if (@($Languages).Count -eq 0) { return }
    $fontsDone = @{}
    foreach ($lang in @($Languages)) {
        Assert-NotCancelled
        Add-Packages $MountPath @([pscustomobject]@{ FullName = $LpFiles[$lang] }) $Target -Label "language pack $lang"
        if (@($FodSource).Count -eq 0) { continue }
        $caps = @("Language.Basic~~~$lang~0.0.1.0", "Language.OCR~~~$lang~0.0.1.0", "Language.Handwriting~~~$lang~0.0.1.0",
                  "Language.TextToSpeech~~~$lang~0.0.1.0", "Language.Speech~~~$lang~0.0.1.0")
        if ($script:LangFontScripts.ContainsKey($lang)) {
            $fs = $script:LangFontScripts[$lang]
            if (-not $fontsDone.ContainsKey($fs)) { $caps = @("Language.Fonts.$fs~~~und-$($fs.ToUpperInvariant())~0.0.1.0") + $caps; $fontsDone[$fs] = $true }
        }
        foreach ($cap in $caps) {
            try {
                Write-Log "Adding capability $cap to $Target"
                Add-WindowsCapability -Name $cap -Path $MountPath -Source $FodSource -LimitAccess @dl -ErrorAction Stop | Out-Null
                $capCategory = if ($cap -like 'Language.Fonts.*') { 'Font' } else { 'Capability' }
                Add-ChangeEvent -Category $capCategory -Item $cap -Target $Target
            } catch { Write-Log "Capability $cap was unavailable or not applicable: $($_.Exception.Message)" 'WARN' }
        }
    }
}

# ---------- servicing ----------
function Service-WinRe {
    # Extracts winre.wim from the currently mounted OS image, services it, and exports the result to $OutputPath.
    # No languages: they go into install.wim only; WinRE and boot.wim stay English-only (Terry, 2026-09-26).
    param([string]$OsMount, [string]$WinReMount, [string]$Temp, [string]$OutputPath, [hashtable]$Packages)
    Assert-NotCancelled
    $dl = $script:DismLogArgs
    $embedded = Join-Chain $OsMount @('Windows', 'System32', 'Recovery', 'winre.wim')
    if (-not (Test-Path -LiteralPath $embedded)) { Write-Log "No WinRE image found at $embedded" 'WARN'; return $false }
    Remove-DirectoryContents $WinReMount
    $working = Join-Path $Temp 'winre.wim'
    $optimized = Join-Path $Temp 'winre.optimized.wim'
    Remove-Item -LiteralPath $working, $optimized -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $embedded -Destination $working -Force
    Write-Log 'Servicing WinRE (done once and reused for every index).'
    try {
        Mount-WindowsImage -ImagePath $working -Index 1 -Path $WinReMount -CheckIntegrity @dl -ErrorAction Stop | Out-Null
        Add-Packages $WinReMount $Packages.SSU 'WinRE' -Label 'SSU' -IgnoreCombinedLcu7007e
        # Microsoft's WinRE step 1: add the combined LCU; only its servicing stack applies to WinRE, the LCU payload does not.
        Add-Packages $WinReMount $Packages.LCU 'WinRE' -Label 'LCU (servicing stack only)' -IgnoreCombinedLcu7007e
        Add-Packages $WinReMount $Packages.SafeOS 'WinRE' -Label 'Safe OS DU'
        Invoke-DismExe -Arguments @("/Image:$WinReMount", '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase', '/Defer') -Description 'Cleaning WinRE'
        Dismount-WindowsImage -Path $WinReMount -Save -CheckIntegrity @dl -ErrorAction Stop | Out-Null
        Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue
        Export-WindowsImage -SourceImagePath $working -SourceIndex 1 -DestinationImagePath $OutputPath -CompressionType Max -CheckIntegrity @dl -ErrorAction Stop | Out-Null
        Add-ChangeEvent -Category 'WinRE' -Item 'WinRE image serviced (once, reused for every index)' -Target 'WinRE'
        return $true
    } catch {
        Dismount-IfMounted $WinReMount
        throw
    }
}
# ---------- provisioned apps (TODO steps 11 / 11b) ----------
# The Apps tab lists the provisioned apps of the selected edition from Profiles\Apps\<profile folder>_Appx.json (11b,
# Terry 2026-09-27): one scan per OS. The list is read from the image only by "Read apps from the ISO", or by a preflight
# when there is no list yet or the OS ISO has changed (name, size or date - a new ISO may add or remove apps). A real run
# never writes it. Ticked apps are kept by DisplayName (versions change with every ISO).
$script:OldAppInventoryFileName = 'ProvisionedApps.json'   # step 11's place, <OS folder>\ProvisionedApps.json; moved once
function Get-AppListPath {
    param([Parameter(Mandatory)][string]$ProfilesDir, [Parameter(Mandatory)][pscustomobject]$Definition)
    return [System.IO.Path]::Combine($ProfilesDir, 'Apps', "$($Definition.Folder)_Appx.json")
}
function Move-OldAppInventory {
    # Moves a step-11 <OS folder>\ProvisionedApps.json to the Apps folder once (only when there is no list there yet).
    param([string]$OsRoot, [Parameter(Mandatory)][string]$File)
    if (-not $OsRoot) { return }
    $old = [System.IO.Path]::Combine($OsRoot, $script:OldAppInventoryFileName)
    if ((Test-Path -LiteralPath $old) -and -not (Test-Path -LiteralPath $File)) {
        try { Ensure-Directory (Split-Path $File -Parent); Move-Item -LiteralPath $old -Destination $File -ErrorAction Stop; Write-Log "App list moved from $old to $File" }
        catch { Write-Log "The old app list $old could not be moved: $($_.Exception.Message)" 'WARN' }
    }
}
function Get-IsoIdentity {
    # What tells one ISO from another for the app list: name, size and last-write time (a new month's ISO can keep its name).
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    $i = Get-Item -LiteralPath $Path
    # Time as UTC ticks: an ISO-8601 date string would come back from ConvertFrom-Json as a DateTime in PowerShell 7.
    return [pscustomobject]@{ Name = $i.Name; Size = [int64]$i.Length; Time = [string]$i.LastWriteTimeUtc.Ticks }
}
function Test-AppInventoryCurrent {
    # True when the list was read from this very ISO (name, size, date) and this index.
    param($Inventory, $Iso, [int]$Index)
    if (-not $Inventory -or -not $Iso) { return $false }
    return ($Inventory.Source -eq $Iso.Name -and [string]$Inventory.IsoSize -eq [string]$Iso.Size -and $Inventory.IsoTime -eq $Iso.Time -and $Inventory.Index -eq $Index)
}
function Get-ProvisionedApps {
    param([Parameter(Mandatory)][string]$Mount)
    return @(Get-AppxProvisionedPackage -Path $Mount -ErrorAction Stop | Sort-Object DisplayName | ForEach-Object {
        [pscustomobject]@{ DisplayName = [string]$_.DisplayName; Version = [string]$_.Version; PackageName = [string]$_.PackageName } })
}
function Save-AppInventory {
    param([Parameter(Mandatory)][string]$File, [object[]]$Apps = @(), [string]$Source, [int]$Index, [string]$ImageName, [string]$Version, [string]$IsoSize = '', [string]$IsoTime = '')
    $file = $File
    Ensure-Directory (Split-Path $file -Parent)
    $data = [ordered]@{
        schemaVersion = 2; read = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); source = $Source; isoSize = $IsoSize; isoTime = $IsoTime; index = $Index; imageName = $ImageName; version = $Version
        apps = @(@($Apps) | ForEach-Object { [ordered]@{ displayName = $_.DisplayName; version = $_.Version; packageName = $_.PackageName } })
    }
    [System.IO.File]::WriteAllText($file, (($data | ConvertTo-Json -Depth 4) + [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))
    Write-Log "App list: $(@($Apps).Count) provisioned app(s) in $Source index $Index ($ImageName) saved to $file"
    return $file
}
function Read-AppInventory {
    # A saved app list, or $null when there is none or it is unusable (WARN).
    param([string]$File)
    if (-not $File) { return $null }
    $file = $File
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try {
        $o = [System.IO.File]::ReadAllText($file) | ConvertFrom-Json -ErrorAction Stop
        $apps = @(@(Get-ProfileValue $o 'apps' @()) | ForEach-Object {
            $n = [string](Get-ProfileValue $_ 'displayName' '')
            if (-not $n) { throw 'an app has no displayName.' }
            [pscustomobject]@{ DisplayName = $n; Version = [string](Get-ProfileValue $_ 'version' ''); PackageName = [string](Get-ProfileValue $_ 'packageName' '') } })
        return [pscustomobject]@{ File = $file; Read = [string](Get-ProfileValue $o 'read' ''); Source = [string](Get-ProfileValue $o 'source' ''); Index = [int](Get-ProfileValue $o 'index' 0)
            IsoSize = [string](Get-ProfileValue $o 'isoSize' ''); IsoTime = [string](Get-ProfileValue $o 'isoTime' '')
            ImageName = [string](Get-ProfileValue $o 'imageName' ''); Version = [string](Get-ProfileValue $o 'version' ''); Apps = $apps }
    } catch { Write-Log "App list $file could not be used ($($_.Exception.Message))." 'WARN'; return $null }
}
function Remove-ProvisionedApps {
    # Removes the ticked provisioned apps from a mounted image, matched by DisplayName. A ticked app the image does not
    # have is logged and skipped; a removal that fails is a WARN (the image stays valid). Returns the number removed.
    param([Parameter(Mandatory)][string]$Mount, [string[]]$Names = @(), [string]$Target)
    $want = @($Names | Where-Object { $_ })
    if ($want.Count -eq 0) { return 0 }
    $present = @(Get-ProvisionedApps $Mount)
    $removed = 0
    foreach ($name in $want) {
        $hits = @($present | Where-Object { $_.DisplayName -eq $name })
        if ($hits.Count -eq 0) { Write-Log "App removal: $name is not provisioned in $Target; nothing to remove."; continue }
        foreach ($h in $hits) {
            Assert-NotCancelled
            try {
                Remove-AppxProvisionedPackage -Path $Mount -PackageName $h.PackageName -ErrorAction Stop | Out-Null
                Write-Log "Removed provisioned app $($h.DisplayName) $($h.Version) from $Target"
                Add-ChangeEvent -Category 'AppRemoved' -Item $h.DisplayName -Target $Target -Detail "provisioned app removed ($($h.PackageName))"
                $removed++
            } catch { Write-Log "Could not remove provisioned app $($h.DisplayName) from ${Target}: $($_.Exception.Message)" 'WARN' }
        }
    }
    return $removed
}
function Update-AppInventoryFromIso {
    # Reads the selected edition's provisioned apps straight from the OS ISO (read-only mount; an install.esd is first
    # exported to a temporary WIM, as ESD files cannot be mounted) and saves them for the Apps tab.
    param([hashtable]$Paths, [string]$SourceWim, [object]$Selected, [string]$IsoPath, [Parameter(Mandatory)][string]$File)
    $iso = Get-IsoIdentity $IsoPath
    $IsoFile = if ($iso) { $iso.Name } else { Split-Path $IsoPath -Leaf }
    $dl = if ($script:DismLogArgs) { $script:DismLogArgs } else { @{} }
    $wim = $SourceWim; $idx = [int]$Selected.ImageIndex; $tmp = $null
    # Each step is shown in the status line and the header, as a read takes a few minutes (mostly the mount and discard).
    if ($SourceWim -like '*.esd') {
        Set-Phase 'Exporting the edition from install.esd'; Set-Progress 25 'Exporting the edition from install.esd (ESD files cannot be mounted; can take several minutes)'
        $tmp = Join-Path $Paths.Temp 'apps.read.wim'; Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        Export-WindowsImage -SourceImagePath $SourceWim -SourceIndex $idx -DestinationImagePath $tmp -CompressionType Max @dl -ErrorAction Stop | Out-Null
        $wim = $tmp; $idx = 1
    }
    Write-Log "Reading the provisioned apps of index $($Selected.ImageIndex) ($($Selected.ImageName)) from $IsoFile (read-only mount)"
    Remove-DirectoryContents $Paths.MainMount
    try {
        Set-Phase 'Mounting the edition read-only'; Set-Progress 40 "Mounting index $($Selected.ImageIndex) ($($Selected.ImageName)) read-only"
        Mount-WindowsImage -ImagePath $wim -Index $idx -Path $Paths.MainMount -ReadOnly @dl -ErrorAction Stop | Out-Null
        Set-Phase 'Reading the provisioned apps'; Set-Progress 70 'Reading the provisioned apps'
        $apps = @(Get-ProvisionedApps $Paths.MainMount)
        Set-Phase 'Discarding the read-only mount'; Set-Progress 85 "Discarding the read-only mount ($($apps.Count) app(s) found)"
        Dismount-WindowsImage -Path $Paths.MainMount -Discard @dl -ErrorAction Stop | Out-Null
    } catch { Dismount-IfMounted $Paths.MainMount; throw }
    finally { if ($tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } }
    $version = [string](Get-WindowsImage -ImagePath $SourceWim -Index ([int]$Selected.ImageIndex)).Version
    [void](Save-AppInventory -File $File -Apps $apps -Source $IsoFile -Index ([int]$Selected.ImageIndex) -ImageName $Selected.ImageName -Version $version `
        -IsoSize $(if ($iso) { [string]$iso.Size } else { '' }) -IsoTime $(if ($iso) { $iso.Time } else { '' }))
    return $apps
}
function Service-InstallIndex {
    param([string]$ImagePath, [int]$Index, [hashtable]$Paths, [hashtable]$Packages, [string]$OsDrive,
          [hashtable]$LpFiles, [string[]]$FodSource = @(), [string[]]$Languages = @(), [bool]$DoWinRe, [bool]$DoNetFx3,
          [string[]]$RemoveApps = @())
    Assert-NotCancelled
    $dl = $script:DismLogArgs
    $target = "install.wim index $Index"
    $hasLang = (@($Languages).Count -gt 0)
    Remove-DirectoryContents $Paths.MainMount
    Write-Log "Mounting $target"
    try {
        Mount-WindowsImage -ImagePath $ImagePath -Index $Index -Path $Paths.MainMount -CheckIntegrity @dl -ErrorAction Stop | Out-Null

        # 0. Provisioned apps (step 11): the ticked apps are removed - the first change to the image, so every later step only
        #    services the apps that stay (Terry, 2026-09-22). They are matched against what this image really provisions, not
        #    against the Apps tab's list, which a run never writes (11b).
        if (@($RemoveApps).Count -gt 0) {
            $nRemoved = Remove-ProvisionedApps -Mount $Paths.MainMount -Names $RemoveApps -Target $target
            Write-Log "App removal: $nRemoved provisioned app(s) removed from $target."
        }

        # 1. WinRE: serviced once (from the first index processed), then reused for every index.
        if ($DoWinRe) {
            $cache = Join-Path $Paths.WinRE 'winre.serviced.wim'
            if (-not (Test-Path -LiteralPath $cache)) {
                [void](Service-WinRe -OsMount $Paths.MainMount -WinReMount $Paths.WinReMount -Temp $Paths.Temp -OutputPath $cache -Packages $Packages)
            }
            if (Test-Path -LiteralPath $cache) {
                Write-Log "Applying serviced WinRE to $target"
                Copy-Item -LiteralPath $cache -Destination (Join-Chain $Paths.MainMount @('Windows', 'System32', 'Recovery', 'winre.wim')) -Force
            }
        } else { Write-Log 'WinRE servicing is OFF (box unticked); WinRE is left as shipped.' 'WARN' }

        # 2. Servicing stack, then (only when adding languages) LCU pass 1 so the newest stack is in place.
        Add-Packages $Paths.MainMount $Packages.SSU $target -Label 'SSU'
        if ($hasLang) {
            Add-Packages $Paths.MainMount $Packages.LCU $target -Label 'LCU (pass 1)'
            # 3. Language packs, then FODs and fonts.
            Add-OfflineLanguages -MountPath $Paths.MainMount -LpFiles $LpFiles -FodSource $FodSource -Languages $Languages -Target $target
        }
        # 4. Final LCU, applied after all languages/FODs so they are brought to the current level.
        Add-Packages $Paths.MainMount $Packages.LCU $target -Label 'LCU (final)'

        # 5. Cleanup BEFORE NetFx3 (NetFx3 creates pending operations that make cleanup fail with 0x800F0806).
        Invoke-DismExe -Arguments @("/Image:$($Paths.MainMount)", '/Cleanup-Image', '/StartComponentCleanup') -Description "Component cleanup on $target" -AllowPending
        Add-ChangeEvent -Category 'Cleanup' -Item 'Component cleanup' -Target $target

        # 6. .NET Framework 3.5, then the .NET cumulative update(s).
        if ($DoNetFx3) {
            $sxs = Join-Chain $OsDrive @('sources', 'sxs')
            Write-Log "Enabling NetFX3 from $sxs on $target"
            Enable-WindowsOptionalFeature -Path $Paths.MainMount -FeatureName NetFx3 -All -Source $sxs -LimitAccess @dl -ErrorAction Stop | Out-Null
            Add-ChangeEvent -Category 'NetFx3' -Item 'NetFx3 enabled' -Target $target
        }
        Add-Packages $Paths.MainMount $Packages.NetCU $target -Label '.NET CU' -SkipNotApplicable

        Dismount-WindowsImage -Path $Paths.MainMount -Save -CheckIntegrity @dl -ErrorAction Stop | Out-Null
    } catch {
        Dismount-IfMounted $Paths.MainMount
        throw
    }
}
function Export-OptimizedWim {
    param([string]$Source, [string]$Destination)
    Assert-NotCancelled
    $dl = $script:DismLogArgs
    Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
    foreach ($image in @(Get-WindowsImage -ImagePath $Source)) {
        Write-Log "Final optimized export: index $($image.ImageIndex), $($image.ImageName)"
        Export-WindowsImage -SourceImagePath $Source -SourceIndex $image.ImageIndex -DestinationImagePath $Destination -DestinationName $image.ImageName -CompressionType Max -CheckIntegrity @dl -ErrorAction Stop | Out-Null
    }
}
function Save-BootMediaFiles {
    # Microsoft's media steps save these from the patched Setup image of boot.wim: setup.exe, setuphost.exe (24H2 and
    # later) and the boot manager files. New-RefreshedMedia copies them onto the media (Update-MediaBootFiles).
    param([string]$Mount, [string]$Destination, [string]$Target)
    $files = [ordered]@{
        'setup.exe' = @('sources', 'setup.exe'); 'setuphost.exe' = @('sources', 'setuphost.exe')
        'bootmgfw.efi' = @('Windows', 'Boot', 'EFI', 'bootmgfw.efi'); 'bootmgr.efi' = @('Windows', 'Boot', 'EFI', 'bootmgr.efi'); 'boot.stl' = @('Windows', 'Boot', 'EFI', 'boot.stl')
    }
    foreach ($name in $files.Keys) {
        $src = Join-Chain $Mount $files[$name]
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $Destination $name) -Force; Write-Log "Saved $name from the patched $Target for the media." }
    }
}
function Save-Boot2023Files {
    # The boot files signed with 'Windows UEFI CA 2023' that the 2024-04 and later cumulative updates add to boot.wim
    # (Windows\Boot\EFI_EX, FONTS_EX, DVD_EX), saved after the LCU for the CA 2023 media (Set-Media2023BootFiles).
    # Returns $false when the image does not have them (LCU older than 2024-04).
    param([string]$Mount, [string]$Destination, [string]$Target)
    $boot = Join-Chain $Mount @('Windows', 'Boot')
    foreach ($d in 'EFI_EX', 'FONTS_EX', 'DVD_EX') { if (-not (Test-Path -LiteralPath (Join-Path $boot $d))) { return $false } }
    Ensure-Directory $Destination
    foreach ($d in 'EFI_EX', 'FONTS_EX', 'DVD_EX') { Copy-Item -LiteralPath (Join-Path $boot $d) -Destination (Join-Path $Destination $d) -Recurse -Force }
    $stl = Join-Chain $boot @('EFI', 'boot.stl')
    if (Test-Path -LiteralPath $stl) { Copy-Item -LiteralPath $stl -Destination (Join-Path $Destination 'boot.stl') -Force }
    Write-Log "Saved the Windows UEFI CA 2023 boot files (EFI_EX, FONTS_EX, DVD_EX) from the patched $Target."
    return $true
}
function Service-BootWim {
    # Patches every boot.wim image (1 = WinPE, 2 = WinPE + Windows Setup) for the refreshed media. No languages: boot.wim
    # stays English-only (Terry, 2026-09-26). Returns the folder holding the files saved from the Setup image, and with
    # -Save2023 the CA 2023 boot files in its CA2023 sub-folder (taken from the first image, as Microsoft's script does).
    param([string]$SourceBoot, [string]$Destination, [hashtable]$Paths, [hashtable]$Packages, [switch]$Save2023)
    $dl = $script:DismLogArgs
    $working = Join-Path $Paths.Working 'boot.working.wim'
    $optimized = Join-Path $Paths.Temp 'boot.optimized.wim'
    $saved = Join-Path $Paths.Working 'bootfiles'
    Remove-DirectoryContents $saved
    Copy-Item -LiteralPath $SourceBoot -Destination $working -Force
    Set-ItemProperty -LiteralPath $working -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
    foreach ($image in @(Get-WindowsImage -ImagePath $working)) {
        $target = "boot.wim index $($image.ImageIndex)"
        Remove-DirectoryContents $Paths.WinPeMount
        Write-Log "Mounting $target"
        try {
            Mount-WindowsImage -ImagePath $working -Index $image.ImageIndex -Path $Paths.WinPeMount -CheckIntegrity @dl -ErrorAction Stop | Out-Null
            Add-Packages $Paths.WinPeMount $Packages.SSU $target -Label 'SSU' -IgnoreCombinedLcu7007e
            Add-Packages $Paths.WinPeMount $Packages.LCU $target -Label 'LCU' -IgnoreCombinedLcu7007e
            Invoke-DismExe -Arguments @("/Image:$($Paths.WinPeMount)", '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase', '/Defer') -Description "Cleaning $target"
            # The Setup image is the one with sources\setup.exe (index 2 on Microsoft media).
            if (Test-Path -LiteralPath (Join-Chain $Paths.WinPeMount @('sources', 'setup.exe'))) { Save-BootMediaFiles -Mount $Paths.WinPeMount -Destination $saved -Target $target }
            if ($Save2023 -and -not (Test-Path -LiteralPath (Join-Path $saved 'CA2023'))) { [void](Save-Boot2023Files -Mount $Paths.WinPeMount -Destination (Join-Path $saved 'CA2023') -Target $target) }
            Dismount-WindowsImage -Path $Paths.WinPeMount -Save -CheckIntegrity @dl -ErrorAction Stop | Out-Null
        } catch {
            Dismount-IfMounted $Paths.WinPeMount
            throw
        }
    }
    Remove-Item -LiteralPath $optimized -Force -ErrorAction SilentlyContinue
    foreach ($image in @(Get-WindowsImage -ImagePath $working)) {
        Export-WindowsImage -SourceImagePath $working -SourceIndex $image.ImageIndex -DestinationImagePath $optimized -DestinationName $image.ImageName -CompressionType Max -CheckIntegrity @dl -ErrorAction Stop | Out-Null
    }
    Copy-Item -LiteralPath $optimized -Destination $Destination -Force
    if (@(Get-ChildItem -LiteralPath $saved -File).Count -eq 0) { Write-Log 'No boot.wim image holds sources\setup.exe; setup.exe and the boot manager files on the media are left as they are.' 'WARN' }
    return $saved
}

# ---------- verification ----------
function Test-OutputWim {
    # Read-only mounts each index of the final WIM, logs what is really in it, returns the number of issues, and (as a side
    # effect, in $script:VerifyInventory / $script:VerifyBuildAfter) collects the change log's Section B: the image's final state.
    param([string]$WimPath, [hashtable]$Paths, [string[]]$Languages = @(), [bool]$ExpectLcu, [string[]]$RemovedApps = @())
    $dl = $script:DismLogArgs
    $issues = 0
    $script:VerifyInventory = [System.Collections.Generic.List[object]]::new()
    $script:VerifyBuildAfter = $null
    foreach ($img in @(Get-WindowsImage -ImagePath $WimPath)) {
        Assert-NotCancelled
        $detail = Get-WindowsImage -ImagePath $WimPath -Index $img.ImageIndex
        Write-Log ("VERIFY index {0} '{1}': image version {2}" -f $img.ImageIndex, $img.ImageName, $detail.Version)
        if (-not $script:VerifyBuildAfter) { $script:VerifyBuildAfter = [string]$detail.Version }
        Remove-DirectoryContents $Paths.MainMount
        try {
            Mount-WindowsImage -ImagePath $WimPath -Index $img.ImageIndex -Path $Paths.MainMount -ReadOnly @dl -ErrorAction Stop | Out-Null
            $pk = @(Get-WindowsPackage -Path $Paths.MainMount @dl)
            $roll = @($pk | Where-Object { $_.PackageName -like 'Package_for_RollupFix*' -and $_.PackageState -eq 'Installed' })
            if ($roll.Count -gt 0) { Write-Log ('VERIFY   RollupFix installed: ' + ((@($roll | ForEach-Object { $_.PackageName })) -join '; ')) }
            elseif ($ExpectLcu) { Write-Log 'VERIFY   NO RollupFix (cumulative update) package is installed in this image.' 'WARN'; $issues++ }
            $pending = @($pk | Where-Object { $_.PackageState -match 'Pending' })
            if ($pending.Count -gt 0) { Write-Log ("VERIFY   {0} package(s) are in a pending state (normal for offline-serviced images; first boot completes them)." -f $pending.Count) }
            foreach ($lang in @($Languages)) {
                $lp = @($pk | Where-Object { $_.PackageName -like "*LanguagePack-Package*~$lang~*" -and $_.PackageState -eq 'Installed' })
                if ($lp.Count -gt 0) { Write-Log "VERIFY   language pack $lang present" }
                else { Write-Log "VERIFY   language pack $lang is MISSING" 'WARN'; $issues++ }
            }
            $allCaps = @(Get-WindowsCapability -Path $Paths.MainMount @dl | Where-Object { $_.State -eq 'Installed' })
            if (@($Languages).Count -gt 0) {
                $langCaps = @($allCaps | Where-Object { $_.Name -like 'Language.*' })
                Write-Log "VERIFY   language capabilities installed: $($langCaps.Count)"
                foreach ($lang in @($Languages)) {
                    if ($script:LangFontScripts.ContainsKey($lang)) {
                        $fs = $script:LangFontScripts[$lang]
                        if (-not @($langCaps | Where-Object { $_.Name -like "Language.Fonts.$fs~*" })) { Write-Log "VERIFY   font capability for $lang ($fs) is MISSING" 'WARN'; $issues++ }
                    }
                }
            }

            # ---- Section B: final-state inventory (read from this same read-only mount, not tracked during the run) ----
            foreach ($p in $pk) {
                $script:VerifyInventory.Add([pscustomobject]@{ Index = $img.ImageIndex; Category = 'Package'; Item = $p.PackageName; Version = ''; Kb = (Get-KbFromName $p.PackageName); State = [string]$p.PackageState })
            }
            foreach ($c in $allCaps) {
                $capCategory = if ($c.Name -like 'Language.Fonts.*') { 'Font' } elseif ($c.Name -like 'Language.*') { 'Language capability' } else { 'Capability' }
                $script:VerifyInventory.Add([pscustomobject]@{ Index = $img.ImageIndex; Category = $capCategory; Item = $c.Name; Version = ''; Kb = ''; State = [string]$c.State })
            }
            foreach ($f in @(Get-WindowsOptionalFeature -Path $Paths.MainMount -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Enabled' })) {
                $script:VerifyInventory.Add([pscustomobject]@{ Index = $img.ImageIndex; Category = 'Optional feature'; Item = $f.FeatureName; Version = ''; Kb = ''; State = 'Enabled' })
            }
            $provisioned = @(Get-AppxProvisionedPackage -Path $Paths.MainMount -ErrorAction SilentlyContinue)
            foreach ($a in $provisioned) {
                $script:VerifyInventory.Add([pscustomobject]@{ Index = $img.ImageIndex; Category = 'Provisioned appx'; Item = $a.DisplayName; Version = [string]$a.Version; Kb = ''; State = 'Provisioned' })
            }
            if (@($RemovedApps).Count -gt 0) {
                $still = @($RemovedApps | Where-Object { $n = $_; @($provisioned | Where-Object { $_.DisplayName -eq $n }).Count -gt 0 })
                if ($still.Count -gt 0) { Write-Log "VERIFY   app(s) ticked for removal are still provisioned: $($still -join ', ')" 'WARN'; $issues += $still.Count }
                else { Write-Log "VERIFY   none of the $(@($RemovedApps).Count) app(s) ticked for removal is provisioned" }
            }
            # No per-user appx exists offline; the closest offline equivalent is what is actually staged under WindowsApps.
            $appxFolder = Join-Chain $Paths.MainMount @('Program Files', 'WindowsApps')
            if (Test-Path -LiteralPath $appxFolder) {
                foreach ($d in @(Get-ChildItem -LiteralPath $appxFolder -Directory -ErrorAction SilentlyContinue | Where-Object { Test-AppxPackageFolder $_.Name })) {
                    $script:VerifyInventory.Add([pscustomobject]@{ Index = $img.ImageIndex; Category = 'Appx package (staged)'; Item = $d.Name; Version = ''; Kb = ''; State = 'Present' })
                }
            }
            # Get-HotFix only works on a running system; offline, a hotfix is a servicing package that names a KB.
            foreach ($h in @($pk | Where-Object { $_.PackageState -eq 'Installed' -and (Get-KbFromName $_.PackageName) })) {
                $script:VerifyInventory.Add([pscustomobject]@{ Index = $img.ImageIndex; Category = 'Hotfix'; Item = (Get-KbFromName $h.PackageName); Version = ''; Kb = (Get-KbFromName $h.PackageName); State = 'Installed' })
            }

            Dismount-WindowsImage -Path $Paths.MainMount -Discard @dl -ErrorAction Stop | Out-Null
        } catch {
            Dismount-IfMounted $Paths.MainMount
            throw
        }
    }
    Write-Log "VERIFY complete: $issues issue(s)."
    return $issues
}

# ---------- change log ----------
function Test-AppxPackageFolder {
    # Package folders under WindowsApps are named <Name>_<Version>_<Arch>_<ResourceId>_<PublisherId>; Windows' own
    # housekeeping folders there ("Deleted", "Merged", "MovedPackages", ...) are not packages (Terry's 2026-09-25 change log).
    param([string]$Name)
    return ($Name -match '^[^_]+_\d+(\.\d+){1,3}_')
}
function Write-ChangeLog {
    # Writes the per-image change log (HTML + CSV) built from $script:ChangeEvents (Section A) and $script:VerifyInventory
    # (Section B, only populated when Test-OutputWim ran). Returns the file paths, or $null if it could not be written.
    param(
        [Parameter(Mandatory)][string]$OsName, [Parameter(Mandatory)][hashtable]$Paths, [Parameter(Mandatory)][string]$Stamp,
        [string]$ToolVersion, [string]$BuildBefore, [string]$BuildAfter, [string[]]$Languages = @(),
        [bool]$ServiceAllIndexes, [pscustomobject]$Selected, [object[]]$IsoSources, [object[]]$Events, [object[]]$Inventory,
        [Nullable[int]]$VerifyIssues, [string]$Gate, [bool]$VerifyRan
    )
    try {
        $safe = ConvertTo-SafeFileName $OsName
        $buildTag = ConvertTo-SafeFileName ($(if ($BuildAfter) { $BuildAfter } elseif ($BuildBefore) { $BuildBefore } else { 'unknown' }))
        $base = "ChangeLog_{0}_{1}_{2}" -f $safe, $buildTag, $Stamp
        $htmlPath = Join-Path $Paths.Logs "$base.html"
        $csvPath = Join-Path $Paths.Logs "$base.csv"
        $runDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $edition = if ($ServiceAllIndexes) { 'All indexes (serviced and recombined)' } elseif ($Selected) { "[$($Selected.ImageIndex)] $($Selected.ImageName)" } else { 'n/a' }
        $langText = if (@($Languages).Count -gt 0) { $Languages -join ', ' } else { '(none - English only)' }
        $verifyText = if (-not $VerifyRan) { 'Skipped (Verify was not selected for this run)' } elseif ($null -eq $VerifyIssues) { 'n/a' } else { "$VerifyIssues issue(s) found" }

        # ---- one row list feeds both the CSV and the HTML tables, so they can never drift apart ----
        $rows = [System.Collections.Generic.List[object]]::new()
        $addRow = { param($Section, $Item, $Ver, $State, $Source, $Index, $When = '')
            $rows.Add([pscustomobject]@{ Date = $(if ($When) { $When } else { $runDate }); Section = $Section; Item = $Item; VerKb = $Ver; State = $State; Source = $Source; Index = $Index })
        }
        & $addRow 'Header' 'Operating system' $OsName '' '' ''
        & $addRow 'Header' 'Build before patching' $(if ($BuildBefore) { $BuildBefore } else { 'n/a' }) '' '' ''
        & $addRow 'Header' 'Build after patching' $(if ($BuildAfter) { $BuildAfter } else { 'n/a' }) '' '' ''
        & $addRow 'Header' 'Edition / index serviced' $edition '' '' ''
        & $addRow 'Header' 'Languages' $langText '' '' ''
        & $addRow 'Header' 'Tool version' $ToolVersion '' '' ''
        & $addRow 'Header' 'Validation gate' $Gate '' '' ''
        & $addRow 'Header' 'Verification' $verifyText '' '' ''
        foreach ($src in @($IsoSources | Where-Object { $_ })) { & $addRow 'Header' "Source ISO ($($src.Role))" $src.File '' '' '' }
        foreach ($e in @($Events | Sort-Object Time)) {
            $ver = if ($e.Kb) { $e.Kb } else { $e.Detail }
            # Each Section A row carries the time its step succeeded, not the time the log was written (Terry, 2026-09-25).
            $when = if ($e.Time -is [datetime]) { $e.Time.ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
            & $addRow 'A' $e.Item $ver 'Added' $e.Target '' $when
        }
        foreach ($r in @($Inventory | Sort-Object Index, Category, Item)) {
            $ver = if ($r.Kb) { $r.Kb } elseif ($r.Version) { $r.Version } else { '' }
            & $addRow 'B' $r.Item $ver $r.State $r.Category $r.Index
        }

        # ---- CSV: Date | Section | Item | Version / KB | State | Source | Index ----
        $csvRows = @($rows | ForEach-Object { [pscustomobject]@{ Date = $_.Date; Section = $_.Section; Item = $_.Item; 'Version / KB' = $_.VerKb; State = $_.State; Source = $_.Source; Index = $_.Index } })
        $csvRows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

        # ---- HTML ----
        $enc = { param($t) [System.Net.WebUtility]::HtmlEncode([string]$t) }
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('<!DOCTYPE html><html><head><meta charset="utf-8"><title>' + (& $enc "$OsName change log") + '</title><style>')
        [void]$sb.AppendLine('body{font-family:Segoe UI,Arial,sans-serif;margin:24px;color:#1a1a1a}h1{margin-bottom:2px}h2{margin-top:28px;border-bottom:2px solid #0078D4;padding-bottom:4px}')
        [void]$sb.AppendLine('table{border-collapse:collapse;width:100%;margin-top:8px;font-size:13px}th,td{border:1px solid #ddd;padding:5px 8px;text-align:left;vertical-align:top}th{background:#0078D4;color:#fff;position:sticky;top:0}tr:nth-child(even){background:#f6f8fa}')
        [void]$sb.AppendLine('.meta td:first-child{font-weight:600;width:220px;background:#f6f8fa}.gate-passed{color:#0a7d27;font-weight:700}.gate-failed{color:#c0271e;font-weight:700}.note{color:#555}</style></head><body>')
        [void]$sb.AppendLine('<h1>' + (& $enc $OsName) + '</h1><p class="note">Build ' + (& $enc $(if ($BuildAfter) { $BuildAfter } elseif ($BuildBefore) { $BuildBefore } else { 'unknown' })) + ' &nbsp;|&nbsp; run ' + (& $enc $runDate) + ' &nbsp;|&nbsp; WimForge ' + (& $enc $ToolVersion) + '</p>')
        if (-not $VerifyRan) { [void]$sb.AppendLine('<p class="note"><strong>Note:</strong> Verify was not selected for this run, so Section B (final-state inventory) and the validation gate are not available below.</p>') }
        [void]$sb.AppendLine('<table class="meta">')
        foreach ($h in @($rows | Where-Object { $_.Section -eq 'Header' })) {
            $cls = if ($h.Item -eq 'Validation gate') { if ($h.VerKb -eq 'PASSED') { ' class="gate-passed"' } elseif ($h.VerKb -eq 'FAILED') { ' class="gate-failed"' } else { '' } } else { '' }
            [void]$sb.AppendLine("<tr><td>$(& $enc $h.Item)</td><td$cls>$(& $enc $h.VerKb)</td></tr>")
        }
        [void]$sb.AppendLine('</table>')
        [void]$sb.AppendLine('<h2>Section A - what this tool changed</h2>')
        $aRows = @($rows | Where-Object { $_.Section -eq 'A' })
        if ($aRows.Count -eq 0) { [void]$sb.AppendLine('<p class="note">No changes were recorded (Preflight, or nothing needed adding).</p>') }
        else {
            [void]$sb.AppendLine('<table><tr><th>Date</th><th>Item</th><th>KB / version</th><th>Target</th></tr>')
            foreach ($r in $aRows) { [void]$sb.AppendLine("<tr><td>$(& $enc $r.Date)</td><td>$(& $enc $r.Item)</td><td>$(& $enc $r.VerKb)</td><td>$(& $enc $r.Source)</td></tr>") }
            [void]$sb.AppendLine('</table>')
        }
        [void]$sb.AppendLine('<h2>Section B - final state of the image</h2>')
        $bAll = @($rows | Where-Object { $_.Section -eq 'B' })
        if ($bAll.Count -eq 0) { [void]$sb.AppendLine('<p class="note">Not available (Verify was not selected for this run).</p>') }
        else {
            foreach ($idx in @($bAll | Select-Object -ExpandProperty Index -Unique | Sort-Object)) {
                [void]$sb.AppendLine("<h3>Index $idx</h3><table><tr><th>Date</th><th>Category</th><th>Item</th><th>Version / KB</th><th>State</th></tr>")
                foreach ($r in @($bAll | Where-Object { $_.Index -eq $idx })) { [void]$sb.AppendLine("<tr><td>$(& $enc $r.Date)</td><td>$(& $enc $r.Source)</td><td>$(& $enc $r.Item)</td><td>$(& $enc $r.VerKb)</td><td>$(& $enc $r.State)</td></tr>") }
                [void]$sb.AppendLine('</table>')
            }
        }
        [void]$sb.AppendLine('</body></html>')
        Set-Content -LiteralPath $htmlPath -Value $sb.ToString() -Encoding UTF8
        Write-Log "Change log written: $htmlPath"
        return [pscustomobject]@{ Html = $htmlPath; Csv = $csvPath }
    } catch {
        Write-Log "Change log could not be written: $($_.Exception.Message)" 'WARN'
        return $null
    }
}

# ---------- refreshed media ----------
function Update-MediaBootFiles {
    # Microsoft's last media steps (after the Setup DU): setup.exe / setuphost.exe and the boot manager files saved from
    # the patched boot.wim replace the media's own, so Setup and the boot files match the patched WinPE. Microsoft: if
    # setup.exe in sources and in boot.wim differ, Windows Setup fails.
    param([string]$Media, [string]$BootFiles)
    foreach ($name in 'setup.exe', 'setuphost.exe') {
        $src = Join-Path $BootFiles $name
        if (-not (Test-Path -LiteralPath $src)) { continue }
        Copy-Item -LiteralPath $src -Destination (Join-Chain $Media @('sources', $name)) -Force
        Write-Log "Media: sources\$name replaced with the one from the patched boot.wim."
        Add-ChangeEvent -Category 'Media' -Item $name -Target 'Media\sources' -Detail 'from the patched boot.wim (Setup image)'
    }
    $fw = Join-Path $BootFiles 'bootmgfw.efi'; $mgr = Join-Path $BootFiles 'bootmgr.efi'
    foreach ($f in @(Get-ChildItem -LiteralPath $Media -Recurse -File -Force -Filter 'b*.efi')) {
        $from = if ($f.Name -in @('bootmgfw.efi', 'bootx64.efi', 'bootia32.efi', 'bootaa64.efi')) { $fw } elseif ($f.Name -eq 'bootmgr.efi') { $mgr } else { $null }
        if (-not $from -or -not (Test-Path -LiteralPath $from)) { continue }
        Copy-Item -LiteralPath $from -Destination $f.FullName -Force
        $rel = $f.FullName.Substring($Media.TrimEnd('\').Length + 1)
        Write-Log "Media: $rel replaced with the patched $(Split-Path $from -Leaf)."
        Add-ChangeEvent -Category 'Media' -Item $rel -Target 'Media' -Detail "boot manager from the patched boot.wim ($(Split-Path $from -Leaf))"
    }
    $stl = Join-Path $BootFiles 'boot.stl'
    if (Test-Path -LiteralPath $stl) {
        $dst = Join-Chain $Media @('efi', 'microsoft', 'boot', 'boot.stl'); Ensure-Directory (Split-Path $dst -Parent)
        Copy-Item -LiteralPath $stl -Destination $dst -Force
        Write-Log 'Media: efi\microsoft\boot\boot.stl copied from the patched boot.wim.'
        Add-ChangeEvent -Category 'Media' -Item 'efi\microsoft\boot\boot.stl' -Target 'Media' -Detail 'from the patched boot.wim'
    }
}
function Get-EmbeddedSignerIssuer {
    # Issuer of the signature embedded in a boot file - what UEFI firmware checks. (Get-AuthenticodeSignature reports the
    # Windows catalog signature for boot files, which is PCA 2011 for both the old and the CA 2023 boot manager.)
    param([string]$Path)
    try { return [string]([System.Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($Path)).Issuer } catch { return '' }
}
function Set-Media2023BootFiles {
    # Microsoft's Make2023BootableMedia.ps1 (v1.4, Copy-2023BootBins; BSD licence), applied to a copy of the refreshed
    # media: bootmgfw_EX.efi -> efi\boot\bootx64.efi (bootaa64.efi on ARM64 media), bootmgr_EX.efi -> bootmgr.efi when
    # present, efisys_EX.bin -> efi\microsoft\boot\efisys_ex.bin (the ISO's UEFI boot image), FONTS_EX -> efi\microsoft\boot\fonts
    # with _EX dropped from the names, boot.stl when the media has none. Returns the boot manager path on the media.
    param([string]$Media, [string]$ExFiles)
    $bootmgfw = Join-Chain $ExFiles @('EFI_EX', 'bootmgfw_EX.efi'); $efisys = Join-Chain $ExFiles @('DVD_EX', 'EFI', 'en-US', 'efisys_EX.bin')
    foreach ($req in $bootmgfw, $efisys) { if (-not (Test-Path -LiteralPath $req)) { throw "The CA 2023 boot file $(Split-Path $req -Leaf) is missing from boot.wim; it comes with the 2024-04 or later cumulative update." } }
    $bootDir = Join-Chain $Media @('efi', 'boot'); Ensure-Directory $bootDir
    $name = if (Test-Path -LiteralPath (Join-Path $bootDir 'bootaa64.efi')) { 'bootaa64.efi' } else { 'bootx64.efi' }
    $target = Join-Path $bootDir $name
    Copy-Item -LiteralPath $bootmgfw -Destination $target -Force
    Write-Log "CA 2023 media: efi\boot\$name <- bootmgfw_EX.efi"
    Add-ChangeEvent -Category 'Media CA 2023' -Item "efi\boot\$name" -Target 'Media_CA2023' -Detail 'boot manager signed by Windows UEFI CA 2023 (bootmgfw_EX.efi)'
    $mgr = Join-Chain $ExFiles @('EFI_EX', 'bootmgr_EX.efi')
    if (Test-Path -LiteralPath $mgr) {
        Copy-Item -LiteralPath $mgr -Destination (Join-Path $Media 'bootmgr.efi') -Force
        Write-Log 'CA 2023 media: bootmgr.efi <- bootmgr_EX.efi'
        Add-ChangeEvent -Category 'Media CA 2023' -Item 'bootmgr.efi' -Target 'Media_CA2023' -Detail 'bootmgr_EX.efi'
    }
    $msBoot = Join-Chain $Media @('efi', 'microsoft', 'boot'); Ensure-Directory $msBoot
    Copy-Item -LiteralPath $efisys -Destination (Join-Path $msBoot 'efisys_ex.bin') -Force
    Write-Log 'CA 2023 media: efi\microsoft\boot\efisys_ex.bin <- efisys_EX.bin (UEFI boot image for the ISO)'
    Add-ChangeEvent -Category 'Media CA 2023' -Item 'efi\microsoft\boot\efisys_ex.bin' -Target 'Media_CA2023' -Detail 'efisys_EX.bin, the UEFI boot image of the CA 2023 ISO'
    $fontsEx = Join-Path $ExFiles 'FONTS_EX'
    if (Test-Path -LiteralPath $fontsEx) {
        $fonts = Join-Path $msBoot 'fonts'; Ensure-Directory $fonts
        $n = 0
        foreach ($f in @(Get-ChildItem -LiteralPath $fontsEx -File)) { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $fonts ($f.Name -replace '_EX', '')) -Force; $n++ }
        Write-Log "CA 2023 media: $n boot font(s) from FONTS_EX copied to efi\microsoft\boot\fonts"
        Add-ChangeEvent -Category 'Media CA 2023' -Item 'efi\microsoft\boot\fonts' -Target 'Media_CA2023' -Detail "$n boot font(s) from FONTS_EX"
    }
    $stl = Join-Path $ExFiles 'boot.stl'; $stlDst = Join-Path $msBoot 'boot.stl'
    if ((Test-Path -LiteralPath $stl) -and -not (Test-Path -LiteralPath $stlDst)) { Copy-Item -LiteralPath $stl -Destination $stlDst -Force; Write-Log 'CA 2023 media: efi\microsoft\boot\boot.stl added' }
    return $target
}
function New-Media2023 {
    # The CA 2023 media, built alongside the standard media (Terry, 2026-09-27): a copy of the finished refreshed media
    # with the CA 2023 boot files swapped in, then checked - the boot manager's embedded signature must be issued by
    # 'Windows UEFI CA 2023'. It boots only on PCs whose firmware trusts that certificate.
    param([string]$MediaFolder, [string]$ExFiles, [hashtable]$Paths)
    if (-not $ExFiles -or -not (Test-Path -LiteralPath $ExFiles)) { throw 'boot.wim has no Windows UEFI CA 2023 boot files (Windows\Boot\EFI_EX, FONTS_EX, DVD_EX). They come with the 2024-04 or later cumulative update; check PATCHES\LCU.' }
    $media = Join-Path $Paths.NewWim 'Media_CA2023'
    Remove-DirectoryContents $media
    Write-Log "Copying the refreshed media to $media"
    Copy-Item -Path (Join-Path $MediaFolder '*') -Destination $media -Recurse -Force
    $bootmgr = Set-Media2023BootFiles -Media $media -ExFiles $ExFiles
    $issuer = Get-EmbeddedSignerIssuer $bootmgr
    if ($issuer -notmatch 'Windows UEFI CA 2023') { throw "The boot manager on the CA 2023 media ($bootmgr) is signed by '$issuer', not 'Windows UEFI CA 2023'." }
    Write-Log "VERIFY CA 2023 media: $(Split-Path $bootmgr -Leaf) is signed by $issuer."
    $std = Get-EmbeddedSignerIssuer (Join-Chain $MediaFolder @('efi', 'boot', (Split-Path $bootmgr -Leaf)))
    if ($std) { Write-Log "Standard media: $(Split-Path $bootmgr -Leaf) is signed by $std." }
    Write-Log "CA 2023 media folder ready: $media"
    return $media
}
function New-RefreshedMedia {
    param([string]$OsDrive, [hashtable]$Paths, [string]$InstallWim, [string]$BootWim, [object[]]$SetupDu, [string]$BootFiles)
    $media = Join-Path $Paths.NewWim 'Media'
    Remove-DirectoryContents $media
    Write-Log "Copying mounted OS media to $media"
    Copy-Item -Path (Join-Path $OsDrive '*') -Destination $media -Recurse -Force
    Get-ChildItem -LiteralPath $media -Recurse -File -Force | ForEach-Object { $_.IsReadOnly = $false }
    Copy-Item -LiteralPath $InstallWim -Destination (Join-Chain $media @('sources', 'install.wim')) -Force
    $esd = Join-Chain $media @('sources', 'install.esd'); if (Test-Path -LiteralPath $esd) { Remove-Item -LiteralPath $esd -Force }
    if ($BootWim -and (Test-Path -LiteralPath $BootWim)) { Copy-Item -LiteralPath $BootWim -Destination (Join-Chain $media @('sources', 'boot.wim')) -Force }
    foreach ($du in @($SetupDu | Where-Object { $_ })) {
        Write-Log "Expanding Setup DU $($du.FullName)"
        & "$env:SystemRoot\System32\expand.exe" $du.FullName '-F:*' (Join-Path $media 'sources') | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Setup DU expansion failed with exit code $LASTEXITCODE." }
        $duName = Split-Path $du.FullName -Leaf
        Add-ChangeEvent -Category 'SetupDU' -Item $duName -Target 'Media\sources' -Kb (Get-KbFromName $duName) -Detail 'Setup DU expanded into the refreshed media'
    }
    if ($BootWim -and (Test-Path -LiteralPath $BootWim)) {
        Add-ChangeEvent -Category 'Media' -Item 'sources\boot.wim' -Target 'Media\sources' -Detail 'patched boot.wim (WinPE and Setup)'
        if ($BootFiles -and (Test-Path -LiteralPath $BootFiles)) { Update-MediaBootFiles -Media $media -BootFiles $BootFiles }
    }
    Write-Log "Refreshed media folder ready: $media"
    return $media
}
function Build-IsoFromMedia {
    # -EfiBootFile efisys_ex.bin for the CA 2023 media (its UEFI boot image), as Microsoft's script does.
    param([string]$MediaFolder, [hashtable]$Paths, [string]$EfiBootFile = 'efisys.bin', [string]$NamePrefix = 'UpdatedMedia')
    $oscdimg = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools" -Filter oscdimg.exe -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $oscdimg) { throw 'Oscdimg.exe was not found. Install the Windows ADK Deployment Tools.' }
    $bios = Join-Chain $MediaFolder @('boot', 'etfsboot.com'); $uefi = Join-Chain $MediaFolder @('efi', 'microsoft', 'boot', $EfiBootFile)
    if (-not (Test-Path -LiteralPath $bios) -or -not (Test-Path -LiteralPath $uefi)) { throw "Required BIOS or UEFI boot sector files (etfsboot.com, $EfiBootFile) were not found in the media." }
    $isoOut = Join-Path $Paths.NewWim ("{0}_{1}.iso" -f $NamePrefix, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $bootData = "-bootdata:2#p0,e,b$bios#pEF,e,b$uefi"
    Write-Log "Building ISO $isoOut"
    & $oscdimg.FullName '-m' '-o' '-u2' '-udfver102' $bootData $MediaFolder $isoOut | ForEach-Object { Write-Log $_ }
    if ($LASTEXITCODE -ne 0) { throw "Oscdimg failed with exit code $LASTEXITCODE." }
    Write-Log "ISO ready: $isoOut"
    return $isoOut
}

# ---------- output safety ----------
function Backup-PreviousOutput {
    # Moves whatever is in NEWWIM (previous install.wim, boot.wim, Media, ISO, change logs) into NEWWIM\Archive\<stamp> the first time
    # this run is about to write output, so a run never silently overwrites the last good result. Runs once per run.
    param([Parameter(Mandatory)][hashtable]$Paths, [Parameter(Mandatory)][string]$Stamp, [int]$Keep = 3)
    if ($script:OutputArchived) { return }
    $script:OutputArchived = $true
    $items = @(Get-ChildItem -LiteralPath $Paths.NewWim -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'Archive' })
    if ($items.Count -eq 0) { return }
    $archiveRoot = Join-Path $Paths.NewWim 'Archive'
    $dest = Join-Path $archiveRoot $Stamp
    # Two runs started in the same second would share a stamp; the second gets _2, _3, ... instead of failing.
    $n = 1; while (Test-Path -LiteralPath $dest) { $n++; $dest = Join-Path $archiveRoot "${Stamp}_$n" }
    Ensure-Directory $dest
    foreach ($i in $items) { Move-Item -LiteralPath $i.FullName -Destination $dest -Force }
    Write-Log "Previous output ($($items.Count) item(s)) archived to $dest"
    if ($Keep -gt 0) {
        $dirs = @(Get-ChildItem -LiteralPath $archiveRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
        foreach ($old in @($dirs | Select-Object -Skip $Keep)) {
            Remove-Item -LiteralPath $old.FullName -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Removed old archive $($old.Name) (keeping the newest $Keep)."
        }
    }
}
function Get-FreeSpaceGB {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $root = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Path))
        return [Math]::Round(([System.IO.DriveInfo]::new($root)).AvailableFreeSpace / 1GB, 1)
    } catch { return $null }
}
function Test-FreeSpace {
    # Rough estimate: the source WIM is copied to OLDWIM and WORKING and exported to NEWWIM (about 3 copies) plus scratch space;
    # media / ISO output each add about one OS ISO. The profile's minFreeGB is a floor.
    param([Parameter(Mandatory)]$Definition, [Parameter(Mandatory)][hashtable]$Paths, [string]$SourceWim, [string]$OsIsoPath, $Options)
    if ($Definition.SpaceCheck -eq 'off') { return }
    $wimGB = 0.0; $isoGB = 0.0
    if ($SourceWim -and (Test-Path -LiteralPath $SourceWim)) {
        $wimGB = (Get-Item -LiteralPath $SourceWim).Length / 1GB
        if ($SourceWim -like '*.esd') { $wimGB = $wimGB * 2.5 }   # ESD is heavily compressed
    }
    if ($OsIsoPath -and (Test-Path -LiteralPath $OsIsoPath)) { $isoGB = (Get-Item -LiteralPath $OsIsoPath).Length / 1GB }
    $need = $wimGB * 3 + 6
    if ($Options.BuildMedia -or $Options.BuildIso) { $need += $isoGB }
    if ($Options.BuildIso) { $need += $isoGB }
    if ([bool](Get-ProfileValue $Options 'Media2023' $false) -and [bool](Get-ProfileValue $Options 'Boot' $false) -and ($Options.BuildMedia -or $Options.BuildIso)) {
        $need += $isoGB; if ($Options.BuildIso) { $need += $isoGB }   # the CA 2023 media folder and ISO, alongside the standard ones
    }
    $need = [Math]::Max([Math]::Ceiling($need), $Definition.MinFreeGB)
    $free = Get-FreeSpaceGB -Path $Paths.Root
    if ($null -eq $free) { Write-Log 'Free disk space could not be read; skipping the space check.' 'WARN'; return }
    $driveName = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Paths.Root))
    $msg = "Free space on $driveName is $free GB; this run needs about $need GB (profile minimum $($Definition.MinFreeGB) GB)."
    if ($free -ge $need) { Write-Log $msg; return }
    if ($Definition.SpaceCheck -eq 'warn') { Write-Log "$msg Continuing because spaceCheck is 'warn'." 'WARN'; return }
    throw "Not enough free disk space. $msg Free up space, or set spaceCheck to 'warn' or 'off' in the profile file $($Definition.SourceFile)."
}

# ---------- repository ----------
function Get-OsRootPath {
    # The OS folder under the repository root: its folder name, or an accepted alternative name that exists. Creates nothing.
    # [IO.Path]::Combine, not Join-Path: Join-Path throws for a drive that does not exist (the window asks with any root typed).
    param([string]$Root, [pscustomobject]$Definition)
    $leaf = $Definition.Folder
    if (-not (Test-Path -LiteralPath ([System.IO.Path]::Combine($Root, $leaf)))) {
        foreach ($alt in @($Definition.AltFolders)) { if (Test-Path -LiteralPath ([System.IO.Path]::Combine($Root, $alt))) { $leaf = $alt; break } }
    }
    return [System.IO.Path]::Combine($Root, $leaf)
}
function Select-SourceImage {
    # The edition to service on a client OS: by name (EditionRegex), falling back to PreferredIndex, with a WARN when the
    # name matched a different index than preferred. Shared by servicing runs, preflights and reading the app list.
    param([object[]]$Inventory, [pscustomobject]$Definition, [string]$Name)
    $edMatches = @($Inventory | Where-Object { $_.ImageName -match $Definition.EditionRegex })
    if ($edMatches.Count -gt 1) { throw "Edition pattern '$($Definition.EditionRegex)' matched more than one image: $((@($edMatches | ForEach-Object { "[$($_.ImageIndex)] $($_.ImageName)" })) -join '; '). Tighten EditionRegex for '$Name' in OsDefinitions, or set PreferredIndex." }
    $selected = if ($edMatches.Count -eq 1) { $edMatches[0] } else { $Inventory | Where-Object { $_.ImageIndex -eq $Definition.PreferredIndex } | Select-Object -First 1 }
    if (-not $selected) { throw "No edition matched '$($Definition.EditionRegex)' and preferred index $($Definition.PreferredIndex) is unavailable. Images found: $((@($Inventory | ForEach-Object { "[$($_.ImageIndex)] $($_.ImageName)" })) -join '; ')" }
    if ($edMatches.Count -eq 0) { Write-Log "No image name matched '$($Definition.EditionRegex)'; falling back to preferred index $($Definition.PreferredIndex). Check the detected indexes above." 'WARN' }
    elseif ($Definition.PreferredIndex -gt 0 -and $selected.ImageIndex -ne $Definition.PreferredIndex) { Write-Log "The edition name matched index $($selected.ImageIndex), not the profile's preferred index $($Definition.PreferredIndex); using index $($selected.ImageIndex). Check the detected indexes above and correct 'preferredIndex' in the profile if the ISO layout changed." 'WARN' }
    Write-Log "Selected client image index $($selected.ImageIndex): $($selected.ImageName)"
    return $selected
}
function Initialize-Repository {
    param([string]$Root, [pscustomobject]$Definition)
    $osRoot = Get-OsRootPath -Root $Root -Definition $Definition
    $p = @{
        Root = $osRoot; ISO = (Join-Path $osRoot 'ISO'); Patches = (Join-Path $osRoot 'PATCHES')
        OldWim = (Join-Path $osRoot 'OLDWIM'); NewWim = (Join-Path $osRoot 'NEWWIM')
        Working = (Join-Path $osRoot 'WORKING'); Temp = (Join-Path $osRoot 'TEMP')
        Logs = (Join-Path $osRoot 'LOGS'); MainMount = (Join-Path $osRoot 'MOUNT\MainOS')
        WinReMount = (Join-Path $osRoot 'MOUNT\WinRE'); WinPeMount = (Join-Path $osRoot 'MOUNT\WinPE')
        WinRE = (Join-Path $osRoot 'WINRE'); WinPE = (Join-Path $osRoot 'WINPE')
    }
    foreach ($dir in @($p.Values) + @('LCU', 'SSU', 'NETCU', 'SAFEOSDU', 'SETUPDU' | ForEach-Object { Join-Path $p.Patches $_ })) { Ensure-Directory $dir }
    return $p
}

# ---------- SCCM import (TODO step 7) ----------
# A finished run writes NEWWIM\RunResult.json; "Import into SCCM" (SCCM tab) copies that run's install.wim (OS image) or
# media folder (upgrade package) into a sub-folder of the content source folder on this server, creates the OS image /
# upgrade package from its UNC path, and distributes it to a distribution point or group. Decisions (Terry, 2026-09-27):
# a same-named object is never touched - the new one gets " (2)", " (3)", ...; an image whose validation gate FAILED is
# refused; an import is started with the button, or after a run when "Import after the run finishes" is ticked.
# Every call into Configuration Manager goes through the small Sccm* wrappers below, so the test kit can replace them.
$script:SccmNameDateFormat = 'yyyyMM'   # image name = OS name + this date (Terry, 2026-09-21)
$script:RunResultFileName  = 'RunResult.json'
function Get-SccmImageName {
    param([string]$OsName, [datetime]$Date = (Get-Date))
    return "$OsName $($Date.ToString($script:SccmNameDateFormat))"
}
function Get-SccmUniqueName {
    # $Name, or "$Name (2)", "(3)", ... when a same-named object exists (compared case-insensitively). SCCM allows 50 characters.
    param([string]$Name, [string[]]$Existing = @())
    $taken = @($Existing | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
    $candidate = $Name; $n = 1
    while ($taken -contains $candidate.ToLowerInvariant()) { $n++; $candidate = "$Name ($n)" }
    if ($candidate.Length -gt 50) { throw "The image name '$candidate' is $($candidate.Length) characters; Configuration Manager allows 50. Shorten the name on the SCCM tab." }
    return $candidate
}
function Save-RunResult {
    # The record of a finished run that the SCCM import works from (and refuses when its gate FAILED).
    param([hashtable]$Paths, [string]$OsName, [string]$Build, [string]$Gate, [string]$Install, [string]$Media, [string]$ChangeLog)
    $data = [ordered]@{ schemaVersion = 1; finished = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); os = $OsName; build = $Build; gate = $Gate; install = $Install; media = $Media; changeLog = $ChangeLog; toolVersion = $script:ToolVersion }
    $file = [System.IO.Path]::Combine($Paths.NewWim, $script:RunResultFileName)
    [System.IO.File]::WriteAllText($file, (($data | ConvertTo-Json) + [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))
    return $file
}
function Read-RunResult {
    param([string]$NewWim)
    $file = [System.IO.Path]::Combine($NewWim, $script:RunResultFileName)
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try {
        $o = [System.IO.File]::ReadAllText($file) | ConvertFrom-Json -ErrorAction Stop
        return [pscustomobject]@{ File = $file; Finished = [string](Get-ProfileValue $o 'finished' ''); Os = [string](Get-ProfileValue $o 'os' ''); Build = [string](Get-ProfileValue $o 'build' '')
            Gate = [string](Get-ProfileValue $o 'gate' ''); Install = [string](Get-ProfileValue $o 'install' ''); Media = [string](Get-ProfileValue $o 'media' ''); ChangeLog = [string](Get-ProfileValue $o 'changeLog' '') }
    } catch { Write-Log "Run record $file could not be used ($($_.Exception.Message))." 'WARN'; return $null }
}
function Get-ServerShares {
    # This server's ordinary file shares (not the admin shares such as C$ or ADMIN$), as Name / Path.
    return @(Get-SmbShare -ErrorAction Stop | Where-Object { -not $_.Special -and $_.Path -and $_.Name -notmatch '\$$' } | ForEach-Object { [pscustomobject]@{ Name = [string]$_.Name; Path = [string]$_.Path } })
}
function ConvertTo-SccmUncPath {
    # A local folder on this server -> \\<Server>\<share>\<rest>, using the share whose path is the longest that contains
    # the folder. A path that is already UNC is returned as it is. Throws when no share contains the folder.
    param([string]$LocalPath, [string]$Server, [object[]]$Shares = @())
    $p = $LocalPath.TrimEnd('\')
    if ($p.StartsWith('\\')) { return $p }
    $best = $null
    foreach ($s in @($Shares)) {
        $sp = ([string]$s.Path).TrimEnd('\')
        if ((Test-PathUnder $p $sp) -and ($null -eq $best -or $sp.Length -gt ([string]$best.Path).TrimEnd('\').Length)) { $best = $s }
    }
    if (-not $best) { throw "The content source folder $LocalPath is not inside a shared folder on this server, so Configuration Manager cannot reach it. Share it (or a parent folder) and try again." }
    $rest = $p.Substring(([string]$best.Path).TrimEnd('\').Length).TrimStart('\')
    return ('\\' + $Server + '\' + $best.Name + $(if ($rest) { '\' + $rest } else { '' }))
}
function Get-SccmSafeFolderName { param([string]$Name) return (($Name -replace '[\\/:*?"<>|]', '') -replace '\s+', ' ').Trim() }
function Import-SccmModule {
    # The Configuration Manager console's PowerShell module (installed with the console).
    if (Get-Module ConfigurationManager) { return }
    $ui = $env:SMS_ADMIN_UI_PATH
    if (-not $ui) { throw 'The Configuration Manager console is not installed on this machine (SMS_ADMIN_UI_PATH is not set). Install the console, then try again.' }
    $psd = Join-Path (Split-Path $ui -Parent) 'ConfigurationManager.psd1'
    if (-not (Test-Path -LiteralPath $psd)) { throw "The Configuration Manager PowerShell module was not found at $psd." }
    Import-Module $psd -ErrorAction Stop -WarningAction SilentlyContinue
}
function Get-SccmSiteCode {
    param([Parameter(Mandatory)][string]$SiteServer)
    $loc = @(Get-CimInstance -ComputerName $SiteServer -Namespace 'root\SMS' -ClassName SMS_ProviderLocation -ErrorAction Stop | Where-Object { $_.ProviderForLocalSite }) | Select-Object -First 1
    if (-not $loc) { throw "No SMS Provider for a site was found on $SiteServer. Check the site server name." }
    return [string]$loc.SiteCode
}
function Invoke-InSccmSite {
    # Runs $Script on the site drive (<site code>:), which Configuration Manager cmdlets need; file work stays outside it.
    param([Parameter(Mandatory)][string]$SiteCode, [Parameter(Mandatory)][string]$SiteServer, [Parameter(Mandatory)][scriptblock]$Script)
    if (-not (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) { New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SiteServer -ErrorAction Stop | Out-Null }
    Push-Location "$($SiteCode):\"
    try { return (& $Script) } finally { Pop-Location }
}
function Connect-SccmSite {
    # Loads the module, reads the site code and lists the distribution points and groups (the SCCM tab's Connect button).
    param([Parameter(Mandatory)][string]$SiteServer)
    Write-Log "Connecting to Configuration Manager site server $SiteServer"
    # Loading the console's module alone usually takes 20-60 seconds (Terry's first Connect took about a minute), so each
    # step is shown in the status line and the header.
    Set-Phase 'Loading the Configuration Manager module'; Set-Progress 10 'Loading the Configuration Manager module (can take a minute)'
    Import-SccmModule
    Set-Phase 'Reading the site code'; Set-Progress 45 "Reading the site code from $SiteServer"
    $code = Get-SccmSiteCode -SiteServer $SiteServer
    Write-Log "Site code: $code"
    Set-Phase 'Listing distribution points'; Set-Progress 70 "Listing the distribution points and groups of site $code"
    $lists = Invoke-InSccmSite -SiteCode $code -SiteServer $SiteServer -Script {
        [pscustomobject]@{
            DPs    = @(Get-CMDistributionPoint -AllSite | ForEach-Object { ([string]$_.NetworkOSPath).TrimStart('\') } | Where-Object { $_ } | Sort-Object -Unique)
            Groups = @(Get-CMDistributionPointGroup | ForEach-Object { [string]$_.Name } | Where-Object { $_ } | Sort-Object -Unique)
        } }
    Write-Log "Found $(@($lists.DPs).Count) distribution point(s) and $(@($lists.Groups).Count) distribution point group(s)."
    return [pscustomobject]@{ Mode = 'SccmConnect'; SiteServer = $SiteServer; SiteCode = $code; DPs = @($lists.DPs); Groups = @($lists.Groups) }
}
function Invoke-SccmImport {
    # -DryRun: checks everything and returns the plan, changes nothing. Otherwise: copies, imports, distributes.
    param([Parameter(Mandatory)][pscustomobject]$Options, [Parameter(Mandatory)][pscustomobject]$Definition, [Parameter(Mandatory)][hashtable]$Paths, [switch]$DryRun)
    Set-Phase -OsName $Definition.Name -Phase $(if ($DryRun) { 'Checking the SCCM import' } else { 'Importing into SCCM' })
    $siteServer = ([string](Get-ProfileValue $Options 'SccmSiteServer' '')).Trim()
    $target = ([string](Get-ProfileValue $Options 'SccmTarget' '')).Trim()
    $targetIsGroup = ([string](Get-ProfileValue $Options 'SccmTargetType' 'DP')) -eq 'DPGroup'
    $sourceLocal = ([string](Get-ProfileValue $Options 'SccmContentSource' '')).Trim()
    $sourceServer = ([string](Get-ProfileValue $Options 'SccmSourceServer' $env:COMPUTERNAME)).Trim()
    $isUpgrade = ([string](Get-ProfileValue $Options 'SccmPackageType' 'Image')) -eq 'Upgrade'
    $wantedName = ([string](Get-ProfileValue $Options 'SccmImageName' '')).Trim()
    $kind = if ($isUpgrade) { 'OS upgrade package' } else { 'OS image' }
    foreach ($req in @(@('Site server', $siteServer), @('Distribution point or group', $target), @('Content source folder', $sourceLocal), @('Image name', $wantedName))) {
        if (-not $req[1]) { throw "$($req[0]) is empty on the SCCM tab." }
    }
    # 1. The finished run to import: it must exist and must not have FAILED its validation gate.
    $run = Read-RunResult -NewWim $Paths.NewWim
    if (-not $run) { throw "There is no finished run to import in $($Paths.NewWim). Run a servicing run for $($Definition.Name) first." }
    if ($run.Gate -eq 'FAILED') { throw "Refused: the image in $($Paths.NewWim) (build $($run.Build), finished $($run.Finished)) FAILED its validation gate. Fix the cause and run again; a failed image is never imported." }
    if ($run.Gate -ne 'PASSED') { Write-Log "The image in $($Paths.NewWim) was not verified (validation gate: $($run.Gate)); importing it anyway." 'WARN' }
    $content = if ($isUpgrade) { $run.Media } else { $run.Install }
    if (-not $content -or -not (Test-Path -LiteralPath $content)) {
        throw $(if ($isUpgrade) { "An upgrade package needs the refreshed media folder, and the last run did not build one (or it is gone). Tick 'Create refreshed media folder' and run again, or import a Full OS image." } else { "The last run's install.wim ($content) is not there any more. Run again." })
    }
    $sizeGB = if ($isUpgrade) { (@(Get-ChildItem -LiteralPath $content -Recurse -File -Force | Measure-Object -Property Length -Sum).Sum) / 1GB } else { (Get-Item -LiteralPath $content).Length / 1GB }
    # 2. The content source folder: local on this server, reachable by UNC under \\<this server>\.
    if (-not (Test-Path -LiteralPath $sourceLocal)) { throw "The content source folder $sourceLocal does not exist." }
    $sourceUnc = ConvertTo-SccmUncPath -LocalPath $sourceLocal -Server $sourceServer -Shares $(if ($sourceLocal.StartsWith('\\')) { @() } else { @(Get-ServerShares) })
    if (-not $sourceUnc.StartsWith("\\$sourceServer\", [System.StringComparison]::OrdinalIgnoreCase)) { throw "The content source $sourceUnc must be on this server (\\$sourceServer\)." }
    $free = Get-FreeSpaceGB -Path $sourceLocal
    if ($null -ne $free -and $free -lt ($sizeGB * 1.1 + 1)) { throw ("Not enough free space for the copy: {0:N1} GB free in {1}, about {2:N1} GB needed." -f $free, $sourceLocal, ($sizeGB * 1.1 + 1)) }
    # 3. The site: module, site code, existing names, distribution target.
    Import-SccmModule
    $siteCode = Get-SccmSiteCode -SiteServer $siteServer
    $existing = Invoke-InSccmSite -SiteCode $siteCode -SiteServer $siteServer -Script {
        if ($isUpgrade) { @(Get-CMOperatingSystemInstaller -Name "$wantedName*" | ForEach-Object { [string]$_.Name }) } else { @(Get-CMOperatingSystemImage -Name "$wantedName*" | ForEach-Object { [string]$_.Name }) } }
    $name = Get-SccmUniqueName -Name $wantedName -Existing @($existing)
    if ($name -ne $wantedName) { Write-Log "A $kind named '$wantedName' already exists; this one is imported as '$name' (the existing one is not changed)." 'WARN' }
    $folderName = Get-SccmSafeFolderName $name
    $destLocal = Join-Path $sourceLocal $folderName; $n = 1
    while (Test-Path -LiteralPath $destLocal) { $n++; $destLocal = Join-Path $sourceLocal "$folderName ($n)" }
    $destUnc = $sourceUnc + '\' + (Split-Path $destLocal -Leaf)
    $importPath = if ($isUpgrade) { $destUnc } else { $destUnc + '\install.wim' }
    $description = ("WimForge $($script:ToolVersion); build $($run.Build); gate $($run.Gate); change log $(Split-Path $run.ChangeLog -Leaf)")
    if ($description.Length -gt 127) { $description = $description.Substring(0, 127) }
    $plan = [pscustomobject]@{ Mode = 'SccmImport'; DryRun = [bool]$DryRun; Kind = $kind; Name = $name; RequestedName = $wantedName; Build = $run.Build; Gate = $run.Gate; Finished = $run.Finished
        Content = $content; SizeGB = [Math]::Round($sizeGB, 1); DestinationLocal = $destLocal; ImportPath = $importPath; SiteServer = $siteServer; SiteCode = $siteCode
        Target = $target; TargetIsGroup = $targetIsGroup; PackageId = $null; Description = $description }
    Write-Log "SCCM import plan: $kind '$name' from $importPath (copy of $content, $($plan.SizeGB) GB), site $siteCode on $siteServer, distribute to $(if ($targetIsGroup) { 'distribution point group' } else { 'distribution point' }) $target."
    if ($DryRun) { Set-Phase 'Done'; return $plan }
    # 4. Copy (local), import (UNC), distribute.
    Set-Phase 'Copying to the content source'; Set-Progress 20 'Copying to the content source'
    Ensure-Directory $destLocal
    if ($isUpgrade) { Copy-Item -Path (Join-Path $content '*') -Destination $destLocal -Recurse -Force -ErrorAction Stop }
    else { Copy-Item -LiteralPath $content -Destination (Join-Path $destLocal 'install.wim') -Force -ErrorAction Stop }
    Write-Log "Copied $content to $destLocal"
    Assert-NotCancelled
    Set-Phase "Importing the $kind"; Set-Progress 70 "Importing the $kind"
    $pkgId = Invoke-InSccmSite -SiteCode $siteCode -SiteServer $siteServer -Script {
        $obj = if ($isUpgrade) { New-CMOperatingSystemInstaller -Name $name -Path $importPath -Description $description -Version $run.Build -ErrorAction Stop }
               else { New-CMOperatingSystemImage -Name $name -Path $importPath -Description $description -Version $run.Build -ErrorAction Stop }
        [string]$obj.PackageID }
    Write-Log "Imported $kind '$name' as package $pkgId."
    $plan.PackageId = $pkgId
    Set-Phase 'Distributing content'; Set-Progress 85 'Distributing content'
    Invoke-InSccmSite -SiteCode $siteCode -SiteServer $siteServer -Script {
        $dist = @{ ErrorAction = 'Stop' }
        if ($isUpgrade) { $dist['OperatingSystemInstallerId'] = $pkgId } else { $dist['OperatingSystemImageId'] = $pkgId }
        if ($targetIsGroup) { $dist['DistributionPointGroupName'] = $target } else { $dist['DistributionPointName'] = $target }
        Start-CMContentDistribution @dist | Out-Null }
    Write-Log "Content distribution of $pkgId to $target started. The console shows its progress (Monitoring > Distribution Status)."
    Write-Log "SCCM import completed successfully: $kind '$name' ($pkgId)."
    Set-Progress 100 'Imported into SCCM'; Set-Phase 'Done'
    return $plan
}

# ---------- main run ----------
function Invoke-MediaRefresh {
    param([Parameter(Mandatory)][pscustomobject]$Options)
    $script:Cancelled = $false
    $script:LastResult = $null
    $script:OutputArchived = $false
    $script:ChangeEvents = [System.Collections.Generic.List[object]]::new()
    $script:IsoSources = [System.Collections.Generic.List[object]]::new()
    $script:VerifyInventory = [System.Collections.Generic.List[object]]::new()
    $script:VerifyBuildAfter = $null
    $script:BuildBefore = $null
    if ($Options.PSObject.Properties['ProfilesDir'] -and $Options.ProfilesDir) { $script:OsDefinitions = Import-OsProfiles -Directory ([string]$Options.ProfilesDir) }
    if ([string](Get-ProfileValue $Options 'Mode' 'Service') -eq 'Cleanup') {
        # Tools menu > Cleanup Mountpoints: the whole repository root, not one OS. The real pass logs to <root>\LOGS.
        $cleanRoot = ([string]$Options.Root).Trim()
        $dry = [bool](Get-ProfileValue $Options 'DryRun' $true)
        if (-not $dry -and (Test-Path -LiteralPath $cleanRoot)) {
            $cleanLogs = Join-Path $cleanRoot 'LOGS'; Ensure-Directory $cleanLogs
            $script:LogFile = Join-Path $cleanLogs ("MountCleanup_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        }
        return (Invoke-MountCleanup -Root $cleanRoot -DryRun:$dry)
    }
    if ([string](Get-ProfileValue $Options 'Mode' 'Service') -eq 'SccmConnect') {
        $srv = ([string](Get-ProfileValue $Options 'SccmSiteServer' '')).Trim()
        if (-not $srv) { throw 'Enter the site server name on the SCCM tab.' }
        Set-Phase -OsName 'SCCM' -Phase 'Connecting'
        $r = Connect-SccmSite -SiteServer $srv
        Set-Phase 'Done'; $script:LastResult = $r; return $r
    }
    $name = [string]$Options.OsName
    if (-not $name) { throw 'Select an operating system.' }
    $definition = $script:OsDefinitions[$name]
    if (-not $definition) { throw "Unknown OS profile '$name'." }
    if ([string](Get-ProfileValue $Options 'Mode' 'Service') -eq 'SccmImport') {
        $paths = Initialize-Repository -Root $Options.Root.Trim() -Definition $definition
        $dry = [bool](Get-ProfileValue $Options 'DryRun' $true)
        if (-not $dry) { $script:LogFile = Join-Path $paths.Logs ("SccmImport_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss')) }
        Write-Log "WimForge v$($script:ToolVersion): SCCM import for $name$(if ($dry) { ' (check only)' })"
        $r = Invoke-SccmImport -Options $Options -Definition $definition -Paths $paths -DryRun:$dry
        $script:LastResult = $r; return $r
    }
    if ([string](Get-ProfileValue $Options 'Mode' 'Service') -eq 'Download') {
        # Step 5: acquisition-layer run instead of a servicing run. Everything below this branch (mount/service/verify)
        # is untouched and only reached when Mode is absent or 'Service'.
        $paths = Initialize-Repository -Root $Options.Root.Trim() -Definition $definition
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $script:LogFile = Join-Path $paths.Logs ("MediaRefresh_{0}.log" -f $stamp)
        Write-Log "Starting WimForge v$($script:ToolVersion) patch acquisition for $name"
        Write-ProfileMessages
        $result = Invoke-PatchAcquisition -Options $Options -Definition $definition -Paths $paths
        $script:LastResult = $result
        return $result
    }
    Set-Phase -OsName $name -Phase $(if ([string](Get-ProfileValue $Options 'Mode' '') -eq 'Apps') { 'Reading provisioned apps' } elseif ($Options.PreflightOnly) { 'Preflight' } else { 'Starting' })
    $paths = Initialize-Repository -Root $Options.Root.Trim() -Definition $definition
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:LogFile = Join-Path $paths.Logs ("MediaRefresh_{0}.log" -f $stamp)
    $script:DismLogArgs = @{ LogPath = (Join-Path $paths.Logs ("DISM_{0}.log" -f $stamp)) }
    Write-Log "Starting WimForge v$($script:ToolVersion) for $name"
    Write-ProfileMessages
    Write-Log "Profile: $($definition.SourceFile)"
    Write-SupportStatus -Definition $definition
    Write-Log "Repository: $($paths.Root)"
    Write-Log "DISM log: $($script:DismLogArgs['LogPath'])"
    $dl = $script:DismLogArgs
    # The Apps tab's list for this OS (11b): Profiles\Apps\<folder>_Appx.json; without a Profiles folder (scripted use, the
    # test kit) an Apps folder beside the OS folders. A step-11 <OS folder>\ProvisionedApps.json is moved there once.
    $profDir = [string](Get-ProfileValue $Options 'ProfilesDir' '')
    $appListFile = if ($profDir) { Get-AppListPath -ProfilesDir $profDir -Definition $definition } else { [System.IO.Path]::Combine((Split-Path $paths.Root -Parent), 'Apps', "$($definition.Folder)_Appx.json") }
    Move-OldAppInventory -OsRoot $paths.Root -File $appListFile

    try {
        Set-Phase 'Clearing stale mounts'
        Clear-StaleMounts $paths.Root
        Clear-StaleIsoMounts $paths.ISO
        foreach ($d in @($paths.Working, $paths.Temp, $paths.WinRE, $paths.MainMount, $paths.WinReMount, $paths.WinPeMount)) { Remove-DirectoryContents $d }

        $appsOnly = ([string](Get-ProfileValue $Options 'Mode' 'Service') -eq 'Apps')
        if ($appsOnly -and $definition.ServiceAllIndexes) { throw 'App removal is for client editions; Windows Server has no provisioned consumer apps to list.' }
        $removeApps = @(@(Get-ProfileValue $Options 'RemoveApps' @()) | Where-Object { $_ } | ForEach-Object { [string]$_ } | Select-Object -Unique)
        if ($removeApps.Count -gt 0 -and $definition.ServiceAllIndexes) { Write-Log 'App removal is for client editions; the ticked apps are ignored for this Windows Server profile.' 'WARN'; $removeApps = @() }
        $languages = @(if (-not $appsOnly) { $Options.Languages | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() } })
        $hasLang = ($languages.Count -gt 0)
        Write-Log ('Languages: ' + $(if ($hasLang) { $languages -join ', ' } else { '(none - English only)' }))
        $doMedia = [bool]$Options.BuildMedia -or [bool]$Options.BuildIso
        $doBoot = [bool]$Options.Boot -and $doMedia
        if ([bool]$Options.Boot -and -not $doMedia) { Write-Log 'Patch boot.wim is ticked, but no media folder or ISO is being built; boot.wim is patched only for the media, so it is skipped.' }
        elseif ($doMedia) { Write-Log $(if ($doBoot) { 'Media: boot.wim (WinPE and Setup) is patched, and setup.exe and the boot manager files on the media are refreshed from it.' } else { 'Media: boot.wim is left as on the ISO (Patch boot.wim is not ticked).' }) }
        $want2023 = [bool](Get-ProfileValue $Options 'Media2023' $false)
        $do2023 = $want2023 -and $doBoot
        if ($want2023 -and -not $doBoot) { Write-Log 'CA 2023 media is ticked, but it needs the media and Patch boot.wim (its boot files come from the patched boot.wim); it is skipped.' 'WARN' }
        elseif ($do2023) { Write-Log "CA 2023 media: built alongside the standard media in NEWWIM\Media_CA2023$(if ($Options.BuildIso) { ', with its own ISO' }), boot manager signed by Windows UEFI CA 2023." }
        $enabled = @{ LCU = [bool]$Options.LCU; SSU = [bool]$Options.SSU; NetCU = [bool]$Options.NetCU; SafeOS = [bool]$Options.SafeOS; SetupDU = [bool]$Options.SetupDU }
        $lcuComing = $false
        if (-not $appsOnly) {
            # Step 14 (Terry, 2026-09-27): "Download the latest patches before the run" - the catalog check and a download
            # of only what is missing, before the patch folders are read. Unticked, the run uses PATCHES as it is.
            if ([bool](Get-ProfileValue $Options 'AutoDownload' $false)) {
                $acqOpts = [pscustomobject]@{ OsName = $name; Root = $Options.Root; Mode = 'Download'; DryRun = [bool]$Options.PreflightOnly
                    LCU = $enabled.LCU; NetCU = $enabled.NetCU; SafeOS = $enabled.SafeOS; SetupDU = $enabled.SetupDU }
                Set-Phase $(if ($Options.PreflightOnly) { 'Checking for new patches' } else { 'Downloading the latest patches' })
                try {
                    $acq = Invoke-PatchAcquisition -Options $acqOpts -Definition $definition -Paths $paths
                    if ($Options.PreflightOnly) {
                        $toGet = @(@($acq.Plan) | Where-Object { -not $_.Present })
                        $lcuComing = @($toGet | Where-Object { $_.Class -eq 'LCU' }).Count -gt 0
                        Write-Log $(if ($toGet.Count -eq 0) { 'Latest patches: PATCHES is up to date; the run will download nothing.' } else { "Latest patches: the run will first download $($toGet.Count) catalog entr$(if ($toGet.Count -eq 1) { 'y' } else { 'ies' }): $(($toGet | ForEach-Object { "$($_.Class) $($_.Kb)" }) -join ', ')." })
                    }
                } catch {
                    Write-Log "The latest patches could not be $(if ($Options.PreflightOnly) { 'checked' } else { 'downloaded' }) ($($_.Exception.Message)); $(if ($Options.PreflightOnly) { 'the run will try again' } else { 'this run uses the patches already in the folders' })." 'WARN'
                }
                Set-Phase -OsName $name -Phase $(if ($Options.PreflightOnly) { 'Preflight' } else { 'Starting' })
            } else { Write-Log 'Patches: the ones already in PATCHES are used (Download the latest patches before the run is not ticked).' }
            $packages = Get-PackageSet -PatchRoot $paths.Patches -Enabled $enabled -Order $definition.PackageOrder
            $checkEnabled = $enabled.Clone()
            if ($lcuComing -and @($packages.LCU).Count -eq 0) {
                # A preflight with an empty PATCHES\LCU is fine when the run downloads the LCU first.
                Write-Log 'PATCHES\LCU is empty now; the run downloads the LCU before servicing.'
                $checkEnabled.LCU = $false
            }
            Test-PackageSet -Definition $definition -Packages $packages -Enabled $checkEnabled -DoWinRe ([bool]$Options.WinRE) -BuildMedia ([bool]$Options.BuildMedia)
        }

        # ISO discovery by content
        Set-Phase 'Mounting ISOs'
        Set-Progress 3 'Mounting source media'
        $isoFiles = @(Get-ChildItem -LiteralPath $paths.ISO -Filter '*.iso' -File)
        if ($isoFiles.Count -eq 0) { throw "No ISO files found in $($paths.ISO)." }
        if ($appsOnly) {
            # Apps tab > Read apps from the ISO needs only the OS ISO (Terry, 2026-09-27: "at least a few minutes"). The full
            # role detection below searches the Language Pack and FOD ISOs file by file, so here each ISO is mounted in turn
            # until the one with sources\install.wim (or .esd) is found; any other ISO is dismounted again at once.
            Set-Phase 'Finding the OS ISO'; Set-Progress 10 'Finding the OS ISO'
            $osDrive = $null; $osIsoFile = $null; $osIsoPath = $null
            foreach ($f in $isoFiles) {
                $drv = Mount-IsoFile $f.FullName
                if ((Test-Path -LiteralPath (Join-Chain $drv @('sources', 'install.wim'))) -or (Test-Path -LiteralPath (Join-Chain $drv @('sources', 'install.esd')))) { $osDrive = $drv; $osIsoFile = $f.Name; $osIsoPath = $f.FullName; break }
                try { Dismount-DiskImage -ImagePath $f.FullName -ErrorAction Stop | Out-Null } catch { }
                [void]$script:MountedIsoPaths.Remove($f.FullName)
                Write-Log "$($f.Name) is not the OS ISO; dismounted again."
            }
            if (-not $osDrive) { throw "No OS ISO (one with sources\install.wim or install.esd) was found in $($paths.ISO)." }
            Write-Log "OS ISO: $osIsoFile"
            $sourceWim = if (Test-Path -LiteralPath (Join-Chain $osDrive @('sources', 'install.wim'))) { Join-Chain $osDrive @('sources', 'install.wim') } else { Join-Chain $osDrive @('sources', 'install.esd') }
            $inventory = @(Get-WindowsImage -ImagePath $sourceWim)
            Write-Log ('Detected indexes: ' + (($inventory | ForEach-Object { "[$($_.ImageIndex)] $($_.ImageName)" }) -join '; '))
            $selected = Select-SourceImage -Inventory $inventory -Definition $definition -Name $name
            $appsRead = @(Update-AppInventoryFromIso -Paths $paths -SourceWim $sourceWim -Selected $selected -IsoPath $osIsoPath -File $appListFile)
            Set-Progress 100 'App list read'; Set-Phase 'Done'
            $script:LastResult = [pscustomobject]@{ Mode = 'Apps'; Count = $appsRead.Count; Source = $osIsoFile; Index = [int]$selected.ImageIndex; ImageName = $selected.ImageName; File = $appListFile }
            return $script:LastResult
        }
        $mounted = @()
        foreach ($f in $isoFiles) { $mounted += [pscustomobject]@{ Path = $f.FullName; Drive = (Mount-IsoFile $f.FullName) } }
        $roles = Get-IsoRoleMap $mounted
        Write-Log "ISO roles - OS: $($roles.OsDrive)  LanguagePack: $($roles.LpDrive)  FOD: $(@($roles.FodDrives) -join ', ')"
        foreach ($u in $roles.Unclassified) { Write-Log "ISO not recognised as OS, Language Pack or FOD (ignored): $u" 'WARN' }
        $osDrive = $roles.OsDrive
        if ([bool]$Options.NetFx3 -and -not $appsOnly) {
            # .NET Framework 3.5 always comes from the OS ISO's own sources\sxs (never Windows Update: -LimitAccess), for
            # every OS; checked here so a missing source stops the run before any image is touched.
            $sxsCheck = Join-Chain $osDrive @('sources', 'sxs')
            if (-not (Test-Path -LiteralPath $sxsCheck)) { throw ".NET Framework 3.5 is ticked, but the OS ISO has no sources\sxs folder ($sxsCheck), which is where its files come from. Use a complete Microsoft OS ISO, or untick .NET Framework 3.5." }
            Write-Log ".NET Framework 3.5 source: $sxsCheck (the OS ISO)"
        }
        $fodSource = @(Get-FodSource $roles.FodDrives)
        $driveToFile = @{}
        foreach ($m in $mounted) { $driveToFile[$m.Drive] = (Split-Path $m.Path -Leaf) }
        $script:IsoSources.Add([pscustomobject]@{ Role = 'OS'; File = $driveToFile[$osDrive] })
        if ($roles.LpDrive) { $script:IsoSources.Add([pscustomobject]@{ Role = 'Language Pack'; File = $driveToFile[$roles.LpDrive] }) }
        foreach ($fd in @($roles.FodDrives)) { $script:IsoSources.Add([pscustomobject]@{ Role = 'FOD'; File = $driveToFile[$fd] }) }

        $lpFiles = @{}
        if ($hasLang) {
            if (-not $roles.LpDrive) { throw "Languages are selected but no Language Pack ISO (containing $($definition.LpPattern -f '<lang>')) is in $($paths.ISO)." }
            if (@($roles.FodDrives).Count -eq 0) { throw "Languages are selected but no Features on Demand ISO is in $($paths.ISO); language features and fonts need it. Add it or untick the languages." }
            $lpFiles = Resolve-LanguagePacks -LpRoot $roles.LpDrive -Pattern $definition.LpPattern -Languages $languages
            Write-Log "All $($languages.Count) language packs located."
            if ([bool]$Options.WinRE -or $doBoot) { Write-Log 'Languages are added to install.wim only; WinRE and boot.wim stay English-only.' }
        }

        $sourceWim = if (Test-Path -LiteralPath (Join-Chain $osDrive @('sources', 'install.wim'))) { Join-Chain $osDrive @('sources', 'install.wim') } else { Join-Chain $osDrive @('sources', 'install.esd') }
        $inventory = @(Get-WindowsImage -ImagePath $sourceWim)
        Write-Log ('Detected indexes: ' + (($inventory | ForEach-Object { "[$($_.ImageIndex)] $($_.ImageName)" }) -join '; '))
        $selected = $null
        if (-not $definition.ServiceAllIndexes) { $selected = Select-SourceImage -Inventory $inventory -Definition $definition -Name $name }
        else { Write-Log "All $($inventory.Count) indexes will be serviced and recombined." }
        $osIsoPath = @($mounted | Where-Object { $_.Drive -eq $osDrive } | Select-Object -First 1 | ForEach-Object { $_.Path })[0]
        $osIsoFile = $driveToFile[$osDrive]
        Test-FreeSpace -Definition $definition -Paths $paths -SourceWim $sourceWim -OsIsoPath $osIsoPath -Options $Options
        if ($selected) {
            # The Apps tab's list (11b): one scan per OS. A preflight reads it when there is none yet, or when the OS ISO is not
            # the one it was read from (name, size or date: a new ISO may add or remove apps) or the index differs. A real run
            # never writes it - it only says when the list is out of date (removal matches the mounted image anyway).
            $appInv = Read-AppInventory -File $appListFile
            $isCurrent = Test-AppInventoryCurrent -Inventory $appInv -Iso (Get-IsoIdentity $osIsoPath) -Index ([int]$selected.ImageIndex)
            if ($Options.PreflightOnly -and -not $isCurrent) {
                Set-Phase 'Reading provisioned apps'
                Write-Log $(if ($appInv) { "The app list was read from $($appInv.Source) (index $($appInv.Index)); the OS ISO is now $osIsoFile, which may add or remove apps, so index $($selected.ImageIndex) is read again." } else { 'No app list yet for this OS; reading it for the Apps tab.' })
                # Not fatal: a preflight checks the run's inputs; the app list is a convenience for the Apps tab.
                try { [void](Update-AppInventoryFromIso -Paths $paths -SourceWim $sourceWim -Selected $selected -IsoPath $osIsoPath -File $appListFile) }
                catch { Write-Log "The app list could not be read ($($_.Exception.Message)); use Read apps from the ISO on the Apps tab." 'WARN' }
                $appInv = Read-AppInventory -File $appListFile
            } elseif (-not $Options.PreflightOnly -and -not $isCurrent -and $removeApps.Count -gt 0) {
                Write-Log "The Apps tab's list is $(if ($appInv) { "from $($appInv.Source), not the current OS ISO $osIsoFile" } else { 'missing' }); this run removes the ticked apps it finds in the image. A preflight or Read apps from the ISO brings the list up to date." 'WARN'
            }
            if ($removeApps.Count -gt 0) {
                Write-Log "App removal: $($removeApps.Count) app(s) ticked: $($removeApps -join ', ')"
                if ($appInv) {
                    $absent = @($removeApps | Where-Object { $n = $_; @($appInv.Apps | Where-Object { $_.DisplayName -eq $n }).Count -eq 0 })
                    if ($absent.Count -gt 0) { Write-Log "App removal: not in this image's app list (skipped when the run gets there): $($absent -join ', ')" 'WARN' }
                }
            }
        }
        if ($Options.PreflightOnly) {
            Set-Progress 100 'Preflight passed'
            Set-Phase 'Done'
            Write-Log 'PREFLIGHT OK: ISO roles, patch folders, language packs, edition selection and free space all check out. No image was changed.'
            $script:LastResult = [pscustomobject]@{ NewWim = $paths.NewWim; Install = $null; Boot = $null; Media = $null; VerifyIssues = $null; Preflight = $true; Gate = 'Skipped'; ChangeLogHtml = $null; ChangeLogCsv = $null }
            return
        }
        Set-Phase 'Exporting image'
        $old = Join-Path $paths.OldWim 'install.wim'; Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue
        if ($definition.ServiceAllIndexes) {
            foreach ($img in $inventory) { Export-WindowsImage -SourceImagePath $sourceWim -SourceIndex $img.ImageIndex -DestinationImagePath $old -DestinationName $img.ImageName -CompressionType Max -CheckIntegrity @dl -ErrorAction Stop | Out-Null }
        } else {
            Export-WindowsImage -SourceImagePath $sourceWim -SourceIndex $selected.ImageIndex -DestinationImagePath $old -DestinationName $selected.ImageName -CompressionType Max -CheckIntegrity @dl -ErrorAction Stop | Out-Null
        }
        $first = Get-WindowsImage -ImagePath $old -Index (@(Get-WindowsImage -ImagePath $old)[0].ImageIndex)
        Test-DismHostVersion -ImageVersion $first.Version
        $script:BuildBefore = [string]$first.Version

        $workingInstall = Join-Path $paths.Working 'install.working.wim'; Copy-Item -LiteralPath $old -Destination $workingInstall -Force
        $finalInstall = $null; $finalBoot = $null; $verifyIssues = $null; $mediaFolder = $null; $gate = 'Skipped'
        $iso = $null; $media2023 = $null; $iso2023 = $null; $media2023Error = $null
        if ($Options.Install) {
            $workImages = @(Get-WindowsImage -ImagePath $workingInstall)
            $n = 0
            foreach ($img in $workImages) {
                $n++
                $indexLabel = if ($workImages.Count -gt 1) { "index $($img.ImageIndex) of $($workImages.Count)" } else { "index $($img.ImageIndex)" }
                Set-Progress (15 + [int](45 * $n / $workImages.Count)) "Servicing install.wim $indexLabel"
                Set-Phase "Servicing install.wim ($indexLabel)"
                Service-InstallIndex -ImagePath $workingInstall -Index $img.ImageIndex -Paths $paths -Packages $packages -OsDrive $osDrive `
                    -LpFiles $lpFiles -FodSource $fodSource -Languages $languages -DoWinRe ([bool]$Options.WinRE) -DoNetFx3 ([bool]$Options.NetFx3) `
                    -RemoveApps $removeApps
            }
            Backup-PreviousOutput -Paths $paths -Stamp $stamp -Keep $definition.KeepArchives
            $finalInstall = Join-Path $paths.NewWim 'install.wim'
            Set-Phase 'Exporting install.wim'
            Set-Progress 65 'Optimizing final install.wim'
            Export-OptimizedWim $workingInstall $finalInstall
            $finalCount = @(Get-WindowsImage -ImagePath $finalInstall).Count
            if ((-not $definition.ServiceAllIndexes) -and $finalCount -ne 1) { throw "Client output validation failed: expected one index, found $finalCount." }
            Write-Log "Import-ready install.wim created: $finalInstall ($finalCount index(es))"
            if ($Options.Verify) {
                Set-Phase 'Verifying image'
                Set-Progress 68 'Verifying final install.wim'
                $verifyIssues = Test-OutputWim -WimPath $finalInstall -Paths $paths -Languages $languages -ExpectLcu $enabled.LCU -RemovedApps $removeApps
                $gate = if ($verifyIssues -eq 0) { 'PASSED' } else { 'FAILED' }
                if ($gate -eq 'FAILED') { Write-Log "VALIDATION GATE: FAILED ($verifyIssues issue(s)). Review the VERIFY lines above before importing this image into SCCM." 'ERROR' }
                else { Write-Log 'VALIDATION GATE: PASSED.' }
            } else {
                Write-Log 'Verify was not selected, so the validation gate and the change log Section B (final-state inventory) are not available for this run.' 'WARN'
            }
        }

        $bootFiles = $null
        if ($doMedia -and -not $finalInstall) { throw 'Refreshed media requires Create updated install.wim.' }
        if ($doBoot) {
            # boot.wim is patched only for the refreshed media / ISO (Terry, 2026-09-27): SCCM task sequences and upgrade
            # packages never use the OS media's boot.wim, so there is no separate NEWWIM\boot.wim any more.
            $sourceBoot = Join-Chain $osDrive @('sources', 'boot.wim')
            if (-not (Test-Path -LiteralPath $sourceBoot)) { throw "boot.wim not found at $sourceBoot" }
            Set-Phase 'Servicing boot.wim'
            Set-Progress 75 'Servicing boot.wim'
            $finalBoot = Join-Path $paths.Working 'boot.serviced.wim'
            $bootFiles = Service-BootWim -SourceBoot $sourceBoot -Destination $finalBoot -Paths $paths -Packages $packages -Save2023:$do2023
            Write-Log "Patched boot.wim ready for the media: $finalBoot"
        }
        if ($doMedia) {
            Set-Phase 'Building refreshed media folder'
            Set-Progress 88 'Building refreshed media folder'
            Backup-PreviousOutput -Paths $paths -Stamp $stamp -Keep $definition.KeepArchives
            $mediaFolder = New-RefreshedMedia -OsDrive $osDrive -Paths $paths -InstallWim $finalInstall -BootWim $finalBoot -SetupDu $packages.SetupDU -BootFiles $bootFiles
            if ($doBoot) { $finalBoot = Join-Chain $mediaFolder @('sources', 'boot.wim') }
            if ($do2023) {
                # Not fatal: the standard media and install.wim are already good, so a CA 2023 problem is reported, not thrown.
                Set-Phase 'Building CA 2023 media'; Set-Progress 91 'Building CA 2023 media'
                try { $media2023 = New-Media2023 -MediaFolder $mediaFolder -ExFiles (Join-Path $bootFiles 'CA2023') -Paths $paths }
                catch { $media2023 = $null; $media2023Error = $_.Exception.Message; Write-Log "CA 2023 media was not created: $media2023Error" 'ERROR' }
            }
            if ($Options.BuildIso) {
                Set-Phase 'Building ISO'; Set-Progress 94 'Building ISO'
                $iso = Build-IsoFromMedia -MediaFolder $mediaFolder -Paths $paths
                if ($media2023) { Set-Phase 'Building CA 2023 ISO'; $iso2023 = Build-IsoFromMedia -MediaFolder $media2023 -Paths $paths -EfiBootFile 'efisys_ex.bin' -NamePrefix 'UpdatedMedia_CA2023' }
            }
        }
        $changeLogPaths = $null
        if ($Options.Install) {
            Set-Phase 'Writing change log'
            $changeLogPaths = Write-ChangeLog -OsName $name -Paths $paths -Stamp $stamp -ToolVersion $script:ToolVersion -BuildBefore $script:BuildBefore -BuildAfter $script:VerifyBuildAfter `
                -Languages $languages -ServiceAllIndexes $definition.ServiceAllIndexes -Selected $selected -IsoSources @($script:IsoSources) -Events @($script:ChangeEvents) `
                -Inventory @($script:VerifyInventory) -VerifyIssues $verifyIssues -Gate $gate -VerifyRan ([bool]$Options.Verify)
            if ($changeLogPaths) {
                foreach ($f in @($changeLogPaths.Html, $changeLogPaths.Csv)) { Copy-Item -LiteralPath $f -Destination $paths.NewWim -Force -ErrorAction SilentlyContinue }
            }
            # The record the SCCM import works from (step 7): what this run produced and whether it passed.
            $runBuild = if ($script:VerifyBuildAfter) { $script:VerifyBuildAfter } else { $script:BuildBefore }
            [void](Save-RunResult -Paths $paths -OsName $name -Build $runBuild -Gate $gate -Install $finalInstall -Media $mediaFolder -ChangeLog $(if ($changeLogPaths) { $changeLogPaths.Html } else { '' }))
        }
        Set-Progress 100 'Completed successfully'
        Set-Phase 'Done'
        if ($null -ne $verifyIssues -and $verifyIssues -gt 0) { Write-Log "Media refresh finished, but verification reported $verifyIssues issue(s). Review the VERIFY lines above." 'WARN' }
        else { Write-Log 'Media refresh completed successfully.' }
        $script:LastResult = [pscustomobject]@{
            NewWim = $paths.NewWim; Install = $finalInstall; Boot = $finalBoot; Media = $mediaFolder; VerifyIssues = $verifyIssues; Preflight = $false
            Iso = $iso; Media2023 = $media2023; Iso2023 = $iso2023; Media2023Error = $media2023Error
            Gate = $gate; ChangeLogHtml = $(if ($changeLogPaths) { $changeLogPaths.Html } else { $null }); ChangeLogCsv = $(if ($changeLogPaths) { $changeLogPaths.Csv } else { $null })
        }
    } finally { Dismount-AllIso }
}

# ---------- run config files and the command line (Terry, 2026-09-28) ----------
# Tools > Save run config... writes everything the window would pass to a run into one JSON file; the script then runs
# the same session without a window:  MediaRefresh_v2.4.ps1 -Config <file> [-Preflight]. The option names are the saved-
# settings names ($script:SettingOptionNames); a missing option takes the window's default (below - a test keeps the two
# in step), missing languages take the profile's default languages; an unknown OS, language, key or a non-true/false
# option is an error, so a misspelling never quietly changes a run. Foundation for the scheduled run (TODO step 8).
$script:OptionDefaults = [ordered]@{
    Preflight = $false; Install = $true; Boot = $true; WinRE = $true; Verify = $true; BuildMedia = $false; BuildIso = $false; Media2023 = $false
    SSU = $true; LCU = $true; SafeOS = $true; NetCU = $true; SetupDU = $true; NetFx3 = $false; AppRemoval = $true; SccmAutoImport = $false; AutoDownload = $false
}
$script:RunConfigSccmKeys = @('siteServer', 'targetType', 'target', 'contentSource', 'sourceServer', 'packageType', 'imageName')
function Save-RunConfig {
    param([Parameter(Mandatory)][string]$File, [Parameter(Mandatory)][string]$OsName, [string]$Root, [hashtable]$Options = @{}, [string[]]$Languages = @(), [string[]]$RemoveApps = @(), [hashtable]$Sccm = @{})
    $opts = [ordered]@{}
    foreach ($k in $script:SettingOptionNames) { $opts[$k] = $(if ($Options.ContainsKey($k)) { [bool]$Options[$k] } else { [bool]$script:OptionDefaults[$k] }) }
    $sc = [ordered]@{}; foreach ($k in $script:RunConfigSccmKeys) { $sc[$k] = [string]$Sccm[$k] }
    $data = [ordered]@{
        schemaVersion = 1; tool = 'WimForge'; toolVersion = $script:ToolVersion; saved = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        os = $OsName; root = $Root; options = $opts
        languages = @($Languages | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() })
        removeApps = @($RemoveApps | Where-Object { $_ } | ForEach-Object { [string]$_ }); sccm = $sc
    }
    Ensure-Directory (Split-Path $File -Parent)
    [System.IO.File]::WriteAllText($File, (($data | ConvertTo-Json -Depth 5) + [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))
    return $File
}
function Read-RunConfig {
    # Reads and checks a run config; throws one message listing every problem found.
    param([Parameter(Mandatory)][string]$File, [Parameter(Mandatory)]$Definitions, [object[]]$LanguageList = @())
    if (-not (Test-Path -LiteralPath $File)) { throw "The run config $File does not exist." }
    try { $o = [System.IO.File]::ReadAllText($File) | ConvertFrom-Json -ErrorAction Stop } catch { throw "The run config $File is not valid JSON: $($_.Exception.Message)" }
    $problems = [System.Collections.Generic.List[string]]::new()
    $known = @('schemaVersion', 'tool', 'toolVersion', 'saved', 'os', 'root', 'options', 'languages', 'removeApps', 'sccm', 'note')
    foreach ($p in @($o.PSObject.Properties.Name)) { if ($known -notcontains $p) { $problems.Add("unknown setting '$p'") } }
    $schema = [int](Get-ProfileValue $o 'schemaVersion' 1); if ($schema -gt 1) { $problems.Add("schemaVersion $schema is newer than this version of WimForge understands (1)") }
    $os = [string](Get-ProfileValue $o 'os' '')
    if (-not $os) { $problems.Add("'os' is missing") } elseif (-not $Definitions.Contains($os)) { $problems.Add("'os' is '$os', which is not one of the profiles: $(@($Definitions.Keys) -join ', ')") }
    $root = [string](Get-ProfileValue $o 'root' ''); if (-not $root) { $problems.Add("'root' (the repository root) is missing") }
    $opts = @{}
    foreach ($k in $script:SettingOptionNames) { $opts[$k] = [bool]$script:OptionDefaults[$k] }
    $oo = Get-ProfileValue $o 'options' $null
    if ($null -ne $oo) {
        foreach ($p in @($oo.PSObject.Properties)) {
            $name = @($script:SettingOptionNames | Where-Object { $_ -ieq $p.Name }) | Select-Object -First 1
            if (-not $name) { $problems.Add("unknown option '$($p.Name)' (known: $($script:SettingOptionNames -join ', '))"); continue }
            if ($p.Value -isnot [bool]) { $problems.Add("option '$($p.Name)' must be true or false"); continue }
            $opts[$name] = $p.Value
        }
    }
    $langsGiven = $null -ne $o.PSObject.Properties['languages']
    $langs = @(@(Get-ProfileValue $o 'languages' @()) | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() })
    if ($LanguageList.Count -gt 0) {
        $codes = @($LanguageList | ForEach-Object { $_.Code })
        foreach ($l in $langs) { if ($codes -notcontains $l) { $problems.Add("language '$l' is not in Languages.json") } }
    }
    $sccm = @{}
    $so = Get-ProfileValue $o 'sccm' $null
    if ($null -ne $so) { foreach ($p in @($so.PSObject.Properties)) { if ($script:RunConfigSccmKeys -notcontains $p.Name) { $problems.Add("unknown sccm setting '$($p.Name)'") } else { $sccm[$p.Name] = [string]$p.Value } } }
    if ($problems.Count -gt 0) { throw "The run config $File has $($problems.Count) problem(s): $($problems -join '; ')." }
    return [pscustomobject]@{ File = $File; OsName = $os; Root = $root; Options = $opts; LanguagesGiven = $langsGiven; Languages = $langs
        RemoveApps = @(@(Get-ProfileValue $o 'removeApps' @()) | Where-Object { $_ } | ForEach-Object { [string]$_ }); Sccm = $sccm }
}
function ConvertTo-RunOptions {
    # A read run config -> the options object a run takes (the same shape the window builds in Get-UiOptions).
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)]$Definition, [string]$ProfilesDir, [switch]$PreflightOnly)
    $o = $Config.Options
    $langs = if ($Config.LanguagesGiven) { @($Config.Languages) } else { @($Definition.DefaultLanguages | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() }) }
    $s = $Config.Sccm
    return [pscustomobject]@{
        OsName = $Config.OsName; Root = $Config.Root; PreflightOnly = ([bool]$PreflightOnly -or [bool]$o.Preflight)
        Install = [bool]$o.Install; Boot = [bool]$o.Boot; WinRE = [bool]$o.WinRE; Verify = [bool]$o.Verify
        BuildMedia = [bool]$o.BuildMedia; BuildIso = ([bool]$o.BuildIso -and [bool]$o.BuildMedia); Media2023 = [bool]$o.Media2023
        SSU = [bool]$o.SSU; LCU = [bool]$o.LCU; SafeOS = [bool]$o.SafeOS; NetCU = [bool]$o.NetCU; SetupDU = [bool]$o.SetupDU; NetFx3 = [bool]$o.NetFx3; AutoDownload = [bool]$o.AutoDownload
        Languages = $langs; RemoveApps = $(if ([bool]$o.AppRemoval) { @($Config.RemoveApps) } else { @() })
        SccmSiteServer = [string]$s['siteServer']; SccmTargetType = $(if ([string]$s['targetType']) { [string]$s['targetType'] } else { 'DP' }); SccmTarget = [string]$s['target']
        SccmContentSource = [string]$s['contentSource']; SccmSourceServer = $(if ([string]$s['sourceServer']) { [string]$s['sourceServer'] } else { $env:COMPUTERNAME })
        SccmPackageType = $(if ([string]$s['packageType']) { [string]$s['packageType'] } else { 'Image' }); SccmImageName = $(if ([string]$s['imageName']) { [string]$s['imageName'] } else { Get-SccmImageName -OsName $Config.OsName })
        ProfilesDir = $ProfilesDir
    }
}
function Invoke-CommandLineRun {
    # MediaRefresh_v2.4.ps1 -Config <file> [-Preflight]: the run without a window. Returns the exit code: 0 success,
    # 1 failed (including a bad config), 2 finished but the validation gate FAILED, 3 run fine but the SCCM import failed.
    param([Parameter(Mandatory)][string]$ConfigFile, [Parameter(Mandatory)][string]$ProfilesDir, [switch]$PreflightOnly)
    try {
        $script:OsDefinitions = Import-OsProfiles -Directory $ProfilesDir
        Write-ProfileMessages
        $cfg = Read-RunConfig -File $ConfigFile -Definitions $script:OsDefinitions -LanguageList @(Import-LanguageList -Directory $ProfilesDir)
        $opts = ConvertTo-RunOptions -Config $cfg -Definition $script:OsDefinitions[$cfg.OsName] -ProfilesDir $ProfilesDir -PreflightOnly:$PreflightOnly
        Write-Log "Command line run from $ConfigFile$(if ($opts.PreflightOnly) { ' (preflight only)' })"
        Invoke-MediaRefresh -Options $opts | Out-Null
        $res = $script:LastResult
    } catch {
        Write-Log $_.Exception.Message 'ERROR'
        Dismount-AllIso
        return 1
    }
    if ([bool](Get-ProfileValue $res 'Preflight' $false)) { return 0 }
    $gate = [string](Get-ProfileValue $res 'Gate' '')
    if ($gate -eq 'FAILED') {
        if ([bool]$cfg.Options.SccmAutoImport) { Write-Log 'The validation gate FAILED, so the image is not imported into SCCM.' 'WARN' }
        return 2
    }
    if ([bool]$cfg.Options.SccmAutoImport -and (Get-ProfileValue $res 'Install' $null)) {
        Write-Log 'Importing into SCCM (the config asks for it; no confirmation in a command line run).'
        $imp = $opts.PSObject.Copy()
        $imp | Add-Member -NotePropertyName Mode -NotePropertyValue 'SccmImport' -Force
        $imp | Add-Member -NotePropertyName DryRun -NotePropertyValue $false -Force
        try { Invoke-MediaRefresh -Options $imp | Out-Null } catch { Write-Log "SCCM import failed: $($_.Exception.Message)" 'ERROR'; return 3 }
    }
    return 0
}
#endregion ENGINE
# Command line (-Config): run without the window and exit with the run's exit code.
if ($Config) {
    $cliProfiles = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'Profiles' } else { Join-Path $env:LOCALAPPDATA 'MediaRefreshStudio\Profiles' }
    $cliConfig = if ([System.IO.Path]::IsPathRooted($Config)) { $Config } else { Join-Path (Get-Location).Path $Config }
    $cliCode = @(Invoke-CommandLineRun -ConfigFile $cliConfig -ProfilesDir $cliProfiles -PreflightOnly:$Preflight)
    Write-Host "WimForge exit code: $($cliCode[-1])"
    exit ([int]$cliCode[-1])
}

#region GUI
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="WimForge v2.4" Height="780" Width="1040" WindowStartupLocation="CenterScreen" Background="{DynamicResource WF.WindowBg}" Foreground="{DynamicResource WF.Text}">
 <Grid Margin="18"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <Grid Grid.Row="0" Margin="0,0,0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
   <Button x:Name="ToolsButton" Grid.Column="2" Content="Tools &#x25BE;" Margin="16,0,0,0" Padding="12,5" VerticalAlignment="Center" ToolTip="Maintenance tools">
    <Button.ContextMenu><ContextMenu><MenuItem x:Name="CleanupMountsItem" Header="Cleanup Mountpoints..." ToolTip="Find images and ISOs still mounted under the repository root (for example after a crash), show them, and after confirmation discard / dismount them. Nothing outside the repository root is touched."/><Separator/><MenuItem x:Name="SaveRunConfigItem" Header="Save run config..." ToolTip="Saves every choice for the selected OS (outputs, updates, languages, apps, SCCM) to a JSON file for a run without the window: MediaRefresh_v2.4.ps1 -Config &lt;file&gt; [-Preflight]"/></ContextMenu></Button.ContextMenu>
   </Button>
   <StackPanel Grid.Column="0"><TextBlock Text="WimForge" FontSize="25" FontWeight="SemiBold" Foreground="{DynamicResource WF.Title}"/><TextBlock Text="Create cleaned, optimized, verified install.wim files, with optional refreshed media and ISO." TextWrapping="Wrap" Foreground="{DynamicResource WF.SubtleText}" Margin="0,4,0,0"/></StackPanel>
   <StackPanel Grid.Column="1" HorizontalAlignment="Right" VerticalAlignment="Center" MinWidth="220"><TextBlock x:Name="HeaderOs" Text="" FontSize="16" FontWeight="SemiBold" TextAlignment="Right" HorizontalAlignment="Right"/><TextBlock x:Name="HeaderPhase" Text="Idle" FontSize="13" Foreground="{DynamicResource WF.SubtleText}" TextAlignment="Right" HorizontalAlignment="Right" Margin="0,2,0,0"/></StackPanel>
  </Grid>
  <TabControl Grid.Row="1">
   <TabItem Header="Source and Targets"><Grid Margin="18"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions><Grid.ColumnDefinitions><ColumnDefinition Width="220"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <TextBlock Grid.Row="0" Grid.Column="0" Text="Repository root" Margin="0,8"/><TextBox x:Name="RootText" Grid.Row="0" Grid.Column="1" Text="F:\mediaRefresh" Height="30" Padding="6"/>
    <TextBlock Grid.Row="1" Grid.Column="0" Text="Operating system" Margin="0,14,0,8"/><StackPanel Grid.Row="1" Grid.Column="1" Margin="0,8"><DockPanel><Button x:Name="ReloadProfilesButton" DockPanel.Dock="Right" Content="Reload profiles" Margin="8,0,0,0" Padding="12,0" ToolTip="Re-read the JSON files in the Profiles folder"/><Button x:Name="AcquirePatchesButton" DockPanel.Dock="Right" Content="Download patches..." Margin="8,0,0,0" Padding="12,0" ToolTip="Search the Microsoft Update Catalog (MSCatalogLTS) for the selected OS. Shows a dry-run preview first and requires confirmation; never touches PATCHES\SSU."/><ComboBox x:Name="OsCombo" Height="32"/></DockPanel><TextBlock x:Name="ProfileInfo" Margin="2,6,0,0" Foreground="{DynamicResource WF.SubtleText}" TextWrapping="Wrap"/></StackPanel>
    <GroupBox Grid.Row="2" Grid.ColumnSpan="2" Header="Outputs" Margin="0,14,0,0"><StackPanel Margin="12"><CheckBox x:Name="ChkPreflight" Content="Preflight check only (about a minute: checks ISOs, patch folders, language packs and edition; changes nothing)" IsChecked="False" Margin="0,3"/><CheckBox x:Name="ChkInstall" Content="Create updated install.wim" IsChecked="True" Margin="0,3"/><CheckBox x:Name="ChkWinRE" Content="Service embedded WinRE (once, reused for every index)" IsChecked="True" Margin="0,3"/><CheckBox x:Name="ChkVerify" Content="Verify the final install.wim (read-only mount, logs RollupFix, language packs, fonts)" IsChecked="True" Margin="0,3"/><CheckBox x:Name="ChkBuildMedia" Content="Create refreshed media folder (NEWWIM\Media) for an OS Upgrade Package, a bootable USB or the ISO" IsChecked="False" Margin="0,3"/><CheckBox x:Name="ChkBuildIso" Content="Also build an ISO from that media (requires Windows ADK Oscdimg)" IsChecked="False" IsEnabled="False" Margin="22,3,0,3" ToolTip="Available when the media folder is created"/><CheckBox x:Name="ChkBoot" Content="Patch boot.wim (WinPE and Setup) for booting the media / ISO / USB directly - not used by SCCM task sequences or upgrade packages" IsChecked="True" IsEnabled="False" Margin="22,3,0,3" ToolTip="Adds the SSU and LCU to both boot.wim images on the media and copies setup.exe, setuphost.exe and the boot manager files from the patched Setup image onto the media, as Microsoft's media steps require. Available when the media folder is created."/><CheckBox x:Name="ChkMedia2023" Content="Also build CA 2023 media alongside it (NEWWIM\Media_CA2023 and a _CA2023 ISO): boot manager signed by 'Windows UEFI CA 2023'" IsChecked="False" IsEnabled="False" Margin="44,3,0,3" ToolTip="A second copy of the media whose boot files (boot manager, UEFI boot image, boot fonts) are the 'Windows UEFI CA 2023' signed ones from the patched boot.wim, as Microsoft's Make2023BootableMedia.ps1 does. It boots only on PCs whose firmware trusts Windows UEFI CA 2023; the standard media is still built for the others. Needs Patch boot.wim and a 2024-04 or later LCU."/></StackPanel></GroupBox>
    <TextBlock Grid.Row="3" Grid.ColumnSpan="2" Margin="0,18" TextWrapping="Wrap" Foreground="{DynamicResource WF.SubtleText}" Text="ISO roles (OS, Language Pack, Features on Demand) are detected from ISO content, so file names do not matter. Keep one ISO per role in the ISO folder. Client operating systems export a single index; Windows Server 2022 preserves and services every index."/>
   </Grid></TabItem>
   <TabItem Header="Updates and Features"><Grid Margin="18"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <GroupBox Grid.Column="0" Header="Patch selection" Margin="0,0,10,0"><StackPanel Margin="12"><CheckBox x:Name="ChkAutoDownload" IsChecked="False" Margin="0,0,0,10" ToolTip="Ticked: the run first searches the Microsoft Update Catalog (like Download patches...) and downloads only the ticked updates that are not in PATCHES yet. Unticked: the run uses the patches already in the folders. PATCHES\SSU is always placed by hand."><TextBlock TextWrapping="Wrap" Text="Download the latest patches before the run (only what is missing). Unticked: use the patches already in the folders."/></CheckBox><CheckBox x:Name="ChkSSU" Content="Servicing Stack Update (PATCHES\SSU)" IsChecked="True" Margin="0,5"/><CheckBox x:Name="ChkLCU" Content="Latest Cumulative Update (PATCHES\LCU)" IsChecked="True" Margin="0,5"/><CheckBox x:Name="ChkSafeOS" Content="Safe OS Dynamic Update (PATCHES\SAFEOSDU, used for WinRE)" IsChecked="True" Margin="0,5"/><CheckBox x:Name="ChkNetCU" Content=".NET Cumulative Update (PATCHES\NETCU)" IsChecked="True" Margin="0,5"/><CheckBox x:Name="ChkSetupDU" Content="Setup Dynamic Update (PATCHES\SETUPDU, used for refreshed media)" IsChecked="True" Margin="0,5"/></StackPanel></GroupBox>
    <GroupBox Grid.Column="1" Header="Optional content" Margin="10,0,0,0"><StackPanel Margin="12"><CheckBox x:Name="ChkNetFx3" Content="Enable .NET Framework 3.5 from OS ISO sources\sxs" IsChecked="False" Margin="0,5"/><TextBlock Text="Ticked patch types with an empty folder are logged and skipped, except LCU (and the SSU on legacy OSes), which stop the run so you never get an unpatched image by accident." TextWrapping="Wrap" Foreground="{DynamicResource WF.SubtleText}" Margin="0,16,0,0"/></StackPanel></GroupBox>
   </Grid></TabItem>
   <TabItem Header="Languages"><Grid Margin="18"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions><TextBlock Text="Language packs, language features and fonts to add to install.wim (WinRE and boot.wim stay English-only). Requires a Language Pack ISO and a Features on Demand ISO. Leave empty for English only. Defaults follow the selected operating system. The list comes from Profiles\Languages.json." TextWrapping="Wrap"/><ListBox x:Name="LanguageList" Grid.Row="1" SelectionMode="Multiple" Margin="0,12,0,0"/></Grid></TabItem>
   <TabItem Header="Apps"><Grid Margin="18"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <TextBlock TextWrapping="Wrap" Text="Provisioned apps in the selected operating system's edition. Ticked apps are removed from install.wim as the first servicing step, before WinRE, updates and languages. The list is read from the edition in the OS's ISO folder: with Read apps from the ISO, by a preflight when there is no list yet or the ISO has changed, and again by every run. Ticks are saved by app name with Save settings, so they carry over to newer ISOs."/>
    <DockPanel Grid.Row="1" Margin="0,12,0,0"><Button x:Name="ReadAppsButton" DockPanel.Dock="Right" Content="Read apps from the ISO" Padding="12,3" ToolTip="Mounts the selected edition from the OS ISO read-only (about a minute) and lists its provisioned apps. Changes nothing."/><CheckBox x:Name="ChkAppRemoval" Content="Remove the ticked apps" IsChecked="True" VerticalAlignment="Center"/></DockPanel>
    <TextBlock x:Name="AppsSource" Grid.Row="2" Margin="0,8,0,0" TextWrapping="Wrap" Foreground="{DynamicResource WF.SubtleText}"/>
    <ListBox x:Name="AppList" Grid.Row="3" SelectionMode="Multiple" Margin="0,8,0,0"/>
   </Grid></TabItem>
   <TabItem Header="SCCM"><ScrollViewer VerticalScrollBarVisibility="Auto"><Grid Margin="18">
    <Grid.ColumnDefinitions><ColumnDefinition Width="190"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Grid.ColumnSpan="2" TextWrapping="Wrap" Margin="0,0,0,14" Text="Imports the latest finished run of the selected operating system into Configuration Manager: copies it into a new sub-folder of the content source folder on this server, creates the OS image (or OS upgrade package) from that folder's UNC path, and distributes it. An image whose validation gate FAILED is never imported; an existing image with the same name is never changed (the new one gets a number). Needs the Configuration Manager console on this machine."/>
    <TextBlock Grid.Row="1" Text="Site server" VerticalAlignment="Center"/>
    <DockPanel Grid.Row="1" Grid.Column="1"><Button x:Name="SccmConnectButton" DockPanel.Dock="Right" Content="Connect" Margin="8,0,0,0" Padding="14,3" ToolTip="Checks the console module and the site, reads the site code and lists the distribution points and groups"/><TextBox x:Name="SccmSiteServer" Height="28" Padding="4"/></DockPanel>
    <TextBlock x:Name="SccmSiteInfo" Grid.Row="2" Grid.Column="1" Margin="0,4,0,10" TextWrapping="Wrap" Foreground="{DynamicResource WF.SubtleText}" Text="Not connected. Connect reads the site code and lists the distribution points and groups."/>
    <TextBlock Grid.Row="3" Text="Distribute to" VerticalAlignment="Top" Margin="0,4,0,0"/>
    <StackPanel Grid.Row="3" Grid.Column="1"><StackPanel Orientation="Horizontal"><RadioButton x:Name="SccmTargetDP" Content="Distribution point" IsChecked="True" Margin="0,0,18,0"/><RadioButton x:Name="SccmTargetGroup" Content="Distribution point group"/></StackPanel>
     <DockPanel Margin="0,6,0,0"><ComboBox x:Name="SccmTargetList" DockPanel.Dock="Right" Width="230" Height="28" Margin="8,0,0,0" ToolTip="Filled by Connect; picking one copies it into the box"/><TextBox x:Name="SccmTarget" Height="28" Padding="4" ToolTip="Distribution point server name (FQDN) or distribution point group name"/></DockPanel></StackPanel>
    <TextBlock Grid.Row="4" Text="Content source folder" VerticalAlignment="Center" Margin="0,14,0,0"/>
    <DockPanel Grid.Row="4" Grid.Column="1" Margin="0,14,0,0"><Button x:Name="SccmBrowseButton" DockPanel.Dock="Right" Content="Browse..." Margin="8,0,0,0" Padding="14,3"/><TextBox x:Name="SccmContentSource" Height="28" Padding="4" ToolTip="A folder on this server inside a shared folder; each import creates a sub-folder named after the image"/></DockPanel>
    <TextBlock x:Name="SccmUncPreview" Grid.Row="5" Grid.Column="1" Margin="0,4,0,10" TextWrapping="Wrap" Foreground="{DynamicResource WF.SubtleText}"/>
    <TextBlock Grid.Row="6" Text="Image name" VerticalAlignment="Center"/>
    <DockPanel Grid.Row="6" Grid.Column="1"><Button x:Name="SccmNameResetButton" DockPanel.Dock="Right" Content="Reset" Margin="8,0,0,0" Padding="14,3" ToolTip="Back to the OS name with the month (yyyyMM)"/><TextBox x:Name="SccmImageName" Height="28" Padding="4" MaxLength="50"/></DockPanel>
    <TextBlock Grid.Row="7" Text="Package type" VerticalAlignment="Center" Margin="0,12,0,0"/>
    <ComboBox x:Name="SccmPackageType" Grid.Row="7" Grid.Column="1" Width="260" Height="28" HorizontalAlignment="Left" Margin="0,12,0,0"><ComboBoxItem Content="Full OS image" Tag="Image" IsSelected="True"/><ComboBoxItem Content="Upgrade package (needs the media folder)" Tag="Upgrade"/></ComboBox>
    <CheckBox x:Name="ChkSccmAutoImport" Grid.Row="8" Grid.Column="1" Margin="0,14,0,0" IsChecked="False" Content="Import after the run finishes (no confirmation; only when the run succeeds and its validation gate did not fail)"/>
    <StackPanel Grid.Row="9" Grid.Column="1" Margin="0,14,0,0"><Button x:Name="SccmImportButton" Content="Import into SCCM..." HorizontalAlignment="Left" Padding="16,5" ToolTip="Checks everything first and shows what it will do; nothing changes until you confirm"/><TextBlock x:Name="SccmLastRun" Margin="0,8,0,0" TextWrapping="Wrap" Foreground="{DynamicResource WF.SubtleText}"/></StackPanel>
   </Grid></ScrollViewer></TabItem>
   <TabItem Header="Log"><RichTextBox x:Name="LogBox" Margin="12" IsReadOnly="True" VerticalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="12" Background="{DynamicResource WF.LogBg}" Foreground="{DynamicResource WF.LogText}"><FlowDocument PagePadding="4"><Paragraph Margin="0"/></FlowDocument></RichTextBox></TabItem>
   <TabItem Header="Instructions"><Grid Margin="12"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <DockPanel Margin="0,0,0,8"><Button x:Name="ReloadInstructionsButton" DockPanel.Dock="Right" Content="Reload" Padding="14,3" ToolTip="Read INSTRUCTIONS.md again, for example after editing it"/><TextBlock x:Name="InstructionsSource" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" Foreground="{DynamicResource WF.SubtleText}"/></DockPanel>
    <FlowDocumentScrollViewer x:Name="InstructionsViewer" Grid.Row="1" VerticalScrollBarVisibility="Auto" IsToolBarVisible="False"/>
   </Grid></TabItem>
   <TabItem Header="General Settings"><StackPanel Margin="18"><GroupBox Header="Color scheme"><StackPanel Margin="12">
    <DockPanel><TextBlock Text="Scheme" Width="120" VerticalAlignment="Center"/><ComboBox x:Name="ColorSchemeCombo" Height="30" Width="300" HorizontalAlignment="Left"/></DockPanel>
    <TextBlock Text="Applies straight away and is remembered for the next start (Settings\General.json)." Foreground="{DynamicResource WF.SubtleText}" Margin="120,6,0,0" TextWrapping="Wrap"/>
    <TextBlock Text="Palette" Margin="0,14,0,4"/><WrapPanel x:Name="SchemeSwatches"/>
    <TextBlock Text="Log preview" Margin="0,14,0,4"/>
    <Border Background="{DynamicResource WF.LogBg}" Padding="8" HorizontalAlignment="Left" MinWidth="460"><StackPanel>
     <TextBlock FontFamily="Consolas" FontSize="12" Foreground="{DynamicResource WF.LogText}" Text="10:15:02 [INFO] Adding LCU windows10.0-kb5129236-x64.msu to install.wim index 1"/>
     <TextBlock FontFamily="Consolas" FontSize="12" Foreground="{DynamicResource WF.LogSuccess}" Text="10:58:40 [INFO] VALIDATION GATE: PASSED"/>
     <TextBlock FontFamily="Consolas" FontSize="12" Foreground="{DynamicResource WF.LogWarn}" Text="10:31:12 [WARN] Skipped .NET CU part: not applicable to this image"/>
     <TextBlock FontFamily="Consolas" FontSize="12" Foreground="{DynamicResource WF.LogError}" Text="10:32:05 [ERROR] Add-WindowsPackage failed (0x800f0922)"/>
    </StackPanel></Border>
   </StackPanel></GroupBox></StackPanel></TabItem>
  </TabControl>
  <Grid Grid.Row="2" Margin="0,14,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel><TextBlock x:Name="Status" Text="Ready"/><ProgressBar x:Name="Progress" Height="18" Minimum="0" Maximum="100" Margin="0,5,14,0"/></StackPanel><Button x:Name="SaveSettingsButton" Grid.Column="1" Content="Save settings" Width="110" Height="38" Margin="0,0,8,0" ToolTip="Save the ticked options and languages for the selected operating system (Settings folder beside Profiles). They are loaded whenever this OS is selected."/><Button x:Name="ResetSettingsButton" Grid.Column="2" Content="Reset to defaults" Width="120" Height="38" Margin="0,0,14,0" ToolTip="Delete the saved settings for the selected operating system and go back to the defaults."/><Button x:Name="RunButton" Grid.Column="3" Content="Start refresh" Width="130" Height="38" Margin="0,0,8,0" Background="{DynamicResource WF.Accent}" Foreground="{DynamicResource WF.AccentText}" FontWeight="SemiBold"/><Button x:Name="CancelButton" Grid.Column="4" Content="Cancel" Width="90" Height="38" IsEnabled="False"/></Grid>
 </Grid>
</Window>
'@
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
foreach ($ctl in @('HeaderOs','HeaderPhase','RootText','OsCombo','ReloadProfilesButton','AcquirePatchesButton','ProfileInfo','ChkPreflight','ChkInstall','ChkBoot','ChkWinRE','ChkVerify','ChkBuildMedia','ChkBuildIso','ChkMedia2023','ChkAutoDownload','ChkSSU','ChkLCU','ChkSafeOS','ChkNetCU','ChkSetupDU','ChkNetFx3','LanguageList','LogBox','ColorSchemeCombo','SchemeSwatches','Status','Progress','RunButton','CancelButton','SaveSettingsButton','ResetSettingsButton','ToolsButton','CleanupMountsItem','SaveRunConfigItem','ReloadInstructionsButton','InstructionsSource','InstructionsViewer','ReadAppsButton','ChkAppRemoval','AppsSource','AppList','SccmSiteServer','SccmConnectButton','SccmSiteInfo','SccmTargetDP','SccmTargetGroup','SccmTargetList','SccmTarget','SccmContentSource','SccmBrowseButton','SccmUncPreview','SccmImageName','SccmNameResetButton','SccmPackageType','ChkSccmAutoImport','SccmImportButton','SccmLastRun')) {
    Set-Variable -Name $ctl -Value $window.FindName($ctl) -Scope Script
}
# Profiles: JSON files in a Profiles folder beside the script (or under LOCALAPPDATA when the script has no file path).
$script:ProfilesDir = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'Profiles' } else { Join-Path $env:LOCALAPPDATA 'MediaRefreshStudio\Profiles' }
# Saved GUI choices (step 10c): Settings\<OS folder>.json per OS and Settings\General.json, beside Profiles.
$script:SettingsDir = Join-Path (Split-Path $script:ProfilesDir -Parent) 'Settings'

# ---- Colour schemes (General Settings tab) ----
# Every colour in the window comes from a WF.<role> brush (DynamicResource), so a scheme is applied by swapping the
# window's merged resource dictionaries. The Default scheme sets only the brushes and keeps the standard Windows
# controls; the dark schemes also add the styles below, because the standard ComboBox, TabItem, Button and ListBoxItem
# templates ignore most colour settings.
$script:ThemedStyleXaml = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
 <Style TargetType="TextBox"><Setter Property="Background" Value="{DynamicResource WF.ControlBg}"/><Setter Property="Foreground" Value="{DynamicResource WF.Text}"/><Setter Property="BorderBrush" Value="{DynamicResource WF.Border}"/><Setter Property="CaretBrush" Value="{DynamicResource WF.Text}"/><Setter Property="SelectionBrush" Value="{DynamicResource WF.Accent}"/></Style>
 <Style TargetType="RichTextBox"><Setter Property="BorderBrush" Value="{DynamicResource WF.Border}"/><Setter Property="SelectionBrush" Value="{DynamicResource WF.Accent}"/></Style>
 <Style TargetType="GroupBox"><Setter Property="BorderBrush" Value="{DynamicResource WF.Border}"/><Setter Property="Foreground" Value="{DynamicResource WF.Text}"/><Setter Property="Template"><Setter.Value>
  <ControlTemplate TargetType="GroupBox"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
   <Border Grid.RowSpan="2" Margin="0,9,0,0" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="3"/>
   <Border Margin="8,0,0,0" Padding="4,0" HorizontalAlignment="Left" Background="{DynamicResource WF.PanelBg}"><ContentPresenter ContentSource="Header" TextElement.Foreground="{DynamicResource WF.Title}"/></Border>
   <ContentPresenter Grid.Row="1" Margin="{TemplateBinding Padding}"/></Grid></ControlTemplate>
 </Setter.Value></Setter></Style>
 <Style TargetType="CheckBox"><Setter Property="Foreground" Value="{DynamicResource WF.Text}"/><Setter Property="Template"><Setter.Value>
  <ControlTemplate TargetType="CheckBox"><StackPanel Orientation="Horizontal" Background="Transparent">
    <Border x:Name="Box" Width="16" Height="16" VerticalAlignment="Center" Background="{DynamicResource WF.ControlBg}" BorderBrush="{DynamicResource WF.SubtleText}" BorderThickness="1" CornerRadius="2"><Path x:Name="Mark" Data="M3,8 L6.5,11.5 L13,4.5" Stroke="{DynamicResource WF.AccentText}" StrokeThickness="2" Visibility="Collapsed"/></Border>
    <ContentPresenter Margin="6,0,0,0" VerticalAlignment="Center"/></StackPanel>
   <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Box" Property="BorderBrush" Value="{DynamicResource WF.Accent}"/></Trigger>
    <Trigger Property="IsChecked" Value="True"><Setter TargetName="Box" Property="Background" Value="{DynamicResource WF.Accent}"/><Setter TargetName="Box" Property="BorderBrush" Value="{DynamicResource WF.Accent}"/><Setter TargetName="Mark" Property="Visibility" Value="Visible"/></Trigger>
    <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger></ControlTemplate.Triggers></ControlTemplate>
 </Setter.Value></Setter></Style>
 <Style TargetType="RadioButton"><Setter Property="Foreground" Value="{DynamicResource WF.Text}"/><Setter Property="Template"><Setter.Value>
  <ControlTemplate TargetType="RadioButton"><StackPanel Orientation="Horizontal" Background="Transparent">
    <Grid Width="16" Height="16" VerticalAlignment="Center"><Ellipse x:Name="Ring" Fill="{DynamicResource WF.ControlBg}" Stroke="{DynamicResource WF.SubtleText}" StrokeThickness="1"/><Ellipse x:Name="Dot" Width="8" Height="8" Fill="{DynamicResource WF.Accent}" Visibility="Collapsed"/></Grid>
    <ContentPresenter Margin="6,0,0,0" VerticalAlignment="Center"/></StackPanel>
   <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Ring" Property="Stroke" Value="{DynamicResource WF.Accent}"/></Trigger>
    <Trigger Property="IsChecked" Value="True"><Setter TargetName="Ring" Property="Stroke" Value="{DynamicResource WF.Accent}"/><Setter TargetName="Dot" Property="Visibility" Value="Visible"/></Trigger>
    <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger></ControlTemplate.Triggers></ControlTemplate>
 </Setter.Value></Setter></Style>
 <Style TargetType="ProgressBar"><Setter Property="Background" Value="{DynamicResource WF.ControlBg}"/><Setter Property="Foreground" Value="{DynamicResource WF.Accent}"/><Setter Property="BorderBrush" Value="{DynamicResource WF.Border}"/></Style>
 <Style TargetType="ListBox"><Setter Property="Background" Value="{DynamicResource WF.ControlBg}"/><Setter Property="Foreground" Value="{DynamicResource WF.Text}"/><Setter Property="BorderBrush" Value="{DynamicResource WF.Border}"/></Style>
 <Style TargetType="ListBoxItem"><Setter Property="Foreground" Value="{DynamicResource WF.Text}"/><Setter Property="Padding" Value="6,3"/><Setter Property="Template"><Setter.Value>
  <ControlTemplate TargetType="ListBoxItem"><Border x:Name="Bd" Background="Transparent" Padding="{TemplateBinding Padding}"><ContentPresenter/></Border>
   <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource WF.Hover}"/></Trigger>
    <Trigger Property="IsSelected" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource WF.SelectionBg}"/><Setter Property="Foreground" Value="{DynamicResource WF.SelectionText}"/></Trigger></ControlTemplate.Triggers></ControlTemplate>
 </Setter.Value></Setter></Style>
 <Style TargetType="ComboBoxItem"><Setter Property="Foreground" Value="{DynamicResource WF.Text}"/><Setter Property="Padding" Value="8,4"/><Setter Property="Template"><Setter.Value>
  <ControlTemplate TargetType="ComboBoxItem"><Border x:Name="Bd" Background="Transparent" Padding="{TemplateBinding Padding}"><ContentPresenter/></Border>
   <ControlTemplate.Triggers><Trigger Property="IsSelected" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource WF.SelectionBg}"/><Setter Property="Foreground" Value="{DynamicResource WF.SelectionText}"/></Trigger>
    <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource WF.Hover}"/><Setter Property="Foreground" Value="{DynamicResource WF.Text}"/></Trigger></ControlTemplate.Triggers></ControlTemplate>
 </Setter.Value></Setter></Style>
 <Style TargetType="ComboBox"><Setter Property="Foreground" Value="{DynamicResource WF.Text}"/><Setter Property="Template"><Setter.Value>
  <ControlTemplate TargetType="ComboBox"><Grid>
   <ToggleButton Focusable="False" ClickMode="Press" IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"><ToggleButton.Template><ControlTemplate TargetType="ToggleButton">
    <Border x:Name="Bd" Background="{DynamicResource WF.ControlBg}" BorderBrush="{DynamicResource WF.Border}" BorderThickness="1" CornerRadius="2"><Path HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,10,0" Data="M0,0 L4,4 L8,0 Z" Fill="{DynamicResource WF.Text}"/></Border>
    <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource WF.Accent}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></ToggleButton.Template></ToggleButton>
   <ContentPresenter IsHitTestVisible="False" Margin="8,0,28,0" VerticalAlignment="Center" HorizontalAlignment="Left" Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"/>
   <Popup IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True" Focusable="False">
    <Border Background="{DynamicResource WF.ControlBg}" BorderBrush="{DynamicResource WF.Border}" BorderThickness="1" MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}" MaxHeight="{TemplateBinding MaxDropDownHeight}"><ScrollViewer><ItemsPresenter/></ScrollViewer></Border></Popup>
  </Grid></ControlTemplate>
 </Setter.Value></Setter></Style>
 <Style TargetType="Button"><Setter Property="Background" Value="{DynamicResource WF.ButtonBg}"/><Setter Property="Foreground" Value="{DynamicResource WF.ButtonText}"/><Setter Property="BorderBrush" Value="{DynamicResource WF.Border}"/><Setter Property="Template"><Setter.Value>
  <ControlTemplate TargetType="Button"><Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="3" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
   <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource WF.Text}"/></Trigger>
    <Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.8"/></Trigger>
    <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.45"/></Trigger></ControlTemplate.Triggers></ControlTemplate>
 </Setter.Value></Setter></Style>
 <Style TargetType="ContextMenu"><Setter Property="Background" Value="{DynamicResource WF.ControlBg}"/><Setter Property="Foreground" Value="{DynamicResource WF.Text}"/><Setter Property="BorderBrush" Value="{DynamicResource WF.Border}"/></Style>
 <Style TargetType="MenuItem"><Setter Property="Foreground" Value="{DynamicResource WF.Text}"/></Style>
 <Style TargetType="TabControl"><Setter Property="Background" Value="{DynamicResource WF.PanelBg}"/><Setter Property="BorderBrush" Value="{DynamicResource WF.Border}"/><Setter Property="Foreground" Value="{DynamicResource WF.Text}"/></Style>
 <!-- The header colour is set on the header presenter only: the tab's page content inherits the TabItem's Foreground. -->
 <Style TargetType="TabItem"><Setter Property="Foreground" Value="{DynamicResource WF.Text}"/><Setter Property="Template"><Setter.Value>
  <ControlTemplate TargetType="TabItem"><Border x:Name="Bd" Background="{DynamicResource WF.TabBg}" BorderBrush="{DynamicResource WF.Border}" BorderThickness="1,1,1,0" Margin="0,0,2,0" Padding="12,6">
    <Grid><Border x:Name="Bar" Height="2" VerticalAlignment="Top" Margin="-12,-6,-12,0" Background="Transparent"/><ContentPresenter x:Name="Hdr" ContentSource="Header" HorizontalAlignment="Center" TextElement.Foreground="{DynamicResource WF.SubtleText}"/></Grid></Border>
   <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Hdr" Property="TextElement.Foreground" Value="{DynamicResource WF.Text}"/></Trigger>
    <Trigger Property="IsSelected" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource WF.PanelBg}"/><Setter TargetName="Bar" Property="Background" Value="{DynamicResource WF.Accent}"/><Setter TargetName="Hdr" Property="TextElement.Foreground" Value="{DynamicResource WF.TabSelectedText}"/><Setter Property="Panel.ZIndex" Value="1"/></Trigger></ControlTemplate.Triggers></ControlTemplate>
 </Setter.Value></Setter></Style>
</ResourceDictionary>
'@
$script:ColorSchemes = Get-ColorSchemes
$script:ColorSchemeName = ''
$script:ThemedStyles = $null   # parsed from ThemedStyleXaml on first use
function New-SchemeBrush([string]$Hex) {
    $b = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($Hex)); $b.Freeze(); return $b
}
function Set-TitleBarDark {
    # Dark or light window title bar to match the scheme (Windows 10 20H1+ / 11); silently does nothing elsewhere.
    param([bool]$Dark)
    try {
        if (-not ('WimForge.NativeDwm' -as [type])) { Add-Type -Namespace WimForge -Name NativeDwm -MemberDefinition '[System.Runtime.InteropServices.DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int value, int size);' }
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper $window).Handle
        if ($hwnd -eq [IntPtr]::Zero) { return }
        $v = [int]$Dark
        if ([WimForge.NativeDwm]::DwmSetWindowAttribute($hwnd, 20, [ref]$v, 4) -ne 0) { [void][WimForge.NativeDwm]::DwmSetWindowAttribute($hwnd, 19, [ref]$v, 4) }
    } catch { }
}
function Set-ColorScheme {
    # Applies a scheme from Get-ColorSchemes to the window (unknown names fall back to Default) and shows its palette.
    param([string]$Name)
    if (-not $script:ColorSchemes.Contains($Name)) { $Name = 'Default' }
    $scheme = $script:ColorSchemes[$Name]
    $brushes = New-Object System.Windows.ResourceDictionary
    # The cast unwraps PowerShell's PSObject wrapper; WPF rejects a wrapped brush as a resource value.
    foreach ($role in $scheme.Colors.Keys) { $brushes["WF.$role"] = [System.Windows.Media.SolidColorBrush](New-SchemeBrush $scheme.Colors[$role]) }
    $window.Resources.MergedDictionaries.Clear()
    $window.Resources.MergedDictionaries.Add($brushes)
    if ($scheme.Dark) {
        if (-not $script:ThemedStyles) { $script:ThemedStyles = [Windows.Markup.XamlReader]::Parse($script:ThemedStyleXaml) }
        $window.Resources.MergedDictionaries.Add($script:ThemedStyles)
    }
    if ($script:SchemeSwatches) {
        $script:SchemeSwatches.Children.Clear()
        foreach ($entry in $scheme.Palette) {
            $hex = ($entry -split ' ')[-1]
            $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '0,0,14,6'; $sp.Width = 110
            $sw = New-Object System.Windows.Controls.Border; $sw.Height = 26; $sw.BorderThickness = 1; $sw.Background = New-SchemeBrush $hex
            $sw.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'WF.SubtleText')
            $tb = New-Object System.Windows.Controls.TextBlock; $tb.Text = $entry.Substring(0, $entry.Length - $hex.Length).Trim() + "`n" + $hex; $tb.FontSize = 11; $tb.Margin = '0,3,0,0'
            [void]$sp.Children.Add($sw); [void]$sp.Children.Add($tb); [void]$script:SchemeSwatches.Children.Add($sp)
        }
    }
    Set-TitleBarDark ([bool]$scheme.Dark)
    $script:ColorSchemeName = $Name
    return $Name
}
function Add-LogText {
    # Appends text to the Log tab, one line per log line, coloured by Get-LogLineKind with the scheme's log colours.
    param([string]$Text)
    $para = $script:LogBox.Document.Blocks.FirstBlock
    foreach ($ln in ($Text -split '\r?\n')) {
        if ($ln -eq '') { continue }
        $run = New-Object System.Windows.Documents.Run $ln
        $key = switch (Get-LogLineKind $ln) { 'Error' { 'WF.LogError' } 'Warn' { 'WF.LogWarn' } 'Success' { 'WF.LogSuccess' } default { $null } }
        if ($key) { $run.SetResourceReference([System.Windows.Documents.TextElement]::ForegroundProperty, $key) }
        $para.Inlines.Add($run); $para.Inlines.Add((New-Object System.Windows.Documents.LineBreak))
    }
    $script:LogBox.ScrollToEnd()
}
$savedScheme = Read-ColorSchemeSetting -Directory $script:SettingsDir
[void](Set-ColorScheme $savedScheme)
foreach ($n in $script:ColorSchemes.Keys) { [void]$script:ColorSchemeCombo.Items.Add($n) }
$script:ColorSchemeCombo.SelectedItem = $script:ColorSchemeName
if ($savedScheme -and $savedScheme -ne $script:ColorSchemeName) { Write-Log "Saved color scheme '$savedScheme' is not known; using Default." 'WARN' }
$script:ColorSchemeCombo.Add_SelectionChanged({
    $name = [string]$script:ColorSchemeCombo.SelectedItem
    if (-not $name -or $name -eq $script:ColorSchemeName) { return }
    [void](Set-ColorScheme $name)
    try { Save-GeneralSettings -Directory $script:SettingsDir -ColorScheme $name; Write-Log "Color scheme: $name (saved to Settings\General.json)." }
    catch { Write-Log "Color scheme $name applied, but it could not be saved: $($_.Exception.Message)" 'WARN' }
})
$window.Add_SourceInitialized({ Set-TitleBarDark ([bool]$script:ColorSchemes[$script:ColorSchemeName].Dark) })

# ---- Instructions tab (TODO 10b): INSTRUCTIONS.md beside the script, shown as a formatted document ----
# ConvertFrom-MarkdownBlocks / Split-MarkdownInline (engine region) parse it; the colours are WF.* brushes, so the
# document follows the colour scheme like the rest of the window.
$script:InstructionsPath = Join-Path (Split-Path $script:ProfilesDir -Parent) 'INSTRUCTIONS.md'
function Add-MarkdownInlines {
    param($Inlines, [string]$Text)
    foreach ($r in @(Split-MarkdownInline $Text)) {
        $run = New-Object System.Windows.Documents.Run $r.Text
        switch ($r.Kind) {
            'Bold'   { $run.FontWeight = [System.Windows.FontWeights]::SemiBold }
            'Italic' { $run.FontStyle = [System.Windows.FontStyles]::Italic }
            'Code'   { $run.FontFamily = New-Object System.Windows.Media.FontFamily 'Consolas'; $run.SetResourceReference([System.Windows.Documents.TextElement]::BackgroundProperty, 'WF.CodeBg') }
        }
        if ($r.Kind -eq 'Link') {
            $link = New-Object System.Windows.Documents.Hyperlink $run
            $link.SetResourceReference([System.Windows.Documents.TextElement]::ForegroundProperty, 'WF.Title')
            if ($r.Url -match '^https?://') {
                $link.NavigateUri = [uri]$r.Url; $link.ToolTip = $r.Url
                $link.Add_RequestNavigate({ param($s, $e) try { Start-Process $e.Uri.AbsoluteUri } catch { }; $e.Handled = $true })
            }
            $Inlines.Add($link)
        } else { $Inlines.Add($run) }
    }
}
function New-InstructionsDocument {
    # Headings, paragraphs, (nested) bullet and numbered lists and code blocks become a FlowDocument.
    param([string]$Markdown)
    $doc = New-Object System.Windows.Documents.FlowDocument
    $doc.FontFamily = New-Object System.Windows.Media.FontFamily 'Segoe UI'; $doc.FontSize = 13
    $doc.PagePadding = New-Object System.Windows.Thickness 18, 10, 18, 18
    $doc.TextAlignment = [System.Windows.TextAlignment]::Left
    $doc.SetResourceReference([System.Windows.Documents.FlowDocument]::ForegroundProperty, 'WF.Text')
    $sizes = @{ 1 = 24; 2 = 18; 3 = 15; 4 = 14; 5 = 13; 6 = 13 }
    $lists = @{}   # nesting level -> the List being filled
    foreach ($b in @(ConvertFrom-MarkdownBlocks $Markdown)) {
        if ($b.Type -ne 'ListItem') { $lists = @{} }
        switch ($b.Type) {
            'Heading' {
                $p = New-Object System.Windows.Documents.Paragraph
                $p.FontSize = $sizes[[int]$b.Level]; $p.FontWeight = [System.Windows.FontWeights]::SemiBold
                $p.Margin = New-Object System.Windows.Thickness 0, $(if ($b.Level -eq 1) { 0 } elseif ($b.Level -eq 2) { 16 } else { 10 }), 0, 6
                $p.SetResourceReference([System.Windows.Documents.TextElement]::ForegroundProperty, 'WF.Title')
                Add-MarkdownInlines $p.Inlines $b.Text; $doc.Blocks.Add($p)
            }
            'Paragraph' {
                $p = New-Object System.Windows.Documents.Paragraph; $p.Margin = New-Object System.Windows.Thickness 0, 0, 0, 10
                Add-MarkdownInlines $p.Inlines $b.Text; $doc.Blocks.Add($p)
            }
            'Code' {
                $p = New-Object System.Windows.Documents.Paragraph
                $p.FontFamily = New-Object System.Windows.Media.FontFamily 'Consolas'; $p.FontSize = 12
                $p.Padding = New-Object System.Windows.Thickness 10, 6, 10, 6; $p.Margin = New-Object System.Windows.Thickness 0, 0, 0, 10
                $p.SetResourceReference([System.Windows.Documents.TextElement]::BackgroundProperty, 'WF.CodeBg')
                $first = $true
                foreach ($codeLine in ($b.Text -split "`n")) {
                    if (-not $first) { $p.Inlines.Add((New-Object System.Windows.Documents.LineBreak)) }
                    $p.Inlines.Add((New-Object System.Windows.Documents.Run $codeLine)); $first = $false
                }
                $doc.Blocks.Add($p)
            }
            'ListItem' {
                $lvl = [Math]::Min([int]$b.Level, $lists.Count)   # a jump of more than one level nests one level only
                foreach ($k in @($lists.Keys | Where-Object { $_ -gt $lvl })) { $lists.Remove($k) }
                if (-not $lists.ContainsKey($lvl)) {
                    $list = New-Object System.Windows.Documents.List
                    $list.MarkerStyle = if ($b.Ordered) { [System.Windows.TextMarkerStyle]::Decimal } else { [System.Windows.TextMarkerStyle]::Disc }
                    $list.Margin = New-Object System.Windows.Thickness 0, 0, 0, $(if ($lvl -eq 0) { 10 } else { 2 })
                    $list.Padding = New-Object System.Windows.Thickness 22, 0, 0, 0
                    if ($lvl -eq 0) { $doc.Blocks.Add($list) } else { $lists[$lvl - 1].ListItems.LastListItem.Blocks.Add($list) }
                    $lists[$lvl] = $list
                }
                $item = New-Object System.Windows.Documents.ListItem
                $p = New-Object System.Windows.Documents.Paragraph; $p.Margin = New-Object System.Windows.Thickness 0, 0, 0, 3
                Add-MarkdownInlines $p.Inlines $b.Text
                $item.Blocks.Add($p); $lists[$lvl].ListItems.Add($item)
            }
        }
    }
    return $doc
}
function Update-InstructionsTab {
    # Renders INSTRUCTIONS.md (at start-up and on Reload). A missing or unreadable file is shown as such, never a crash.
    $path = $script:InstructionsPath
    try {
        if (Test-Path -LiteralPath $path) {
            $md = [System.IO.File]::ReadAllText($path)
            $src = "$path   (read at $(Get-Date -Format 'HH:mm:ss'))"
        } else {
            $md = '# Instructions' + "`n`n" + '`INSTRUCTIONS.md` was not found next to the script (' + $path + '). Copy it there and press Reload.'
            $src = "$path (not found)"
        }
        $script:InstructionsViewer.Document = New-InstructionsDocument $md
        $script:InstructionsSource.Text = $src
    } catch {
        Write-Log "INSTRUCTIONS.md could not be shown: $($_.Exception.Message)" 'WARN'
        $script:InstructionsSource.Text = "$path (could not be shown; see the Log tab)"
    }
}
Update-InstructionsTab
$script:ReloadInstructionsButton.Add_Click({ Update-InstructionsTab })

# The window's own checkbox defaults, restored when an OS without saved settings is selected.
$script:DefaultChecks = @{}
foreach ($n in $script:SettingOptionNames) { $script:DefaultChecks[$n] = [bool](Get-Variable -Name "Chk$n" -Scope Script -ValueOnly).IsChecked }
$script:LanguageOptions = @(Import-LanguageList)   # built-in list until the Profiles folder is loaded
function Update-LanguageItems {
    # One entry per Languages.json row, shown as "German (Germany) - de-de"; the code is kept in Tag and is what runs use.
    $script:LanguageList.Items.Clear()
    foreach ($l in @($script:LanguageOptions)) {
        $li = New-Object System.Windows.Controls.ListBoxItem
        $li.Content = $l.Display; $li.Tag = $l.Code
        [void]$script:LanguageList.Items.Add($li)
    }
}
function Set-DefaultLanguages {
    $def = $script:OsDefinitions[[string]$script:OsCombo.SelectedItem]
    if (-not $def) { return }
    $sel = Get-DefaultLanguageSelection -Definition $def -LanguageList $script:LanguageOptions
    foreach ($item in $script:LanguageList.Items) { $item.IsSelected = (@($sel.Select) -contains [string]$item.Tag) }
    if (@($sel.Missing).Count -gt 0) { Write-Log "Default language(s) $(@($sel.Missing) -join ', ') of $($def.Name) are not in $($script:LanguagesFileName) and were not selected." 'WARN' }
}
function Set-OsSettings {
    # Applies the selected OS's saved settings, or the defaults (window defaults + the profile's default languages).
    $def = $script:OsDefinitions[[string]$script:OsCombo.SelectedItem]
    if (-not $def) { return }
    $saved = Read-OsSettings -Directory $script:SettingsDir -Definition $def -LanguageList $script:LanguageOptions
    foreach ($n in $script:SettingOptionNames) {
        $value = if ($saved -and $saved.Options.ContainsKey($n)) { $saved.Options[$n] } else { $script:DefaultChecks[$n] }
        (Get-Variable -Name "Chk$n" -Scope Script -ValueOnly).IsChecked = [bool]$value
    }
    if ($saved) {
        foreach ($item in $script:LanguageList.Items) { $item.IsSelected = (@($saved.Languages) -contains [string]$item.Tag) }
        if (@($saved.MissingLanguages).Count -gt 0) { Write-Log "Saved language(s) $(@($saved.MissingLanguages) -join ', ') for $($def.Name) are not in $($script:LanguagesFileName) and were not selected." 'WARN' }
        Write-Log "Settings for $($def.Name) loaded from $($saved.File)"
    } else { Set-DefaultLanguages }
    Update-AppList -Ticked $(if ($saved) { @($saved.RemoveApps) } else { @() })
    Set-SccmOsValues $(if ($saved) { $saved.Sccm } else { $null })
}
function Get-SelectedSettings {
    $opts = @{}
    foreach ($n in $script:SettingOptionNames) { $opts[$n] = [bool](Get-Variable -Name "Chk$n" -Scope Script -ValueOnly).IsChecked }
    $langs = @(foreach ($item in $script:LanguageList.Items) { if ($item.IsSelected) { [string]$item.Tag } })
    return [pscustomobject]@{ Options = $opts; Languages = $langs; RemoveApps = @(Get-TickedApps) }
}
function Get-TickedApps { return @(foreach ($item in $script:AppList.Items) { if ($item.IsSelected) { [string]$item.Tag } }) }
function Update-AppList {
    # Fills the Apps tab for the selected OS from Profiles\Apps\<folder>_Appx.json (11b), ticking $Ticked (app names). A
    # ticked app that is not in the current list stays on it, marked, so a tick never disappears silently.
    param([string[]]$Ticked = @())
    $script:AppList.Items.Clear()
    $def = $script:OsDefinitions[[string]$script:OsCombo.SelectedItem]
    if (-not $def) { return }
    $client = -not $def.ServiceAllIndexes
    $script:AppList.IsEnabled = $client; $script:ReadAppsButton.IsEnabled = $client; $script:ChkAppRemoval.IsEnabled = $client
    if (-not $client) { $script:AppsSource.Text = 'App removal is for client editions; Windows Server has no provisioned consumer apps.'; return }
    $osRoot = Get-OsRootPath -Root ([string]$script:RootText.Text).Trim() -Definition $def
    $listFile = Get-AppListPath -ProfilesDir $script:ProfilesDir -Definition $def
    Move-OldAppInventory -OsRoot $osRoot -File $listFile
    $inv = Read-AppInventory -File $listFile
    # Is the list still from the ISO in the OS's ISO folder? (A preflight reads it again when not.)
    $changed = $false
    if ($inv) {
        $isoNow = @(Get-ChildItem -LiteralPath ([System.IO.Path]::Combine($osRoot, 'ISO')) -Filter '*.iso' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $inv.Source })
        $changed = ($isoNow.Count -eq 0) -or -not (Test-AppInventoryCurrent -Inventory $inv -Iso (Get-IsoIdentity $isoNow[0].FullName) -Index $inv.Index)
    }
    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($a in @(if ($inv) { $inv.Apps })) {
        if ($names.Contains($a.DisplayName)) { continue }
        $names.Add($a.DisplayName)
        $li = New-Object System.Windows.Controls.ListBoxItem; $li.Content = "$($a.DisplayName)   ($($a.Version))"; $li.Tag = $a.DisplayName
        [void]$script:AppList.Items.Add($li)
    }
    foreach ($t in @($Ticked | Where-Object { $_ -and -not $names.Contains($_) })) {
        $li = New-Object System.Windows.Controls.ListBoxItem; $li.Content = "$t   (ticked, but not in the current app list)"; $li.Tag = $t
        [void]$script:AppList.Items.Add($li); $names.Add($t)
    }
    foreach ($item in $script:AppList.Items) { $item.IsSelected = (@($Ticked) -contains [string]$item.Tag) }
    $script:AppsSource.Text = if ($inv) { "$(@($inv.Apps).Count) provisioned app(s) in $($inv.Source), index $($inv.Index) ($($inv.ImageName), $($inv.Version)); read $($inv.Read).$(if ($changed) { ' The OS ISO in the folder has changed since - the next preflight reads the list again, or press Read apps from the ISO.' })" } else { 'No app list for this OS yet: run a preflight, or press Read apps from the ISO.' }
    $script:AppsSource.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $(if ($changed) { 'WF.WarnText' } else { 'WF.SubtleText' }))
}
# ---- SCCM tab (step 7) ----
$script:SccmLists = $null        # distribution points and groups from the last Connect
$script:ServerShares = $null     # this server's shares, read once for the UNC preview
$script:SccmSourceServer = $env:COMPUTERNAME
function Get-SccmAutoName { $os = [string]$script:OsCombo.SelectedItem; if ($os) { return (Get-SccmImageName -OsName $os) } else { return '' } }
function Get-SccmPackageTypeTag { if ($script:SccmPackageType.SelectedItem) { return [string]$script:SccmPackageType.SelectedItem.Tag } else { return 'Image' } }
function Set-SccmPackageType {
    param([string]$Tag)
    $pick = @($script:SccmPackageType.Items | Where-Object { [string]$_.Tag -eq $Tag }) | Select-Object -First 1
    $script:SccmPackageType.SelectedItem = if ($pick) { $pick } else { $script:SccmPackageType.Items[0] }
}
function Update-SccmTargetList {
    $script:SccmTargetList.Items.Clear()
    if (-not $script:SccmLists) { return }
    $names = if ([bool]$script:SccmTargetGroup.IsChecked) { @($script:SccmLists.Groups) } else { @($script:SccmLists.DPs) }
    foreach ($n in $names) { [void]$script:SccmTargetList.Items.Add([string]$n) }
}
function Update-SccmUncPreview {
    $p = ([string]$script:SccmContentSource.Text).Trim()
    $warn = $false
    $script:SccmUncPreview.Text = if (-not $p) { 'Choose a folder on this server inside a shared folder; each import creates a sub-folder named after the image.' }
    else {
        try {
            if (-not $p.StartsWith('\\') -and $null -eq $script:ServerShares) { $script:ServerShares = @(Get-ServerShares) }
            $unc = ConvertTo-SccmUncPath -LocalPath $p -Server $script:SccmSourceServer -Shares $(if ($p.StartsWith('\\')) { @() } else { @($script:ServerShares) })
            "Configuration Manager imports from $unc\<image name>"
        } catch { $warn = $true; $_.Exception.Message }
    }
    $script:SccmUncPreview.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $(if ($warn) { 'WF.WarnText' } else { 'WF.SubtleText' }))
}
function Update-SccmLastRun {
    # What "Import into SCCM" would import for the selected OS: the latest finished run's record in its NEWWIM folder.
    $def = $script:OsDefinitions[[string]$script:OsCombo.SelectedItem]
    if (-not $def) { $script:SccmLastRun.Text = ''; return }
    $r = Read-RunResult -NewWim ([System.IO.Path]::Combine((Get-OsRootPath -Root ([string]$script:RootText.Text).Trim() -Definition $def), 'NEWWIM'))
    $failed = $r -and $r.Gate -eq 'FAILED'
    $script:SccmLastRun.Text = if (-not $r) { "No finished run yet for $($def.Name); run one first." }
        else { "Latest run: build $($r.Build), validation gate $($r.Gate), finished $($r.Finished)$(if ($r.Media) { ', with the media folder' })$(if ($failed) { ' - it will not be imported.' })" }
    $script:SccmLastRun.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $(if ($failed) { 'WF.WarnText' } else { 'WF.SubtleText' }))
}
function Set-SccmOsValues {
    # The selected OS's saved SCCM values; the image name follows the OS (name + yyyyMM) unless one was typed and saved.
    param($Saved)
    $script:SccmContentSource.Text = if ($Saved -and $Saved.ContentSource) { $Saved.ContentSource } else { '' }
    Set-SccmPackageType $(if ($Saved -and $Saved.PackageType) { $Saved.PackageType } else { 'Image' })
    $script:SccmImageName.Text = if ($Saved -and $Saved.ImageName) { $Saved.ImageName } else { Get-SccmAutoName }
    Update-SccmUncPreview; Update-SccmLastRun
}
function Get-SccmSelected {
    $name = ([string]$script:SccmImageName.Text).Trim()
    return @{ ContentSource = ([string]$script:SccmContentSource.Text).Trim(); PackageType = (Get-SccmPackageTypeTag); ImageName = $(if ($name -and $name -ne (Get-SccmAutoName)) { $name } else { '' }) }
}
function Save-CurrentOsSettings {
    $def = $script:OsDefinitions[[string]$script:OsCombo.SelectedItem]
    if (-not $def) { return $null }
    $sel = Get-SelectedSettings
    $file = Save-OsSettings -Directory $script:SettingsDir -Definition $def -Options $sel.Options -Languages $sel.Languages -RemoveApps $sel.RemoveApps -Sccm (Get-SccmSelected)
    Save-GeneralSettings -Directory $script:SettingsDir -Root ([string]$script:RootText.Text) -SccmSiteServer ([string]$script:SccmSiteServer.Text).Trim() `
        -SccmTargetType $(if ([bool]$script:SccmTargetGroup.IsChecked) { 'DPGroup' } else { 'DP' }) -SccmTarget ([string]$script:SccmTarget.Text).Trim()
    Write-Log "Settings for $($def.Name) saved to $file ($(@($sel.Languages).Count) language(s), $(@($sel.RemoveApps).Count) app(s) to remove); repository root saved."
    return $file
}
function Reset-CurrentOsSettings {
    $def = $script:OsDefinitions[[string]$script:OsCombo.SelectedItem]
    if (-not $def) { return }
    if (Remove-OsSettings -Directory $script:SettingsDir -Definition $def) { Write-Log "Saved settings for $($def.Name) removed; defaults restored." }
    else { Write-Log "No saved settings for $($def.Name); defaults restored." }
    Set-OsSettings
}
function Update-ProfileInfo {
    $def = $script:OsDefinitions[[string]$script:OsCombo.SelectedItem]
    if (-not $def) { $script:ProfileInfo.Text = ''; return }
    $st = Get-SupportStatus -Definition $def
    $script:ProfileInfo.Text = "Profile file: $($def.SourceFile)   |   $($st.Text)"
    $script:ProfileInfo.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $(if ($st.Level -in @('Past', 'Soon')) { 'WF.WarnText' } else { 'WF.InfoText' }))
}
function Update-HeaderIdle {
    # Shows the selected OS in the header while nothing is running. During a run, Update-RunUi overwrites this from the queue.
    if (-not $script:RunButton.IsEnabled) { return }
    $script:HeaderOs.Text = [string]$script:OsCombo.SelectedItem
    $script:HeaderPhase.Text = 'Idle'
}
function Update-ProfileList {
    $previous = [string]$script:OsCombo.SelectedItem
    $script:OsDefinitions = Import-OsProfiles -Directory $script:ProfilesDir
    $script:LanguageOptions = @(Import-LanguageList -Directory $script:ProfilesDir)
    Write-ProfileMessages
    Update-LanguageItems
    $script:OsCombo.Items.Clear()
    foreach ($osName in $script:OsDefinitions.Keys) { [void]$script:OsCombo.Items.Add($osName) }
    $script:OsCombo.SelectedIndex = if ($previous -and $script:OsCombo.Items.Contains($previous)) { $script:OsCombo.Items.IndexOf($previous) } else { 0 }
}
function Get-UiOptions {
    $langs = @(foreach ($item in $script:LanguageList.Items) { if ($item.IsSelected) { [string]$item.Tag } })
    return [pscustomobject]@{
        OsName = [string]$script:OsCombo.SelectedItem; Root = [string]$script:RootText.Text
        PreflightOnly = [bool]$script:ChkPreflight.IsChecked; Install = [bool]$script:ChkInstall.IsChecked; Boot = [bool]$script:ChkBoot.IsChecked; WinRE = [bool]$script:ChkWinRE.IsChecked
        Verify = [bool]$script:ChkVerify.IsChecked; BuildMedia = [bool]$script:ChkBuildMedia.IsChecked; BuildIso = ([bool]$script:ChkBuildIso.IsChecked -and [bool]$script:ChkBuildMedia.IsChecked); Media2023 = [bool]$script:ChkMedia2023.IsChecked
        RemoveApps = $(if ([bool]$script:ChkAppRemoval.IsChecked) { @(Get-TickedApps) } else { @() })
        SccmSiteServer = ([string]$script:SccmSiteServer.Text).Trim(); SccmTargetType = $(if ([bool]$script:SccmTargetGroup.IsChecked) { 'DPGroup' } else { 'DP' }); SccmTarget = ([string]$script:SccmTarget.Text).Trim()
        SccmContentSource = ([string]$script:SccmContentSource.Text).Trim(); SccmSourceServer = $script:SccmSourceServer; SccmPackageType = (Get-SccmPackageTypeTag); SccmImageName = ([string]$script:SccmImageName.Text).Trim()
        SSU = [bool]$script:ChkSSU.IsChecked; LCU = [bool]$script:ChkLCU.IsChecked; SafeOS = [bool]$script:ChkSafeOS.IsChecked
        NetCU = [bool]$script:ChkNetCU.IsChecked; SetupDU = [bool]$script:ChkSetupDU.IsChecked; NetFx3 = [bool]$script:ChkNetFx3.IsChecked; AutoDownload = [bool]$script:ChkAutoDownload.IsChecked
        Languages = $langs; ProfilesDir = $script:ProfilesDir
    }
}
$script:OsCombo.Add_SelectionChanged({ Set-OsSettings; Update-ProfileInfo; Update-HeaderIdle })
function Update-BootOption {
    # The ISO and boot.wim options depend on the media folder, so they are available only while it is ticked (Terry,
    # 2026-09-27); their own ticks are kept, so they come back as they were when the media folder is ticked again.
    $script:ChkBuildIso.IsEnabled = [bool]$script:ChkBuildMedia.IsChecked
    $script:ChkBoot.IsEnabled = [bool]$script:ChkBuildMedia.IsChecked
    # The CA 2023 media takes its boot files from the patched boot.wim, so it also needs Patch boot.wim ticked.
    $script:ChkMedia2023.IsEnabled = $script:ChkBoot.IsEnabled -and [bool]$script:ChkBoot.IsChecked
}
foreach ($chk in @($script:ChkBuildMedia, $script:ChkBuildIso, $script:ChkBoot)) { $chk.Add_Checked({ Update-BootOption }); $chk.Add_Unchecked({ Update-BootOption }) }
$script:SaveSettingsButton.Add_Click({
    if (-not $script:RunButton.IsEnabled) { return }
    try { if (Save-CurrentOsSettings) { $script:Status.Text = "Settings saved for $([string]$script:OsCombo.SelectedItem)" } }
    catch { [System.Windows.MessageBox]::Show("Could not save the settings: $($_.Exception.Message)", 'WimForge', 'OK', 'Error') | Out-Null }
})
$script:ResetSettingsButton.Add_Click({
    if (-not $script:RunButton.IsEnabled) { return }
    $os = [string]$script:OsCombo.SelectedItem
    $answer = [System.Windows.MessageBox]::Show("Delete the saved settings for $os and go back to the defaults?", 'WimForge - reset settings', 'YesNo', 'Question')
    if ($answer -ne 'Yes') { return }
    try { Reset-CurrentOsSettings; $script:Status.Text = "Defaults restored for $os" }
    catch { [System.Windows.MessageBox]::Show("Could not reset the settings: $($_.Exception.Message)", 'WimForge', 'OK', 'Error') | Out-Null }
})
$script:ReloadProfilesButton.Add_Click({
    if (-not $script:RunButton.IsEnabled) { return }
    Update-ProfileList
    Write-Log "Profiles reloaded from $($script:ProfilesDir)"
})
$savedRoot = Read-GeneralSettings -Directory $script:SettingsDir
if ($savedRoot) { $script:RootText.Text = $savedRoot; Write-Log "Repository root loaded from saved settings: $savedRoot" }
$sccmSaved = Read-SccmGeneralSettings -Directory $script:SettingsDir
$script:SccmSiteServer.Text = $sccmSaved.SiteServer; $script:SccmTarget.Text = $sccmSaved.Target
if ($sccmSaved.TargetType -eq 'DPGroup') { $script:SccmTargetGroup.IsChecked = $true }
Update-ProfileList
Set-OsSettings
Update-ProfileInfo
Update-HeaderIdle
Update-BootOption

# ---- Background execution: the engine runs on its own runspace so the window never blocks on DISM ----
# The engine text is read from this file (the ENGINE region) and loaded into a fresh runspace. It talks to the window through a
# thread-safe queue (log lines and progress) and a synchronized hashtable (Cancel flag, final result).
$script:EngineText = $null
try {
    if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
        $selfText = [System.IO.File]::ReadAllText($PSCommandPath)
        $em = [regex]::Match($selfText, '(?s)#region ENGINE(.*?)#endregion ENGINE')
        if ($em.Success) { $script:EngineText = $em.Groups[1].Value }
    }
} catch { $script:EngineText = $null }

$script:RunnerScript = @'
param($RunEngineText, $RunQueue, $RunShared, $RunOptions)
# Parameter names are deliberately unlike the engine's $script:UiQueue / $script:Shared: on a runspace the script scope
# IS the global scope, and the engine initialises its own variables when it is loaded.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    Import-Module Dism -ErrorAction Stop
    . ([scriptblock]::Create($RunEngineText))
    $script:UiQueue = $RunQueue
    $script:Shared  = $RunShared
    try {
        Invoke-MediaRefresh -Options $RunOptions | Out-Null
        $RunShared['Result'] = $script:LastResult
        $RunShared['Ok'] = $true
    } catch {
        $RunShared['Ok'] = $false
        $RunShared['Message'] = $_.Exception.Message
        try {
            Write-Log $_.Exception.ToString() 'ERROR'
            Write-Log ('At line {0}: {1}' -f $_.InvocationInfo.ScriptLineNumber, $_.InvocationInfo.Line.Trim()) 'ERROR'
            Set-Progress 0 'Failed'
        } catch { }
    } finally {
        try { Dismount-AllIso } catch { }
    }
} catch {
    $RunShared['Ok'] = $false
    $RunShared['Message'] = 'Background runner failed to start: ' + $_.Exception.Message
} finally {
    $RunShared['Done'] = $true
}
'@

$script:RunQueue = $null; $script:RunShared = $null; $script:RunPs = $null; $script:RunRs = $null; $script:RunHandle = $null; $script:PendingDownloadOptions = $null; $script:PendingCleanupOptions = $null; $script:CurrentRunMode = ''
$script:RunStatus = 'Ready'; $script:RunStarted = $null
$script:UiTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:UiTimer.Interval = [TimeSpan]::FromMilliseconds(250)

function Update-RunUi {
    # Runs on the GUI thread every 250 ms: drains log/progress messages, refreshes the elapsed time, detects completion.
    $sb = New-Object System.Text.StringBuilder
    $item = $null; $n = 0
    while ($n -lt 400 -and $script:RunQueue.TryDequeue([ref]$item)) {
        $n++
        $parts = ([string]$item) -split "`t", 3
        if ($parts[0] -eq 'L' -and $parts.Count -ge 2) { [void]$sb.AppendLine($parts[1]) }
        elseif ($parts[0] -eq 'P' -and $parts.Count -ge 3) {
            $v = 0; if ([int]::TryParse($parts[1], [ref]$v)) { $script:Progress.Value = $v }
            $script:RunStatus = $parts[2]
        }
        elseif ($parts[0] -eq 'H' -and $parts.Count -ge 3) {
            if ($script:HeaderOs)    { $script:HeaderOs.Text = $parts[1] }
            if ($script:HeaderPhase) { $script:HeaderPhase.Text = $parts[2] }
        }
    }
    if ($sb.Length -gt 0) { Add-LogText $sb.ToString() }
    if ($script:RunStarted) {
        $el = [DateTime]::Now - $script:RunStarted
        $script:Status.Text = ('{0}   (elapsed {1:00}:{2:00}:{3:00})' -f $script:RunStatus, [int][Math]::Floor($el.TotalHours), $el.Minutes, $el.Seconds)
    }
    if ($script:RunHandle -and $script:RunHandle.IsCompleted -and $script:RunQueue.IsEmpty) { Complete-BackgroundRun }
}

function Complete-BackgroundRun {
    $script:UiTimer.Stop()
    $shared = $script:RunShared
    $engineErrors = @()
    try { [void]$script:RunPs.EndInvoke($script:RunHandle) } catch { $engineErrors += $_.Exception.Message }
    try { $engineErrors += @($script:RunPs.Streams.Error | ForEach-Object { $_.ToString() }) } catch { }
    try { $script:RunPs.Dispose() } catch { }
    try { $script:RunRs.Close(); $script:RunRs.Dispose() } catch { }
    $script:RunHandle = $null; $script:RunPs = $null; $script:RunRs = $null; $script:RunStarted = $null
    $ok = ($shared.ContainsKey('Ok') -and $shared['Ok'])
    $wasCancelled = ($script:Cancelled -or ($shared.ContainsKey('Cancel') -and $shared['Cancel']))
    $res = if ($shared.ContainsKey('Result')) { $shared['Result'] } else { $null }
    $isDownload = ($ok -and $res -and ([string](Get-ProfileValue $res 'Mode' '')) -eq 'Download')
    $isCleanup = ($ok -and $res -and ([string](Get-ProfileValue $res 'Mode' '')) -eq 'Cleanup')
    $isApps = ($ok -and $res -and ([string](Get-ProfileValue $res 'Mode' '')) -eq 'Apps')
    # A preflight, a run or Read apps may have written the OS's app list: refresh the Apps tab, keeping the ticks.
    try { Update-AppList -Ticked @(Get-TickedApps) } catch { }
    try { Update-SccmLastRun } catch { }
    $resMode = if ($ok -and $res) { [string](Get-ProfileValue $res 'Mode' '') } else { '' }

    # SCCM tab: Connect finished - fill the distribution point / group list.
    if ($resMode -eq 'SccmConnect') {
        $script:SccmLists = $res
        $script:SccmSiteInfo.Text = "Connected to site $($res.SiteCode) on $($res.SiteServer): $(@($res.DPs).Count) distribution point(s), $(@($res.Groups).Count) group(s)."
        Update-SccmTargetList
        $script:Status.Text = 'Ready'; $script:Progress.Value = 0
        $script:RunButton.IsEnabled = $true; $script:AcquirePatchesButton.IsEnabled = $true; $script:CancelButton.IsEnabled = $false
        Update-HeaderIdle
        return
    }
    # SCCM tab: the check-only import pass finished - show exactly what would happen and ask.
    if ($resMode -eq 'SccmImport' -and [bool]$res.DryRun -and -not $wasCancelled) {
        $script:Status.Text = 'Ready'; $script:Progress.Value = 0
        $script:RunButton.IsEnabled = $true; $script:AcquirePatchesButton.IsEnabled = $true; $script:CancelButton.IsEnabled = $false
        Update-HeaderIdle
        $dup = if ($res.Name -ne $res.RequestedName) { "`n(A $($res.Kind) named '$($res.RequestedName)' already exists and is not changed.)" } else { '' }
        $gateNote = if ($res.Gate -ne 'PASSED') { "`nNote: this image was not verified (validation gate: $($res.Gate))." } else { '' }
        $msg = "Import into Configuration Manager:`n`n  $($res.Kind): $($res.Name)$dup`n  Build $($res.Build), validation gate $($res.Gate), run finished $($res.Finished)$gateNote`n`n  Copy ($($res.SizeGB) GB): $($res.Content)`n    to $($res.DestinationLocal)`n  Import from: $($res.ImportPath)`n  Site $($res.SiteCode) on $($res.SiteServer)`n  Distribute to $(if ($res.TargetIsGroup) { 'distribution point group' } else { 'distribution point' }): $($res.Target)`n`nImport now?"
        if ([System.Windows.MessageBox]::Show($msg, 'WimForge - SCCM import', 'YesNo', 'Question') -eq 'Yes' -and $script:PendingSccmOptions) {
            $go = $script:PendingSccmOptions; $go | Add-Member -NotePropertyName DryRun -NotePropertyValue $false -Force
            # the confirmed name, so a duplicate that appears meanwhile cannot change what was shown
            $go | Add-Member -NotePropertyName SccmImageName -NotePropertyValue $res.Name -Force
            $script:RunButton.IsEnabled = $false; $script:AcquirePatchesButton.IsEnabled = $false; $script:CancelButton.IsEnabled = $true
            try { Start-BackgroundRun -Options $go }
            catch {
                $script:RunButton.IsEnabled = $true; $script:AcquirePatchesButton.IsEnabled = $true; $script:CancelButton.IsEnabled = $false
                [System.Windows.MessageBox]::Show("Could not start the import: $($_.Exception.Message)", 'WimForge', 'OK', 'Error') | Out-Null
            }
        }
        return
    }

    # Tools > Cleanup Mountpoints: the check-only pass finished. Show what it found and ask before discarding anything.
    if ($isCleanup -and [bool]$res.DryRun -and -not $wasCancelled) {
        $script:Status.Text = 'Ready'; $script:Progress.Value = 0
        $script:RunButton.IsEnabled = $true; $script:AcquirePatchesButton.IsEnabled = $true; $script:CancelButton.IsEnabled = $false
        Update-HeaderIdle
        $plan = $res.Plan
        $outside = @($plan.OtherWimMounts | ForEach-Object { "  $($_.Path)" })
        $outsideText = if ($outside.Count -gt 0) { "`n`nMounted outside the repository root (left alone):`n$($outside -join "`n")" } else { '' }
        if ($plan.Count -eq 0) {
            [System.Windows.MessageBox]::Show("Nothing to clean up under $($res.Root): no mounted images, no mounted ISOs and no leftover files in the MOUNT folders.$outsideText", 'WimForge - Cleanup Mountpoints', 'OK', 'Information') | Out-Null
            return
        }
        $lines = @(@($plan.WimMounts | ForEach-Object { "  Discard mounted image: $($_.Path)" }) + @($plan.Isos | ForEach-Object { "  Dismount ISO: $_" }) + @($plan.LeftoverFolders | ForEach-Object { "  Empty leftover files in: $_" }))
        $warnWim = if ($plan.WimMounts.Count -gt 0) { "`n`nDiscarding a mounted image throws away any changes in it. Only do this when no WimForge run or other DISM work is using it." } else { '' }
        $answer = [System.Windows.MessageBox]::Show("Found under $($res.Root):`n`n$($lines -join "`n")$warnWim$outsideText`n`nClean these up now?", 'WimForge - Cleanup Mountpoints', 'YesNo', 'Warning')
        if ($answer -eq 'Yes' -and $script:PendingCleanupOptions) {
            $go = $script:PendingCleanupOptions
            $go | Add-Member -NotePropertyName DryRun -NotePropertyValue $false -Force
            $script:RunButton.IsEnabled = $false; $script:AcquirePatchesButton.IsEnabled = $false; $script:CancelButton.IsEnabled = $true
            try { Start-BackgroundRun -Options $go }
            catch {
                $script:RunButton.IsEnabled = $true; $script:AcquirePatchesButton.IsEnabled = $true; $script:CancelButton.IsEnabled = $false
                [System.Windows.MessageBox]::Show("Could not start the cleanup: $($_.Exception.Message)", 'WimForge', 'OK', 'Error') | Out-Null
            }
        }
        return
    }

    # Step 5: a dry-run search finished. Show what it found and ask before really downloading, instead of unlocking
    # the buttons - the user's answer either restarts the background run for real, or returns everything to Ready.
    if ($isDownload -and [bool](Get-ProfileValue $res 'DryRun' $false) -and -not $wasCancelled) {
        $script:Status.Text = 'Ready'; $script:Progress.Value = 0
        if ($script:HeaderPhase) { $script:HeaderPhase.Text = 'Idle' }
        $plan = @($res.Plan)
        if ($plan.Count -eq 0) {
            $skip = @($res.SkippedClasses) -join "`n - "
            $msg = "No catalog results to download.$(if ($skip) { "`n`nSkipped:`n - $skip" })"
            [System.Windows.MessageBox]::Show($msg, 'WimForge', 'OK', 'Information') | Out-Null
            $script:RunButton.IsEnabled = $true; $script:AcquirePatchesButton.IsEnabled = $true; $script:CancelButton.IsEnabled = $false
        } elseif (@($plan | Where-Object { -not [bool](Get-ProfileValue $_ 'Present' $false) }).Count -eq 0) {
            # Step 14: everything detected is already in the folders - nothing to download, so no confirmation.
            $lines = @($plan | ForEach-Object { "  $($_.Class): $(Format-CatalogPick -Title $_.Title -Kb $_.Kb -Date $_.Date -Classification $_.Classification -Release:($_.Class -eq 'LCU'))" })
            [System.Windows.MessageBox]::Show("PATCHES is up to date - every detected patch is already in its folder, so nothing needs downloading:`n`n$($lines -join "`n")", 'WimForge - Download patches', 'OK', 'Information') | Out-Null
            $script:RunButton.IsEnabled = $true; $script:AcquirePatchesButton.IsEnabled = $true; $script:CancelButton.IsEnabled = $false
        } else {
            $lines = @($plan | ForEach-Object { "  $($_.Class): $(Format-CatalogPick -Title $_.Title -Kb $_.Kb -Date $_.Date -Classification $_.Classification -Release:($_.Class -eq 'LCU'))`n      $(if ([bool](Get-ProfileValue $_ 'Present' $false)) { "already in PATCHES\$($_.Folder) - not downloaded again" } else { 'will be downloaded' })" })
            $msg = "Latest patches found (older files in the same PATCHES class are removed; PATCHES\SSU is never touched):`n`n$($lines -join "`n")`n`nThe newest cumulative release is picked, out-of-band included. The LCU line says whether its release date is Patch Tuesday (the second Tuesday) or out-of-band.`n`nDownload the missing ones now?"
            $answer = [System.Windows.MessageBox]::Show($msg, 'WimForge - confirm download', 'YesNo', 'Question')
            if ($answer -eq 'Yes' -and $script:PendingDownloadOptions) {
                $go = $script:PendingDownloadOptions
                $go | Add-Member -NotePropertyName DryRun -NotePropertyValue $false -Force
                try { Start-BackgroundRun -Options $go; return }
                catch {
                    [System.Windows.MessageBox]::Show("Could not start the download: $($_.Exception.Message)", 'WimForge', 'OK', 'Error') | Out-Null
                    $script:RunButton.IsEnabled = $true; $script:AcquirePatchesButton.IsEnabled = $true; $script:CancelButton.IsEnabled = $false
                }
            } else {
                $script:RunButton.IsEnabled = $true; $script:AcquirePatchesButton.IsEnabled = $true; $script:CancelButton.IsEnabled = $false
            }
        }
        return
    }

    $script:RunButton.IsEnabled = $true; $script:AcquirePatchesButton.IsEnabled = $true; $script:CancelButton.IsEnabled = $false
    if ($ok) {
        $script:Status.Text = 'Done'; $script:Progress.Value = 100
        if ($script:HeaderPhase) { $script:HeaderPhase.Text = 'Done' }
        if ($resMode -eq 'SccmImport') {
            [System.Windows.MessageBox]::Show("Imported into Configuration Manager:`n`n  $($res.Kind) '$($res.Name)' - package $($res.PackageId)`n  from $($res.ImportPath)`n`nContent distribution to $($res.Target) has started; the console shows its progress (Monitoring > Distribution Status).", 'WimForge - SCCM import', 'OK', 'Information') | Out-Null
            Update-HeaderIdle
            return
        }
        # A servicing run finished and "Import after the run finishes" is ticked: import straight away, without a dialog
        # (the engine refuses an image whose validation gate FAILED).
        if ($resMode -eq '' -and $res -and -not [bool](Get-ProfileValue $res 'Preflight' $false) -and (Get-ProfileValue $res 'Install' $null) -and [bool]$script:ChkSccmAutoImport.IsChecked) {
            if ([string](Get-ProfileValue $res 'Gate' '') -eq 'FAILED') {
                Add-LogText '[WARN] Import after the run finishes is ticked, but the validation gate FAILED, so the image is not imported.'
            } else {
                Add-LogText '[INFO] The run finished; starting the SCCM import (Import after the run finishes is ticked).'
                Start-SccmBackground -Mode 'SccmImport' -DryRun $false
                return
            }
        }
        if ($isApps) {
            [System.Windows.MessageBox]::Show("$($res.Count) provisioned app(s) read from $($res.Source), index $($res.Index) ($($res.ImageName)).`n`nTick the apps to remove on the Apps tab, then press Save settings.", 'WimForge - Apps', 'OK', 'Information') | Out-Null
            Update-HeaderIdle
            return
        }
        if ($isCleanup) {
            $left = @($res.Remaining)
            $msg = "Cleaned up $(@($res.Done).Count) item(s) under $($res.Root)."
            if (@($res.Done).Count -gt 0) { $msg += "`n`n" + ((@($res.Done) | ForEach-Object { "  $_" }) -join "`n") }
            if ($left.Count -gt 0) { $msg += "`n`nStill left:`n" + (($left | ForEach-Object { "  $_" }) -join "`n") + "`n`nRestarting the build machine usually releases these; then run Cleanup Mountpoints again." }
            [System.Windows.MessageBox]::Show($msg, 'WimForge - Cleanup Mountpoints', 'OK', $(if ($left.Count -gt 0) { 'Warning' } else { 'Information' })) | Out-Null
            Update-HeaderIdle
            return
        }
        if ($isDownload) {
            $dl = @($res.Downloaded); $rm = @($res.Removed); $skip = @($res.SkippedClasses)
            $msg = "Downloaded $($dl.Count) file(s); $(@(Get-ProfileValue $res 'AlreadyPresent' @()).Count) already present."
            if ($dl.Count -gt 0) { $msg += "`n`n" + (($dl | ForEach-Object { "  $($_.Class): $(Split-Path $_.File -Leaf)" }) -join "`n") }
            if ($rm.Count -gt 0) { $msg += "`n`nRemoved $($rm.Count) superseded file(s)." }
            if ($skip.Count -gt 0) { $msg += "`n`nSkipped: " + ($skip -join '; ') }
            [System.Windows.MessageBox]::Show($msg, 'WimForge', 'OK', 'Information') | Out-Null
            return
        }
        if ($null -eq $res) { $res = [pscustomobject]@{ NewWim = ''; Preflight = $false; VerifyIssues = $null; Gate = $null } }
        $msg = "Completed successfully.`n`nOutput: $($res.NewWim)"
        if ($res.Preflight) { $msg = 'Preflight passed. No image was changed. See the Log tab for the ISO roles, patch counts and selected edition.' }
        if ($null -ne $res.VerifyIssues -and $res.VerifyIssues -gt 0) { $msg = "Completed with $($res.VerifyIssues) verification issue(s). Review the Log tab.`n`nOutput: $($res.NewWim)" }
        $m2023 = [string](Get-ProfileValue $res 'Media2023' ''); $e2023 = [string](Get-ProfileValue $res 'Media2023Error' '')
        if ($m2023) { $msg += "`n`nCA 2023 media: $m2023$(if (Get-ProfileValue $res 'Iso2023' '') { "`nCA 2023 ISO: $($res.Iso2023)" })`n(boots only on PCs whose firmware trusts Windows UEFI CA 2023)" }
        if ($res.Gate -eq 'FAILED') {
            $msg = "Completed, but the VALIDATION GATE FAILED (build, edition or applied-patch check did not pass). Review the change log and Log tab before importing this image into SCCM.`n`nOutput: $($res.NewWim)"
            [System.Windows.MessageBox]::Show($msg, 'WimForge', 'OK', 'Warning') | Out-Null
        } elseif ($e2023) {
            [System.Windows.MessageBox]::Show("$msg`n`nThe CA 2023 media was NOT created: $e2023`nThe standard media and install.wim are fine.", 'WimForge', 'OK', 'Warning') | Out-Null
        } else {
            [System.Windows.MessageBox]::Show($msg, 'WimForge', 'OK', 'Information') | Out-Null
        }
    } else {
        $script:Status.Text = if ($wasCancelled) { 'Cancelled' } else { 'Failed' }
        $script:Progress.Value = 0
        if ($script:HeaderPhase) { $script:HeaderPhase.Text = if ($wasCancelled) { 'Cancelled' } else { 'Failed' } }
        $m = if ($wasCancelled -and -not ($shared.ContainsKey('Message') -and $shared['Message'])) { 'The run was cancelled.' } elseif ($shared.ContainsKey('Message') -and $shared['Message']) { [string]$shared['Message'] } elseif ($engineErrors.Count -gt 0) { [string]$engineErrors[0] } else { 'The run ended unexpectedly. See the Log tab.' }
        Add-LogText "[$(if ($wasCancelled) { 'CANCELLED' } else { 'ERROR' })] $m"
        if ($script:CurrentRunMode -eq 'SccmConnect') { $script:SccmSiteInfo.Text = "Not connected: $m" }
        [System.Windows.MessageBox]::Show($m, 'WimForge', 'OK', $(if ($wasCancelled) { 'Warning' } else { 'Error' })) | Out-Null
    }
}

function Start-BackgroundRun {
    param($Options)
    $script:CurrentRunMode = [string](Get-ProfileValue $Options 'Mode' '')
    $script:RunQueue  = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
    $script:RunShared = [hashtable]::Synchronized(@{ Cancel = $false; Done = $false })
    $script:RunStatus = 'Starting...'; $script:RunStarted = [DateTime]::Now
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'; $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript($script:RunnerScript, $true).AddArgument($script:EngineText).AddArgument($script:RunQueue).AddArgument($script:RunShared).AddArgument($Options)
    $script:RunRs = $rs; $script:RunPs = $ps
    $script:RunHandle = $ps.BeginInvoke()
    $script:UiTimer.Start()
}
$script:UiTimer.Add_Tick({ try { Update-RunUi } catch { $script:UiTimer.Stop(); [System.Windows.MessageBox]::Show("Display update failed: $($_.Exception.Message)`nThe run may still be active; check the log file in the OS LOGS folder.", 'WimForge') | Out-Null } })

$script:RunButton.Add_Click({
    $script:RunButton.IsEnabled = $false; $script:AcquirePatchesButton.IsEnabled = $false; $script:CancelButton.IsEnabled = $true
    $script:Cancelled = $false
    $opts = Get-UiOptions
    if ($script:EngineText) {
        try { Start-BackgroundRun -Options $opts }
        catch {
            $script:RunButton.IsEnabled = $true; $script:AcquirePatchesButton.IsEnabled = $true; $script:CancelButton.IsEnabled = $false
            [System.Windows.MessageBox]::Show("Could not start the background run: $($_.Exception.Message)", 'WimForge', 'OK', 'Error') | Out-Null
        }
        return
    }
    # Fallback (script was not started from a file, so the engine text is unavailable): run on the GUI thread as v2.0 did.
    try {
        Invoke-MediaRefresh -Options $opts
        $res = $script:LastResult
        $msg = "Completed successfully.`n`nOutput: $($res.NewWim)"
        if ($res.Preflight) { $msg = 'Preflight passed. No image was changed. See the Log tab for the ISO roles, patch counts and selected edition.' }
        if ($null -ne $res.VerifyIssues -and $res.VerifyIssues -gt 0) { $msg = "Completed with $($res.VerifyIssues) verification issue(s). Review the Log tab.`n`nOutput: $($res.NewWim)" }
        [System.Windows.MessageBox]::Show($msg, 'WimForge', 'OK', 'Information') | Out-Null
    } catch {
        Write-Log $_.Exception.ToString() 'ERROR'
        Write-Log "At line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())" 'ERROR'
        Set-Progress 0 'Failed'
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'WimForge', 'OK', 'Error') | Out-Null
    } finally { Dismount-AllIso; $script:RunButton.IsEnabled = $true; $script:AcquirePatchesButton.IsEnabled = $true; $script:CancelButton.IsEnabled = $false }
})
$script:AcquirePatchesButton.Add_Click({
    # Step 5: always starts with a dry run (search only). Complete-BackgroundRun shows the results and asks for
    # confirmation before a second background run actually downloads anything.
    if (-not $script:RunButton.IsEnabled) { return }
    $opts = Get-UiOptions
    $opts | Add-Member -NotePropertyName Mode -NotePropertyValue 'Download' -Force
    $opts | Add-Member -NotePropertyName DryRun -NotePropertyValue $true -Force
    $script:PendingDownloadOptions = $opts
    $script:RunButton.IsEnabled = $false; $script:AcquirePatchesButton.IsEnabled = $false; $script:CancelButton.IsEnabled = $true
    $script:Cancelled = $false
    if ($script:EngineText) {
        try { Start-BackgroundRun -Options $opts }
        catch {
            $script:RunButton.IsEnabled = $true; $script:AcquirePatchesButton.IsEnabled = $true; $script:CancelButton.IsEnabled = $false
            [System.Windows.MessageBox]::Show("Could not start the catalog search: $($_.Exception.Message)", 'WimForge', 'OK', 'Error') | Out-Null
        }
    } else {
        $script:RunButton.IsEnabled = $true; $script:AcquirePatchesButton.IsEnabled = $true; $script:CancelButton.IsEnabled = $false
        [System.Windows.MessageBox]::Show('Downloading patches needs the script running from a file (the background engine text is unavailable).', 'WimForge', 'OK', 'Error') | Out-Null
    }
})
$script:ToolsButton.Add_Click({
    $menu = $script:ToolsButton.ContextMenu
    $menu.PlacementTarget = $script:ToolsButton; $menu.Placement = 'Bottom'; $menu.IsOpen = $true
})
function Start-SccmBackground {
    # Connect / check / import on the background runspace, like the other long operations.
    param([string]$Mode, [bool]$DryRun = $true)
    if (-not $script:RunButton.IsEnabled) { return }
    if (-not $script:EngineText) { [System.Windows.MessageBox]::Show('This needs the script running from a file (the background engine text is unavailable).', 'WimForge', 'OK', 'Error') | Out-Null; return }
    $opts = Get-UiOptions
    $opts | Add-Member -NotePropertyName Mode -NotePropertyValue $Mode -Force
    $opts | Add-Member -NotePropertyName DryRun -NotePropertyValue $DryRun -Force
    if ($Mode -eq 'SccmImport') { $script:PendingSccmOptions = $opts }
    $script:RunButton.IsEnabled = $false; $script:AcquirePatchesButton.IsEnabled = $false; $script:CancelButton.IsEnabled = $true
    $script:Cancelled = $false
    try { Start-BackgroundRun -Options $opts }
    catch {
        $script:RunButton.IsEnabled = $true; $script:AcquirePatchesButton.IsEnabled = $true; $script:CancelButton.IsEnabled = $false
        [System.Windows.MessageBox]::Show("Could not start: $($_.Exception.Message)", 'WimForge', 'OK', 'Error') | Out-Null
    }
}
$script:PendingSccmOptions = $null
$script:SccmConnectButton.Add_Click({
    if (-not $script:RunButton.IsEnabled) { return }
    $script:SccmSiteInfo.Text = "Connecting to $(([string]$script:SccmSiteServer.Text).Trim()): loading the Configuration Manager module and reading the site. This usually takes up to a minute; the status line below shows each step."
    Start-SccmBackground -Mode 'SccmConnect'
})
$script:SccmImportButton.Add_Click({ Start-SccmBackground -Mode 'SccmImport' -DryRun $true })
$script:SccmTargetDP.Add_Checked({ Update-SccmTargetList }); $script:SccmTargetGroup.Add_Checked({ Update-SccmTargetList })
$script:SccmTargetList.Add_SelectionChanged({ if ($script:SccmTargetList.SelectedItem) { $script:SccmTarget.Text = [string]$script:SccmTargetList.SelectedItem } })
$script:SccmContentSource.Add_LostFocus({ Update-SccmUncPreview })
$script:SccmNameResetButton.Add_Click({ $script:SccmImageName.Text = Get-SccmAutoName })
$script:SccmBrowseButton.Add_Click({
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Content source folder for the SCCM import (a folder on this server inside a shared folder)'
    if ($script:SccmContentSource.Text -and (Test-Path -LiteralPath $script:SccmContentSource.Text)) { $dlg.SelectedPath = $script:SccmContentSource.Text }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $script:SccmContentSource.Text = $dlg.SelectedPath; Update-SccmUncPreview }
})
$script:ReadAppsButton.Add_Click({
    # Apps tab: read the selected edition's provisioned apps from the OS ISO on the background runspace (read-only).
    if (-not $script:RunButton.IsEnabled) { return }
    if (-not $script:EngineText) {
        [System.Windows.MessageBox]::Show('Reading the apps needs the script running from a file (the background engine text is unavailable).', 'WimForge', 'OK', 'Error') | Out-Null
        return
    }
    $opts = Get-UiOptions
    $opts | Add-Member -NotePropertyName Mode -NotePropertyValue 'Apps' -Force
    $script:RunButton.IsEnabled = $false; $script:AcquirePatchesButton.IsEnabled = $false; $script:CancelButton.IsEnabled = $true
    $script:Cancelled = $false
    try { Start-BackgroundRun -Options $opts }
    catch {
        $script:RunButton.IsEnabled = $true; $script:AcquirePatchesButton.IsEnabled = $true; $script:CancelButton.IsEnabled = $false
        [System.Windows.MessageBox]::Show("Could not start reading the apps: $($_.Exception.Message)", 'WimForge', 'OK', 'Error') | Out-Null
    }
})
function Save-CurrentRunConfig {
    # Tools > Save run config...: the selected OS's current choices as a run config for MediaRefresh_v2.4.ps1 -Config.
    param([Parameter(Mandatory)][string]$File)
    $sel = Get-SelectedSettings
    $sc = @{ siteServer = ([string]$script:SccmSiteServer.Text).Trim(); targetType = $(if ([bool]$script:SccmTargetGroup.IsChecked) { 'DPGroup' } else { 'DP' }); target = ([string]$script:SccmTarget.Text).Trim()
             contentSource = ([string]$script:SccmContentSource.Text).Trim(); sourceServer = $script:SccmSourceServer; packageType = (Get-SccmPackageTypeTag); imageName = (Get-SccmSelected).ImageName }
    return (Save-RunConfig -File $File -OsName ([string]$script:OsCombo.SelectedItem) -Root ([string]$script:RootText.Text).Trim() -Options $sel.Options -Languages $sel.Languages -RemoveApps $sel.RemoveApps -Sccm $sc)
}
$script:SaveRunConfigItem.Add_Click({
    $def = $script:OsDefinitions[[string]$script:OsCombo.SelectedItem]
    if (-not $def) { return }
    $dir = Join-Path (Split-Path $script:ProfilesDir -Parent) 'Configs'; Ensure-Directory $dir
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.InitialDirectory = $dir; $dlg.FileName = "$($def.Folder)_run.json"; $dlg.Filter = 'WimForge run config (*.json)|*.json'; $dlg.DefaultExt = '.json'
    if (-not $dlg.ShowDialog($window)) { return }
    try {
        $f = Save-CurrentRunConfig -File $dlg.FileName
        Write-Log "Run config for $($def.Name) saved to $f"
        $note = if ([bool]$script:ChkPreflight.IsChecked) { "`n`nNote: 'Preflight check only' is ticked, so this config only runs a preflight." } else { '' }
        [System.Windows.MessageBox]::Show("Run config saved to:`n$f`n`nRun it without the window (elevated Windows PowerShell 5.1):`n.\$(Split-Path $PSCommandPath -Leaf) -Config `"$f`"`n`nAdd -Preflight for a check only. Exit codes: 0 success, 1 failed, 2 validation gate FAILED, 3 SCCM import failed.$note", 'WimForge - run config', 'OK', 'Information') | Out-Null
    } catch { [System.Windows.MessageBox]::Show("Could not save the run config: $($_.Exception.Message)", 'WimForge', 'OK', 'Error') | Out-Null }
})
$script:CleanupMountsItem.Add_Click({
    # Tools > Cleanup Mountpoints: a check-only background pass first; Complete-BackgroundRun lists what it found and
    # asks before a second pass discards / dismounts anything.
    if (-not $script:RunButton.IsEnabled) {
        [System.Windows.MessageBox]::Show('A run is in progress. Cleanup Mountpoints is available once it has finished or been cancelled.', 'WimForge', 'OK', 'Information') | Out-Null
        return
    }
    if (-not $script:EngineText) {
        [System.Windows.MessageBox]::Show('Cleanup Mountpoints needs the script running from a file (the background engine text is unavailable).', 'WimForge', 'OK', 'Error') | Out-Null
        return
    }
    $opts = [pscustomobject]@{ Mode = 'Cleanup'; DryRun = $true; Root = ([string]$script:RootText.Text).Trim(); OsName = [string]$script:OsCombo.SelectedItem }
    $script:PendingCleanupOptions = $opts
    $script:RunButton.IsEnabled = $false; $script:AcquirePatchesButton.IsEnabled = $false; $script:CancelButton.IsEnabled = $true
    $script:Cancelled = $false
    try { Start-BackgroundRun -Options $opts }
    catch {
        $script:RunButton.IsEnabled = $true; $script:AcquirePatchesButton.IsEnabled = $true; $script:CancelButton.IsEnabled = $false
        [System.Windows.MessageBox]::Show("Could not start Cleanup Mountpoints: $($_.Exception.Message)", 'WimForge', 'OK', 'Error') | Out-Null
    }
})
$script:CancelButton.Add_Click({
    $script:Cancelled = $true
    if ($script:RunShared) { $script:RunShared['Cancel'] = $true }
    $script:RunStatus = 'Cancellation requested. Stops at the next safe point; a running DISM operation must finish first.'
    $script:Status.Text = $script:RunStatus
})
$window.Add_Closing({ if (-not $script:RunButton.IsEnabled) { $_.Cancel = $true; [System.Windows.MessageBox]::Show('A servicing operation is active. Use Cancel and allow the current DISM operation to finish.', 'WimForge') | Out-Null } })
[void]$window.ShowDialog()
#endregion GUI
