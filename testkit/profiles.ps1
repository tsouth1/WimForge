. ./mocks.ps1
# capture Write-Log output (mocks.ps1 prints; we also want to inspect)
$script:LogLines = [System.Collections.Generic.List[string]]::new()
function Write-Log { param($Message,$Level='INFO') $script:LogLines.Add("[$Level] $Message") }
$tmp = Join-Path $PWD 'ptest'; if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }; New-Item -ItemType Directory $tmp | Out-Null
function New-File($p,$c='x'){ New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null; Set-Content $p $c }

Write-Host "`n=== P1 built-in profiles ==="
$b = Import-OsProfiles
Check '5 built-in profiles' ($b.Count -eq 5)
Check 'order follows sortOrder' ((@($b.Keys) -join '|') -eq 'Windows 10 Enterprise LTSC 2019 (IoT)|Windows 10 IoT Enterprise LTSC 2021|Windows 10 Enterprise LTSC 2021 (KMS)|Windows 11 Enterprise 24H2|Windows Server 2022')
Check 'KMS profile: folder, regex, EOS' ($b['Windows 10 Enterprise LTSC 2021 (KMS)'].Folder -eq 'Win10_Enterprise_LTSC_2021_KMS' -and $b['Windows 10 Enterprise LTSC 2021 (KMS)'].EndOfSupport -eq '2027-01-13')
Check 'IoT regex requires IoT' ('Windows 10 Enterprise LTSC 2021' -notmatch $b['Windows 10 IoT Enterprise LTSC 2021'].EditionRegex -and 'Windows 10 IoT Enterprise LTSC 2021' -match $b['Windows 10 IoT Enterprise LTSC 2021'].EditionRegex)
Check 'Server profile: all indexes, server LP pattern' ($b['Windows Server 2022'].ServiceAllIndexes -and $b['Windows Server 2022'].LpPattern -like '*Server-Language-Pack*')
Check 'default languages: client 10, Win11 none' (@($b['Windows 10 Enterprise LTSC 2019 (IoT)'].DefaultLanguages).Count -eq 10 -and @($b['Windows 11 Enterprise 24H2'].DefaultLanguages).Count -eq 0)
Check 'package order has all five classes (empty)' (@($b['Windows Server 2022'].PackageOrder.Keys).Count -eq 5)

Write-Host "`n=== P2 first run creates the files, then loads them ==="
$dir = Join-Path $tmp 'Profiles'
$t = Import-OsProfiles -Directory $dir
$files = @(Get-ChildItem $dir -Filter *.json)
Check 'folder created with 5 JSON files' ($files.Count -eq 5) ($files.Name -join ',')
Check 'loaded 5 profiles from the files' ($t.Count -eq 5 -and $t['Windows 11 Enterprise 24H2'].SourceFile -eq 'Win11_Enterprise_24H2.json')
Check 'a creation message was recorded' (@($script:ProfileMessages | Where-Object { $_.Text -like 'Profile files created*' }).Count -eq 1)
$same = $true
foreach ($k in $b.Keys) { foreach ($prop in 'Folder','EditionRegex','PreferredIndex','LpPattern','SsuRequired','EndOfSupport','KeepArchives','MinFreeGB','SpaceCheck','ServiceAllIndexes') { if ("$($b[$k].$prop)" -ne "$($t[$k].$prop)") { $same=$false; Write-Host "   diff $k $prop '$($b[$k].$prop)' vs '$($t[$k].$prop)'" } }
  if ((@($b[$k].DefaultLanguages) -join ',') -ne (@($t[$k].DefaultLanguages) -join ',')) { $same=$false }
  if ((@($b[$k].AltFolders) -join ',') -ne (@($t[$k].AltFolders) -join ',')) { $same=$false } }
Check 'file round trip equals the built-ins' $same
$json = Get-Content (Join-Path $dir 'Win10_Enterprise_LTSC_2021_KMS.json') -Raw
Check 'JSON is readable, camelCase, arrays stay arrays' ($json -match '"editionRegex"' -and $json -match '"altFolders":\s*\[\s*\]' -and $json -match '"defaultLanguages":\s*\[')
Check 'no BOM in the files' ([System.IO.File]::ReadAllBytes((Join-Path $dir 'Win11_Enterprise_24H2.json'))[0] -eq 0x7B)

Write-Host "`n=== P3 a new OS by file only; deleted built-in stays deleted; edits apply ==="
$s25 = [ordered]@{ schemaVersion=1; name='Windows Server 2025'; sortOrder=60; folder='Windows_Server_2025'; serviceAllIndexes=$true; lpPattern='Microsoft-Windows-Server-Language-Pack_x64_{0}.cab'; endOfSupport='2034-11-14' }
[System.IO.File]::WriteAllText((Join-Path $dir 'Windows_Server_2025.json'), ($s25 | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
Remove-Item (Join-Path $dir 'Win10_Enterprise_LTSC_2019.json')
$edit = Get-Content (Join-Path $dir 'Win11_Enterprise_24H2.json') -Raw | ConvertFrom-Json; $edit.preferredIndex = 4
[System.IO.File]::WriteAllText((Join-Path $dir 'Win11_Enterprise_24H2.json'), ($edit | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
$t = Import-OsProfiles -Directory $dir
Check 'Server 2025 appears last, others remain' ($t.Count -eq 5 -and @($t.Keys)[-1] -eq 'Windows Server 2025')
Check 'deleted 2019 profile is not re-created' (-not $t.Contains('Windows 10 Enterprise LTSC 2019 (IoT)') -and -not (Test-Path (Join-Path $dir 'Win10_Enterprise_LTSC_2019.json')))
Check 'edit to preferredIndex applied' ($t['Windows 11 Enterprise 24H2'].PreferredIndex -eq 4)
Check 'defaults filled in for a minimal file' ($t['Windows Server 2025'].KeepArchives -eq 3 -and $t['Windows Server 2025'].SpaceCheck -eq 'enforce' -and $t['Windows Server 2025'].MinFreeGB -eq 30)

Write-Host "`n=== P4 invalid files are skipped with a clear message, the rest still load ==="
$bad = @{
 'bad1.json' = '{ not json';
 'bad2.json' = '{"name":"X","folder":"X","editionRegex":"(unclosed","preferredIndex":1}';
 'bad3.json' = '{"folder":"NoName","editionRegex":"a"}';
 'bad4.json' = '{"name":"BadClass","folder":"B","editionRegex":"a","packageOrder":{"Bogus":["*.msu"]}}';
 'bad5.json' = '{"name":"BadLp","folder":"B","editionRegex":"a","lpPattern":"no-placeholder.cab"}';
 'bad6.json' = '{"name":"BadDate","folder":"B","editionRegex":"a","endOfSupport":"13/01/2027"}';
 'bad7.json' = '{"name":"BadSpace","folder":"B","editionRegex":"a","spaceCheck":"maybe"}';
 'bad8.json' = '{"name":"BadLang","folder":"B","editionRegex":"a","defaultLanguages":["german"]}';
 'bad9.json' = '{"name":"Windows Server 2025","folder":"Dup","serviceAllIndexes":true}';
 'bad10.json' = '{"name":"NoEdition","folder":"B"}'
}
foreach ($k in $bad.Keys) { [System.IO.File]::WriteAllText((Join-Path $dir $k), $bad[$k]) }
$t = Import-OsProfiles -Directory $dir
Check 'good profiles still load (5)' ($t.Count -eq 5)
$msgs = @($script:ProfileMessages | ForEach-Object { $_.Text })
foreach ($k in ($bad.Keys | Where-Object { $_ -ne 'bad9.json' })) { Check "message names $k" (@($msgs | Where-Object { $_ -like "Profile file $k skipped:*" }).Count -eq 1) ($msgs -join ' | ') }
Check 'duplicate name: first file by name wins, the other is skipped and named' (@($msgs | Where-Object { $_ -like 'Profile file Windows_Server_2025.json skipped: another file already defines*' }).Count -eq 1 -and $t['Windows Server 2025'].SourceFile -eq 'bad9.json')
Check 'unknown class message lists valid classes' (@($msgs | Where-Object { $_ -like '*unknown class*SSU, LCU, NetCU, SafeOS, SetupDU*' }).Count -eq 1)

Write-Host "`n=== P5 empty folder gets files; only invalid files falls back to built-ins ==="
$d2 = Join-Path $tmp 'empty'; New-Item -ItemType Directory $d2 | Out-Null
$t2 = Import-OsProfiles -Directory $d2
Check 'empty folder is populated' ($t2.Count -eq 5 -and @(Get-ChildItem $d2 -Filter *.json).Count -eq 5)
$d3 = Join-Path $tmp 'allbad'; New-Item -ItemType Directory $d3 | Out-Null; Set-Content (Join-Path $d3 'x.json') '{ nope'
$t3 = Import-OsProfiles -Directory $d3
Check 'only-invalid folder falls back to built-ins with a warning' ($t3.Count -eq 5 -and @($script:ProfileMessages | Where-Object { $_.Text -like '*using the built-in profiles*' }).Count -eq 1)
$t4 = Import-OsProfiles -Directory (Join-Path $tmp 'nested\deep\Profiles')
Check 'missing nested folder is created' ($t4.Count -eq 5 -and (Test-Path (Join-Path $tmp 'nested\deep\Profiles\Windows_Server_2022.json')))

Write-Host "`n=== P6 package order manifest ==="
$pk = Join-Path $tmp 'SSU'; foreach ($n in 'a-first.msu','z-ssu-19041.3562-x64.msu','m-kb5005112.msu','b-other.cab') { New-File (Join-Path $pk $n) }
$plain = @(Get-PackageFiles -Path $pk | ForEach-Object Name)
Check 'no manifest = name order' (($plain -join ',') -eq 'a-first.msu,b-other.cab,m-kb5005112.msu,z-ssu-19041.3562-x64.msu') ($plain -join ',')
$script:LogLines.Clear()
$ord = @(Get-PackageFiles -Path $pk -Order @('*kb5005112*','z-ssu-*') | ForEach-Object Name)
Check 'manifest patterns first, in pattern order; the rest by name' (($ord -join ',') -eq 'm-kb5005112.msu,z-ssu-19041.3562-x64.msu,a-first.msu,b-other.cab') ($ord -join ',')
$ord2 = @(Get-PackageFiles -Path $pk -Order @('nomatch*','b-other*') | ForEach-Object Name)
Check 'a pattern that matches nothing warns but is harmless' (@($script:LogLines | Where-Object { $_ -like "[[]WARN] Order manifest pattern 'nomatch*' matched no file*" }).Count -eq 1 -and $ord2[0] -eq 'b-other.cab')
$ps = Get-PackageSet -PatchRoot $tmp -Enabled @{ LCU=$false; SSU=$true; NetCU=$false; SafeOS=$false; SetupDU=$false } -Order @{ SSU = @('z-*') }
Check 'Get-PackageSet passes the class order through' (@($ps.SSU)[0].Name -eq 'z-ssu-19041.3562-x64.msu')
$script:LogLines.Clear()
Test-PackageSet -Definition ([pscustomobject]@{ SsuRequired=$false }) -Packages $ps -Enabled @{ LCU=$false; SSU=$true; NetCU=$false; SafeOS=$false; SetupDU=$false } -DoWinRe $false -BuildMedia $false
Check 'the applied order is logged' (@($script:LogLines | Where-Object { $_ -like '*SSU order: z-ssu-19041.3562-x64.msu -> a-first.msu*' }).Count -eq 1) ($script:LogLines -join ' | ')

Write-Host "`n=== P7 support status ==="
$def = [pscustomobject]@{ EndOfSupport='2027-01-13' }
function St($now) { (Get-SupportStatus -Definition $def -Now ([datetime]::ParseExact($now,'yyyy-MM-dd',$null))) }
Check '2026-09-21 -> 114 days, Soon' ((St '2026-09-21').Days -eq 114 -and (St '2026-09-21').Level -eq 'Soon')
Check '181 days out -> OK' ((St '2026-07-16').Days -eq 181 -and (St '2026-07-16').Level -eq 'OK')
Check '180 days out -> Soon' ((St '2026-07-17').Days -eq 180 -and (St '2026-07-17').Level -eq 'Soon')
Check 'on the day -> Soon (0 days)' ((St '2027-01-13').Days -eq 0 -and (St '2027-01-13').Level -eq 'Soon')
Check 'day after -> Past with text' ((St '2027-01-14').Level -eq 'Past' -and (St '2027-01-14').Text -eq 'Support ended 2027-01-13 (1 days ago).')
Check 'empty date -> Unknown' ((Get-SupportStatus -Definition ([pscustomobject]@{ EndOfSupport='' })).Level -eq 'Unknown')
$script:LogLines.Clear(); Write-SupportStatus -Definition ([pscustomobject]@{ EndOfSupport='2001-01-01' })
Check 'past date is logged as WARN' ($script:LogLines[0] -like '[[]WARN] Support ended 2001-01-01*')
$script:LogLines.Clear(); Write-SupportStatus -Definition ([pscustomobject]@{ EndOfSupport='2999-01-01' })
Check 'far date is logged as INFO' ($script:LogLines[0] -like '[[]INFO] Support ends 2999-01-01*')

Write-Host "`n=== P8 archive previous output ==="
$paths = @{ NewWim = (Join-Path $tmp 'NEWWIM') }
New-File (Join-Path $paths.NewWim 'install.wim') 'old'; New-File (Join-Path $paths.NewWim 'Media\sources\install.wim') 'old'; New-File (Join-Path $paths.NewWim 'ChangeLog.html') 'old'
foreach ($n in '20260101_000000','20260201_000000','20260301_000000') { New-File (Join-Path $paths.NewWim "Archive\$n\install.wim") 'older' }
$script:OutputArchived = $false; $script:LogLines.Clear()
Backup-PreviousOutput -Paths $paths -Stamp '20260921_120000' -Keep 3
$arch = @(Get-ChildItem (Join-Path $paths.NewWim 'Archive') -Directory | ForEach-Object Name)
Check 'previous output moved into a dated folder' ((Test-Path (Join-Path $paths.NewWim 'Archive\20260921_120000\install.wim')) -and (Test-Path (Join-Path $paths.NewWim 'Archive\20260921_120000\Media\sources\install.wim')) -and (Test-Path (Join-Path $paths.NewWim 'Archive\20260921_120000\ChangeLog.html')))
Check 'NEWWIM top level is clear except Archive' ((@(Get-ChildItem $paths.NewWim | ForEach-Object Name) -join ',') -eq 'Archive')
Check 'only the newest 3 archives are kept' (($arch -join ',') -eq '20260201_000000,20260301_000000,20260921_120000') ($arch -join ',')
Check 'removal was logged' (@($script:LogLines | Where-Object { $_ -like '*Removed old archive 20260101_000000*' }).Count -eq 1)
New-File (Join-Path $paths.NewWim 'install.wim') 'new'
Backup-PreviousOutput -Paths $paths -Stamp '20260921_130000' -Keep 3
Check 'second call in the same run does nothing' ((Test-Path (Join-Path $paths.NewWim 'install.wim')) -and -not (Test-Path (Join-Path $paths.NewWim 'Archive\20260921_130000')))
$script:OutputArchived = $false
$e = @{ NewWim = (Join-Path $tmp 'EMPTYOUT') }; New-Item -ItemType Directory $e.NewWim | Out-Null
Backup-PreviousOutput -Paths $e -Stamp 'x' -Keep 3
Check 'empty NEWWIM: no archive folder is created' (-not (Test-Path (Join-Path $e.NewWim 'Archive')))
$script:OutputArchived = $false
$k0 = @{ NewWim = (Join-Path $tmp 'KEEPALL') }; foreach ($n in 1..6) { New-File (Join-Path $k0.NewWim "Archive\a$n\f") }; New-File (Join-Path $k0.NewWim 'install.wim')
Backup-PreviousOutput -Paths $k0 -Stamp 'z' -Keep 0
Check 'keep 0 = keep every archive' (@(Get-ChildItem (Join-Path $k0.NewWim 'Archive') -Directory).Count -eq 7)

Write-Host "`n=== P9 free-space check ==="
# restore the real function (mocks.ps1 replaced it) so we can also test the raw reader, then mock per case
$real = (Get-Content -Raw $(if ($env:MR_SCRIPT) { $env:MR_SCRIPT } else { (Join-Path $PSScriptRoot '../MediaRefresh_v2.4.ps1') }))
$gm = [regex]::Match($real, '(?s)function Get-FreeSpaceGB \{.*?\r?\n\}\r?\n').Value
Invoke-Expression $gm
$fs = Get-FreeSpaceGB -Path $tmp
Check 'real reader returns a positive number' ($fs -gt 0) "$fs"
Check 'unreadable path returns null instead of throwing' ($null -eq (Get-FreeSpaceGB -Path "bad`0path"))
function Get-FreeSpaceGB { param([string]$Path) return $script:FreeGB }
$wim = Join-Path $tmp 'src\install.wim'; New-Item -ItemType Directory (Split-Path $wim) | Out-Null
$fsx = [System.IO.File]::Create($wim); $fsx.SetLength(2GB); $fsx.Close()
$defA = [pscustomobject]@{ MinFreeGB = 0; SpaceCheck = 'enforce'; SourceFile = 'X.json' }
$pp = @{ Root = $tmp }
$opt = [pscustomobject]@{ BuildMedia=$false; BuildIso=$false }
$script:FreeGB = 13.0; $script:LogLines.Clear(); Test-FreeSpace -Definition $defA -Paths $pp -SourceWim $wim -OsIsoPath $null -Options $opt
Check '2 GB WIM needs about 12 GB; 13 GB free passes' (@($script:LogLines | Where-Object { $_ -like '*needs about 12 GB*' }).Count -eq 1) ($script:LogLines -join ' | ')
$script:FreeGB = 11.0; $m = ''; try { Test-FreeSpace -Definition $defA -Paths $pp -SourceWim $wim -OsIsoPath $null -Options $opt } catch { $m = $_.Exception.Message }
Check '11 GB free fails with numbers and the profile file to edit' ($m -like 'Not enough free disk space.*11*12 GB*X.json*') $m
$defW = [pscustomobject]@{ MinFreeGB = 0; SpaceCheck = 'warn'; SourceFile = 'X.json' }; $script:LogLines.Clear()
Test-FreeSpace -Definition $defW -Paths $pp -SourceWim $wim -OsIsoPath $null -Options $opt
Check 'warn mode logs a WARN and continues' (@($script:LogLines | Where-Object { $_ -like '[[]WARN] Free space*Continuing because spaceCheck is*' }).Count -eq 1)
$defO = [pscustomobject]@{ MinFreeGB = 0; SpaceCheck = 'off'; SourceFile = 'X.json' }; $script:LogLines.Clear()
Test-FreeSpace -Definition $defO -Paths $pp -SourceWim $wim -OsIsoPath $null -Options $opt
Check 'off mode does nothing' ($script:LogLines.Count -eq 0)
$defF = [pscustomobject]@{ MinFreeGB = 40; SpaceCheck = 'enforce'; SourceFile = 'X.json' }; $script:FreeGB = 39.0; $m=''
try { Test-FreeSpace -Definition $defF -Paths $pp -SourceWim $wim -OsIsoPath $null -Options $opt } catch { $m = $_.Exception.Message }
Check 'profile minimum is a floor above the estimate' ($m -like '*needs about 40 GB*')
$iso = Join-Path $tmp 'os.iso'; $fsx = [System.IO.File]::Create($iso); $fsx.SetLength(4GB); $fsx.Close()
$script:FreeGB = 500.0; $script:LogLines.Clear()
Test-FreeSpace -Definition $defA -Paths $pp -SourceWim $wim -OsIsoPath $iso -Options ([pscustomobject]@{ BuildMedia=$true; BuildIso=$true })
Check 'media + ISO add one ISO size each (12 + 4 + 4 = 20)' (@($script:LogLines | Where-Object { $_ -like '*needs about 20 GB*' }).Count -eq 1) ($script:LogLines -join ' | ')
$script:LogLines.Clear()
Test-FreeSpace -Definition $defA -Paths $pp -SourceWim $wim -OsIsoPath $iso -Options ([pscustomobject]@{ BuildMedia=$true; BuildIso=$true; Boot=$true; Media2023=$true })
Check 'CA 2023 media + ISO alongside add two more ISO sizes (20 + 4 + 4 = 28)' (@($script:LogLines | Where-Object { $_ -like '*needs about 28 GB*' }).Count -eq 1) ($script:LogLines -join ' | ')
$esd = Join-Path $tmp 'src\install.esd'; $fsx = [System.IO.File]::Create($esd); $fsx.SetLength(2GB); $fsx.Close(); $script:LogLines.Clear()
Test-FreeSpace -Definition $defA -Paths $pp -SourceWim $esd -OsIsoPath $null -Options $opt
Check 'ESD is treated as about 2.5x larger (2*2.5*3+6 = 21)' (@($script:LogLines | Where-Object { $_ -like '*needs about 21 GB*' }).Count -eq 1) ($script:LogLines -join ' | ')
$script:FreeGB = $null; $script:LogLines.Clear(); Test-FreeSpace -Definition $defA -Paths $pp -SourceWim $wim -OsIsoPath $null -Options $opt
Check 'unreadable free space skips with a WARN' (@($script:LogLines | Where-Object { $_ -like '[[]WARN] Free disk space could not be read*' }).Count -eq 1)

Write-Host "`n=== P10 Languages tab list from Profiles\Languages.json (TODO step 10e) ==="
# Windows PowerShell 5.1 ConvertFrom-Json passes a JSON array on as ONE object, so enumerate it explicitly
$repoLangs = @(([System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '../Languages.json')) | ConvertFrom-Json) | ForEach-Object { $_ })
$builtLangs = @(ConvertTo-LanguageList -Data (Get-BuiltInLanguageData))
Check 'the built-in list matches the repo Languages.json exactly (names, codes, order)' ((($builtLangs | ForEach-Object { "$($_.Name)|$($_.Code)" }) -join ';') -eq (($repoLangs | ForEach-Object { "$($_.language)|$($_.code)" }) -join ';'))
Check 'each entry is shown as "full name - code"' ($builtLangs[0].Display -eq 'Catalan (Spain) - ca-es' -and ($builtLangs | Where-Object { $_.Code -eq 'zh-tw' }).Display -eq 'Chinese (Traditional, Taiwan) - zh-tw')
$langDir = Join-Path $tmp 'langprof'
$script:ProfileMessages.Clear()
$l1 = @(Import-LanguageList -Directory $langDir)
$langFile = Join-Path $langDir 'Languages.json'
Check 'a missing Languages.json is created from the built-in list and loaded' ((Test-Path $langFile) -and $l1.Count -eq 20 -and [bool]($script:ProfileMessages | Where-Object { $_.Text -like 'Language list created*' }))
Check 'the created file has the same content as the repo Languages.json' ((((Get-Content $langFile -Raw) | ConvertFrom-Json) | ForEach-Object { "$($_.language)|$($_.code)" }) -join ';' -eq (($repoLangs | ForEach-Object { "$($_.language)|$($_.code)" }) -join ';'))
Check 'the created file has no BOM (same as the profile files)' ([System.IO.File]::ReadAllBytes($langFile)[0] -eq [byte][char]'[')
[System.IO.File]::WriteAllText($langFile, '[ { "language": "German (Germany)", "code": "de-de" }, { "language": "Welsh (United Kingdom)", "code": "CY-GB" } ]')
$l2 = @(Import-LanguageList -Directory $langDir)
Check 'an edited file wins over the built-in list (codes lower-cased)' ((($l2 | ForEach-Object { $_.Code }) -join ',') -eq 'de-de,cy-gb' -and $l2[1].Display -eq 'Welsh (United Kingdom) - cy-gb')
foreach ($bad in @('not json', '[]', '[ { "language": "German" } ]', '[ { "language": "German", "code": "german" } ]', '[ { "language": "A", "code": "de-de" }, { "language": "B", "code": "DE-DE" } ]')) {
    [System.IO.File]::WriteAllText($langFile, $bad); $script:ProfileMessages.Clear()
    $lb = @(Import-LanguageList -Directory $langDir)
    Check "a bad file falls back to the built-in list with a WARN: $bad" ($lb.Count -eq 20 -and [bool]($script:ProfileMessages | Where-Object { $_.Level -eq 'WARN' -and $_.Text -like 'Language list * could not be used*' }))
}
# Languages.json sits in the Profiles folder but is not an OS profile
$mixDir = Join-Path $tmp 'mixprof'; $script:ProfileMessages.Clear()
$null = Import-LanguageList -Directory $mixDir
$pm = Import-OsProfiles -Directory $mixDir
Check 'a Profiles folder holding only Languages.json still gets the 5 profile files' ($pm.Count -eq 5 -and @(Get-ChildItem $mixDir -Filter '*.json').Count -eq 6)
$script:ProfileMessages.Clear(); $pm2 = Import-OsProfiles -Directory $mixDir
Check 'Languages.json is not read as an OS profile (no "skipped" message)' ($pm2.Count -eq 5 -and -not ($script:ProfileMessages | Where-Object { $_.Text -like '*Languages.json*' }))
# profile defaults vs the list
$kms = $b['Windows 10 Enterprise LTSC 2021 (KMS)']
$s1 = Get-DefaultLanguageSelection -Definition $kms -LanguageList $builtLangs
Check 'every built-in profile default is on the list (en-gb and zh-tw added 2026-09-26)' (@($s1.Missing).Count -eq 0 -and @($s1.Select).Count -eq 10)
$s2 = Get-DefaultLanguageSelection -Definition ([pscustomobject]@{ Name = 'X'; DefaultLanguages = @('de-de', 'en-us') }) -LanguageList $builtLangs
Check 'a default that is not on the list is reported and not selected' ((@($s2.Select) -join ',') -eq 'de-de' -and (@($s2.Missing) -join ',') -eq 'en-us')

Write-Host "`n=== P11 saved settings per OS in Settings\<folder>.json (TODO step 10c) ==="
$setDir = Join-Path $tmp 'Settings'
Check 'an OS without saved settings reads as none' ($null -eq (Read-OsSettings -Directory $setDir -Definition $kms -LanguageList $builtLangs))
$optsIn = @{ Preflight = $false; Install = $true; Boot = $true; WinRE = $false; Verify = $true; BuildMedia = $false; BuildIso = $false; SSU = $true; LCU = $true; SafeOS = $false; NetCU = $true; SetupDU = $false; NetFx3 = $true; Bogus = $true }
$sf = Save-OsSettings -Directory $setDir -Definition $kms -Options $optsIn -Languages @('de-de', 'JA-JP')
Check 'settings are saved to Settings\<profile folder>.json, without a BOM' ((Split-Path $sf -Leaf) -eq 'Win10_Enterprise_LTSC_2021_KMS.json' -and [System.IO.File]::ReadAllBytes($sf)[0] -eq [byte][char]'{')
$rs = Read-OsSettings -Directory $setDir -Definition $kms -LanguageList $builtLangs
$optsOk = @($script:SettingOptionNames | Where-Object { $rs.Options[$_] -ne $optsIn[$_] }).Count -eq 0
Check 'save then load returns the same options and languages (codes lower-cased, unknown option names dropped)' ($optsOk -and -not $rs.Options.ContainsKey('Bogus') -and (@($rs.Languages) -join ',') -eq 'de-de,ja-jp')
$null = Save-OsSettings -Directory $setDir -Definition $kms -Options @{ LCU = $true } -Languages @()
Check 'saving no languages loads as none (English only), not as the defaults' (@((Read-OsSettings -Directory $setDir -Definition $kms -LanguageList $builtLangs).Languages).Count -eq 0)
$null = Save-OsSettings -Directory $setDir -Definition $kms -Options $optsIn -Languages @('de-de', 'cy-gb')
$rs2 = Read-OsSettings -Directory $setDir -Definition $kms -LanguageList $builtLangs
Check 'a saved language no longer in Languages.json is reported, not selected' ((@($rs2.Languages) -join ',') -eq 'de-de' -and (@($rs2.MissingLanguages) -join ',') -eq 'cy-gb')
foreach ($bad in @('not json', '{ "languages": [] }', '{ "options": { "LCU": "yes" } }')) {
    [System.IO.File]::WriteAllText($sf, $bad); $script:LogLines.Clear()
    Check "an unusable settings file is ignored with a WARN: $bad" ($null -eq (Read-OsSettings -Directory $setDir -Definition $kms -LanguageList $builtLangs) -and [bool]($script:LogLines -match 'WARN.*Saved settings .* could not be used'))
}
Check 'Remove-OsSettings deletes the file, then reports there is none' ((Remove-OsSettings -Directory $setDir -Definition $kms) -and -not (Test-Path $sf) -and -not (Remove-OsSettings -Directory $setDir -Definition $kms))
Check 'no saved repository root reads as empty' ((Read-GeneralSettings -Directory $setDir) -eq '')
Save-GeneralSettings -Directory $setDir -Root 'G:\mediaRefresh'
Check 'the repository root is saved in Settings\General.json and read back' ((Read-GeneralSettings -Directory $setDir) -eq 'G:\mediaRefresh' -and (Test-Path (Join-Path $setDir 'General.json')))
# Regenerating the profiles (delete Profiles\ and reload, the 2026-09-24 fix) must not touch saved settings
$regenProf = Join-Path $tmp 'regen\Profiles'; $regenSet = Join-Path $tmp 'regen\Settings'
$null = Import-OsProfiles -Directory $regenProf; $null = Save-OsSettings -Directory $regenSet -Definition $kms -Options $optsIn -Languages @('fr-fr')
Remove-Item -Recurse -Force $regenProf; $null = Import-OsProfiles -Directory $regenProf
Check 'regenerating the Profiles folder leaves the saved settings in place' ((@((Read-OsSettings -Directory $regenSet -Definition $kms -LanguageList $builtLangs).Languages) -join ',') -eq 'fr-fr')

Write-Host "`n=== P12 colour schemes (General Settings tab, Terry 2026-09-27) ==="
$cs = Get-ColorSchemes
Check 'five schemes, Default first, in the order given' ((@($cs.Keys) -join '|') -eq 'Default|Industrial Forge|Modern Sysadmin|Arcane Tech (Runic Teal)|Minimalist Forge')
$roles0 = @($cs['Default'].Colors.Keys) -join ','
Check 'every scheme sets the same colour roles, each a #RRGGBB value' (@($cs.Keys | Where-Object { (@($cs[$_].Colors.Keys) -join ',') -ne $roles0 -or @($cs[$_].Colors.Values | Where-Object { $_ -notmatch '^#[0-9A-F]{6}$' }).Count -gt 0 }).Count -eq 0)
$d0 = $cs['Default'].Colors
Check 'Default keeps the original colours (window, muted text, Start button, log)' ($d0.WindowBg -eq '#F4F6F8' -and $d0.SubtleText -eq '#555555' -and $d0.Accent -eq '#0078D4' -and $d0.AccentText -eq '#FFFFFF' -and $d0.LogBg -eq '#111827' -and $d0.LogText -eq '#E5E7EB' -and -not $cs['Default'].Dark)
$given = [ordered]@{
    'Industrial Forge'         = '#2B2B2B #3A5F7D #1A1A1A #FF6A00 #FFC14A'
    'Modern Sysadmin'          = '#0078D4 #3C3C3C #5A5A5A #D0D0D0 #A4E400'
    'Arcane Tech (Runic Teal)' = '#00A6A6 #0F0F0F #2F3B45 #4B2E83 #C6A667'
    'Minimalist Forge'         = '#121212 #B8B8B8 #2E2E2E #D7263D #F2F2F2' }
foreach ($n in $given.Keys) { Check "$n palette is exactly the five colours given" ((@($cs[$n].Palette | ForEach-Object { ($_ -split ' ')[-1] }) -join ' ') -eq $given[$n]) }
Check 'log text colours as given: Industrial Amber Glow, Arcane Electrum Gold' ($cs['Industrial Forge'].Colors.LogText -eq '#FFC14A' -and $cs['Arcane Tech (Runic Teal)'].Colors.LogText -eq '#C6A667')
Check 'Modern Sysadmin log: Cloud Gray general, Lime Signal success' ($cs['Modern Sysadmin'].Colors.LogText -eq '#D0D0D0' -and $cs['Modern Sysadmin'].Colors.LogSuccess -eq '#A4E400')
Check 'Minimalist Forge log: Soft Gray general, Forge Red errors' ($cs['Minimalist Forge'].Colors.LogText -eq '#B8B8B8' -and $cs['Minimalist Forge'].Colors.LogError -eq '#D7263D')
function Get-Contrast([string]$A, [string]$B) {
    $lum = { param($h) $c = @(1, 3, 5 | ForEach-Object { $v = [Convert]::ToInt32($h.Substring($_, 2), 16) / 255.0; if ($v -le 0.03928) { $v / 12.92 } else { [Math]::Pow(($v + 0.055) / 1.055, 2.4) } }); 0.2126 * $c[0] + 0.7152 * $c[1] + 0.0722 * $c[2] }
    $x = & $lum $A; $y = & $lum $B; ([Math]::Max($x, $y) + 0.05) / ([Math]::Min($x, $y) + 0.05)
}
# Colours chosen for readability (not the log colours Terry specified) must reach 4.3:1 against what they sit on
$pairs = 'Text/WindowBg', 'Text/PanelBg', 'Text/ControlBg', 'Text/CodeBg', 'SubtleText/PanelBg', 'SubtleText/WindowBg', 'ButtonText/ButtonBg', 'AccentText/Accent', 'SelectionText/SelectionBg', 'TabSelectedText/PanelBg', 'Text/Hover', 'WarnText/PanelBg', 'InfoText/PanelBg', 'LogText/LogBg', 'LogWarn/LogBg'
$low = foreach ($n in $cs.Keys) { foreach ($p in $pairs) { $f, $b = $p -split '/'; $r = Get-Contrast $cs[$n].Colors[$f] $cs[$n].Colors[$b]; if ($r -lt 4.3) { "$n $p {0:N1}" -f $r } } }
Check 'every scheme keeps text readable (contrast 4.3:1 or better)' (@($low).Count -eq 0) ($low -join '; ')
Check 'log lines are classed by level: ERROR, WARN / CANCELLED, success, normal' (
    (Get-LogLineKind '10:32:05 [ERROR] Add-WindowsPackage failed') -eq 'Error' -and (Get-LogLineKind '[ERROR] run failed') -eq 'Error' -and
    (Get-LogLineKind '10:31:12 [WARN] Skipped .NET CU') -eq 'Warn' -and (Get-LogLineKind '[CANCELLED] stopped') -eq 'Warn' -and
    (Get-LogLineKind '10:58:40 [INFO] VALIDATION GATE: PASSED') -eq 'Success' -and (Get-LogLineKind '09:44:01 [INFO] PREFLIGHT OK: ISO roles ...') -eq 'Success' -and
    (Get-LogLineKind '11:04:10 [INFO] Media refresh completed successfully.') -eq 'Success' -and
    (Get-LogLineKind '10:15:02 [INFO] Adding LCU x.msu to install.wim index 1') -eq 'Normal' -and (Get-LogLineKind '10:15:02 [INFO] mentions [ERROR] later') -eq 'Normal')
$gs = Join-Path $tmp 'Settings_scheme'
Check 'no saved colour scheme reads as empty' ((Read-ColorSchemeSetting -Directory $gs) -eq '')
Save-GeneralSettings -Directory $gs -Root 'G:\mediaRefresh'
Save-GeneralSettings -Directory $gs -ColorScheme 'Modern Sysadmin'
Check 'saving the colour scheme keeps the saved repository root' ((Read-ColorSchemeSetting -Directory $gs) -eq 'Modern Sysadmin' -and (Read-GeneralSettings -Directory $gs) -eq 'G:\mediaRefresh')
Save-GeneralSettings -Directory $gs -Root 'H:\mr'
Check 'saving the repository root (Save settings button) keeps the colour scheme' ((Read-ColorSchemeSetting -Directory $gs) -eq 'Modern Sysadmin' -and (Read-GeneralSettings -Directory $gs) -eq 'H:\mr')
[System.IO.File]::WriteAllText((Join-Path $gs 'General.json'), 'not json'); $script:LogLines.Clear()
Check 'an unusable General.json reads as no scheme, with a WARN' ((Read-ColorSchemeSetting -Directory $gs) -eq '' -and [bool]($script:LogLines -match 'WARN.*could not be used'))
Save-GeneralSettings -Directory $gs -ColorScheme 'Minimalist Forge'
Check 'saving over an unusable General.json writes a good file' ((Read-ColorSchemeSetting -Directory $gs) -eq 'Minimalist Forge' -and (Read-GeneralSettings -Directory $gs) -eq '')

Write-Host "`n=== P13 Instructions tab: the Markdown subset INSTRUCTIONS.md uses (TODO 10b) ==="
$md13 = @(
    '# Title', '', 'First line of a paragraph', 'continues here.', '', '## Section', '### Sub',
    '- one', '- two', '  continued text', '  - nested a', '    - deeper', '- three', '', '1. first', '2. second', '',
    '```', 'code line 1', '  code line 2', '```', 'After code.'
) -join "`r`n"
$b13 = @(ConvertFrom-MarkdownBlocks $md13)
$shape13 = ($b13 | ForEach-Object { "$($_.Type)$($_.Level)$(if ($_.Ordered) { 'o' })" }) -join ','
Check 'blocks: headings with levels, paragraph, nested and numbered list items, code, paragraph' ($shape13 -eq 'Heading1,Paragraph0,Heading2,Heading3,ListItem0,ListItem0,ListItem1,ListItem2,ListItem0,ListItem0o,ListItem0o,Code0,Paragraph0') $shape13
Check 'paragraph lines and list continuation lines are joined with a space' ($b13[1].Text -eq 'First line of a paragraph continues here.' -and $b13[5].Text -eq 'two continued text')
Check 'a code block keeps its lines and indentation, and markup inside it is not parsed' ($b13[11].Text -eq "code line 1`n  code line 2")
$in13 = @(Split-MarkdownInline 'Run **it elevated** with `Unblock-File .\x.ps1`, see [KB](https://support.microsoft.com/kb) or *this*.')
Check 'inline: bold, code, link and italic runs, with the plain text between them' ((($in13 | ForEach-Object { "$($_.Kind):$($_.Text)" }) -join '|') -eq 'Text:Run |Bold:it elevated|Text: with |Code:Unblock-File .\x.ps1|Text:, see |Link:KB|Text: or |Italic:this|Text:.' -and $in13[5].Url -eq 'https://support.microsoft.com/kb')
$in13b = @(Split-MarkdownInline 'Paths like NEWWIM\Media_CA2023 and `MediaRefresh_*` and C:\*.iso stay as written')
Check 'underscores and a lone * are not markup; a * inside code stays in the code' ((($in13b | ForEach-Object { "$($_.Kind):$($_.Text)" }) -join '|') -eq 'Text:Paths like NEWWIM\Media_CA2023 and |Code:MediaRefresh_*|Text: and C:\*.iso stay as written')
Write-Host "`n=== P14 provisioned apps: the saved list and the ticks (TODO step 11) ==="
$os14 = Join-Path $tmp 'apps14\Win11_Enterprise_24H2'
Check 'no app list yet reads as none' ($null -eq (Read-AppInventory -OsRoot $os14))
$apps14 = @([pscustomobject]@{ DisplayName = 'Microsoft.BingNews'; Version = '4.1.0.0'; PackageName = 'Microsoft.BingNews_4.1.0.0_neutral_~_8wekyb3d8bbwe' },
            [pscustomobject]@{ DisplayName = 'Microsoft.Copilot'; Version = '1.0.0.0'; PackageName = 'Microsoft.Copilot_1.0.0.0_neutral_~_8wekyb3d8bbwe' })
$f14 = Save-AppInventory -OsRoot $os14 -Apps $apps14 -Source 'os11.iso' -Index 3 -ImageName 'Windows 11 Enterprise' -Version '10.0.26100.1'
$r14 = Read-AppInventory -OsRoot $os14
Check 'the app list is saved in <OS folder>\ProvisionedApps.json and read back with its source, index and apps' ((Split-Path $f14 -Leaf) -eq 'ProvisionedApps.json' -and $r14.Source -eq 'os11.iso' -and $r14.Index -eq 3 -and (@($r14.Apps).DisplayName -join ',') -eq 'Microsoft.BingNews,Microsoft.Copilot' -and $r14.Apps[1].PackageName -like 'Microsoft.Copilot_*')
[System.IO.File]::WriteAllText($f14, '{ "apps": [ { "version": "1" } ] }'); $script:LogLines.Clear()
Check 'an unusable app list reads as none, with a WARN' ($null -eq (Read-AppInventory -OsRoot $os14) -and [bool]($script:LogLines -match 'WARN.*App list .* could not be used'))
$sf14 = Save-OsSettings -Directory (Join-Path $tmp 'apps14\Settings') -Definition $kms -Options @{ AppRemoval = $true } -Languages @() -RemoveApps @('Microsoft.BingNews', 'Microsoft.Copilot')
$rs14 = Read-OsSettings -Directory (Join-Path $tmp 'apps14\Settings') -Definition $kms -LanguageList $builtLangs
Check 'the ticked apps (by name) and the Remove the ticked apps option are saved per OS and read back' ((@($rs14.RemoveApps) -join ',') -eq 'Microsoft.BingNews,Microsoft.Copilot' -and $rs14.Options['AppRemoval'] -eq $true)
[System.IO.File]::WriteAllText($sf14, '{ "schemaVersion": 1, "options": { "LCU": true }, "languages": [ "de-de" ] }')
$old14 = Read-OsSettings -Directory (Join-Path $tmp 'apps14\Settings') -Definition $kms -LanguageList $builtLangs
Check 'a settings file saved before the Apps tab existed reads back with no ticked apps' ($null -ne $old14 -and @($old14.RemoveApps).Count -eq 0 -and (@($old14.Languages) -join ',') -eq 'de-de')
$w11def = [pscustomobject]@{ Folder = 'Win11_Enterprise_24H2'; AltFolders = @('Win11Enterprise_24H2') }
New-Item -ItemType Directory -Force (Join-Path $tmp 'apps14b\Win11Enterprise_24H2') | Out-Null
Check 'Get-OsRootPath uses an accepted alternative folder name that exists, and never throws for a missing drive' ((Get-OsRootPath -Root (Join-Path $tmp 'apps14b') -Definition $w11def) -like '*\Win11Enterprise_24H2' -and (Get-OsRootPath -Root 'Q:\nowhere' -Definition $w11def) -eq 'Q:\nowhere\Win11_Enterprise_24H2')

$guide13 = Join-Path (Split-Path $PSScriptRoot -Parent) 'INSTRUCTIONS.md'
if (Test-Path $guide13) {
    $gb13 = @(ConvertFrom-MarkdownBlocks ([System.IO.File]::ReadAllText($guide13)))
    $left13 = @($gb13 | Where-Object { $_.Type -ne 'Code' } | ForEach-Object { Split-MarkdownInline $_.Text } | Where-Object { $_.Kind -eq 'Text' -and ($_.Text -match '\*\*|`') } | ForEach-Object { $_.Text })
    Check 'the real INSTRUCTIONS.md parses with no stray ** or ` left in the text' ($gb13.Count -gt 50 -and @($gb13 | Where-Object { $_.Type -eq 'Heading' -and $_.Text -eq 'Where the logs are' }).Count -eq 1 -and $left13.Count -eq 0) ($left13 -join ' || ')
} else { Write-Host 'SKIP  INSTRUCTIONS.md not found next to the script' }

Write-Host "`nRESULT: $pass passed, $fail failed"
