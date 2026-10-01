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

Write-Host "`n=== P3 a new OS by file only; a deleted built-in comes back on Reload; .disabled switches one off; edits apply ==="
$s25 = [ordered]@{ schemaVersion=1; name='Windows Server 2025'; sortOrder=60; folder='Windows_Server_2025'; serviceAllIndexes=$true; lpPattern='Microsoft-Windows-Server-Language-Pack_x64_{0}.cab'; endOfSupport='2034-11-14' }
[System.IO.File]::WriteAllText((Join-Path $dir 'Windows_Server_2025.json'), ($s25 | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
# Hand edits in the 2019 file, then the file is deleted: Reload writes a fresh built-in copy (2026-09-27)
$e19 = Get-Content (Join-Path $dir 'Win10_Enterprise_LTSC_2019.json') -Raw | ConvertFrom-Json; $e19.preferredIndex = 7
[System.IO.File]::WriteAllText((Join-Path $dir 'Win10_Enterprise_LTSC_2019.json'), ($e19 | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
Remove-Item (Join-Path $dir 'Win10_Enterprise_LTSC_2019.json')
$edit = Get-Content (Join-Path $dir 'Win11_Enterprise_24H2.json') -Raw | ConvertFrom-Json; $edit.preferredIndex = 4
[System.IO.File]::WriteAllText((Join-Path $dir 'Win11_Enterprise_24H2.json'), ($edit | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
$t = Import-OsProfiles -Directory $dir
Check 'Server 2025 appears last, the five built-ins remain' ($t.Count -eq 6 -and @($t.Keys)[-1] -eq 'Windows Server 2025')
Check 'a deleted built-in profile is written again on Reload, fresh from the built-ins' ((Test-Path (Join-Path $dir 'Win10_Enterprise_LTSC_2019.json')) -and $t['Windows 10 Enterprise LTSC 2019 (IoT)'].PreferredIndex -eq 1 -and [bool]($script:ProfileMessages | Where-Object { $_.Text -like 'Profile files created from the built-in profiles in *: Win10_Enterprise_LTSC_2019.json' }))
Check 'edit to preferredIndex applied, and existing files are never rewritten' ($t['Windows 11 Enterprise 24H2'].PreferredIndex -eq 4)
Rename-Item (Join-Path $dir 'Win10_Enterprise_LTSC_2019.json') 'Win10_Enterprise_LTSC_2019.json.disabled'
$t = Import-OsProfiles -Directory $dir
Check 'renaming a file to .json.disabled switches that OS off (not written again)' (-not $t.Contains('Windows 10 Enterprise LTSC 2019 (IoT)') -and -not (Test-Path (Join-Path $dir 'Win10_Enterprise_LTSC_2019.json')) -and @($script:ProfileMessages | Where-Object { $_.Text -like 'Profile files created*' }).Count -eq 0)
Rename-Item (Join-Path $dir 'Win10_Enterprise_LTSC_2019.json.disabled') 'Win10_Enterprise_LTSC_2019.json'
Rename-Item (Join-Path $dir 'Win10_Enterprise_LTSC_2021_KMS.json') 'KMS - my copy.json'
$t = Import-OsProfiles -Directory $dir
Check 'an OS kept under another file name is not duplicated by a new built-in file' (-not (Test-Path (Join-Path $dir 'Win10_Enterprise_LTSC_2021_KMS.json')) -and $t['Windows 10 Enterprise LTSC 2021 (KMS)'].SourceFile -eq 'KMS - my copy.json' -and @($script:ProfileMessages | Where-Object { $_.Level -eq 'WARN' }).Count -eq 0)
Rename-Item (Join-Path $dir 'KMS - my copy.json') 'Win10_Enterprise_LTSC_2021_KMS.json'
Remove-Item (Join-Path $dir 'Win10_Enterprise_LTSC_2019.json'); Rename-Item (Join-Path $dir 'Windows_Server_2025.json') 'Windows_Server_2025.json.keep'
$t = Import-OsProfiles -Directory $dir; Rename-Item (Join-Path $dir 'Windows_Server_2025.json.keep') 'Windows_Server_2025.json'; Remove-Item (Join-Path $dir 'Win10_Enterprise_LTSC_2019.json')
$t = Import-OsProfiles -Directory $dir   # leave the folder as the later sections expect: 2019 written again, Server 2025 present
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
Check 'good profiles still load (the five built-ins and Server 2025)' ($t.Count -eq 6)
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
Check 'a folder holding only a broken file gets the built-in files written beside it; the broken one is reported' ($t3.Count -eq 5 -and @(Get-ChildItem $d3 -Filter *.json).Count -eq 6 -and @($script:ProfileMessages | Where-Object { $_.Text -like 'Profile file x.json skipped:*' }).Count -eq 1)
$d3b = Join-Path $tmp 'readonly_fallback'
function Save-BuiltInProfiles { param($Directory, $SkipNames) throw 'Access to the path is denied.' }   # a folder that cannot be written
$t3b = Import-OsProfiles -Directory $d3b
Check 'a Profiles folder that cannot be written falls back to the built-in profiles with a warning' ($t3b.Count -eq 5 -and @($script:ProfileMessages | Where-Object { $_.Text -like '*could not be used*' }).Count -eq 1 -and @($script:ProfileMessages | Where-Object { $_.Text -like '*using the built-in profiles*' }).Count -eq 1)
. ([scriptblock]::Create([regex]::Match((Get-Content -Raw $(if ($env:MR_SCRIPT) { $env:MR_SCRIPT } else { (Join-Path $PSScriptRoot '../MediaRefresh_v2.4.ps1') })), '(?s)function Save-BuiltInProfiles \{.*?\r?\n\}\r?\n').Value))   # the real one again
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
Check 'a missing Languages.json is created from the built-in list and loaded' ((Test-Path $langFile) -and $l1.Count -eq 21 -and [bool]($script:ProfileMessages | Where-Object { $_.Text -like 'Language list created*' }))
Check 'the created file has the same content as the repo Languages.json' ((((Get-Content $langFile -Raw) | ConvertFrom-Json) | ForEach-Object { "$($_.language)|$($_.code)" }) -join ';' -eq (($repoLangs | ForEach-Object { "$($_.language)|$($_.code)" }) -join ';'))
Check 'the created file has no BOM (same as the profile files)' ([System.IO.File]::ReadAllBytes($langFile)[0] -eq [byte][char]'[')
[System.IO.File]::WriteAllText($langFile, '[ { "language": "German (Germany)", "code": "de-de" }, { "language": "Welsh (United Kingdom)", "code": "CY-GB" } ]')
$l2 = @(Import-LanguageList -Directory $langDir)
Check 'an edited file wins over the built-in list (codes lower-cased)' ((($l2 | ForEach-Object { $_.Code }) -join ',') -eq 'de-de,cy-gb' -and $l2[1].Display -eq 'Welsh (United Kingdom) - cy-gb')
foreach ($bad in @('not json', '[]', '[ { "language": "German" } ]', '[ { "language": "German", "code": "german" } ]', '[ { "language": "A", "code": "de-de" }, { "language": "B", "code": "DE-DE" } ]')) {
    [System.IO.File]::WriteAllText($langFile, $bad); $script:ProfileMessages.Clear()
    $lb = @(Import-LanguageList -Directory $langDir)
    Check "a bad file falls back to the built-in list with a WARN: $bad" ($lb.Count -eq 21 -and [bool]($script:ProfileMessages | Where-Object { $_.Level -eq 'WARN' -and $_.Text -like 'Language list * could not be used*' }))
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

Write-Host "`n=== P12 colour schemes (General Settings tab, 2026-09-27) ==="
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
# Colours chosen for readability (not the log colours the operator specified) must reach 4.3:1 against what they sit on
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
$w11d14 = [pscustomobject]@{ Folder = 'Win11_Enterprise_24H2'; Name = 'Windows 11 Enterprise 24H2' }
$list14 = Get-AppListPath -ProfilesDir (Join-Path $tmp 'apps14\Profiles') -Definition $w11d14
Check 'the app list for an OS lives in Profiles\Apps\<profile folder>_Appx.json (11b)' ($list14 -eq (Join-Path $tmp 'apps14\Profiles\Apps\Win11_Enterprise_24H2_Appx.json'))
Check 'no app list yet reads as none' ($null -eq (Read-AppInventory -File $list14))
$apps14 = @([pscustomobject]@{ DisplayName = 'Microsoft.BingNews'; Version = '4.1.0.0'; PackageName = 'Microsoft.BingNews_4.1.0.0_neutral_~_8wekyb3d8bbwe' },
            [pscustomobject]@{ DisplayName = 'Microsoft.Copilot'; Version = '1.0.0.0'; PackageName = 'Microsoft.Copilot_1.0.0.0_neutral_~_8wekyb3d8bbwe' })
$iso14 = Join-Path $tmp 'apps14\os11.iso'; New-Item -ItemType Directory -Force (Split-Path $iso14) | Out-Null; Set-Content $iso14 'iso-v1'; (Get-Item $iso14).LastWriteTimeUtc = [datetime]'2026-09-10T08:00:00Z'
$id14 = Get-IsoIdentity $iso14
$f14 = Save-AppInventory -File $list14 -Apps $apps14 -Source 'os11.iso' -Index 3 -ImageName 'Windows 11 Enterprise' -Version '10.0.26100.1' -IsoSize ([string]$id14.Size) -IsoTime $id14.Time
$r14 = Read-AppInventory -File $list14
Check 'the app list is saved (creating Profiles\Apps) and read back with its ISO (name, size, date), index and apps' ($f14 -eq $list14 -and $r14.Source -eq 'os11.iso' -and $r14.IsoSize -eq [string]$id14.Size -and $r14.IsoTime -eq [string]([datetime]::SpecifyKind([datetime]'2026-09-10T08:00:00', 'Utc')).Ticks -and $r14.Index -eq 3 -and (@($r14.Apps).DisplayName -join ',') -eq 'Microsoft.BingNews,Microsoft.Copilot' -and $r14.Apps[1].PackageName -like 'Microsoft.Copilot_*')
Check 'the list is current for the same ISO and index' (Test-AppInventoryCurrent -Inventory $r14 -Iso (Get-IsoIdentity $iso14) -Index 3)
(Get-Item $iso14).LastWriteTimeUtc = [datetime]'2026-10-14T08:00:00Z'
$newDate14 = -not (Test-AppInventoryCurrent -Inventory $r14 -Iso (Get-IsoIdentity $iso14) -Index 3)
(Get-Item $iso14).LastWriteTimeUtc = [datetime]'2026-09-10T08:00:00Z'; Set-Content $iso14 'iso-v2-bigger'; (Get-Item $iso14).LastWriteTimeUtc = [datetime]'2026-09-10T08:00:00Z'
Check 'a new ISO under the same name (other date, or other size), or another index, makes the list out of date' ($newDate14 -and -not (Test-AppInventoryCurrent -Inventory $r14 -Iso (Get-IsoIdentity $iso14) -Index 3) -and -not (Test-AppInventoryCurrent -Inventory $r14 -Iso $id14 -Index 2) -and -not (Test-AppInventoryCurrent -Inventory $null -Iso $id14 -Index 3))
[System.IO.File]::WriteAllText($f14, '{ "apps": [ { "version": "1" } ] }'); $script:LogLines.Clear()
Check 'an unusable app list reads as none, with a WARN' ($null -eq (Read-AppInventory -File $list14) -and [bool]($script:LogLines -match 'WARN.*App list .* could not be used'))
Remove-Item $list14 -Force; New-Item -ItemType Directory -Force $os14 | Out-Null
[System.IO.File]::WriteAllText((Join-Path $os14 'ProvisionedApps.json'), '{ "source": "old.iso", "index": 3, "apps": [ { "displayName": "Microsoft.BingNews" } ] }')
Move-OldAppInventory -OsRoot $os14 -File $list14
Check 'a step-11 <OS folder>\ProvisionedApps.json is moved to Profiles\Apps once' (-not (Test-Path (Join-Path $os14 'ProvisionedApps.json')) -and (Read-AppInventory -File $list14).Source -eq 'old.iso')
[System.IO.File]::WriteAllText((Join-Path $os14 'ProvisionedApps.json'), '{ "source": "older.iso", "apps": [] }')
Move-OldAppInventory -OsRoot $os14 -File $list14
Check 'an old file never overwrites a list already in Profiles\Apps' ((Read-AppInventory -File $list14).Source -eq 'old.iso')
$pf14 = Join-Path $tmp 'apps14\Profiles'; $null = Import-OsProfiles -Directory $pf14
Check 'the app lists in Profiles\Apps are not read as OS profiles' (@($script:ProfileMessages | Where-Object { $_.Level -eq 'WARN' }).Count -eq 0 -and (Test-Path $list14))
$sf14 = Save-OsSettings -Directory (Join-Path $tmp 'apps14\Settings') -Definition $kms -Options @{ AppRemoval = $true } -Languages @() -RemoveApps @('Microsoft.BingNews', 'Microsoft.Copilot')
$rs14 = Read-OsSettings -Directory (Join-Path $tmp 'apps14\Settings') -Definition $kms -LanguageList $builtLangs
Check 'the ticked apps (by name) and the Remove the ticked apps option are saved per OS and read back' ((@($rs14.RemoveApps) -join ',') -eq 'Microsoft.BingNews,Microsoft.Copilot' -and $rs14.Options['AppRemoval'] -eq $true)
[System.IO.File]::WriteAllText($sf14, '{ "schemaVersion": 1, "options": { "LCU": true }, "languages": [ "de-de" ] }')
$old14 = Read-OsSettings -Directory (Join-Path $tmp 'apps14\Settings') -Definition $kms -LanguageList $builtLangs
Check 'a settings file saved before the Apps tab existed reads back with no ticked apps' ($null -ne $old14 -and @($old14.RemoveApps).Count -eq 0 -and (@($old14.Languages) -join ',') -eq 'de-de')
$w11def = [pscustomobject]@{ Folder = 'Win11_Enterprise_24H2'; AltFolders = @('Win11Enterprise_24H2') }
New-Item -ItemType Directory -Force (Join-Path $tmp 'apps14b\Win11Enterprise_24H2') | Out-Null
Check 'Get-OsRootPath uses an accepted alternative folder name that exists, and never throws for a missing drive' ((Get-OsRootPath -Root (Join-Path $tmp 'apps14b') -Definition $w11def) -like '*\Win11Enterprise_24H2' -and (Get-OsRootPath -Root 'Q:\nowhere' -Definition $w11def) -eq 'Q:\nowhere\Win11_Enterprise_24H2')

Write-Host "`n=== P15 SCCM import: names, UNC paths, the run record, saved values (TODO step 7) ==="
Check 'image name = OS name + yyyyMM' ((Get-SccmImageName -OsName 'Windows 10 Enterprise LTSC 2021 (KMS)' -Date ([datetime]'2026-09-27')) -eq 'Windows 10 Enterprise LTSC 2021 (KMS) 202609')
Check 'a free name is kept; a taken one (any case) gets (2), then (3)' ((Get-SccmUniqueName -Name 'Win 202609' -Existing @('Other')) -eq 'Win 202609' -and (Get-SccmUniqueName -Name 'Win 202609' -Existing @('WIN 202609')) -eq 'Win 202609 (2)' -and (Get-SccmUniqueName -Name 'Win 202609' -Existing @('Win 202609', 'Win 202609 (2)')) -eq 'Win 202609 (3)')
$threw = $false; try { Get-SccmUniqueName -Name ('x' * 49) -Existing @('x' * 49) } catch { $threw = $true; $m15 = $_.Exception.Message }
Check 'a name over 50 characters (after the suffix) is refused with the reason' ($threw -and $m15 -like '*Configuration Manager allows 50*')
$sh15 = @([pscustomobject]@{ Name = 'Sources'; Path = 'F:\Sources' }, [pscustomobject]@{ Name = 'OSD'; Path = 'F:\Sources\OSD\' }, [pscustomobject]@{ Name = 'FRoot'; Path = 'F:\' })
Check 'UNC path: the longest share that contains the folder wins' ((ConvertTo-SccmUncPath -LocalPath 'F:\Sources\OSD\Images\' -Server 'BUILD01' -Shares $sh15) -eq '\\BUILD01\OSD\Images' -and (ConvertTo-SccmUncPath -LocalPath 'F:\Sources\Drivers' -Server 'BUILD01' -Shares $sh15) -eq '\\BUILD01\Sources\Drivers' -and (ConvertTo-SccmUncPath -LocalPath 'F:\Other' -Server 'BUILD01' -Shares $sh15) -eq '\\BUILD01\FRoot\Other')
Check 'UNC path: the share folder itself, a folder name that only starts like a share, and a UNC typed in' ((ConvertTo-SccmUncPath -LocalPath 'F:\Sources' -Server 'B' -Shares $sh15[0..1]) -eq '\\B\Sources' -and (ConvertTo-SccmUncPath -LocalPath '\\B\OSD\X\' -Server 'B' -Shares @()) -eq '\\B\OSD\X')
$threw = $false; try { ConvertTo-SccmUncPath -LocalPath 'G:\SourcesX' -Server 'B' -Shares $sh15[0..1] } catch { $threw = $true; $m15 = $_.Exception.Message }
Check 'UNC path: a folder outside every share is refused with what to do' ($threw -and $m15 -like '*not inside a shared folder on this server*')
$threw = $false; try { ConvertTo-SccmUncPath -LocalPath 'F:\SourcesX\Y' -Server 'B' -Shares $sh15[0..1] } catch { $threw = $true }
Check 'UNC path: F:\SourcesX is not inside the F:\Sources share' $threw
$nw15 = Join-Path $tmp 'sccm15\NEWWIM'; New-Item -ItemType Directory -Force $nw15 | Out-Null
Check 'no run record reads as none' ($null -eq (Read-RunResult -NewWim $nw15))
[void](Save-RunResult -Paths @{ NewWim = $nw15 } -OsName 'KMS' -Build '10.0.19044.6456' -Gate 'PASSED' -Install "$nw15\install.wim" -Media "$nw15\Media" -ChangeLog "$tmp\LOGS\ChangeLog_x.html")
$rr15 = Read-RunResult -NewWim $nw15
Check 'the run record keeps build, gate, outputs and change log' ($rr15.Build -eq '10.0.19044.6456' -and $rr15.Gate -eq 'PASSED' -and $rr15.Install -like '*\install.wim' -and $rr15.Media -like '*\Media' -and $rr15.ChangeLog -like '*ChangeLog_x.html' -and $rr15.Finished)
$gs15 = Join-Path $tmp 'sccm15\Settings'
Save-GeneralSettings -Directory $gs15 -Root 'F:\mediaRefresh' -ColorScheme 'Modern Sysadmin'
Save-GeneralSettings -Directory $gs15 -SccmSiteServer 'cm01.contoso.com' -SccmTargetType 'DPGroup' -SccmTarget 'All DPs'
$sg15 = Read-SccmGeneralSettings -Directory $gs15
Check 'SCCM site server and target are saved in General.json without losing the root or the colour scheme' ($sg15.SiteServer -eq 'cm01.contoso.com' -and $sg15.TargetType -eq 'DPGroup' -and $sg15.Target -eq 'All DPs' -and (Read-GeneralSettings -Directory $gs15) -eq 'F:\mediaRefresh' -and (Read-ColorSchemeSetting -Directory $gs15) -eq 'Modern Sysadmin')
[void](Save-OsSettings -Directory $gs15 -Definition $kms -Options @{ SccmAutoImport = $true } -Sccm @{ ContentSource = 'F:\Sources\OSD'; PackageType = 'Upgrade'; ImageName = 'KMS custom' })
$os15 = Read-OsSettings -Directory $gs15 -Definition $kms -LanguageList $builtLangs
Check 'per OS: content source, package type, a hand-typed image name and Import after the run are saved' ($os15.Sccm.ContentSource -eq 'F:\Sources\OSD' -and $os15.Sccm.PackageType -eq 'Upgrade' -and $os15.Sccm.ImageName -eq 'KMS custom' -and $os15.Options['SccmAutoImport'] -eq $true)

Write-Host "`n=== P16 run config files for the command line (2026-09-28) ==="
$defs16 = Import-OsProfiles
$cf16 = Join-Path $tmp 'cfg16\Configs\kms_run.json'
[void](Save-RunConfig -File $cf16 -OsName 'Windows 10 Enterprise LTSC 2021 (KMS)' -Root 'F:\mediaRefresh' -Options @{ Verify = $true; BuildMedia = $true; BuildIso = $true; AutoDownload = $true; SccmAutoImport = $true } -Languages @('DE-DE', 'ja-jp') -RemoveApps @('Microsoft.BingNews') -Sccm @{ siteServer = 'cm01.contoso.com'; target = 'dp01.contoso.com'; contentSource = 'F:\Sources\OSD' })
$rc16 = Read-RunConfig -File $cf16 -Definitions $defs16 -LanguageList $builtLangs
Check 'a saved run config reads back: OS, root, every option, languages (lower case), apps, SCCM values' ($rc16.OsName -eq 'Windows 10 Enterprise LTSC 2021 (KMS)' -and $rc16.Root -eq 'F:\mediaRefresh' -and $rc16.Options['AutoDownload'] -and $rc16.Options['BuildIso'] -and -not $rc16.Options['NetFx3'] -and (@($rc16.Languages) -join ',') -eq 'de-de,ja-jp' -and (@($rc16.RemoveApps) -join ',') -eq 'Microsoft.BingNews' -and $rc16.Sccm['siteServer'] -eq 'cm01.contoso.com' -and @($script:SettingOptionNames | Where-Object { -not $rc16.Options.ContainsKey($_) }).Count -eq 0)
$min16 = Join-Path $tmp 'cfg16\min.json'; [System.IO.File]::WriteAllText($min16, '{ "os": "Windows 11 Enterprise 24H2", "root": "F:\\mediaRefresh" }')
$rm16 = Read-RunConfig -File $min16 -Definitions $defs16 -LanguageList $builtLangs
$ro16 = ConvertTo-RunOptions -Config $rm16 -Definition $defs16['Windows 11 Enterprise 24H2'] -ProfilesDir 'P'
Check 'a minimal config (OS and root only) takes the window defaults and the profile''s languages' ($ro16.Install -and $ro16.WinRE -and $ro16.Verify -and $ro16.LCU -and -not $ro16.BuildMedia -and -not $ro16.NetFx3 -and -not $ro16.AutoDownload -and -not $ro16.PreflightOnly -and @($ro16.Languages).Count -eq 0 -and $ro16.ProfilesDir -eq 'P' -and $ro16.SccmImageName -like 'Windows 11 Enterprise 24H2 ??????')
$kmsMin16 = Join-Path $tmp 'cfg16\kmsmin.json'; [System.IO.File]::WriteAllText($kmsMin16, '{ "os": "Windows 10 Enterprise LTSC 2021 (KMS)", "root": "F:\\m" }')
$kmsNone16 = Join-Path $tmp 'cfg16\kmsnone.json'; [System.IO.File]::WriteAllText($kmsNone16, '{ "os": "Windows 10 Enterprise LTSC 2021 (KMS)", "root": "F:\\m", "languages": [] }')
$l1 = @((ConvertTo-RunOptions -Config (Read-RunConfig -File $kmsMin16 -Definitions $defs16) -Definition $defs16['Windows 10 Enterprise LTSC 2021 (KMS)']).Languages).Count
$l2 = @((ConvertTo-RunOptions -Config (Read-RunConfig -File $kmsNone16 -Definitions $defs16) -Definition $defs16['Windows 10 Enterprise LTSC 2021 (KMS)']).Languages).Count
Check 'no "languages" key = the profile''s default languages; an empty list = English only' ($l1 -eq 10 -and $l2 -eq 0)
$ro16b = ConvertTo-RunOptions -Config $rc16 -Definition $defs16['Windows 10 Enterprise LTSC 2021 (KMS)'] -PreflightOnly
Check '-Preflight forces a check-only run; the ISO needs the media folder; ticked apps only with AppRemoval' ($ro16b.PreflightOnly -and $ro16b.BuildIso -and (@($ro16b.RemoveApps) -join ',') -eq 'Microsoft.BingNews')
$rc16.Options['BuildMedia'] = $false; $rc16.Options['AppRemoval'] = $false
$ro16c = ConvertTo-RunOptions -Config $rc16 -Definition $defs16['Windows 10 Enterprise LTSC 2021 (KMS)']
Check '... without the media folder there is no ISO; with AppRemoval off no app is removed' (-not $ro16c.BuildIso -and @($ro16c.RemoveApps).Count -eq 0 -and $ro16c.SccmTargetType -eq 'DP' -and $ro16c.SccmPackageType -eq 'Image')
$bad16 = Join-Path $tmp 'cfg16\bad.json'
[System.IO.File]::WriteAllText($bad16, '{ "os": "Windows 12", "options": { "Verfy": true, "LCU": "yes" }, "languages": ["xx-yy"], "sccm": { "site": "x" }, "extra": 1 }')
$threw = $false; try { Read-RunConfig -File $bad16 -Definitions $defs16 -LanguageList $builtLangs } catch { $threw = $true; $m16 = $_.Exception.Message }
Check 'a bad config lists every problem: unknown OS, missing root, misspelled option, non-true/false, unknown language, unknown keys' ($threw -and $m16 -like "*'os' is 'Windows 12', which is not one of the profiles*" -and $m16 -like "*'root'*missing*" -and $m16 -like "*unknown option 'Verfy'*" -and $m16 -like "*option 'LCU' must be true or false*" -and $m16 -like "*language 'xx-yy'*" -and $m16 -like "*unknown sccm setting 'site'*" -and $m16 -like "*unknown setting 'extra'*") $m16
$threw = $false; try { Read-RunConfig -File (Join-Path $tmp 'cfg16\nope.json') -Definitions $defs16 } catch { $threw = $true; $m16b = $_.Exception.Message }
[System.IO.File]::WriteAllText($bad16, '{ nope'); $threw2 = $false; try { Read-RunConfig -File $bad16 -Definitions $defs16 } catch { $threw2 = $true; $m16c = $_.Exception.Message }
Check 'a missing file or broken JSON is a clear error' ($threw -and $m16b -like '*does not exist*' -and $threw2 -and $m16c -like '*not valid JSON*')

$guide13 = Join-Path (Split-Path $PSScriptRoot -Parent) 'INSTRUCTIONS.md'
if (Test-Path $guide13) {
    $gb13 = @(ConvertFrom-MarkdownBlocks ([System.IO.File]::ReadAllText($guide13)))
    $left13 = @($gb13 | Where-Object { $_.Type -ne 'Code' } | ForEach-Object { Split-MarkdownInline $_.Text } | Where-Object { $_.Kind -eq 'Text' -and ($_.Text -match '\*\*|`') } | ForEach-Object { $_.Text })
    Check 'the real INSTRUCTIONS.md parses with no stray ** or ` left in the text' ($gb13.Count -gt 50 -and @($gb13 | Where-Object { $_.Type -eq 'Heading' -and $_.Text -eq 'Where the logs are' }).Count -eq 1 -and $left13.Count -eq 0) ($left13 -join ' || ')
} else { Write-Host 'SKIP  INSTRUCTIONS.md not found next to the script' }

Write-Host "`n=== P17 portable: no fixed drive or folder, no personal or site names in the shipped files (2026-09-28) ==="
$rootDir17 = Split-Path $PSScriptRoot -Parent
Check 'the default repository root is the script''s own folder (a drive root keeps its backslash)' ((Get-DefaultRoot -ScriptDir 'E:\Tools\WimForge\') -eq 'E:\Tools\WimForge' -and (Get-DefaultRoot -ScriptDir 'E:\') -eq 'E:\' -and (Get-DefaultRoot -ScriptDir '') -eq (Get-Location -PSProvider FileSystem).Path)
$main17 = [System.IO.File]::ReadAllText((Join-Path $rootDir17 'MediaRefresh_v2.4.ps1'))
Check 'the window has no hard-coded repository root; it is filled from the saved settings or the script folder' ($main17 -match 'x:Name="RootText" Grid\.Row="0" Grid\.Column="1" Text=""' -and $main17 -match 'Resolve-SavedRoot -Directory \$script:SettingsDir -ScriptDir \$PSScriptRoot')
$shipped17 = @('MediaRefresh_v2.4.ps1', 'INSTRUCTIONS.md', 'README.md', 'TODO.md', 'Languages.json') | ForEach-Object { Join-Path $rootDir17 $_ } | Where-Object { Test-Path $_ }
$drive17 = @($shipped17 | ForEach-Object { Select-String -LiteralPath $_ -Pattern '(?i)\b[a-z]:\\mediarefresh' } | ForEach-Object { "$($_.Filename):$($_.LineNumber)" })
Check 'no file names a fixed X:\mediaRefresh folder' ($drive17.Count -eq 0) ($drive17 -join ', ')
$d17 = Join-Path $PWD 'tst_root'; if (Test-Path $d17) { Remove-Item $d17 -Recurse -Force }
New-Item -ItemType Directory -Force (Join-Path $d17 'a'), (Join-Path $d17 'b') | Out-Null
[System.IO.File]::WriteAllText((Join-Path $d17 'b\Instructions.MD'), '# b')
Check 'Find-InstructionsFile: first folder that has it, any letter case; $null when none has it' ((Find-InstructionsFile -Folders @((Join-Path $d17 'a'), '', (Join-Path $d17 'b'))) -eq (Join-Path $d17 'b\Instructions.MD') -and $null -eq (Find-InstructionsFile -Folders @((Join-Path $d17 'a'), (Join-Path $d17 'nope'))))
$st17a = Get-FileStamp (Join-Path $d17 'b\Instructions.MD'); [System.IO.File]::WriteAllText((Join-Path $d17 'b\Instructions.MD'), '# b changed')
Check 'Get-FileStamp changes when the file changes, and is "missing" for no file' ($st17a -ne (Get-FileStamp (Join-Path $d17 'b\Instructions.MD')) -and (Get-FileStamp '') -eq 'missing' -and (Get-FileStamp (Join-Path $d17 'nope.md')) -eq 'missing')

Write-Host "`n=== P18 Build an ISO needs the local ADK's Oscdimg (2026-09-29) ==="
$k18 = Join-Path $PWD 'tst_root\kits'; $t18 = Join-Path $k18 'Assessment and Deployment Kit\Deployment Tools'
New-Item -ItemType Directory -Force (Join-Path $t18 'amd64\Oscdimg'), (Join-Path $t18 'x86\Oscdimg') | Out-Null
Set-Content (Join-Path $t18 'x86\Oscdimg\oscdimg.exe') 'x'
Check 'Find-Oscdimg: an ADK with Oscdimg for another architecture only is still found' ((& $script:RealFindOscdimg -KitsRoots @($k18)) -eq (Join-Path $t18 'x86\Oscdimg\oscdimg.exe'))
Set-Content (Join-Path $t18 'amd64\Oscdimg\oscdimg.exe') 'x'
$arch18 = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
if ($arch18 -eq 'amd64') { Check 'Find-Oscdimg: the host architecture''s Oscdimg is preferred, under the ADK root the registry names (any drive)' ((& $script:RealFindOscdimg -KitsRoots @((Join-Path $k18 'nope'), $k18)) -eq (Join-Path $t18 'amd64\Oscdimg\oscdimg.exe')) }
if (-not (Get-Command oscdimg.exe -ErrorAction SilentlyContinue)) {
    Check 'Find-Oscdimg: no ADK under any root and none on the PATH -> $null' ($null -eq (& $script:RealFindOscdimg -KitsRoots @((Join-Path $k18 'nope'))))
} else { Write-Host 'SKIP  Find-Oscdimg not-found case (oscdimg.exe is on the PATH here)' }
Check 'the message is the one asked for' ($script:NoAdkMessage -eq 'No local ADK installation found. This option is not available.')

Write-Host "`n=== P19 adding and renaming an OS: release placeholder, stable folder key, New OS / Rename OS (2026-09-30) ==="
$bi19 = Import-OsProfiles
$w11 = $bi19['Windows 11 Enterprise 24H2']; $w19 = $bi19['Windows 10 Enterprise LTSC 2019 (IoT)']
Check 'built-in profiles carry their release, and {version} gives the same catalog searches as before' ($w11.Version -eq '24H2' -and $w19.Version -eq '1809' -and $w11.CatalogSearch.LCU.search -eq 'Windows 11, version 24H2' -and $w11.CatalogSearch.LCU.buildFilter -eq '^\d{4}-\d{2} Cumulative Update for Windows 11,? version 24H2' -and $w19.CatalogSearch.NetCU.search -eq 'Cumulative Update for .NET Framework 3.5, 4.7.2 and 4.8 for Windows 10 Version 1809 for x64' -and $bi19['Windows Server 2022'].CatalogSearch.SafeOS.productFilter -eq 'Safe OS')
Check 'the built-in data itself uses {version} (a new release is a one-field change)' (@(Get-BuiltInProfileData | Where-Object { ($_.catalogSearch | ConvertTo-Json -Depth 5) -match '\{version\}' }).Count -eq 5)
$d19 = (@(Get-BuiltInProfileData)[3] | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
$d19.version = ''; $err19 = ''; try { [void](ConvertTo-OsProfile -Data $d19) } catch { $err19 = $_.Exception.Message }
Check '{version} with an empty version: a plain message naming the field' ($err19 -like "'catalogSearch.*' uses {version}, but the profile's 'version' is empty.*") $err19
$d19.version = '24.2'; $v19 = ConvertTo-OsProfile -Data $d19
Check 'the release is escaped in the regular-expression fields, literal in the search' ($v19.CatalogSearch.LCU.search -eq 'Windows 11, version 24.2' -and $v19.CatalogSearch.LCU.buildFilter -like '*version 24\.2')
$d19.version = 'bad/name'; $err19 = ''; try { [void](ConvertTo-OsProfile -Data $d19) } catch { $err19 = $_.Exception.Message }
Check 'a release with odd characters is refused' ($err19 -like "'version' must be a short release name*")
Check 'ConvertTo-OsFolderName follows the built-in style' ((ConvertTo-OsFolderName 'Windows 11 Enterprise 26H2') -eq 'Win11_Enterprise_26H2' -and (ConvertTo-OsFolderName 'Windows Server 2025') -eq 'Windows_Server_2025' -and (ConvertTo-OsFolderName 'Windows 10 Enterprise LTSC 2019 (IoT)') -eq 'Win10_Enterprise_LTSC_2019_IoT')
Check 'Test-OsFolderName refuses bad folder names' ((Test-OsFolderName 'Win11_26H2') -eq '' -and (Test-OsFolderName '') -ne '' -and (Test-OsFolderName 'a\b') -ne '' -and (Test-OsFolderName 'CON') -ne '' -and (Test-OsFolderName '_x') -ne '')
# New OS from existing: 26H2 from the 24H2 profile, on disk
$pd19 = Join-Path $PWD 'tst_root\p19profiles'; $root19 = Join-Path $PWD 'tst_root\p19repo'; $set19 = Join-Path $PWD 'tst_root\p19settings'
foreach ($d in $pd19, $root19, $set19) { if (Test-Path $d) { Remove-Item $d -Recurse -Force } }
$defs19 = Import-OsProfiles -Directory $pd19
$n19 = New-OsProfileFromBase -ProfilesDir $pd19 -Base $defs19['Windows 11 Enterprise 24H2'] -Definitions $defs19 -Name 'Windows 11 Enterprise 26H2' -Version '26H2' -Root $root19
$defs19 = Import-OsProfiles -Directory $pd19; $new19 = $defs19['Windows 11 Enterprise 26H2']
Check 'New OS: the profile file, the list entry, and the catalog searches for the new release' ((Split-Path $n19.File -Leaf) -eq 'Win11_Enterprise_26H2.json' -and $null -ne $new19 -and $new19.Version -eq '26H2' -and $new19.CatalogSearch.LCU.search -eq 'Windows 11, version 26H2' -and $new19.CatalogSearch.SetupDU.buildFilter -like '*version 26H2' -and $new19.EditionRegex -eq $defs19['Windows 11 Enterprise 24H2'].EditionRegex -and $new19.SortOrder -eq 41)
Check 'New OS: support date cleared, a note on what to check, and the 24H2 profile unchanged' ($new19.EndOfSupport -eq '' -and $new19.Notes -like "Created from 'Windows 11 Enterprise 24H2'*Check OS profile*" -and $defs19['Windows 11 Enterprise 24H2'].CatalogSearch.LCU.search -eq 'Windows 11, version 24H2')
Check 'New OS: the repository folders are created (ISO, PATCHES\LCU, ...)' ($n19.Repository -eq (Join-Path $root19 'Win11_Enterprise_26H2') -and (Test-Path (Join-Path $root19 'Win11_Enterprise_26H2\ISO')) -and (Test-Path (Join-Path $root19 'Win11_Enterprise_26H2\PATCHES\SETUPDU')))
$e1 = ''; try { [void](New-OsProfileFromBase -ProfilesDir $pd19 -Base $new19 -Definitions $defs19 -Name 'Windows 11 Enterprise 26H2' -Version '27H2') } catch { $e1 = $_.Exception.Message }
$e2 = ''; try { [void](New-OsProfileFromBase -ProfilesDir $pd19 -Base $new19 -Definitions $defs19 -Name 'Another' -Folder 'Win11_Enterprise_24H2' -Version '27H2') } catch { $e2 = $_.Exception.Message }
$e3 = ''; try { [void](New-OsProfileFromBase -ProfilesDir $pd19 -Base $new19 -Definitions $defs19 -Name 'Another' -Folder 'Win11Enterprise_24H2' -Version '27H2') } catch { $e3 = $_.Exception.Message }
Check 'New OS refuses a name or folder already in use (also an accepted old folder name)' ($e1 -eq "An OS named 'Windows 11 Enterprise 26H2' already exists." -and $e2 -like "The folder name 'Win11_Enterprise_24H2' is already used*" -and $e3 -like "The folder name 'Win11Enterprise_24H2' is already used*") "$e1 | $e2 | $e3"
# an older profile file with the release written out (no 'version', no {version}): the text is replaced
$old19 = (@(Get-BuiltInProfileData)[4] | ConvertTo-Json -Depth 8) -replace '\{version\}', '21H2' | ConvertFrom-Json
$old19.PSObject.Properties.Remove('version'); $old19.name = 'Server Old Style'; $old19.folder = 'Server_Old'
[System.IO.File]::WriteAllText((Join-Path $pd19 'Server_Old.json'), ($old19 | ConvertTo-Json -Depth 8))
$defs19 = Import-OsProfiles -Directory $pd19
$n19b = New-OsProfileFromBase -ProfilesDir $pd19 -Base $defs19['Server Old Style'] -Definitions $defs19 -Name 'Server New Style' -Version '24H2' -ReplaceText '21H2'
$defs19 = Import-OsProfiles -Directory $pd19
Check 'New OS from an older profile file: the written-out release is replaced in every catalog search' ($n19b.Replaced -eq 8 -and -not $n19b.UsesPlaceholder -and $defs19['Server New Style'].CatalogSearch.LCU.search -eq 'Cumulative Update for Microsoft server operating system version 24H2' -and $defs19['Server New Style'].CatalogSearch.LCU.buildFilter -like '*version 24H2')
# Rename OS: display name only, then the folder as well
New-Item -ItemType Directory -Force $set19, (Join-Path $pd19 'Apps') | Out-Null
[void](Save-OsSettings -Directory $set19 -Definition $new19 -Options @{ NetFx3 = $true })
[System.IO.File]::WriteAllText((Join-Path $pd19 'Apps\Win11_Enterprise_26H2_Appx.json'), '{ "apps": [] }')
$r1 = Rename-OsProfile -ProfilesDir $pd19 -Definition $new19 -Definitions $defs19 -NewName 'Win 11 26H2 Enterprise' -SettingsDir $set19 -Root $root19
$defs19 = Import-OsProfiles -Directory $pd19
Check 'Rename OS, name only: same file and folder, settings still found (they are keyed by folder)' ($defs19.Contains('Win 11 26H2 Enterprise') -and -not $defs19.Contains('Windows 11 Enterprise 26H2') -and $r1.File -eq $n19.File -and @($r1.Moves).Count -eq 0 -and $null -ne (Read-OsSettings -Directory $set19 -Definition $defs19['Win 11 26H2 Enterprise']))
$r2 = Rename-OsProfile -ProfilesDir $pd19 -Definition $defs19['Win 11 26H2 Enterprise'] -Definitions $defs19 -NewName 'Windows 11 Enterprise 26H2' -NewFolder 'W11_26H2' -SettingsDir $set19 -Root $root19
$defs19 = Import-OsProfiles -Directory $pd19; $ren19 = $defs19['Windows 11 Enterprise 26H2']
Check 'Rename OS, folder too: profile file, saved settings, app list and repository folder move; the old folder stays accepted' ($ren19.Folder -eq 'W11_26H2' -and $ren19.AltFolders -contains 'Win11_Enterprise_26H2' -and (Test-Path (Join-Path $pd19 'W11_26H2.json')) -and -not (Test-Path (Join-Path $pd19 'Win11_Enterprise_26H2.json')) -and (Test-Path (Join-Path $set19 'W11_26H2.json')) -and (Test-Path (Join-Path $pd19 'Apps\W11_26H2_Appx.json')) -and (Test-Path (Join-Path $root19 'W11_26H2\ISO')) -and -not (Test-Path (Join-Path $root19 'Win11_Enterprise_26H2')) -and @($r2.Moves).Count -eq 4) (@($r2.Moves) -join ' | ')
# renaming a built-in's folder leaves <old>.json.disabled, so Reload does not bring the old built-in back
$cnt19 = $defs19.Count
$r3 = Rename-OsProfile -ProfilesDir $pd19 -Definition $defs19['Windows Server 2022'] -Definitions $defs19 -NewName 'Windows Server 2022 Datacenter' -NewFolder 'Server2022' -SettingsDir $set19 -Root $root19
$defs19 = Import-OsProfiles -Directory $pd19
Check 'Rename OS of a built-in: the old built-in is not recreated on Reload' ($defs19.Count -eq $cnt19 -and $defs19.Contains('Windows Server 2022 Datacenter') -and -not $defs19.Contains('Windows Server 2022') -and (Test-Path (Join-Path $pd19 'Windows_Server_2022.json.disabled'))) (@($defs19.Keys) -join ', ')
$e4 = ''; try { [void](Rename-OsProfile -ProfilesDir $pd19 -Definition $ren19 -Definitions $defs19 -NewName 'Windows 11 Enterprise 24H2' -SettingsDir $set19) } catch { $e4 = $_.Exception.Message }
$script:MountedList = @([pscustomobject]@{ Path = (Join-Path $root19 'W11_26H2\MOUNT\MainOS'); MountStatus = 'Ok' })
$e5 = ''; try { [void](Rename-OsProfile -ProfilesDir $pd19 -Definition $ren19 -Definitions $defs19 -NewName 'X' -NewFolder 'X_26H2' -SettingsDir $set19 -Root $root19) } catch { $e5 = $_.Exception.Message }
$script:MountedList = @()
Check 'Rename OS refuses a name in use, and a folder move while an image is mounted in it (nothing changed)' ($e4 -eq "An OS named 'Windows 11 Enterprise 24H2' already exists." -and $e5 -like 'An image is still mounted under *Cleanup Mountpoints*' -and (Test-Path (Join-Path $pd19 'W11_26H2.json'))) "$e4 | $e5"
# run configs: the folder is the stable key
$rc19 = Join-Path $PWD 'tst_root\p19run.json'
[void](Save-RunConfig -File $rc19 -OsName 'Windows 11 Enterprise 26H2' -Folder 'W11_26H2' -Root $root19)
$j19 = Get-Content -Raw $rc19 | ConvertFrom-Json; $j19.os = 'An Old Display Name'; [System.IO.File]::WriteAllText($rc19, ($j19 | ConvertTo-Json -Depth 5))
$c19 = Read-RunConfig -File $rc19 -Definitions $defs19
Check 'a run config whose OS was renamed is found by its folder, and says so' ($c19.OsName -eq 'Windows 11 Enterprise 26H2' -and $c19.ResolvedFrom -eq "'An Old Display Name'" -and $j19.folder -eq 'W11_26H2')
$j19.folder = ''; $j19.os = 'Win11_Enterprise_26H2'; [System.IO.File]::WriteAllText($rc19, ($j19 | ConvertTo-Json -Depth 5))
Check 'a run config may name the OS by a folder name (current or old)' ((Read-RunConfig -File $rc19 -Definitions $defs19).OsName -eq 'Windows 11 Enterprise 26H2')
$j19.os = 'Windows 12'; [System.IO.File]::WriteAllText($rc19, ($j19 | ConvertTo-Json -Depth 5)); $e6 = ''; try { [void](Read-RunConfig -File $rc19 -Definitions $defs19) } catch { $e6 = $_.Exception.Message }
Check 'an unknown OS is still refused with the list of profiles' ($e6 -like "*'os' is 'Windows 12', which is not one of the profiles:*") $e6

Write-Host "`n=== P20 WimForge moved to another server / drive: the saved repository root follows it (2026-10-01) ==="
$b20 = Join-Path $PWD 'tst_root\p20'; if (Test-Path $b20) { Remove-Item $b20 -Recurse -Force }
$old20 = Join-Path $b20 'oldsrv\mediaRefresh'; $here20 = Join-Path $b20 'J\WimForge'; $set20 = Join-Path $here20 'Settings'; $else20 = Join-Path $b20 'elsewhere'
New-Item -ItemType Directory -Force $old20, $set20, $else20 | Out-Null
$f20 = @('Win11_Enterprise_24H2', 'Win10_Enterprise_LTSC_2019')
function Set-General20($o) { [System.IO.File]::WriteAllText((Join-Path $set20 'General.json'), ($o | ConvertTo-Json)) }
$r = Resolve-SavedRoot -Directory $set20 -ScriptDir $here20 -Folders $f20
Check 'nothing saved: the script''s folder' ($r.Root -eq $here20 -and $r.Level -eq 'INFO' -and $r.Note -like '*no root saved yet*')
Set-General20 @{ root = $old20; scriptDir = $old20 }
$r = Resolve-SavedRoot -Directory $set20 -ScriptDir $here20 -Folders $f20
Check 'moved, and the root was WimForge''s own folder: the root moves with it (WARN, says how to keep it)' ($r.Root -eq $here20 -and $r.Level -eq 'WARN' -and $r.Note -like "WimForge was moved from $old20 to $here20*Press Save settings*") $r.Note
Set-General20 @{ root = (Join-Path $old20 'repo'); scriptDir = $old20 }
Check 'moved, root inside WimForge''s folder: the same sub-folder under the new place' ((Resolve-SavedRoot -Directory $set20 -ScriptDir $here20 -Folders $f20).Root -eq (Join-Path $here20 'repo'))
Set-General20 @{ root = $else20; scriptDir = $old20 }
Check 'moved, but the root was somewhere else that still exists: kept' ((Resolve-SavedRoot -Directory $set20 -ScriptDir $here20 -Folders $f20).Root -eq $else20)
Set-General20 @{ root = 'Q:\no\such\drive' }
$r = Resolve-SavedRoot -Directory $set20 -ScriptDir $here20 -Folders $f20
Check 'older settings, saved root missing on this machine: the script''s folder, with a WARN' ($r.Root -eq $here20 -and $r.Level -eq 'WARN' -and $r.Note -like '*does not exist on this machine*')
# the reported case: old General.json says F:\mediaRefresh, F: exists on the new server (Download patches even created folders
# there) but holds no ISO, while the ISOs are beside the script on J:
New-Item -ItemType Directory -Force (Join-Path $old20 'Win10_Enterprise_LTSC_2019\PATCHES\LCU'), (Join-Path $here20 'Win11_Enterprise_24H2\ISO') | Out-Null
Set-Content (Join-Path $here20 'Win11_Enterprise_24H2\ISO\os.iso') 'x'
Set-General20 @{ root = $old20 }
$r = Resolve-SavedRoot -Directory $set20 -ScriptDir $here20 -Folders $f20
Check 'older settings, saved root holds no ISO but the script''s folder does: the script''s folder (the reported case)' ($r.Root -eq $here20 -and $r.Level -eq 'WARN' -and $r.Note -like "*$old20 holds no ISO, but the script's folder $here20 does*") $r.Note
New-Item -ItemType Directory -Force (Join-Path $old20 'Win10_Enterprise_LTSC_2019\ISO') | Out-Null; Set-Content (Join-Path $old20 'Win10_Enterprise_LTSC_2019\ISO\a.iso') 'x'
Check 'older settings, saved root with ISOs: kept' ((Resolve-SavedRoot -Directory $set20 -ScriptDir $here20 -Folders $f20).Root -eq $old20)
Set-General20 @{ root = $here20 }
$r = Resolve-SavedRoot -Directory $set20 -ScriptDir $here20 -Folders $f20
Check 'saved root is the script''s folder: loaded as saved' ($r.Root -eq $here20 -and $r.Level -eq 'INFO' -and $r.Note -like 'Repository root loaded from saved settings*')
Save-GeneralSettings -Directory $set20 -Root $else20; $g20 = Get-Content -Raw (Join-Path $set20 'General.json') | ConvertFrom-Json
Save-GeneralSettings -Directory $set20 -ColorScheme 'Default'; $g20b = Get-Content -Raw (Join-Path $set20 'General.json') | ConvertFrom-Json
Check 'Save settings records where WimForge is (scriptDir), and other saves keep it' ($g20.scriptDir -eq $here20 -and $g20.root -eq $else20 -and $g20b.scriptDir -eq $here20)
Write-Host "`n=== P21 after a move: the run record finds its files here; a run config with the old root stops (2026-10-01) ==="
$os21 = Join-Path $here20 'Win11_Enterprise_24H2'; $nw21 = Join-Path $os21 'NEWWIM'
New-Item -ItemType Directory -Force (Join-Path $nw21 'Media'), (Join-Path $os21 'LOGS') | Out-Null
Set-Content (Join-Path $nw21 'install.wim') 'x'; Set-Content (Join-Path $os21 'LOGS\ChangeLog_x.html') 'x'
$gone21 = 'Q:\mediaRefresh\Win11_Enterprise_24H2'
[void](Save-RunResult -Paths @{ NewWim = $nw21 } -OsName 'Windows 11 Enterprise 24H2' -Build '10.0.26100.9457' -Gate 'PASSED' -Install "$gone21\NEWWIM\install.wim" -Media "$gone21\NEWWIM\Media" -ChangeLog "$gone21\LOGS\ChangeLog_x.html")
$rr21 = Read-RunResult -NewWim $nw21
Check 'a run record from before the move: install.wim, media and change log are found under this OS folder' ($rr21.Install -eq (Join-Path $nw21 'install.wim') -and $rr21.Media -eq (Join-Path $nw21 'Media') -and $rr21.ChangeLog -eq (Join-Path $os21 'LOGS\ChangeLog_x.html') -and @($rr21.Moved).Count -eq 3) (@($rr21.Moved) -join ' | ')
[void](Save-RunResult -Paths @{ NewWim = $nw21 } -OsName 'W' -Build 'b' -Gate 'PASSED' -Install (Join-Path $nw21 'install.wim') -Media '' -ChangeLog "$gone21\LOGS\gone.html")
$rr21b = Read-RunResult -NewWim $nw21
Check 'paths that exist are kept as recorded; a file gone everywhere stays as recorded (reported missing later)' ($rr21b.Install -eq (Join-Path $nw21 'install.wim') -and $rr21b.Media -eq '' -and $rr21b.ChangeLog -eq "$gone21\LOGS\gone.html" -and @($rr21b.Moved).Count -eq 0)
$d21 = $bi19['Windows 11 Enterprise 24H2']
$p1 = Test-RunConfigRoot -Root 'Q:\mediaRefresh' -Definition $d21 -ScriptDir $here20
Check 'run config root gone: stops, names it, and points at WimForge''s folder that holds the ISO' ($p1 -like 'its repository root Q:\mediaRefresh does not exist on this machine. WimForge''s own folder * holds this OS''s ISO - was WimForge moved?*Save the run config again*') $p1
$p2 = Test-RunConfigRoot -Root $old20 -Definition $d21 -ScriptDir $here20
Check 'run config root exists but holds no ISO for this OS while WimForge''s folder does: stops (never switches by itself)' ($p2 -like "its repository root $old20 holds no ISO for Windows 11 Enterprise 24H2, but WimForge's own folder $here20 does*") $p2
Check 'run config root that is fine (or WimForge''s own folder, or no ISO anywhere yet): no problem' ((Test-RunConfigRoot -Root $here20 -Definition $d21 -ScriptDir $here20) -eq '' -and (Test-RunConfigRoot -Root $else20 -Definition $d21 -ScriptDir $else20) -eq '' -and (Test-RunConfigRoot -Root $old20 -Definition $bi19['Windows 10 Enterprise LTSC 2019 (IoT)'] -ScriptDir $here20) -eq '')
$cl21 = [regex]::Match($src, '(?s)function Invoke-CommandLineRun \{.*?\r?\n\}\r?\n').Value
Check 'the command line run checks the config''s root before running (exit code 1 via the error)' ($cl21 -match 'Test-RunConfigRoot -Root \$cfg\.Root' -and $cl21 -match 'throw "The run config \$ConfigFile cannot be used here: \$rootProblem"')
Write-Host "`n=== P22 step 18: the SCCM content source on another server - path rules, share list, write test, robocopy ==="
$rs = Resolve-SccmContentSource -Path '\\cm01.contoso.com\Sources\OSD\Images\' -ThisServer 'WIMFORGE01'
Check 'a UNC path on another server: written and imported there, marked remote' ($rs.Work -eq '\\cm01.contoso.com\Sources\OSD\Images' -and $rs.Unc -eq $rs.Work -and $rs.Remote -and $rs.Server -eq 'cm01.contoso.com')
Check 'a UNC path on this server (short or full name) is not remote' (-not (Resolve-SccmContentSource -Path '\\WIMFORGE01\Sources' -ThisServer 'WIMFORGE01').Remote -and -not (Resolve-SccmContentSource -Path '\\wimforge01.contoso.com\Sources' -ThisServer 'WIMFORGE01').Remote)
$e = ''; try { [void](Resolve-SccmContentSource -Path '\\cm01' -ThisServer 'X') } catch { $e = $_.Exception.Message }
Check 'a UNC path without a share is refused with the expected form' ($e -like '*is not a complete network path. Use \\server\share*') $e
$gmd = ${function:Get-MappedDriveUnc}
function Get-MappedDriveUnc { param($Letter) if ($Letter -eq 'Z') { '\\fs01\deploy' } else { $null } }
$rz = Resolve-SccmContentSource -Path 'Z:\OSD\Images' -ThisServer 'X'
Check 'a mapped drive letter is replaced by its network path (the site server cannot use drive letters), with a note' ($rz.Unc -eq '\\fs01\deploy\OSD\Images' -and $rz.Work -eq $rz.Unc -and $rz.Remote -and $rz.Note -like 'Z: is a mapped network drive*')
$free22 = @([char[]](68..89) | Where-Object { -not (Test-Path "$($_):\") })[0]
$e = ''; try { [void](Resolve-SccmContentSource -Path "$($free22):\OSD" -ThisServer 'X') } catch { $e = $_.Exception.Message }
Check 'a drive letter WimForge cannot see is refused, saying why (Explorer mappings are not visible elevated)' ($e -like "Drive $($free22): is not available to WimForge*running as administrator*") $e
$rl = Resolve-SccmContentSource -Path "$env:SystemDrive\Shares\OSD" -ThisServer 'CMSRV' -Shares @([pscustomobject]@{ Name = 'OSD$'; Path = "$env:SystemDrive\Shares" }, [pscustomobject]@{ Name = 'Sources'; Path = "$env:SystemDrive\Shares\OSD" })
Check 'a local folder on this server still works: the most specific share gives the UNC path' ($rl.Work -eq "$env:SystemDrive\Shares\OSD" -and $rl.Unc -eq '\\CMSRV\Sources' -and -not $rl.Remote)
Set-Item function:Get-MappedDriveUnc $gmd
$nv = @('Shared resources at \\cm01', '', 'Share name  Type  Used as  Comment', '', '-------------------------------------------------------------------------------', 'Sources     Disk           CM content', 'SMS_PS1     Disk', 'Print$      Disk', 'HPLaser     Print          Office', 'The command completed successfully.')
Check 'net view output: the disk shares, without admin shares or printers' ((@(ConvertFrom-NetViewOutput -Lines $nv) -join ',') -eq 'SMS_PS1,Sources')
$w22 = Join-Path $PWD 'tst_root\p22'; if (Test-Path $w22) { Remove-Item $w22 -Recurse -Force }; New-Item -ItemType Directory -Force $w22 | Out-Null
Check 'the write test passes on a writable folder and leaves nothing behind' ((Test-SccmShareWritable -Path $w22) -eq '' -and @(Get-ChildItem $w22 -Force).Count -eq 0)
Check 'the write test never creates a missing folder: it says the folder does not exist' ((Test-SccmShareWritable -Path (Join-Path $w22 'missing\deeper')) -like 'The folder * does not exist or cannot be reached.' -and -not (Test-Path (Join-Path $w22 'missing')))
New-Item -ItemType Directory -Force (Join-Path $w22 'src\media\sources') | Out-Null
Set-Content (Join-Path $w22 'src\install.wim') 'wim'; Set-Content (Join-Path $w22 'src\custom.wim') 'wim2'; Set-Content (Join-Path $w22 'src\media\setup.exe') 'setup'; Set-Content (Join-Path $w22 'src\media\sources\boot.wim') 'boot'
New-Item -ItemType Directory -Force (Join-Path $w22 'd1'), (Join-Path $w22 'd2'), (Join-Path $w22 'd3') | Out-Null
Copy-SccmContent -Source (Join-Path $w22 'src\install.wim') -Destination (Join-Path $w22 'd1')
Copy-SccmContent -Source (Join-Path $w22 'src\custom.wim') -Destination (Join-Path $w22 'd2')
Copy-SccmContent -Source (Join-Path $w22 'src\media') -Destination (Join-Path $w22 'd3') -Folder
Check 'robocopy copies install.wim, renames another file name to install.wim, and copies a media folder with its sub-folders' ((Get-Content -Raw (Join-Path $w22 'd1\install.wim')).Trim() -eq 'wim' -and (Get-Content -Raw (Join-Path $w22 'd2\install.wim')).Trim() -eq 'wim2' -and (Test-Path (Join-Path $w22 'd3\setup.exe')) -and (Test-Path (Join-Path $w22 'd3\sources\boot.wim')))
$e = ''; try { Copy-SccmContent -Source (Join-Path $w22 'nope\install.wim') -Destination (Join-Path $w22 'd4') } catch { $e = $_.Exception.Message }
Check 'a failed robocopy copy throws with its exit code' ($e -like 'The copy to * failed (robocopy exit code *') $e
Invoke-Expression ([regex]::Match($src, '(?s)function Get-FreeSpaceGB \{.*?\r?\n\}\r?\n').Value.Replace('function Get-FreeSpaceGB', 'function Get-RealFreeSpaceGB'))   # mocks.ps1 replaces the real one
Check 'free space: a local path gives a number; a UNC path that cannot be read gives nothing (no error)' ($null -ne (Get-RealFreeSpaceGB -Path $w22) -and $null -eq (Get-RealFreeSpaceGB -Path '\\no-such-server-wimforge\share'))
Write-Host "`n=== P23 TODO step 4: the Windows ADK's DISM when installed (module and dism.exe), else Windows' own ==="
$k23 = Join-Path $PWD 'tst_root\p23kits'; $d23 = Join-Path $k23 "Assessment and Deployment Kit\Deployment Tools\$(if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' })\DISM"
New-Item -ItemType Directory -Force $d23 | Out-Null; Set-Content (Join-Path $d23 'dism.exe') 'x'
Check 'Find-AdkDism finds the ADK''s DISM folder for this architecture under a Kits root, and nothing elsewhere' ((& $script:RealFindAdkDism -KitsRoots @((Join-Path $k23 'nope'), $k23)) -eq $d23 -and $null -eq (& $script:RealFindAdkDism -KitsRoots @((Join-Path $k23 'nope'))))
$path23 = $env:PATH; $idm = ${function:Import-DismModuleFrom}
$script:MockAdkDism = $null; Use-AdkDism -Quiet
Check 'no ADK: Windows'' own DISM, and the log line says how to get the ADK''s' ($script:DismSource -eq 'Windows' -and $script:DismNote.Level -eq 'INFO' -and $script:DismNote.Text -like "DISM: the Windows ADK is not installed*Deployment Tools*" -and $env:PATH -eq $path23)
$script:Imported23 = ''
function Import-DismModuleFrom { param($Folder) $script:Imported23 = $Folder }
$script:MockAdkDism = $d23; Use-AdkDism -Quiet
Check 'ADK found: its module is imported, its folder goes first on the PATH, and the log line names it' ($script:DismSource -eq 'ADK' -and $script:Imported23 -eq $d23 -and ($env:PATH -split ';')[0] -eq $d23 -and $script:DismNote.Text -like "DISM: using the Windows ADK's DISM*from $d23 (PowerShell module and dism.exe).")
$env:PATH = $path23
function Import-DismModuleFrom { param($Folder) throw 'The module was not loaded.' }
$script:DismSource = 'Windows'; Use-AdkDism -Quiet
Check 'ADK found but its module cannot be loaded: Windows'' own DISM with a WARN, PATH unchanged' ($script:DismSource -eq 'Windows' -and $script:DismNote.Level -eq 'WARN' -and $script:DismNote.Text -like "*could not be loaded (The module was not loaded.); Windows' own DISM is used instead." -and $env:PATH -eq $path23)
Set-Item function:Import-DismModuleFrom $idm; $script:MockAdkDism = $null; $script:DismSource = 'Windows'
$e23 = ''; try { Import-DismModuleFrom -Folder $d23 } catch { $e23 = $_.Exception.Message }
Check 'the real module import fails on a folder without the DISM module (so a broken ADK falls back)' ($e23 -ne '') $e23
$inv23 = [regex]::Match($src, '(?s)function Invoke-MediaRefresh \{.*?\r?\n\}\r?\n').Value
Check 'every engine run except the SCCM ones loads the ADK''s DISM before any DISM command, and the runs log it' ($inv23 -match "if \(@\('SccmConnect', 'SccmImport'\) -notcontains .*\) \{ Use-AdkDism -Quiet \}" -and $inv23.IndexOf('Use-AdkDism -Quiet') -lt $inv23.IndexOf("-eq 'Cleanup'") -and ([regex]::Matches($inv23, 'Write-DismNote')).Count -eq 2)
Check 'Find-Oscdimg and Find-AdkDism look in the same ADK places (Get-AdkKitsRoots)' ($src -match '(?s)function Find-Oscdimg \{.*?Get-AdkKitsRoots' -and $src -match '(?s)function Find-AdkDism \{.*?Get-AdkKitsRoots')
Check 'a run with an empty ISO folder says to check the Repository root' ($src -match 'No ISO files found in \$\(\$paths\.ISO\)\. Copy the OS ISO there, or .* correct the Repository root on the Source and Targets tab')

Write-Host "`nRESULT: $pass passed, $fail failed"
