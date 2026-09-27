. ./mocks.ps1
# ---- extra mocks for the end-to-end run ----
$script:ImageCount = 1
function Get-WindowsImage { [CmdletBinding()] param($ImagePath,$Index,[switch]$Mounted)
  if ($Mounted) { return $script:MountedList }
  if ($Index) { return [pscustomobject]@{ ImageIndex=$Index; ImageName="Img$Index"; Version='10.0.17763.9121' } }
  if ($ImagePath -like '*_isos*') { $i=0; return @($script:SourceNames | ForEach-Object { $i++; [pscustomobject]@{ ImageIndex=$i; ImageName=$_ } }) }
  return @(1..$script:ImageCount | ForEach-Object { [pscustomobject]@{ ImageIndex=$_; ImageName=$(if ($script:ImageCount -eq 1) {'Windows 10 Enterprise LTSC'} else {"Edition$_"}) } }) }
$script:SourceNames = @('Windows 10 Enterprise LTSC')
function Get-WindowsPackage { [CmdletBinding()] param($Path,$LogPath)
  return @([pscustomobject]@{ PackageName='Package_for_RollupFix~31bf3856ad364e35~amd64~~17763.9121.1.9'; PackageState='Installed'; ReleaseType='Update' }) + $script:ExtraPkgs + @($script:MockImagePackages) }
function Get-WindowsCapability { [CmdletBinding()] param($Path,$LogPath) return $script:Caps }
$script:AttachedIsos = [System.Collections.Generic.List[string]]::new()   # ISO files "mounted" outside a run (E15)
function Dismount-DiskImage { [CmdletBinding()] param($ImagePath) Note "IsoDismount $(Split-Path $ImagePath -Leaf)"; [void]$script:AttachedIsos.Remove([string]$ImagePath) }
function Get-DiskImage { [CmdletBinding()] param($ImagePath) [pscustomobject]@{ ImagePath = $ImagePath; Attached = $script:AttachedIsos.Contains([string]$ImagePath) } }
function Clear-WindowsCorruptMountPoint { [CmdletBinding()] param() Note 'ClearCorruptMountPoint' }
$script:IsoMap = @{}
function Mount-IsoFile { param([string]$ImagePath) $script:MountedIsoPaths.Add($ImagePath); return $script:IsoMap[(Split-Path $ImagePath -Leaf)] }
$script:ExtraPkgs = @(); $script:Caps = @()

$pass=0;$fail=0
function Check($name,[bool]$ok,$detail=''){ if($ok){$script:pass++;Write-Host "PASS  $name" -ForegroundColor Green}else{$script:fail++;Write-Host "FAIL  $name  $detail" -ForegroundColor Red} }
function Reset-Test { $script:Calls.Clear(); $script:MountedList=@(); $script:MountedIsoPaths.Clear() }
function New-File($p,$c='x'){ New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null; Set-Content $p $c }
$base = Join-Path $PWD 'e2e'; if (Test-Path $base) { Remove-Item -Recurse -Force $base }; New-Item -ItemType Directory $base | Out-Null
$isos = Join-Path $base '_isos'
function Fake-Iso($repoOsFolder,$isoName,$files){ $d = Join-Path $isos $isoName; foreach($f in $files){ New-File (Join-Path $d $f) }; New-File (Join-Path (Join-Path (Join-Path $base $repoOsFolder) 'ISO') "$isoName.iso"); $script:IsoMap["$isoName.iso"] = $d }
function Opts($os,$langs,[hashtable]$o=@{}) {
  $d = @{ Preflight=$false;Install=$true;Boot=$false;WinRE=$true;Verify=$true;BuildMedia=$false;BuildIso=$false;SSU=$true;LCU=$true;SafeOS=$true;NetCU=$true;SetupDU=$true;NetFx3=$true }
  foreach($k in $o.Keys){$d[$k]=$o[$k]}
  [pscustomobject]@{ OsName=$os; Root=$base; PreflightOnly=[bool]$d.Preflight; Install=$d.Install;Boot=$d.Boot;WinRE=$d.WinRE;Verify=$d.Verify;BuildMedia=$d.BuildMedia;BuildIso=$d.BuildIso;SSU=$d.SSU;LCU=$d.LCU;SafeOS=$d.SafeOS;NetCU=$d.NetCU;SetupDU=$d.SetupDU;NetFx3=$d.NetFx3;Languages=@($langs) } }
function Patches($folder,$files){ foreach($f in $files){ New-File (Join-Path (Join-Path (Join-Path $base $folder) 'PATCHES') $f) } }
$langs10 = @('de-de','en-gb','es-es','fr-fr','it-it','ja-jp','ko-kr','pt-br','zh-cn','zh-tw')

Write-Host "`n=== E1 LTSC 2019, 10 languages, but NO Language Pack ISO in the folder (the situation in your logs) ==="
Reset-Test
Fake-Iso 'Win10_Enterprise_LTSC_2019' 'os2019' @('sources/install.wim','sources/sxs/a.cab')
Fake-Iso 'Win10_Enterprise_LTSC_2019' 'fod1809' @('Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~x.cab')
Patches 'Win10_Enterprise_LTSC_2019' @('SSU/windows10.0-kb5005112-x64_81d0.msu','LCU/windows10.0-kb5120238-x64_9260.msu','NETCU/windows10.0-kb5120703-x64-ndp48_6b0e.msu','SAFEOSDU/safeos.cab')
$threw=$false; try { Invoke-MediaRefresh (Opts 'Windows 10 Enterprise LTSC 2019 (IoT)' $langs10) } catch { $threw=$true; $msg=$_.Exception.Message }
Write-Host "   -> $msg"
Check 'stops early with a Language Pack ISO message' ($threw -and $msg -like '*no Language Pack ISO*')
Check 'no image was ever mounted (no 2-hour wasted run)' (-not ($script:Calls -match '^Mount '))
Check 'ISOs were dismounted' (@($script:Calls | Where-Object {$_ -like 'IsoDismount*'}).Count -eq 2)

Write-Host "`n=== E2 same folder, LP ISO added -> full run with verification ==="
Reset-Test; $script:ImageCount=1
Fake-Iso 'Win10_Enterprise_LTSC_2019' 'lpall' (@($langs10 | % { "x64/langpacks/Microsoft-Windows-Client-Language-Pack_x64_$_.cab" }))
# verification data: image contains all LPs and fonts
$script:ExtraPkgs = @($langs10 | % { [pscustomobject]@{ PackageName="Microsoft-Windows-Client-LanguagePack-Package~31bf3856ad364e35~amd64~$($_.Substring(0,3))$($_.Substring(3).ToUpper())~10.0.17763.1"; PackageState='Installed'; ReleaseType='LanguagePack' } })
$script:Caps = @('Jpan','Kore','Hans','Hant' | % { [pscustomobject]@{ Name="Language.Fonts.$_~~~und-$($_.ToUpper())~0.0.1.0"; State='Installed' } })
Invoke-MediaRefresh (Opts 'Windows 10 Enterprise LTSC 2019 (IoT)' $langs10)
$seq = $script:Calls -join "`n"
Check 'run completed and returned a result' ($null -ne $script:LastResult -and $script:LastResult.VerifyIssues -eq 0) "issues=$($script:LastResult.VerifyIssues)"
Check '10 language packs added' (@($script:Calls | Where-Object { $_ -match 'AddPkg Microsoft-Windows-Client-Language-Pack_x64_' }).Count -eq 10)
Check 'all 4 font capabilities added' (@($script:Calls | Where-Object { $_ -match 'AddCap Language.Fonts' }).Count -eq 4)
Check 'read-only verify mount happened after the final export' ((($script:Calls | Select-String 'Export -> install.wim').LineNumber | Select-Object -Last 1) -lt (($script:Calls | Select-String 'Mount install.wim').LineNumber | Select-Object -Last 1))
Check 'nothing left mounted / ISOs dismounted' ($script:MountedList.Count -eq 0 -and @($script:Calls | Where-Object {$_ -like 'IsoDismount*'}).Count -eq 3)

Write-Host "`n=== E2b Step 3: validation gate, change events and change log for the clean E2 run ==="
Check 'validation gate PASSED (0 issues)' ($script:LastResult.Gate -eq 'PASSED') "Gate=$($script:LastResult.Gate)"
Check 'change events were recorded (SSU/LCU/LanguagePack/Font)' (
    (@($script:ChangeEvents | Where-Object { $_.Category -eq 'SSU' }).Count -ge 1) -and
    (@($script:ChangeEvents | Where-Object { $_.Category -eq 'LCU' }).Count -ge 1) -and
    (@($script:ChangeEvents | Where-Object { $_.Category -eq 'LanguagePack' }).Count -eq 10) -and
    (@($script:ChangeEvents | Where-Object { $_.Category -eq 'Font' }).Count -eq 4)
) "categories=$(($script:ChangeEvents | Select-Object -ExpandProperty Category -Unique) -join ',')"
Check 'Section B inventory was collected (Verify=true)' (@($script:VerifyInventory).Count -gt 0)
Check 'change log files exist and were copied to NEWWIM' (
    ($null -ne $script:LastResult.ChangeLogHtml) -and (Test-Path -LiteralPath $script:LastResult.ChangeLogHtml) -and
    ($null -ne $script:LastResult.ChangeLogCsv) -and (Test-Path -LiteralPath $script:LastResult.ChangeLogCsv) -and
    (Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $base 'Win10_Enterprise_LTSC_2019') 'NEWWIM') (Split-Path $script:LastResult.ChangeLogHtml -Leaf)))
)
$csvRows2 = @(Import-Csv -LiteralPath $script:LastResult.ChangeLogCsv)
$missingCols2 = @(@('Date','Section','Item','Version / KB','State','Source','Index') | Where-Object { $_ -notin $csvRows2[0].PSObject.Properties.Name })
Check 'CSV has the required columns' ($csvRows2.Count -gt 0 -and $missingCols2.Count -eq 0) "columns=$($csvRows2[0].PSObject.Properties.Name -join ',')"
$html2 = Get-Content -Raw -LiteralPath $script:LastResult.ChangeLogHtml
Check 'HTML header names the OS and shows PASSED' ($html2 -match 'Windows 10 Enterprise LTSC 2019' -and $html2 -match 'PASSED')

Write-Host "`n=== E3 verification catches a missing LP and missing LCU ==="
Reset-Test; $script:ExtraPkgs=@(); $script:Caps=@()
function Get-WindowsPackage { [CmdletBinding()] param($Path,$LogPath) return @() }
Invoke-MediaRefresh (Opts 'Windows 10 Enterprise LTSC 2019 (IoT)' $langs10)
Check 'issues reported (no RollupFix, 10 LPs, 4 fonts = 15)' ($script:LastResult.VerifyIssues -eq 15) "issues=$($script:LastResult.VerifyIssues)"
Check 'validation gate FAILED (issues > 0)' ($script:LastResult.Gate -eq 'FAILED') "Gate=$($script:LastResult.Gate)"
$html3 = Get-Content -Raw -LiteralPath $script:LastResult.ChangeLogHtml
Check 'HTML header shows FAILED for the dirty run' ($html3 -match 'FAILED')

Write-Host "`n=== E4 Win11 English-only, no SSU folder content, no languages ==="
function Get-WindowsPackage { [CmdletBinding()] param($Path,$LogPath) return @([pscustomobject]@{ PackageName='Package_for_RollupFix~31bf3856ad364e35~amd64~~26100.1.1.9'; PackageState='Installed'; ReleaseType='Update' }) }
Reset-Test; $script:ImageCount=1; $script:SourceNames=@('Windows 11 Pro','Windows 11 Pro N','Windows 11 Enterprise')
Fake-Iso 'Win11Enterprise_24H2' 'os11' @('sources/install.wim')      # folder name as you typed it (alias)
Patches 'Win11Enterprise_24H2' @('LCU/windows11.0-kb1-x64.msu')
Invoke-MediaRefresh (Opts 'Windows 11 Enterprise 24H2' @() @{ NetFx3=$false })
Check 'no-language run works, alias folder used, no duplicate folder created' (($null -ne $script:LastResult) -and -not (Test-Path (Join-Path $base 'Win11_Enterprise_24H2')))
Check 'single LCU pass' (@($script:Calls | Where-Object { $_ -match 'AddPkg windows11.0-kb1-x64.msu @ MainOS' }).Count -eq 1)

Write-Host "`n=== E5 Server 2022: 4 indexes, English only ==="
Reset-Test; $script:ImageCount=4; $script:SourceNames=@('Std Core','Std Desktop','DC Core','DC Desktop')
Fake-Iso 'Windows_Server_2022' 'os2022' @('sources/install.wim')
Fake-Iso 'Windows_Server_2022' 'svrlp' @('LanguagesAndOptionalFeatures/Microsoft-Windows-Server-Language-Pack_x64_de-de.cab','LanguagesAndOptionalFeatures/Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~x.cab')
Patches 'Windows_Server_2022' @('LCU/windows10.0-kb2-x64.msu','SAFEOSDU/safeos.cab')
Invoke-MediaRefresh (Opts 'Windows Server 2022' @() @{ NetFx3=$false })
Check 'all 4 indexes serviced' (@($script:Calls | Where-Object { $_ -match '^Mount install.working.wim idx' }).Count -eq 4)
Check 'WinRE serviced once' (@($script:Calls | Where-Object { $_ -match 'DISM: Cleaning WinRE' }).Count -eq 1)
Check 'final WIM has 4 indexes' ($script:LastResult.Install -like '*install.wim')

Write-Host "`n=== E6 Missing LCU stops the run before any mount ==="
Reset-Test; $script:ImageCount=1; $script:SourceNames=@('Windows 10 Enterprise LTSC 2021')
Fake-Iso 'Win10_Enterprise_LTSC_2021_KMS' 'os2021' @('sources/install.wim')
Patches 'Win10_Enterprise_LTSC_2021_KMS' @('SSU/ssu-19041.3562-x64.msu')
$threw=$false; try { Invoke-MediaRefresh (Opts 'Windows 10 Enterprise LTSC 2021 (KMS)' @()) } catch { $threw=$true; $msg=$_.Exception.Message }
Check 'empty LCU folder is fatal with a clear message' ($threw -and $msg -like '*PATCHES\LCU is empty*')

Write-Host "`n=== E7 Preflight only: checks everything, changes nothing ==="
Reset-Test; $script:ImageCount=1; $script:SourceNames=@('Windows 10 Enterprise LTSC 2021')
Patches 'Win10_Enterprise_LTSC_2021_KMS' @('LCU/windows10.0-kb3-x64.msu')
Fake-Iso 'Win10_Enterprise_LTSC_2021_KMS' 'fod2021' @('Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~x.cab')
Fake-Iso 'Win10_Enterprise_LTSC_2021_KMS' 'lp2021' @('x64/langpacks/Microsoft-Windows-Client-Language-Pack_x64_de-de.cab','x64/langpacks/Microsoft-Windows-Client-Language-Pack_x64_ja-jp.cab')
$script:ExtraPkgs=@(); $script:Caps=@()
Invoke-MediaRefresh (Opts 'Windows 10 Enterprise LTSC 2021 (KMS)' @('de-de','ja-jp') @{ Preflight=$true })
Check 'preflight passes and flags itself' ($script:LastResult.Preflight -eq $true)
Check 'no image is changed: no export, package, capability or feature call, and nothing is saved' (@($script:Calls | Where-Object { $_ -match '^(Export|AddPkg|AddCap|EnableFeature)|save$' }).Count -eq 0) ($script:Calls -join '; ')
Check 'the only mount is the read-only one for the Apps tab list (no list yet), discarded again' ((@($script:Calls | Where-Object { $_ -match '^Mount ' }) -join '|') -eq 'Mount install.wim idx1 -> MainOS' -and ($script:Calls -contains 'Dismount MainOS discard')) ($script:Calls -join '; ')
Check 'ISOs dismounted afterwards' (@($script:Calls | Where-Object {$_ -like 'IsoDismount*'}).Count -eq 3)
# Host DISM vs image (TODO step 4): checked in preflight too, before anything is exported
$script:HostDism = '10.0.20348.2849'
$out7h = (Invoke-MediaRefresh (Opts 'Windows 10 Enterprise LTSC 2021 (KMS)' @('de-de','ja-jp') @{ Preflight=$true }) *>&1 | Out-String)
Check 'preflight logs the host DISM and image versions' ($out7h -match 'Host DISM 10\.0\.20348\.2849; image 10\.0\.17763\.9121 \(index 1\)')
Check 'preflight: no host-DISM WARN when the host is newer than the image' ($out7h -notmatch 'is older than the image build')
$script:HostDism = '10.0.17134.1'
$out7h = (Invoke-MediaRefresh (Opts 'Windows 10 Enterprise LTSC 2021 (KMS)' @('de-de','ja-jp') @{ Preflight=$true }) *>&1 | Out-String)
Check 'preflight WARNs when the host DISM is older than the image, and still passes' ($out7h -match '\[WARN\] Host DISM build 17134 is older than the image build 17763' -and $script:LastResult.Preflight -eq $true)
$hd = Test-DismHostVersion -ImagePath 'x.wim' -Index 2
Check 'Test-DismHostVersion reads the given index and reports the result' ($hd.HostOlder -and $hd.Image -eq [version]'10.0.17763.9121' -and $hd.Host -eq [version]'10.0.17134.1')
function Get-HostDismVersion { throw 'dism.exe not found' }
$out7h = (Invoke-MediaRefresh (Opts 'Windows 10 Enterprise LTSC 2021 (KMS)' @('de-de','ja-jp') @{ Preflight=$true }) *>&1 | Out-String)
Check 'a host DISM that cannot be read is a WARN, never fatal' ($out7h -match 'Could not compare host DISM and image versions: dism.exe not found' -and $script:LastResult.Preflight -eq $true)
function Get-HostDismVersion { return [version]$script:HostDism }
$script:HostDism = '10.0.26100.1'
Reset-Test
$threw=$false; try { Invoke-MediaRefresh (Opts 'Windows 10 Enterprise LTSC 2021 (KMS)' @('de-de','fr-fr') @{ Preflight=$true }) } catch { $threw=$true; $m7=$_.Exception.Message }
Check 'preflight catches a language pack that is not on the ISO (fr-fr)' ($threw -and $m7 -like '*fr-fr*')


Write-Host "`n=== E8 One ISO holding BOTH an Enterprise LTSC index and an IoT index (the reported error) ==="
Reset-Test; $script:ImageCount=1; $script:SourceNames=@('Windows 10 Enterprise LTSC 2021','Windows 10 IoT Enterprise LTSC 2021')
Fake-Iso 'Win10_IoT_Enterprise_LTSC_2021' 'os2021iot' @('sources/install.wim')
Patches 'Win10_IoT_Enterprise_LTSC_2021' @('SSU/ssu-19041.3562-x64.msu','LCU/windows10.0-kb3-x64.msu')
$script:LogCapture = @()
Invoke-MediaRefresh (Opts 'Windows 10 IoT Enterprise LTSC 2021' @() @{ Preflight=$true })
Check 'IoT profile picks the IoT index without an error' ($script:LastResult.Preflight -eq $true)
Invoke-MediaRefresh (Opts 'Windows 10 IoT Enterprise LTSC 2021' @() @{ Preflight=$true }) *>&1 | Out-String | Set-Variable out8
Check 'IoT profile selected index 2' ($out8 -match 'Selected client image index 2: Windows 10 IoT Enterprise LTSC 2021')
Get-ChildItem (Join-Path $base 'Win10_Enterprise_LTSC_2021_KMS\ISO') -Filter *.iso -ErrorAction SilentlyContinue | Remove-Item -Force; Reset-Test; $script:SourceNames=@('Windows 10 Enterprise LTSC 2021','Windows 10 IoT Enterprise LTSC 2021')
Fake-Iso 'Win10_Enterprise_LTSC_2021_KMS' 'os2021kms' @('sources/install.wim')
Patches 'Win10_Enterprise_LTSC_2021_KMS' @('SSU/ssu-19041.3562-x64.msu','LCU/windows10.0-kb3-x64.msu')
Invoke-MediaRefresh (Opts 'Windows 10 Enterprise LTSC 2021 (KMS)' @() @{ Preflight=$true }) *>&1 | Out-String | Set-Variable out8b
Check 'KMS profile selected index 1 (the non-IoT edition)' ($out8b -match 'Selected client image index 1: Windows 10 Enterprise LTSC 2021')
# real ISO layouts (Terry, 2026-09-27): KMS = [1] Enterprise LTSC, [2] Enterprise N LTSC; IoT = [1] Enterprise LTSC, [2] IoT Enterprise LTSC
Reset-Test; $script:SourceNames=@('Windows 10 Enterprise LTSC','Windows 10 Enterprise N LTSC')
Invoke-MediaRefresh (Opts 'Windows 10 Enterprise LTSC 2021 (KMS)' @() @{ Preflight=$true }) *>&1 | Out-String | Set-Variable out8c
Check 'KMS real layout: index 1 (Enterprise LTSC), not the N edition' ($out8c -match 'Selected client image index 1: Windows 10 Enterprise LTSC\r?\n' -and $out8c -notmatch 'preferred index')
Reset-Test; $script:SourceNames=@('Windows 10 Enterprise LTSC','Windows 10 IoT Enterprise LTSC')
Invoke-MediaRefresh (Opts 'Windows 10 IoT Enterprise LTSC 2021' @() @{ Preflight=$true }) *>&1 | Out-String | Set-Variable out8d
Check 'IoT real layout: index 2 (IoT Enterprise LTSC), no index warning' ($out8d -match 'Selected client image index 2: Windows 10 IoT Enterprise LTSC' -and $out8d -notmatch 'preferred index')
Reset-Test; $script:SourceNames=@('Windows 10 Enterprise LTSC','Windows 10 IoT Ent LTSC renamed')
Invoke-MediaRefresh (Opts 'Windows 10 IoT Enterprise LTSC 2021' @() @{ Preflight=$true }) *>&1 | Out-String | Set-Variable out8e
Check 'IoT name not recognised: falls back to index 2, never index 1' ($out8e -match 'falling back to preferred index 2' -and $out8e -match 'Selected client image index 2:')
Reset-Test; $script:SourceNames=@('Windows 10 IoT Enterprise LTSC','Windows 10 Enterprise LTSC')
Invoke-MediaRefresh (Opts 'Windows 10 IoT Enterprise LTSC 2021' @() @{ Preflight=$true }) *>&1 | Out-String | Set-Variable out8f
Check 'IoT edition found at an unexpected index: used, with a WARN naming the preferred index' ($out8f -match 'Selected client image index 1: Windows 10 IoT Enterprise LTSC' -and $out8f -match "not the profile's preferred index 2")
# genuinely ambiguous ISO: the message must list indexes and names
Reset-Test; $script:SourceNames=@('Windows 10 IoT Enterprise LTSC 2021','Windows 10 IoT Enterprise LTSC')
$threw=$false; try { Invoke-MediaRefresh (Opts 'Windows 10 IoT Enterprise LTSC 2021' @() @{ Preflight=$true }) } catch { $threw=$true; $m8=$_.Exception.Message }
Check 'ambiguous match is still an error but lists index and name for each image' ($threw -and $m8.Contains('[1] Windows 10 IoT Enterprise LTSC 2021;') -and $m8.Contains('[2] Windows 10 IoT Enterprise LTSC') -and $m8 -match 'Tighten EditionRegex')


Write-Host "`n=== E9 profile files, order manifest and support status through a real (preflight) run ==="
Reset-Test; $script:ImageCount=1; $script:SourceNames=@('Windows 10 Enterprise LTSC 2021')
$profDir = Join-Path $base '_profiles'
Patches 'Win10_Enterprise_LTSC_2021_KMS' @('SSU/aaa-extra.msu')
function OptsP($os,$langs,[hashtable]$o=@{}) { $x = Opts $os $langs $o; $x | Add-Member -NotePropertyName ProfilesDir -NotePropertyValue $profDir; $x }
$out9 = (Invoke-MediaRefresh (OptsP 'Windows 10 Enterprise LTSC 2021 (KMS)' @() @{ Preflight=$true }) *>&1 | Out-String)
Check 'first run created the profile files' (@(Get-ChildItem $profDir -Filter *.json).Count -eq 5)
Check 'log names the profile file' ($out9 -match 'Profile: Win10_Enterprise_LTSC_2021_KMS\.json')
Check 'log states the support end date' ($out9 -match 'Support (ends|ended) 2027-01-13')
Check 'log reports the profile file creation' ($out9 -match 'Profile files created from the built-in profiles')
Check 'default order = name order' ($out9 -match 'SSU order: aaa-extra\.msu -> ssu-19041\.3562-x64\.msu')
$pf = Join-Path $profDir 'Win10_Enterprise_LTSC_2021_KMS.json'
$j = Get-Content $pf -Raw | ConvertFrom-Json; $j.packageOrder.SSU = @('ssu-19041*'); $j.notes = 'edited'
[System.IO.File]::WriteAllText($pf, ($j | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
Reset-Test
$out9b = (Invoke-MediaRefresh (OptsP 'Windows 10 Enterprise LTSC 2021 (KMS)' @() @{ Preflight=$true }) *>&1 | Out-String)
Check 'edited JSON is picked up on the next run (SSU manifest)' ($out9b -match 'SSU order: ssu-19041\.3562-x64\.msu -> aaa-extra\.msu') $out9b
$j.packageOrder.SSU = @('ssu-19041*'); $j.editionRegex = '(unclosed'
[System.IO.File]::WriteAllText($pf, ($j | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
Reset-Test; $threw=$false; $m9=''
try { Invoke-MediaRefresh (OptsP 'Windows 10 Enterprise LTSC 2021 (KMS)' @() @{ Preflight=$true }) *>&1 | Out-Null } catch { $threw=$true; $m9=$_.Exception.Message }
Check 'a broken profile file removes that OS from the list; the run says Unknown OS profile' ($threw -and $m9 -like "*Unknown OS profile*")
Remove-Item (Join-Path $base 'Win10_Enterprise_LTSC_2021_KMS\PATCHES\SSU\aaa-extra.msu') -Force
Remove-Item $profDir -Recurse -Force
$script:OsDefinitions = Import-OsProfiles   # back to the built-ins for the remaining scenarios

Write-Host "`n=== E10 a second run archives the first run's output instead of overwriting it ==="
Reset-Test; $script:ImageCount=1; $script:SourceNames=@('Windows 10 Enterprise LTSC 2021')
$newDir = Join-Path $base 'Win10_Enterprise_LTSC_2021_KMS\NEWWIM'
Get-ChildItem $newDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
Invoke-MediaRefresh (Opts 'Windows 10 Enterprise LTSC 2021 (KMS)' @() @{ Verify=$false })
Check 'first run: output exists, nothing archived' ((Test-Path (Join-Path $newDir 'install.wim')) -and -not (Test-Path (Join-Path $newDir 'Archive')))
Check 'gate is Skipped when Verify is off' ($script:LastResult.Gate -eq 'Skipped') "Gate=$($script:LastResult.Gate)"
Check 'Section B inventory is empty when Verify is off' (@($script:VerifyInventory).Count -eq 0)
Set-Content (Join-Path $newDir 'install.wim') 'FIRST-RUN'
Start-Sleep -Seconds 1
Reset-Test
$out10 = (Invoke-MediaRefresh (Opts 'Windows 10 Enterprise LTSC 2021 (KMS)' @() @{ Verify=$false }) *>&1 | Out-String)
$arch = @(Get-ChildItem (Join-Path $newDir 'Archive') -Directory -ErrorAction SilentlyContinue)
Check 'second run: one archive folder holding the first run output' ($arch.Count -eq 1 -and (Get-Content (Join-Path $arch[0].FullName 'install.wim')) -eq 'FIRST-RUN')
Check 'second run wrote a new install.wim' ((Get-Content (Join-Path $newDir 'install.wim')) -eq 'x')
Check 'archive was logged' ($out10 -match 'Previous output \(\d+ item\(s\)\) archived to')
Reset-Test
$script:LastResult = $null
Invoke-MediaRefresh (Opts 'Windows 10 Enterprise LTSC 2021 (KMS)' @() @{ Preflight=$true })
Check 'preflight never archives' (@(Get-ChildItem (Join-Path $newDir 'Archive') -Directory).Count -eq 1)

Write-Host "`n=== E11 too little free space stops the run before any image is touched ==="
Reset-Test; $script:FreeGB = 5.0; $threw=$false; $m11=''
try { Invoke-MediaRefresh (Opts 'Windows 10 Enterprise LTSC 2021 (KMS)' @() @{ Preflight=$true }) *>&1 | Out-Null } catch { $threw=$true; $m11=$_.Exception.Message }
Check 'preflight fails with the space message' ($threw -and $m11 -like 'Not enough free disk space.*5*') $m11
Check 'no mount or export happened' (-not ($script:Calls -match '^Mount |^Export'))
Check 'ISOs were dismounted afterwards' (@($script:Calls | Where-Object { $_ -like 'IsoDismount*' }).Count -ge 1)
$script:FreeGB = 500.0

Write-Host "`n=== E12 Win11 LCU with its checkpoint in PATCHES\LCU: only the target LCU is ever added (Microsoft's method) ==="
# After the 2026-09-24 download the Win11 LCU folder holds the out-of-band LCU and checkpoint KB5043080 (the catalog
# entry carries both). DISM applies the checkpoint from the same folder when needed; it must never be added directly.
Reset-Test; $script:ImageCount=1; $script:SourceNames=@('Windows 11 Pro','Windows 11 Pro N','Windows 11 Enterprise')
$lcu12 = Join-Path $base 'Win11Enterprise_24H2\PATCHES\LCU'; Get-ChildItem $lcu12 -File -ErrorAction SilentlyContinue | Remove-Item -Force
Fake-Iso 'Win11Enterprise_24H2' 'os11' @('sources/install.wim', 'sources/boot.wim')
Patches 'Win11Enterprise_24H2' @('LCU/windows11.0-kb5043080-x64.msu', 'LCU/windows11.0-kb5129195-x64.msu')
$logs12 = [System.Collections.Generic.List[string]]::new()
$wl = ${function:Write-Log}; function Write-Log { param($Message,$Level='INFO') $logs12.Add("[$Level] $Message") }
Invoke-MediaRefresh (Opts 'Windows 11 Enterprise 24H2' @() @{ NetFx3=$false; Boot=$true; BuildMedia=$true; SetupDU=$false })   # boot.wim is patched only for the media
Set-Item function:Write-Log $wl
$add12 = @($script:Calls -match '^AddPkg windows11\.0-kb')
Check 'the checkpoint KB5043080 is never added directly (install.wim, WinRE or WinPE)' (@($add12 -match 'kb5043080').Count -eq 0) ($add12 -join ' | ')
Check 'the target LCU KB5129195 is added to install.wim, WinRE and boot.wim' (@($add12 -match 'kb5129195').Count -ge 3) ($add12 -join ' | ')
$lcuLines12 = @($logs12 -match '^\[INFO\] Adding LCU .*kb5129195')
Check 'WinRE log line says the LCU gives WinRE its servicing stack only; install.wim and boot.wim lines do not' (@($lcuLines12 | Where-Object { $_ -match ' to WinRE$' }).Count -eq 1 -and @($lcuLines12 | Where-Object { $_ -match ' to WinRE$' -and $_ -notmatch 'Adding LCU \(servicing stack only\) ' }).Count -eq 0 -and @($lcuLines12 | Where-Object { $_ -notmatch ' to WinRE$' -and $_ -notmatch 'servicing stack only' }).Count -ge 2) ($logs12 -match '^\[INFO\] Adding LCU' -join ' | ')
Check 'the log says only the target is installed and names the checkpoint left in the folder' ([bool]($logs12 -match 'LCU: only windows11\.0-kb5129195-x64\.msu is installed; windows11\.0-kb5043080-x64\.msu stay in the folder'))
$ps12 = Get-PackageSet -PatchRoot (Join-Path $base 'Win11Enterprise_24H2\PATCHES') -Enabled @{ LCU=$true }
Check 'Get-PackageSet: LCU = the target, LcuCheckpoints = the checkpoint' ((@($ps12.LCU).Name -join ',') -eq 'windows11.0-kb5129195-x64.msu' -and (@($ps12.LcuCheckpoints).Name -join ',') -eq 'windows11.0-kb5043080-x64.msu')
function FI($n) { [pscustomobject]@{ Name = $n; FullName = "C:\p\$n"; Extension = [IO.Path]::GetExtension($n); DirectoryName = 'C:\p' } }
$r1 = Resolve-LcuTarget -Files @((FI 'windows10.0-kb5129238-x64.msu'))
Check 'Resolve-LcuTarget: a single LCU (every Win10 / Server profile) is installed as before' ((@($r1.Install).Name -join ',') -eq 'windows10.0-kb5129238-x64.msu' -and @($r1.Checkpoints).Count -eq 0)
$r2 = Resolve-LcuTarget -Files @((FI 'a.msu'), (FI 'b.cab'))
Check 'Resolve-LcuTarget: no KB numbers to go by -> everything installed, as before' (@($r2.Install).Count -eq 2 -and @($r2.Checkpoints).Count -eq 0)
$r3 = Resolve-LcuTarget -Files @((FI 'windows11.0-kb5129195-x64.msu'), (FI 'windows11.0-kb5043080-x64.msu'), (FI 'windows11.0-kb5060842-x64.msu'))
Check 'Resolve-LcuTarget: with several checkpoints the highest KB is the target' ((@($r3.Install).Name -join ',') -eq 'windows11.0-kb5129195-x64.msu' -and @($r3.Checkpoints).Count -eq 2)

Write-Host "`n=== E13 change log fixes from Terry's 2026-09-25 Win11 run ==="
# 1. Section A rows carry the time each step succeeded (the real log had every row at the write time, 11:04:10)
$cl13 = Join-Path $base 'cl13'; New-Item -ItemType Directory -Force (Join-Path $cl13 'LOGS'), (Join-Path $cl13 'NEWWIM') | Out-Null
$ev13 = @(
    [pscustomobject]@{ Time = [datetime]'2026-09-25 09:51:32'; Category = 'LCU'; Item = 'windows11.0-kb5129195-x64.msu'; Kb = 'KB5129195'; Target = 'WinRE'; Detail = 'LCU' },
    [pscustomobject]@{ Time = [datetime]'2026-09-25 10:28:49'; Category = 'LCU'; Item = 'windows11.0-kb5129195-x64.msu'; Kb = 'KB5129195'; Target = 'install.wim index 1'; Detail = 'LCU (final)' })
$paths13 = @{ Logs = (Join-Path $cl13 'LOGS'); NewWim = (Join-Path $cl13 'NEWWIM') }
$out13 = Write-ChangeLog -OsName 'Windows 11 Enterprise 24H2' -Paths $paths13 -Stamp '20260925_094434' -ToolVersion '2.4.0' -BuildBefore '10.0.26100.9168' -BuildAfter '10.0.26100.9457' -Events $ev13 -Inventory @() -Gate 'PASSED' -VerifyRan $false
$csvPath13 = @(Get-ChildItem (Join-Path $cl13 'LOGS') -Filter '*.csv')[0].FullName
$a13 = @(Import-Csv -LiteralPath $csvPath13 | Where-Object { $_.Section -eq 'A' })
Check 'Section A rows carry each step''s own time, not the time the log was written' ((@($a13.Date) -join ',') -eq '2026-09-25 09:51:32,2026-09-25 10:28:49') (@($a13.Date) -join ',')
$html13 = Get-Content -Raw -LiteralPath (@(Get-ChildItem (Join-Path $cl13 'LOGS') -Filter '*.html')[0].FullName)
Check 'the HTML shows the same per-step times' ($html13 -match '2026-09-25 09:51:32' -and $html13 -match '2026-09-25 10:28:49')
# 2. the Setup DU expanded into the media is recorded in Section A
$script:ChangeEvents.Clear()
$os13 = Join-Path $base 'os13'; New-File (Join-Path $os13 'setup.exe'); New-File (Join-Path $os13 'sources\setup.exe')
$wim13 = Join-Path $base 'wim13\install.wim'; New-File $wim13
$du13dir = Join-Path $base 'du13'; New-File (Join-Path $du13dir 'setuphost.exe') 'fake setup DU payload'
$cab13 = Join-Path $du13dir 'windows11.0-kb5127216-x64.cab'
$makecab = Join-Path $env:SystemRoot 'System32\makecab.exe'
if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and (Test-Path $makecab)) {
    # A real Setup DU cab holds many files (a one-file makecab cab would expand to its own name, not its content)
    New-File (Join-Path $du13dir 'setupprep.exe') 'fake setup DU payload 2'
    Set-Content (Join-Path $du13dir 'list.txt') "setuphost.exe`r`nsetupprep.exe"
    Push-Location $du13dir
    $mcArgs = @('/D', 'CompressionType=MSZIP', '/D', "DiskDirectoryTemplate=$du13dir", '/D', "CabinetNameTemplate=$(Split-Path $cab13 -Leaf)", '/F', (Join-Path $du13dir 'list.txt'))
    & $makecab @mcArgs | Out-Null
    Pop-Location
    $media13 = New-RefreshedMedia -OsDrive $os13 -Paths @{ NewWim = (Join-Path $base 'newwim13') } -InstallWim $wim13 -BootWim '' -SetupDu @((Get-Item $cab13))
    $du13 = @($script:ChangeEvents | Where-Object { $_.Category -eq 'SetupDU' })
    Check 'the Setup DU expanded into the media is recorded as a change event (KB5127216, Media\sources)' ($du13.Count -eq 1 -and $du13[0].Kb -eq 'KB5127216' -and $du13[0].Target -eq 'Media\sources' -and (Test-Path (Join-Path $media13 'sources\setuphost.exe')))
} else { Write-Host 'SKIP  Setup DU change event (needs Windows makecab.exe/expand.exe)' }
# 3. housekeeping folders under WindowsApps are not listed as staged appx packages
$names13 = @('Clipchamp.Clipchamp_4.4.10720.0_x64__yxz26nhyzhsrt', 'Clipchamp.Clipchamp_4.4.10720.0_neutral_split.scale-100_yxz26nhyzhsrt', 'Microsoft.ApplicationCompatibilityEnhancements_1.2511.9.0_neutral_~_8wekyb3d8bbwe', 'Deleted', 'Merged', 'MovedPackages', 'DeletedAllUserPackages', 'Mutable')
$kept13 = @($names13 | Where-Object { Test-AppxPackageFolder $_ })
Write-Host "`n=== E14 languages go into install.wim only: WinRE and boot.wim stay English-only (Terry, 2026-09-26) ==="
# Ten languages with WinRE AND Boot ticked, and an LP ISO that also carries the WinPE language cabs the old code used
Reset-Test; $script:ImageCount=1
Fake-Iso 'Win10_Enterprise_LTSC_2019' 'os2019' @('sources/boot.wim')
Fake-Iso 'Win10_Enterprise_LTSC_2019' 'lpall' @('Windows Preinstallation Environment/x64/WinPE_OCs/de-de/lp.cab', 'Windows Preinstallation Environment/x64/WinPE_OCs/WinPE-FontSupport-ja-jp.cab')
$logs14 = [System.Collections.Generic.List[string]]::new()
$wl14 = ${function:Write-Log}; function Write-Log { param($Message,$Level='INFO') $logs14.Add("[$Level] $Message") }
Invoke-MediaRefresh (Opts 'Windows 10 Enterprise LTSC 2019 (IoT)' $langs10 @{ WinRE=$true; Boot=$true; BuildMedia=$true; SetupDU=$false })
Set-Item function:Write-Log $wl14
$winpeAdds = @($script:Calls | Where-Object { $_ -match '^AddPkg .* @ (WinRE|WinPE)$' -and $_ -match '(?i)language|lp\.cab|WinPE-' })
Check 'no language pack or WinPE language cab is added to WinRE or boot.wim' ($winpeAdds.Count -eq 0) ($winpeAdds -join ' | ')
Check 'the 10 language packs still go into install.wim' (@($script:Calls | Where-Object { $_ -match 'AddPkg Microsoft-Windows-Client-Language-Pack_x64_.* @ MainOS' }).Count -eq 10)
Check 'WinRE and boot.wim were still serviced (LCU added to both)' (@($script:Calls -match '^AddPkg .* @ WinRE').Count -ge 1 -and @($script:Calls -match '^AddPkg .* @ WinPE').Count -ge 1)
Check 'the log says languages go into install.wim only' ([bool]($logs14 -match 'Languages are added to install.wim only; WinRE and boot.wim stay English-only'))

Check 'Test-AppxPackageFolder keeps the real package folders and drops Deleted / Merged / other housekeeping folders' ($kept13.Count -eq 3 -and $kept13 -notcontains 'Deleted' -and $kept13 -notcontains 'Merged') ($kept13 -join ',')

Write-Host "`n=== E15 Tools > Cleanup Mountpoints, and ISOs already mounted when a run starts (TODO 10d / step 8) ==="
Check 'Test-PathUnder matches whole folder names only' ((Test-PathUnder 'F:\mr\Win11\MOUNT\MainOS\' 'F:\mr\Win11') -and (Test-PathUnder 'F:\MR\WIN11' 'f:\mr\win11\') -and -not (Test-PathUnder 'F:\mr\Win11_old\MOUNT' 'F:\mr\Win11') -and -not (Test-PathUnder 'G:\other' 'F:\mr'))
# A crashed run: install.wim still mounted in LTSC 2019's MOUNT\MainOS, its WinRE mount failed and left files behind,
# two ISOs still attached, plus an image mounted elsewhere on the machine that is none of our business.
Reset-Test; $script:AttachedIsos.Clear()
$c15 = Join-Path $base 'Win10_Enterprise_LTSC_2019'
$main15 = Join-Path $c15 'MOUNT\MainOS'; $re15 = Join-Path $c15 'MOUNT\WinRE'
New-File (Join-Path $main15 'Windows\x.txt'); New-File (Join-Path $re15 'leftover.txt')
$script:MountedList = @([pscustomobject]@{ Path = $main15 + '\'; ImagePath = (Join-Path $c15 'WORKING\install.wim'); MountStatus = 'Invalid' },
                        [pscustomobject]@{ Path = 'D:\SomeoneElse\Mount'; ImagePath = 'D:\x.wim'; MountStatus = 'Ok' })
$iso15a = Join-Path $c15 'ISO\lp15.iso'; $iso15b = Join-Path $base 'Windows_Server_2022\ISO\srv15.iso'; $iso15c = Join-Path $base 'Windows_Server_2022\ISO\notmounted15.iso'
foreach ($f in $iso15a, $iso15b, $iso15c) { New-File $f }
$script:AttachedIsos.Add($iso15a); $script:AttachedIsos.Add($iso15b)
$dry15 = Invoke-MediaRefresh ([pscustomobject]@{ Mode = 'Cleanup'; DryRun = $true; Root = $base; OsName = '' })
Check 'check-only pass finds the mounted image, both ISOs and the leftover WinRE folder' ($dry15.Mode -eq 'Cleanup' -and $dry15.DryRun -and @($dry15.Plan.WimMounts).Count -eq 1 -and (@($dry15.Plan.Isos | Sort-Object) -join '|') -eq ((@($iso15a, $iso15b) | Sort-Object) -join '|') -and (@($dry15.Plan.LeftoverFolders) -join '|') -eq $re15)
Check 'the mounted folder itself is not listed as leftover files (it is discarded instead)' (@($dry15.Plan.LeftoverFolders) -notcontains $main15)
Check 'an image mounted outside the repository root is listed as left alone' ((@($dry15.Plan.OtherWimMounts).Path -join '|') -eq 'D:\SomeoneElse\Mount')
Check 'the check-only pass changes nothing and writes no log file' ($script:Calls.Count -eq 0 -and $script:AttachedIsos.Count -eq 2 -and (Test-Path (Join-Path $re15 'leftover.txt')) -and -not (Test-Path (Join-Path $base 'LOGS')))
$real15 = Invoke-MediaRefresh ([pscustomobject]@{ Mode = 'Cleanup'; DryRun = $false; Root = $base; OsName = '' })
Check 'the image under the root is discarded, never saved; the other one is left mounted' (@($script:Calls -match '^Dismount MainOS discard').Count -eq 1 -and @($script:Calls -match 'save').Count -eq 0 -and @($script:MountedList).Count -eq 1 -and $script:MountedList[0].Path -eq 'D:\SomeoneElse\Mount') ($script:Calls -join '; ')
Check 'corrupt mount points are cleared after discarding' ([bool]($script:Calls -contains 'ClearCorruptMountPoint'))
Check 'both ISOs are dismounted; an ISO that was not mounted is not touched' ($script:AttachedIsos.Count -eq 0 -and @($script:Calls -match '^IsoDismount').Count -eq 2 -and -not ($script:Calls -contains 'IsoDismount notmounted15.iso'))
Check 'the leftover WinRE mount folder is emptied' (@(Get-ChildItem $re15 -Force).Count -eq 0)
Check 'the result lists four cleaned items and nothing left' (@($real15.Done).Count -eq 4 -and @($real15.Remaining).Count -eq 0 -and -not $real15.DryRun) (@($real15.Done) -join '; ')
Check 'the real pass logs to <root>\LOGS\MountCleanup_<time>.log' ((Test-Path (Join-Path $base 'LOGS')) -and $script:LogFile -like (Join-Path $base 'LOGS\MountCleanup_*.log'))
$script:LogFile = $null
$dwi15 = ${function:Dismount-WindowsImage}
# A discard that keeps failing is reported as still left, not as cleaned
Reset-Test; $script:AttachedIsos.Clear()
$script:MountedList = @([pscustomobject]@{ Path = $main15; ImagePath = 'x.wim'; MountStatus = 'Invalid' })
function Dismount-WindowsImage { [CmdletBinding()] param($Path, [switch]$Save, [switch]$Discard, [switch]$CheckIntegrity, $LogPath) Note 'DismountFail'; throw 'Access is denied' }
$stuck15 = Invoke-MountCleanup -Root $base
Check 'an image that cannot be discarded is reported as still left, with a WARN' (@($stuck15.Remaining).Count -eq 1 -and @($stuck15.Remaining)[0] -like "Mounted image*MainOS" -and @($stuck15.Done).Count -eq 0)
$script:MountedList = @()
Check 'nothing mounted: the check finds nothing to do' ((Invoke-MountCleanup -Root $base -DryRun).Plan.Count -eq 0)
$threw = $false; try { Invoke-MountCleanup -Root (Join-Path $base 'no_such_root') -DryRun } catch { $threw = $true }
Check 'a repository root that does not exist is an error' $threw
# Step 8: an ISO of this OS left attached is dismounted before a run mounts the ISOs itself
Set-Item function:Dismount-WindowsImage $dwi15; Reset-Test
$script:AttachedIsos.Clear(); $iso15k = Join-Path $base 'Win10_Enterprise_LTSC_2021_KMS\ISO\os2021kms.iso'; $script:AttachedIsos.Add($iso15k)
$logs15 = [System.Collections.Generic.List[string]]::new()
$wl15 = ${function:Write-Log}; function Write-Log { param($Message, $Level = 'INFO') $logs15.Add("[$Level] $Message") }
Clear-StaleIsoMounts (Join-Path $base 'Win10_Enterprise_LTSC_2021_KMS\ISO')
Set-Item function:Write-Log $wl15
Check 'an ISO already mounted at the start of a run is dismounted, with a WARN' ($script:AttachedIsos.Count -eq 0 -and [bool]($logs15 -match '^\[WARN\] ISO os2021kms\.iso was already mounted'))
Write-Host "`n=== E16 boot.wim is patched only for the media, with setup.exe and the boot manager files from it (Terry, 2026-09-27) ==="
# boot.wim with two images; index 2 is the Setup image, which carries the patched setup files. The ISO's own copies are 'orig'.
Reset-Test; $script:ImageCount = 1; $script:SourceNames = @('Windows 11 Pro', 'Windows 11 Enterprise')
$lcu16 = Join-Path $base 'Win11Enterprise_24H2\PATCHES\LCU'; Get-ChildItem $lcu16 -File -ErrorAction SilentlyContinue | Remove-Item -Force
Patches 'Win11Enterprise_24H2' @('LCU/windows11.0-kb5129195-x64.msu')
$os16 = Join-Path $isos 'os11'
foreach ($p in 'sources/boot.wim', 'sources/setup.exe', 'sources/setuphost.exe', 'efi/boot/bootx64.efi', 'bootmgr.efi', 'efi/microsoft/boot/bcd') { New-File (Join-Path $os16 $p) 'orig' }
$gwi16 = ${function:Get-WindowsImage}; $mwi16 = ${function:Mount-WindowsImage}
function Get-WindowsImage { [CmdletBinding()] param($ImagePath, $Index, [switch]$Mounted)
    if (-not $Mounted -and -not $Index -and $ImagePath -like '*boot*') { return @([pscustomobject]@{ ImageIndex = 1; ImageName = 'Microsoft Windows PE' }, [pscustomobject]@{ ImageIndex = 2; ImageName = 'Microsoft Windows Setup' }) }
    & $gwi16 @PSBoundParameters }
function Mount-WindowsImage { [CmdletBinding()] param($ImagePath, $Index, $Path, [switch]$CheckIntegrity, [switch]$ReadOnly, $LogPath)
    & $mwi16 @PSBoundParameters
    if ($ImagePath -like '*boot.working.wim' -and $Index -eq 2) {
        foreach ($p in 'sources/setup.exe', 'sources/setuphost.exe', 'Windows/Boot/EFI/bootmgfw.efi', 'Windows/Boot/EFI/bootmgr.efi', 'Windows/Boot/EFI/boot.stl') { New-File (Join-Path $Path $p) "patched $(Split-Path $p -Leaf)" }
    } }
$script:ChangeEvents = $null
Invoke-MediaRefresh (Opts 'Windows 11 Enterprise 24H2' @() @{ NetFx3 = $false; Boot = $true; BuildMedia = $true; SetupDU = $false; WinRE = $false })
$media16 = Join-Path $base 'Win11Enterprise_24H2\NEWWIM\Media'
$read16 = { param($rel) (Get-Content -Raw (Join-Path $media16 $rel)).Trim() }
Check 'both boot.wim images get the LCU' (@($script:Calls -match '^Mount boot\.working\.wim idx[12] ').Count -eq 2 -and @($script:Calls -match '^AddPkg windows11\.0-kb5129195-x64\.msu @ WinPE').Count -eq 2) ($script:Calls -join ' | ')
Check 'the media gets the patched boot.wim, and there is no separate NEWWIM\boot.wim' ((& $read16 'sources\boot.wim') -eq 'x' -and -not (Test-Path (Join-Path $base 'Win11Enterprise_24H2\NEWWIM\boot.wim')) -and $script:LastResult.Boot -eq (Join-Path $media16 'sources\boot.wim'))
Check 'gap 1: setup.exe and setuphost.exe on the media come from the patched Setup image' ((& $read16 'sources\setup.exe') -eq 'patched setup.exe' -and (& $read16 'sources\setuphost.exe') -eq 'patched setuphost.exe')
Check 'gap 2: efi\boot\bootx64.efi <- bootmgfw.efi, bootmgr.efi <- bootmgr.efi, boot.stl added' ((& $read16 'efi\boot\bootx64.efi') -eq 'patched bootmgfw.efi' -and (& $read16 'bootmgr.efi') -eq 'patched bootmgr.efi' -and (& $read16 'efi\microsoft\boot\boot.stl') -eq 'patched boot.stl' -and (& $read16 'efi\microsoft\boot\bcd') -eq 'orig')
$media16Events = @($script:ChangeEvents | Where-Object { $_.Category -eq 'Media' } | ForEach-Object { $_.Item })
Check 'the change log records the patched boot.wim and each replaced media file' ($media16Events -contains 'sources\boot.wim' -and $media16Events -contains 'setup.exe' -and $media16Events -contains 'setuphost.exe' -and $media16Events -contains 'efi\boot\bootx64.efi' -and $media16Events -contains 'bootmgr.efi' -and $media16Events -contains 'efi\microsoft\boot\boot.stl') ($media16Events -join ', ')
# Win10-style Setup image: no setuphost.exe and no boot.stl - the media keeps its own setuphost-less layout
Reset-Test; Remove-Item (Join-Path $os16 'sources\setuphost.exe') -Force
function Mount-WindowsImage { [CmdletBinding()] param($ImagePath, $Index, $Path, [switch]$CheckIntegrity, [switch]$ReadOnly, $LogPath)
    & $mwi16 @PSBoundParameters
    if ($ImagePath -like '*boot.working.wim' -and $Index -eq 2) { foreach ($p in 'sources/setup.exe', 'Windows/Boot/EFI/bootmgfw.efi', 'Windows/Boot/EFI/bootmgr.efi') { New-File (Join-Path $Path $p) "patched $(Split-Path $p -Leaf)" } } }
Invoke-MediaRefresh (Opts 'Windows 11 Enterprise 24H2' @() @{ NetFx3 = $false; Boot = $true; BuildMedia = $true; SetupDU = $false; WinRE = $false })
Check 'files the Setup image does not have (setuphost.exe, boot.stl) are not invented on the media' ((& $read16 'sources\setup.exe') -eq 'patched setup.exe' -and -not (Test-Path (Join-Path $media16 'sources\setuphost.exe')) -and -not (Test-Path (Join-Path $media16 'efi\microsoft\boot\boot.stl')))
# Media without Patch boot.wim: the ISO's boot.wim and setup files stay as they are
Reset-Test
Invoke-MediaRefresh (Opts 'Windows 11 Enterprise 24H2' @() @{ NetFx3 = $false; Boot = $false; BuildMedia = $true; SetupDU = $false; WinRE = $false })
Check 'media with Patch boot.wim unticked keeps the ISO''s boot.wim and setup.exe' (@($script:Calls -match 'boot\.working').Count -eq 0 -and (& $read16 'sources\boot.wim') -eq 'orig' -and (& $read16 'sources\setup.exe') -eq 'orig')
# Patch boot.wim ticked but no media: boot.wim is not touched at all
Reset-Test
$logs16 = [System.Collections.Generic.List[string]]::new()
$wl16 = ${function:Write-Log}; function Write-Log { param($Message, $Level = 'INFO') $logs16.Add("[$Level] $Message") }
Invoke-MediaRefresh (Opts 'Windows 11 Enterprise 24H2' @() @{ NetFx3 = $false; Boot = $true; BuildMedia = $false; SetupDU = $false; WinRE = $false })
Set-Item function:Write-Log $wl16
Check 'Patch boot.wim without media: boot.wim is skipped, with a log line saying why' (@($script:Calls -match 'boot\.working').Count -eq 0 -and [bool]($logs16 -match 'boot\.wim is patched only for the media, so it is skipped'))
Set-Item function:Get-WindowsImage $gwi16; Set-Item function:Mount-WindowsImage $mwi16
# Two runs in the same second share a stamp: the second archive gets _2 instead of failing on Media already being there
$nw16 = Join-Path $base '_arch16\NEWWIM'; New-File (Join-Path $nw16 'Media\a.txt'); New-File (Join-Path $nw16 'Archive\20260927_101010\Media\old.txt')
$script:OutputArchived = $false
Backup-PreviousOutput -Paths @{ NewWim = $nw16 } -Stamp '20260927_101010' -Keep 3
Check 'an archive stamp already used in the same second gets a _2 folder' ((Test-Path (Join-Path $nw16 'Archive\20260927_101010_2\Media\a.txt')) -and (Test-Path (Join-Path $nw16 'Archive\20260927_101010\Media\old.txt')))

Check 'a servicing run calls the ISO check right after the stale-mount check' ($src -match "Clear-StaleMounts \`$paths\.Root\r?\n\s+Clear-StaleIsoMounts \`$paths\.ISO")

Write-Host "`n=== E17 CA 2023 media alongside the standard media (Make2023BootableMedia.ps1 steps; Terry, 2026-09-27) ==="
# boot.wim index 1 carries the CA 2023 boot files (EX); index 2 is the Setup image as in E16. Real boot files are signed
# PE files; here the content says which certificate "signed" them and Get-EmbeddedSignerIssuer reads that.
$gwi17 = ${function:Get-WindowsImage}; $mwi17 = ${function:Mount-WindowsImage}; $iso17 = ${function:Build-IsoFromMedia}; $sig17 = ${function:Get-EmbeddedSignerIssuer}
$script:Ex17 = $true
function Get-WindowsImage { [CmdletBinding()] param($ImagePath, $Index, [switch]$Mounted)
    if (-not $Mounted -and -not $Index -and $ImagePath -like '*boot*') { return @([pscustomobject]@{ ImageIndex = 1; ImageName = 'Microsoft Windows PE' }, [pscustomobject]@{ ImageIndex = 2; ImageName = 'Microsoft Windows Setup' }) }
    & $gwi17 @PSBoundParameters }
function Mount-WindowsImage { [CmdletBinding()] param($ImagePath, $Index, $Path, [switch]$CheckIntegrity, [switch]$ReadOnly, $LogPath)
    & $mwi17 @PSBoundParameters
    if ($ImagePath -notlike '*boot.working.wim') { return }
    New-File (Join-Path $Path 'Windows/Boot/EFI/boot.stl') 'stl'
    if ($script:Ex17) {
        New-File (Join-Path $Path 'Windows/Boot/EFI_EX/bootmgfw_EX.efi') "ex-bootmgfw idx$Index"; New-File (Join-Path $Path 'Windows/Boot/EFI_EX/bootmgr_EX.efi') 'ex-bootmgr'
        New-File (Join-Path $Path 'Windows/Boot/FONTS_EX/chs_boot_EX.ttf') 'ex-font'; New-File (Join-Path $Path 'Windows/Boot/FONTS_EX/segmono_boot_EX.ttf') 'ex-font2'
        New-File (Join-Path $Path 'Windows/Boot/DVD_EX/EFI/en-US/efisys_EX.bin') 'ex-efisys'
    }
    if ($Index -eq 2) { foreach ($p in 'sources/setup.exe', 'Windows/Boot/EFI/bootmgfw.efi', 'Windows/Boot/EFI/bootmgr.efi') { New-File (Join-Path $Path $p) "patched $(Split-Path $p -Leaf)" } } }
$script:IsoCalls17 = [System.Collections.Generic.List[string]]::new()
function Build-IsoFromMedia { param([string]$MediaFolder, [hashtable]$Paths, [string]$EfiBootFile = 'efisys.bin', [string]$NamePrefix = 'UpdatedMedia')
    $script:IsoCalls17.Add("$(Split-Path $MediaFolder -Leaf)|$EfiBootFile|$NamePrefix"); return (Join-Path $Paths.NewWim "$NamePrefix.iso") }
function Get-EmbeddedSignerIssuer { param([string]$Path) $c = (Get-Content -Raw -LiteralPath $Path -ErrorAction SilentlyContinue); if ($c -like 'ex-*') { 'CN=Windows UEFI CA 2023, O=Microsoft Corporation, C=US' } else { 'CN=Microsoft Windows Production PCA 2011' } }
$os17 = Join-Path $isos 'os11'
foreach ($p in 'sources/boot.wim', 'sources/setup.exe', 'efi/boot/bootx64.efi', 'bootmgr.efi', 'efi/microsoft/boot/efisys.bin', 'efi/microsoft/boot/fonts/chs_boot.ttf', 'boot/etfsboot.com') { New-File (Join-Path $os17 $p) 'orig' }
$opts17 = @{ NetFx3 = $false; Boot = $true; BuildMedia = $true; BuildIso = $true; SetupDU = $false; WinRE = $false; Media2023 = $true }
Reset-Test; $script:ChangeEvents = $null
$logs17 = [System.Collections.Generic.List[string]]::new()
$wl17 = ${function:Write-Log}; function Write-Log { param($Message, $Level = 'INFO') $logs17.Add("[$Level] $Message") }
$o17 = Opts 'Windows 11 Enterprise 24H2' @() $opts17; $o17 | Add-Member -NotePropertyName Media2023 -NotePropertyValue $true -Force
Invoke-MediaRefresh $o17
Set-Item function:Write-Log $wl17
$nw17 = Join-Path $base 'Win11Enterprise_24H2\NEWWIM'; $std17 = Join-Path $nw17 'Media'; $ca17 = Join-Path $nw17 'Media_CA2023'
$rd17 = { param($root, $rel) $p = Join-Path $root $rel; if (Test-Path -LiteralPath $p) { (Get-Content -Raw -LiteralPath $p).Trim() } else { '<missing>' } }
Check 'the CA 2023 media is built alongside the standard media' ((Test-Path $std17) -and (Test-Path $ca17) -and $script:LastResult.Media2023 -eq $ca17 -and -not $script:LastResult.Media2023Error)
Check 'CA 2023 boot manager: efi\boot\bootx64.efi <- bootmgfw_EX.efi (from boot.wim index 1); bootmgr.efi <- bootmgr_EX.efi' ((& $rd17 $ca17 'efi\boot\bootx64.efi') -eq 'ex-bootmgfw idx1' -and (& $rd17 $ca17 'bootmgr.efi') -eq 'ex-bootmgr')
Check 'CA 2023 UEFI boot image and fonts: efisys_ex.bin added, FONTS_EX copied without _EX' ((& $rd17 $ca17 'efi\microsoft\boot\efisys_ex.bin') -eq 'ex-efisys' -and (& $rd17 $ca17 'efi\microsoft\boot\fonts\chs_boot.ttf') -eq 'ex-font' -and (& $rd17 $ca17 'efi\microsoft\boot\fonts\segmono_boot.ttf') -eq 'ex-font2')
Check 'the CA 2023 media keeps everything else of the refreshed media (patched setup.exe, install.wim, boot.wim)' ((& $rd17 $ca17 'sources\setup.exe') -eq 'patched setup.exe' -and (Test-Path (Join-Path $ca17 'sources\install.wim')) -and (& $rd17 $ca17 'sources\boot.wim') -eq 'x')
Check 'the standard media is unchanged: PCA 2011 boot manager from the patched boot.wim, no efisys_ex.bin, original fonts' ((& $rd17 $std17 'efi\boot\bootx64.efi') -eq 'patched bootmgfw.efi' -and (& $rd17 $std17 'efi\microsoft\boot\efisys_ex.bin') -eq '<missing>' -and (& $rd17 $std17 'efi\microsoft\boot\fonts\chs_boot.ttf') -eq 'orig')
Check 'two ISOs: the standard one with efisys.bin, the CA 2023 one with efisys_ex.bin' (($script:IsoCalls17 -join ' / ') -eq 'Media|efisys.bin|UpdatedMedia / Media_CA2023|efisys_ex.bin|UpdatedMedia_CA2023' -and $script:LastResult.Iso2023 -like '*UpdatedMedia_CA2023.iso') ($script:IsoCalls17 -join ' / ')
Check 'the CA 2023 boot manager signature is verified and logged' ([bool]($logs17 -match '^\[INFO\] VERIFY CA 2023 media: bootx64\.efi is signed by CN=Windows UEFI CA 2023') -and [bool]($logs17 -match 'Standard media: bootx64\.efi is signed by CN=Microsoft Windows Production PCA 2011'))
$ev17 = @($script:ChangeEvents | Where-Object { $_.Category -eq 'Media CA 2023' } | ForEach-Object { $_.Item })
Check 'the change log records each CA 2023 media change' ($ev17 -contains 'efi\boot\bootx64.efi' -and $ev17 -contains 'bootmgr.efi' -and $ev17 -contains 'efi\microsoft\boot\efisys_ex.bin' -and $ev17 -contains 'efi\microsoft\boot\fonts') ($ev17 -join ', ')
# A boot manager that turns out not to be CA 2023 signed: reported, not shipped as CA 2023; the run and the standard ISO still succeed
Reset-Test; $script:IsoCalls17.Clear()
function Get-EmbeddedSignerIssuer { param([string]$Path) 'CN=Microsoft Windows Production PCA 2011' }
Invoke-MediaRefresh $o17
Check 'a CA 2023 boot manager with the wrong signer: error reported, no CA 2023 ISO, standard ISO still built' ($script:LastResult.Media2023Error -like '*not ''Windows UEFI CA 2023''*' -and $null -eq $script:LastResult.Media2023 -and ($script:IsoCalls17 -join ' / ') -eq 'Media|efisys.bin|UpdatedMedia') ($script:IsoCalls17 -join ' / ')
# boot.wim without the EX files (LCU older than 2024-04)
Reset-Test; $script:IsoCalls17.Clear(); $script:Ex17 = $false
Invoke-MediaRefresh $o17
Check 'no CA 2023 boot files in boot.wim: clear 2024-04 message, the run still completes' ($script:LastResult.Media2023Error -like '*2024-04 or later cumulative update*' -and $script:LastResult.Install -and $script:LastResult.Media)
$script:Ex17 = $true
# CA 2023 ticked without Patch boot.wim: skipped with a WARN, nothing saved from boot.wim
Reset-Test; $script:IsoCalls17.Clear(); $logs17.Clear()
function Write-Log { param($Message, $Level = 'INFO') $logs17.Add("[$Level] $Message") }
$o17b = Opts 'Windows 11 Enterprise 24H2' @() ($opts17 + @{}); $o17b.Boot = $false; $o17b | Add-Member -NotePropertyName Media2023 -NotePropertyValue $true -Force
Invoke-MediaRefresh $o17b
Set-Item function:Write-Log $wl17
Check 'CA 2023 without Patch boot.wim: skipped with a WARN, no Media_CA2023' ([bool]($logs17 -match '^\[WARN\] CA 2023 media is ticked, but it needs the media and Patch boot.wim') -and -not (Test-Path $ca17) -and $null -eq $script:LastResult.Media2023)
# Patch boot.wim without CA 2023: the EX files are not even saved
Reset-Test; $o17c = Opts 'Windows 11 Enterprise 24H2' @() $opts17
Invoke-MediaRefresh $o17c
Check 'without CA 2023 ticked, no CA 2023 files are saved and no Media_CA2023 is built' (-not (Test-Path (Join-Path $base 'Win11Enterprise_24H2\WORKING\bootfiles\CA2023')) -and -not (Test-Path $ca17))
# ARM64 media: bootaa64.efi is the one replaced
$arm17 = Join-Path $base '_arm17'; New-File (Join-Path $arm17 'efi\boot\bootaa64.efi') 'orig'
$exd17 = Join-Path $base '_ex17'; foreach ($p in 'EFI_EX\bootmgfw_EX.efi', 'DVD_EX\EFI\en-US\efisys_EX.bin') { New-File (Join-Path $exd17 $p) 'ex' }
$t17 = Set-Media2023BootFiles -Media $arm17 -ExFiles $exd17
Check 'ARM64 media: bootaa64.efi is replaced, no bootx64.efi is added' ((Split-Path $t17 -Leaf) -eq 'bootaa64.efi' -and (& $rd17 $arm17 'efi\boot\bootaa64.efi') -eq 'ex' -and -not (Test-Path (Join-Path $arm17 'efi\boot\bootx64.efi')))
Set-Item function:Get-WindowsImage $gwi17; Set-Item function:Mount-WindowsImage $mwi17; Set-Item function:Build-IsoFromMedia $iso17; Set-Item function:Get-EmbeddedSignerIssuer $sig17
# The real signature reader on this PC's own boot files (Windows 11 and Server 2025 carry both)
$exReal = 'C:\Windows\Boot\EFI_EX\bootmgfw_EX.efi'; $stdReal = 'C:\Windows\Boot\EFI\bootmgfw.efi'
if ((Test-Path $exReal) -and (Test-Path $stdReal)) {
    Check 'real files: the embedded signer tells CA 2023 and PCA 2011 boot managers apart' ((Get-EmbeddedSignerIssuer $exReal) -match 'Windows UEFI CA 2023' -and (Get-EmbeddedSignerIssuer $stdReal) -match 'Windows Production PCA 2011')
} else { Write-Host 'SKIP  real boot manager signature check (no C:\Windows\Boot\EFI_EX on this PC)' }
Check 'an unsigned or missing file gives an empty issuer, not an error' ((Get-EmbeddedSignerIssuer (Join-Path $arm17 'efi\boot\bootaa64.efi')) -eq '' -and (Get-EmbeddedSignerIssuer 'C:\no\such.efi') -eq '')

Write-Host "`n=== E18 provisioned apps: the Apps tab list and removing ticked apps first (TODO step 11) ==="
# The source edition has three provisioned apps; removing one takes it out of what later mounts see.
function New-App18($n) { [pscustomobject]@{ DisplayName = $n; Version = '1.0.0.0'; PackageName = "$($n)_1.0.0.0_neutral_~_8wekyb3d8bbwe" } }
$script:Prov18 = [System.Collections.Generic.List[object]]::new()
function Reset-Prov18 { $script:Prov18.Clear(); foreach ($n in 'Microsoft.BingNews', 'Microsoft.Copilot', 'Microsoft.WindowsCalculator') { $script:Prov18.Add((New-App18 $n)) } }
$gap18 = ${function:Get-AppxProvisionedPackage}; $gwi18 = ${function:Get-WindowsImage}
function Get-AppxProvisionedPackage { [CmdletBinding()] param($Path) return @($script:Prov18) }
function Remove-AppxProvisionedPackage { [CmdletBinding()] param($Path, $PackageName)
    if ($script:FailRemove18) { throw 'Access is denied' }
    Note "RemoveAppx $PackageName"; $hit = @($script:Prov18 | Where-Object { $_.PackageName -eq $PackageName }); foreach ($h in $hit) { [void]$script:Prov18.Remove($h) } }
function Get-WindowsImage { [CmdletBinding()] param($ImagePath, $Index, [switch]$Mounted)
    if (-not $Mounted -and $ImagePath -like '*boot*' -and -not $Index) { return @([pscustomobject]@{ ImageIndex = 1; ImageName = 'Microsoft Windows PE' }) }
    & $gwi18 @PSBoundParameters }
$script:FailRemove18 = $false
$os18 = Join-Path $base 'Win11Enterprise_24H2'; $appsFile18 = Join-Path $os18 'ProvisionedApps.json'
$script:SourceNames = @('Windows 11 Pro', 'Windows 11 Pro N', 'Windows 11 Enterprise')
# Read apps from the ISO: works with empty PATCHES folders (it needs no patches), only mounts read-only, saves the list
Reset-Test; Reset-Prov18; Remove-Item $appsFile18 -Force -ErrorAction SilentlyContinue
Get-ChildItem (Join-Path $os18 'PATCHES\LCU') -File -ErrorAction SilentlyContinue | Remove-Item -Force
$a18 = Invoke-MediaRefresh ([pscustomobject]@{ OsName = 'Windows 11 Enterprise 24H2'; Root = $base; Mode = 'Apps'; PreflightOnly = $false; Install = $true; Boot = $false; WinRE = $true; Verify = $true; BuildMedia = $false; BuildIso = $false; SSU = $true; LCU = $true; SafeOS = $true; NetCU = $true; SetupDU = $true; NetFx3 = $false; Languages = @('de-de') })
$inv18 = Read-AppInventory -OsRoot $os18
Check 'Read apps: the selected edition (index 3) is read from the OS ISO and saved for the Apps tab' ($a18.Mode -eq 'Apps' -and $a18.Count -eq 3 -and $a18.Index -eq 3 -and $inv18.Index -eq 3 -and $inv18.ImageName -eq 'Windows 11 Enterprise' -and (@($inv18.Apps).DisplayName -join ',') -eq 'Microsoft.BingNews,Microsoft.Copilot,Microsoft.WindowsCalculator')
Check 'Read apps: needs no patches and changes nothing (one read-only mount, discarded)' ((@($script:Calls | Where-Object { $_ -match '^(Mount|Dismount|Export|AddPkg|RemoveAppx)' }) -join '|') -eq 'Mount install.wim idx3 -> MainOS|Dismount MainOS discard') ($script:Calls -join '; ')
$threw = $false; try { Invoke-MediaRefresh ([pscustomobject]@{ OsName = 'Windows Server 2022'; Root = $base; Mode = 'Apps'; PreflightOnly = $false; Languages = @() }) } catch { $threw = $true; $m18 = $_.Exception.Message }
Check 'Read apps on Windows Server: refused with a clear message' ($threw -and $m18 -like 'App removal is for client editions*')
# A real run with two ticked apps (one not in the image): removed first - before WinRE and the SSU / LCU
Patches 'Win11Enterprise_24H2' @('LCU/windows11.0-kb5129195-x64.msu')
Reset-Test; Reset-Prov18; $script:ChangeEvents = $null
$logs18 = [System.Collections.Generic.List[string]]::new()
$wl18 = ${function:Write-Log}; function Write-Log { param($Message, $Level = 'INFO') $logs18.Add("[$Level] $Message") }
$o18 = Opts 'Windows 11 Enterprise 24H2' @() @{ NetFx3 = $false; SetupDU = $false }
$o18 | Add-Member -NotePropertyName RemoveApps -NotePropertyValue @('Microsoft.BingNews', 'Contoso.NotThere') -Force
Invoke-MediaRefresh $o18
Set-Item function:Write-Log $wl18
$c18 = @($script:Calls)
$iRemove = [array]::IndexOf($c18, @($c18 -match '^RemoveAppx Microsoft\.BingNews')[0]); $iFirstPkg = [array]::IndexOf($c18, @($c18 -match '^(AddPkg|Mount winre)')[0])
Check 'the ticked app is removed right after the mount, before WinRE and any package' ($iRemove -ge 0 -and ($iFirstPkg -lt 0 -or $iRemove -lt $iFirstPkg) -and @($c18 -match '^RemoveAppx').Count -eq 1) ($c18 -join ' | ')
Check 'a ticked app the image does not have is logged and skipped' ([bool]($logs18 -match 'App removal: Contoso\.NotThere is not provisioned in install\.wim index 1'))
Check 'the change log records the removed app (category AppRemoved)' (@($script:ChangeEvents | Where-Object { $_.Category -eq 'AppRemoved' -and $_.Item -eq 'Microsoft.BingNews' }).Count -eq 1)
Check 'Verify confirms the ticked apps are gone and the gate passes' ([bool]($logs18 -match 'VERIFY   none of the 2 app\(s\) ticked for removal is provisioned') -and $script:LastResult.Gate -eq 'PASSED')
Check 'the run refreshes the Apps tab list from the mounted image (before removal: the edition''s own apps)' ((@((Read-AppInventory -OsRoot $os18).Apps).DisplayName -join ',') -eq 'Microsoft.BingNews,Microsoft.Copilot,Microsoft.WindowsCalculator')
# A removal that fails: WARN, the run goes on, Verify catches that the app is still there
Reset-Test; Reset-Prov18; $script:FailRemove18 = $true
Invoke-MediaRefresh $o18
$script:FailRemove18 = $false
Check 'a removal that fails is caught by Verify (app still provisioned) and fails the gate' ($script:LastResult.Gate -eq 'FAILED' -and $script:LastResult.VerifyIssues -ge 1)
# Preflight: an up-to-date list is not read again; a list from another index is; ticked apps missing from the list are named
Reset-Test; Reset-Prov18; $logs18.Clear()
function Write-Log { param($Message, $Level = 'INFO') $logs18.Add("[$Level] $Message") }
$p18 = Opts 'Windows 11 Enterprise 24H2' @() @{ Preflight = $true; SetupDU = $false }; $p18 | Add-Member -NotePropertyName RemoveApps -NotePropertyValue @('Microsoft.BingNews', 'Contoso.NotThere') -Force
Invoke-MediaRefresh $p18
Check 'preflight with an up-to-date app list: no mount; ticked apps missing from the list are named' (@($script:Calls -match '^Mount').Count -eq 0 -and [bool]($logs18 -match '^\[WARN\] App removal: not in this image''s app list .*: Contoso\.NotThere$'))
$j18 = Get-Content -Raw $appsFile18 | ConvertFrom-Json; $j18.index = 2; ($j18 | ConvertTo-Json -Depth 4) | Set-Content $appsFile18
Reset-Test; $logs18.Clear()
Invoke-MediaRefresh $p18
Set-Item function:Write-Log $wl18
Check 'preflight with a list from another index: reads it again (read-only)' ([bool]($logs18 -match 'The app list is from os11\.iso index 2; reading it again') -and (Read-AppInventory -OsRoot $os18).Index -eq 3 -and @($script:Calls -match 'save$').Count -eq 0)
# Windows Server: ticked apps are ignored with a WARN
Reset-Test; $logs18.Clear(); $script:ImageCount = 4
function Write-Log { param($Message, $Level = 'INFO') $logs18.Add("[$Level] $Message") }
$s18 = Opts 'Windows Server 2022' @() @{ Preflight = $true }; $s18 | Add-Member -NotePropertyName RemoveApps -NotePropertyValue @('Microsoft.BingNews') -Force
try { Invoke-MediaRefresh $s18 } catch { }
Set-Item function:Write-Log $wl18
Check 'Windows Server: ticked apps are ignored with a WARN' ([bool]($logs18 -match '^\[WARN\] App removal is for client editions; the ticked apps are ignored') -and @($script:Calls -match '^RemoveAppx').Count -eq 0)
$script:ImageCount = 1
Set-Item function:Get-AppxProvisionedPackage $gap18; Set-Item function:Get-WindowsImage $gwi18

Write-Host "`n=== E19 SCCM import: check, copy, import, distribute (TODO step 7; Configuration Manager mocked) ==="
# A real run (E18) writes the run record the import works from
$rrW11 = Read-RunResult -NewWim (Join-Path $base 'Win11Enterprise_24H2\NEWWIM')
Check 'a finished run writes NEWWIM\RunResult.json with its build, gate and install.wim' ($null -ne $rrW11 -and $rrW11.Install -like '*\NEWWIM\install.wim' -and $rrW11.Gate -in @('PASSED', 'FAILED'))
# The site, mocked: module, site code, site drive and the cmdlets the import uses
$script:Cm = @{ Images = [System.Collections.Generic.List[string]]::new(); Installers = [System.Collections.Generic.List[string]]::new(); Calls = [System.Collections.Generic.List[string]]::new() }
function Import-SccmModule { }
function Get-SccmSiteCode { param($SiteServer) 'PS1' }
function Invoke-InSccmSite { param($SiteCode, $SiteServer, [scriptblock]$Script) & $Script }
function Get-CMDistributionPoint { param([switch]$AllSite) @([pscustomobject]@{ NetworkOSPath = '\\dp01.contoso.com' }, [pscustomobject]@{ NetworkOSPath = '\\dp02.contoso.com' }) }
function Get-CMDistributionPointGroup { @([pscustomobject]@{ Name = 'All DPs' }) }
function Get-CMOperatingSystemImage { param($Name) @($script:Cm.Images | Where-Object { $_ -like $Name } | ForEach-Object { [pscustomobject]@{ Name = $_ } }) }
function Get-CMOperatingSystemInstaller { param($Name) @($script:Cm.Installers | Where-Object { $_ -like $Name } | ForEach-Object { [pscustomobject]@{ Name = $_ } }) }
function New-CMOperatingSystemImage { param($Name, $Path, $Description, $Version) $script:Cm.Calls.Add("NewImage|$Name|$Path|$Version"); $script:Cm.Images.Add($Name); [pscustomobject]@{ PackageID = 'PS100123'; Name = $Name } }
function New-CMOperatingSystemInstaller { param($Name, $Path, $Description, $Version) $script:Cm.Calls.Add("NewInstaller|$Name|$Path"); $script:Cm.Installers.Add($Name); [pscustomobject]@{ PackageID = 'PS100124'; Name = $Name } }
function Start-CMContentDistribution { param($OperatingSystemImageId, $OperatingSystemInstallerId, $DistributionPointName, $DistributionPointGroupName) $script:Cm.Calls.Add("Distribute|img=$OperatingSystemImageId|inst=$OperatingSystemInstallerId|dp=$DistributionPointName|group=$DistributionPointGroupName") }
$shareRoot = Join-Path $base '_share'; $contentRoot = Join-Path $shareRoot 'OSD\Images'; New-Item -ItemType Directory -Force $contentRoot | Out-Null
function Get-ServerShares { @([pscustomobject]@{ Name = 'Sources'; Path = $shareRoot }) }
$con19 = Invoke-MediaRefresh ([pscustomobject]@{ Mode = 'SccmConnect'; SccmSiteServer = 'cm01.contoso.com'; Root = $base; OsName = '' })
Check 'Connect: site code, distribution points (without \\) and groups' ($con19.SiteCode -eq 'PS1' -and (@($con19.DPs) -join ',') -eq 'dp01.contoso.com,dp02.contoso.com' -and (@($con19.Groups) -join ',') -eq 'All DPs')
# The KMS run to import: an install.wim and a media folder with a passed gate
$nw19 = Join-Path $base 'Win10_Enterprise_LTSC_2021_KMS\NEWWIM'; New-File (Join-Path $nw19 'install.wim') 'kms-wim'; New-File (Join-Path $nw19 'Media\setup.exe') 'setup'; New-File (Join-Path $nw19 'Media\sources\install.wim') 'kms-wim'
[void](Save-RunResult -Paths @{ NewWim = $nw19 } -OsName 'Windows 10 Enterprise LTSC 2021 (KMS)' -Build '10.0.19044.6456' -Gate 'PASSED' -Install (Join-Path $nw19 'install.wim') -Media (Join-Path $nw19 'Media') -ChangeLog 'C:\x\ChangeLog_KMS.html')
function Opts19([hashtable]$o = @{}) {
    $d = [ordered]@{ Mode = 'SccmImport'; DryRun = $true; OsName = 'Windows 10 Enterprise LTSC 2021 (KMS)'; Root = $base; SccmSiteServer = 'cm01.contoso.com'; SccmTargetType = 'DP'; SccmTarget = 'dp01.contoso.com'
        SccmContentSource = $contentRoot; SccmSourceServer = 'BUILD01'; SccmPackageType = 'Image'; SccmImageName = 'Windows 10 Enterprise LTSC 2021 (KMS) 202609' }
    foreach ($k in $o.Keys) { $d[$k] = $o[$k] }; [pscustomobject]$d }
$script:Cm.Images.Add('Windows 10 Enterprise LTSC 2021 (KMS) 202609')   # already imported earlier this month
$dry19 = Invoke-MediaRefresh (Opts19)
Check 'check only: the plan names the next free name, the UNC import path, size, build and gate' ($dry19.DryRun -and $dry19.Name -eq 'Windows 10 Enterprise LTSC 2021 (KMS) 202609 (2)' -and $dry19.ImportPath -eq '\\BUILD01\Sources\OSD\Images\Windows 10 Enterprise LTSC 2021 (KMS) 202609 (2)\install.wim' -and $dry19.Build -eq '10.0.19044.6456' -and $dry19.Gate -eq 'PASSED' -and $dry19.SiteCode -eq 'PS1')
Check 'check only: nothing is copied, imported or distributed' ($script:Cm.Calls.Count -eq 0 -and @(Get-ChildItem $contentRoot).Count -eq 0)
Check 'the description (127 characters at most) names the build, gate and change log' ($dry19.Description.Length -le 127 -and $dry19.Description -like '*build 10.0.19044.6456; gate PASSED; change log ChangeLog_KMS.html')
$real19 = Invoke-MediaRefresh (Opts19 @{ DryRun = $false; SccmImageName = $dry19.Name })
$dest19 = Join-Path $contentRoot 'Windows 10 Enterprise LTSC 2021 (KMS) 202609 (2)'
Check 'import: install.wim is copied into a new sub-folder named after the image' ((Get-Content -Raw (Join-Path $dest19 'install.wim')).Trim() -eq 'kms-wim')
Check 'import: the OS image is created from the UNC path, with the build as its version' (($script:Cm.Calls | Where-Object { $_ -like 'NewImage|*' }) -eq "NewImage|Windows 10 Enterprise LTSC 2021 (KMS) 202609 (2)|\\BUILD01\Sources\OSD\Images\Windows 10 Enterprise LTSC 2021 (KMS) 202609 (2)\install.wim|10.0.19044.6456")
Check 'import: content is distributed to the chosen distribution point by package ID' (($script:Cm.Calls | Where-Object { $_ -like 'Distribute|*' }) -eq 'Distribute|img=PS100123|inst=|dp=dp01.contoso.com|group=' -and $real19.PackageId -eq 'PS100123')
Check 'import: logs to <OS folder>\LOGS\SccmImport_<time>.log' ($script:LogFile -like (Join-Path $base 'Win10_Enterprise_LTSC_2021_KMS\LOGS\SccmImport_*.log'))
$script:LogFile = $null
# Upgrade package to a distribution point group: the whole media folder
$script:Cm.Calls.Clear()
$up19 = Invoke-MediaRefresh (Opts19 @{ DryRun = $false; SccmPackageType = 'Upgrade'; SccmTargetType = 'DPGroup'; SccmTarget = 'All DPs'; SccmImageName = 'KMS upgrade 202609' })
Check 'upgrade package: the media folder is copied, created as an OS upgrade package and sent to the group' ((Test-Path (Join-Path $contentRoot 'KMS upgrade 202609\setup.exe')) -and (Test-Path (Join-Path $contentRoot 'KMS upgrade 202609\sources\install.wim')) -and ($script:Cm.Calls -join ' / ') -eq 'NewInstaller|KMS upgrade 202609|\\BUILD01\Sources\OSD\Images\KMS upgrade 202609 / Distribute|img=|inst=PS100124|dp=|group=All DPs')
$script:LogFile = $null
# A folder that already exists gets a number; the name check is separate from the folder check
New-Item -ItemType Directory -Force (Join-Path $contentRoot 'Fresh name') | Out-Null
$dry19b = Invoke-MediaRefresh (Opts19 @{ SccmImageName = 'Fresh name' })
Check 'an existing sub-folder of the same name is never reused: the copy goes to "... (2)"' ($dry19b.Name -eq 'Fresh name' -and $dry19b.DestinationLocal -like '*\Fresh name (2)')
# Refusals
function Test-Refused19($o, $like) { $t = $false; $m = ''; try { [void](Invoke-MediaRefresh $o) } catch { $t = $true; $m = $_.Exception.Message }; return ($t -and $m -like $like) }
[void](Save-RunResult -Paths @{ NewWim = $nw19 } -OsName 'KMS' -Build '10.0.19044.6456' -Gate 'FAILED' -Install (Join-Path $nw19 'install.wim') -Media '' -ChangeLog '')
$script:Cm.Calls.Clear()
Check 'a run whose validation gate FAILED is refused, and nothing is copied or imported' ((Test-Refused19 (Opts19 @{ DryRun = $false; SccmImageName = 'Should not exist' }) 'Refused: *FAILED its validation gate*') -and $script:Cm.Calls.Count -eq 0 -and -not (Test-Path (Join-Path $contentRoot 'Should not exist')))
[void](Save-RunResult -Paths @{ NewWim = $nw19 } -OsName 'KMS' -Build '10.0.19044.6456' -Gate 'PASSED' -Install (Join-Path $nw19 'install.wim') -Media '' -ChangeLog '')
Check 'an upgrade package without a media folder is refused with what to do' (Test-Refused19 (Opts19 @{ SccmPackageType = 'Upgrade' }) "*Tick 'Create refreshed media folder'*")
Check 'a content source outside every share is refused' (Test-Refused19 (Opts19 @{ SccmContentSource = $base }) '*not inside a shared folder*')
Check 'an empty field is named' (Test-Refused19 (Opts19 @{ SccmTarget = '' }) 'Distribution point or group is empty*')
Remove-Item (Join-Path $nw19 'RunResult.json') -Force
Check 'no finished run: refused with what to do' (Test-Refused19 (Opts19) 'There is no finished run to import*')

Write-Host "`nRESULT: $pass passed, $fail failed"
