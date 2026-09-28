$src = Get-Content -Raw $(if ($env:MR_SCRIPT) { $env:MR_SCRIPT } else { (Join-Path $PSScriptRoot '../MediaRefresh_v2.4.ps1') })
$pass=0;$fail=0
function Check($n,[bool]$ok,$d=''){ if($ok){$script:pass++;Write-Host "PASS  $n" -ForegroundColor Green}else{$script:fail++;Write-Host "FAIL  $n  $d" -ForegroundColor Red} }
$m = [regex]::Match($src, "(?s)\[xml\]\`$xaml = @'\r?\n(.*?)\r?\n'@")
Check 'XAML block found' $m.Success
$x = $null; try { $x = [xml]$m.Groups[1].Value } catch { Write-Host $_.Exception.Message }
Check 'XAML is well-formed XML' ($null -ne $x)
$ns = New-Object System.Xml.XmlNamespaceManager($x.NameTable); $ns.AddNamespace('x','http://schemas.microsoft.com/winfx/2006/xaml')
$names = @($x.SelectNodes('//*[@x:Name]', $ns) | ForEach-Object { $_.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml') })
$list = [regex]::Match($src, "foreach \(\`$ctl in @\((.*?)\)\)").Groups[1].Value -split ',' | ForEach-Object { $_.Trim().Trim("'") }
$missing = @($list | Where-Object { $names -notcontains $_ })
Check "every control the script looks up exists in the XAML ($($list.Count) controls)" ($missing.Count -eq 0) ($missing -join ',')
$dups = @($names | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object Name)
Check 'no duplicate x:Name values' ($dups.Count -eq 0) ($dups -join ',')
$refs = [regex]::Matches($src, '\$script:(\w+)\.(?:Add_Click|Add_SelectionChanged|IsEnabled|Text|Items)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
$unknown = @($refs | Where-Object { $list -notcontains $_ -and $_ -notin @('UiTimer','RunQueue','RunShared','RunPs','RunRs','RunHandle','RunStatus','RunStarted','LogFile','ProfileMessages') })
Check 'controls used with .Add_Click/.Text/.Items are all registered' ($unknown.Count -eq 0) ($unknown -join ',')

# Languages tab (TODO step 10e): the list is built from Languages.json on real WPF controls, shown as "name - code",
# the OS defaults are pre-selected by code, and a run gets codes. Windows only (WPF).
$langBox = $x.SelectSingleNode('//*[@x:Name="LanguageList"]', $ns)
Check 'the XAML language list has no hard-coded items (it is filled from Languages.json)' ($null -ne $langBox -and $langBox.ChildNodes.Count -eq 0)
$wpf = $false; try { Add-Type -AssemblyName PresentationFramework -ErrorAction Stop; $wpf = $true } catch { Write-Host 'SKIP  WPF language list checks (PresentationFramework not available)' }
if ($wpf) {
    $pass0 = $pass; $fail0 = $fail
    . (Join-Path $PSScriptRoot 'mocks.ps1')   # engine + Write-Log/Check (mocks.ps1 resets the counters)
    $pass = $pass0; $fail = $fail0
    $script:WarnLines = [System.Collections.Generic.List[string]]::new()
    function Write-Log { param($Message, $Level = 'INFO') $script:WarnLines.Add("[$Level] $Message") }
    foreach ($fn in 'Update-LanguageItems', 'Set-DefaultLanguages') {
        $fm = [regex]::Match($src, "(?s)function $fn \{.*?\r?\n\}\r?\n"); Invoke-Expression $fm.Value
    }
    $script:LanguageList = New-Object System.Windows.Controls.ListBox; $script:LanguageList.SelectionMode = 'Multiple'
    $script:OsCombo = New-Object System.Windows.Controls.ComboBox
    $script:OsDefinitions = Import-OsProfiles
    $script:LanguageOptions = @(Import-LanguageList)
    Update-LanguageItems
    foreach ($n in $script:OsDefinitions.Keys) { [void]$script:OsCombo.Items.Add($n) }
    $script:OsCombo.SelectedItem = 'Windows 10 Enterprise LTSC 2021 (KMS)'
    Set-DefaultLanguages
    $items = @($script:LanguageList.Items)
    Check 'WPF: one list item per Languages.json entry, shown as "full name - code"' ($items.Count -eq 21 -and [string]$items[0].Content -eq 'Catalan (Spain) - ca-es' -and [string]$items[0].Tag -eq 'ca-es')
    $selected = @($items | Where-Object { $_.IsSelected } | ForEach-Object { [string]$_.Tag })
    Check 'WPF: the OS profile defaults are pre-selected by code' (($selected -join ',') -eq 'de-de,en-gb,es-es,fr-fr,it-it,ja-jp,ko-kr,pt-br,zh-cn,zh-tw') ($selected -join ',')
    $langsLine = [regex]::Match($src, '\$langs = @\(foreach \(\$item in \$script:LanguageList\.Items\)[^\r\n]*').Value
    $langs = @(); Invoke-Expression $langsLine
    Check 'WPF: a run gets the selected codes, not the display text' (($langs -join ',') -eq ($selected -join ',')) ($langs -join ',')
    $script:OsDefinitions['Windows 10 Enterprise LTSC 2021 (KMS)'].DefaultLanguages = @('de-de', 'en-us'); $script:WarnLines.Clear()
    Set-DefaultLanguages
    Check 'WPF: a profile default not in Languages.json is logged and not selected' ((@($script:LanguageList.Items | Where-Object { $_.IsSelected } | ForEach-Object { [string]$_.Tag }) -join ',') -eq 'de-de' -and [bool]($script:WarnLines -match 'WARN.*en-us.*not in Languages.json'))

    # "Save settings" / "Reset to defaults" (step 10c) on the real window's controls, so the default ticks are the real ones
    $win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
    foreach ($n in $script:SettingOptionNames) { Set-Variable -Name "Chk$n" -Scope Script -Value $win.FindName("Chk$n") }
    $script:RootText = $win.FindName('RootText'); $script:LanguageList = $win.FindName('LanguageList')
    Check 'the Save settings and Reset to defaults buttons are in the window' ($null -ne $win.FindName('SaveSettingsButton') -and $null -ne $win.FindName('ResetSettingsButton'))
    foreach ($n in 'AppList', 'ReadAppsButton', 'ChkAppRemoval', 'AppsSource', 'SccmSiteServer', 'SccmSiteInfo', 'SccmTargetDP', 'SccmTargetGroup', 'SccmTargetList', 'SccmTarget', 'SccmContentSource', 'SccmUncPreview', 'SccmImageName', 'SccmPackageType', 'SccmLastRun') { Set-Variable -Name $n -Scope Script -Value $win.FindName($n) }
    $script:SccmLists = $null; $script:SccmSourceServer = 'BUILD01'
    $script:ServerShares = @([pscustomobject]@{ Name = 'Sources'; Path = 'F:\Sources' })   # not this PC's real shares
    foreach ($fn in 'Set-OsSettings', 'Get-SelectedSettings', 'Save-CurrentOsSettings', 'Reset-CurrentOsSettings', 'Get-TickedApps', 'Update-AppList',
                    'Get-SccmAutoName', 'Get-SccmPackageTypeTag', 'Set-SccmPackageType', 'Update-SccmTargetList', 'Update-SccmUncPreview', 'Update-SccmLastRun', 'Set-SccmOsValues', 'Get-SccmSelected') {
        $fm = [regex]::Match($src, "(?s)function $fn \{.*?\r?\n\}\r?\n"); Invoke-Expression $fm.Value
    }
    $script:SettingsDir = Join-Path $PWD 'tst_settings'; if (Test-Path $script:SettingsDir) { Remove-Item -Recurse -Force $script:SettingsDir }
    $script:ProfilesDir = Join-Path $PWD 'tst_settings_profiles'   # the Apps tab reads Profiles\Apps (11b)
    $script:DefaultChecks = @{}; foreach ($n in $script:SettingOptionNames) { $script:DefaultChecks[$n] = [bool](Get-Variable -Name "Chk$n" -Scope Script -ValueOnly).IsChecked }
    $script:OsDefinitions = Import-OsProfiles
    Update-LanguageItems
    $ticks = { ($script:SettingOptionNames | ForEach-Object { "$_=$([bool](Get-Variable -Name "Chk$_" -Scope Script -ValueOnly).IsChecked)" }) -join ',' }
    $picked = { (@($script:LanguageList.Items | Where-Object { $_.IsSelected } | ForEach-Object { [string]$_.Tag }) -join ',') }
    $defaultTicks = & $ticks
    $script:OsCombo.SelectedItem = 'Windows 10 Enterprise LTSC 2021 (KMS)'; Set-OsSettings
    Check 'WPF: an OS without saved settings gets the window defaults and its profile languages' ((& $ticks) -eq $defaultTicks -and (& $picked) -eq 'de-de,en-gb,es-es,fr-fr,it-it,ja-jp,ko-kr,pt-br,zh-cn,zh-tw')
    $script:ChkBoot.IsChecked = -not $script:ChkBoot.IsChecked; $script:ChkWinRE.IsChecked = -not $script:ChkWinRE.IsChecked
    foreach ($item in $script:LanguageList.Items) { $item.IsSelected = @('de-de', 'ja-jp') -contains [string]$item.Tag }
    $script:RootText.Text = 'G:\mediaRefresh'
    $changedTicks = & $ticks
    $savedFile = Save-CurrentOsSettings
    Check 'WPF: Save settings writes Settings\Win10_Enterprise_LTSC_2021_KMS.json and General.json' ((Split-Path $savedFile -Leaf) -eq 'Win10_Enterprise_LTSC_2021_KMS.json' -and (Read-GeneralSettings -Directory $script:SettingsDir) -eq 'G:\mediaRefresh')
    $script:OsCombo.SelectedItem = 'Windows 11 Enterprise 24H2'; Set-OsSettings
    Check 'WPF: switching to another OS without saved settings restores the defaults' ((& $ticks) -eq $defaultTicks -and (& $picked) -eq '')
    $script:OsCombo.SelectedItem = 'Windows 10 Enterprise LTSC 2021 (KMS)'; Set-OsSettings
    Check 'WPF: switching back loads the saved ticks and languages for that OS' ((& $ticks) -eq $changedTicks -and (& $picked) -eq 'de-de,ja-jp') "$(& $ticks) | $(& $picked)"
    Reset-CurrentOsSettings
    Check 'WPF: Reset to defaults deletes the OS''s settings file and restores the defaults' (-not (Test-Path $savedFile) -and (& $ticks) -eq $defaultTicks -and (& $picked) -eq 'de-de,en-gb,es-es,fr-fr,it-it,ja-jp,ko-kr,pt-br,zh-cn,zh-tw')

    # Apps tab (TODO step 11): the list comes from <OS folder>\ProvisionedApps.json; ticks by name, saved per OS
    $root11 = Join-Path $PWD 'tst_apps'; if (Test-Path $root11) { Remove-Item -Recurse -Force $root11 }
    $kmsDef = $script:OsDefinitions['Windows 10 Enterprise LTSC 2021 (KMS)']
    $script:ProfilesDir = Join-Path $root11 'Profiles'
    $iso11 = Join-Path $root11 "$($kmsDef.Folder)\ISO\os2021.iso"; New-Item -ItemType Directory -Force (Split-Path $iso11) | Out-Null; Set-Content $iso11 'iso'
    $id11 = Get-IsoIdentity $iso11
    [void](Save-AppInventory -File (Get-AppListPath -ProfilesDir $script:ProfilesDir -Definition $kmsDef) -Source 'os2021.iso' -Index 1 -ImageName 'Windows 10 Enterprise LTSC' -Version '10.0.19041.1288' -IsoSize ([string]$id11.Size) -IsoTime $id11.Time `
        -Apps @([pscustomobject]@{ DisplayName = 'Microsoft.SecHealthUI'; Version = '1000.1'; PackageName = 'Microsoft.SecHealthUI_1000.1_x64__8wekyb3d8bbwe' }, [pscustomobject]@{ DisplayName = 'Microsoft.WindowsStore'; Version = '22.1'; PackageName = 'Microsoft.WindowsStore_22.1_x64__8wekyb3d8bbwe' }))
    $script:RootText.Text = $root11
    $script:OsCombo.SelectedItem = 'Windows 10 Enterprise LTSC 2021 (KMS)'; Set-OsSettings
    $appTags = @($script:AppList.Items | ForEach-Object { [string]$_.Tag })
    Check 'WPF Apps tab: the list comes from Profiles\Apps\<folder>_Appx.json, with where it was read from' (($appTags -join ',') -eq 'Microsoft.SecHealthUI,Microsoft.WindowsStore' -and $script:AppsSource.Text -like '2 provisioned app(s) in os2021.iso, index 1*' -and $script:AppsSource.Text -notlike '*has changed since*' -and $script:AppList.IsEnabled -and @(Get-TickedApps).Count -eq 0) "$($appTags -join ',') | $($script:AppsSource.Text)"
    (Get-Item $iso11).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddDays(3); Update-AppList
    Check 'WPF Apps tab: a new ISO in the folder (same name, new date) is pointed out; the list stays until it is read again' ($script:AppsSource.Text -like '*The OS ISO in the folder has changed since*' -and @($script:AppList.Items).Count -eq 2)
    foreach ($item in $script:AppList.Items) { $item.IsSelected = ([string]$item.Tag -eq 'Microsoft.WindowsStore') }
    $saved11 = Save-CurrentOsSettings
    Update-AppList -Ticked @('Microsoft.WindowsStore', 'Contoso.Gone')
    $gone = @($script:AppList.Items | Where-Object { [string]$_.Tag -eq 'Contoso.Gone' })
    Check 'WPF Apps tab: a ticked app missing from the list stays, marked, and ticked' ($gone.Count -eq 1 -and $gone[0].IsSelected -and [string]$gone[0].Content -like '*not in the current app list*')
    $script:OsCombo.SelectedItem = 'Windows 11 Enterprise 24H2'; Set-OsSettings
    $w11Text = $script:AppsSource.Text
    $script:OsCombo.SelectedItem = 'Windows 10 Enterprise LTSC 2021 (KMS)'; Set-OsSettings
    Check 'WPF Apps tab: Save settings keeps the ticks per OS; an OS without a list says how to get one' ((@(Get-TickedApps) -join ',') -eq 'Microsoft.WindowsStore' -and $w11Text -like 'No app list for this OS yet*')
    $langsLine2 = [regex]::Match($src, 'RemoveApps = \$\(if \(\[bool\]\$script:ChkAppRemoval\.IsChecked\)[^\r\n]*').Value
    $script:ChkAppRemoval.IsChecked = $true; $on = (Invoke-Expression ('@{ ' + $langsLine2 + ' }'))['RemoveApps']
    $script:ChkAppRemoval.IsChecked = $false; $off = (Invoke-Expression ('@{ ' + $langsLine2 + ' }'))['RemoveApps']
    Check 'WPF Apps tab: a run gets the ticked apps only while Remove the ticked apps is ticked' ((@($on) -join ',') -eq 'Microsoft.WindowsStore' -and @($off | Where-Object { $_ }).Count -eq 0) "on=$(@($on) -join ',') off=$(@($off) -join ',')"
    $script:ChkAppRemoval.IsChecked = $true
    $script:OsCombo.SelectedItem = 'Windows Server 2022'; Set-OsSettings
    Check 'WPF Apps tab: Windows Server greys the list out and says why' (-not $script:AppList.IsEnabled -and -not $script:ReadAppsButton.IsEnabled -and $script:AppsSource.Text -like 'App removal is for client editions*')
    Remove-Item $saved11 -Force -ErrorAction SilentlyContinue

    # SCCM tab (TODO step 7) on the real window
    $auto = { param($os) "$os $((Get-Date).ToString('yyyyMM'))" }
    $script:OsCombo.SelectedItem = 'Windows 10 Enterprise LTSC 2021 (KMS)'; Set-OsSettings
    Check 'WPF SCCM tab: the image name follows the selected OS (name + yyyyMM); Full OS image by default' ($script:SccmImageName.Text -eq (& $auto 'Windows 10 Enterprise LTSC 2021 (KMS)') -and (Get-SccmPackageTypeTag) -eq 'Image')
    $script:SccmImageName.Text = 'KMS gold image'; Set-SccmPackageType 'Upgrade'; $script:SccmContentSource.Text = 'F:\Sources\OSD'
    $script:SccmSiteServer.Text = 'cm01.contoso.com'; $script:SccmTargetGroup.IsChecked = $true; $script:SccmTarget.Text = 'All DPs'
    $saved12 = Save-CurrentOsSettings
    $script:OsCombo.SelectedItem = 'Windows 11 Enterprise 24H2'; Set-OsSettings
    $w11Name = $script:SccmImageName.Text; $w11Type = Get-SccmPackageTypeTag
    $script:OsCombo.SelectedItem = 'Windows 10 Enterprise LTSC 2021 (KMS)'; Set-OsSettings
    Check 'WPF SCCM tab: a typed name, the package type and the content folder are saved per OS; another OS keeps its own' ($w11Name -eq (& $auto 'Windows 11 Enterprise 24H2') -and $w11Type -eq 'Image' -and $script:SccmImageName.Text -eq 'KMS gold image' -and (Get-SccmPackageTypeTag) -eq 'Upgrade' -and $script:SccmContentSource.Text -eq 'F:\Sources\OSD')
    $sg12 = Read-SccmGeneralSettings -Directory $script:SettingsDir
    Check 'WPF SCCM tab: site server and distribution target are saved once for every OS' ($sg12.SiteServer -eq 'cm01.contoso.com' -and $sg12.TargetType -eq 'DPGroup' -and $sg12.Target -eq 'All DPs')
    $script:SccmImageName.Text = (Get-SccmAutoName)
    Check 'WPF SCCM tab: back to the automatic name, nothing typed is saved' ((Get-SccmSelected).ImageName -eq '')
    Update-SccmUncPreview
    $okPreview = $script:SccmUncPreview.Text
    $script:SccmContentSource.Text = 'G:\Elsewhere'; Update-SccmUncPreview
    Check 'WPF SCCM tab: the UNC preview shows the import path, or why the folder cannot be used' ($okPreview -eq 'Configuration Manager imports from \\BUILD01\Sources\OSD\<image name>' -and $script:SccmUncPreview.Text -like '*not inside a shared folder*')
    $script:SccmLists = [pscustomobject]@{ DPs = @('dp01.contoso.com', 'dp02.contoso.com'); Groups = @('All DPs') }
    $script:SccmTargetDP.IsChecked = $true; Update-SccmTargetList; $dps = @($script:SccmTargetList.Items) -join ','
    $script:SccmTargetGroup.IsChecked = $true; Update-SccmTargetList; $grps = @($script:SccmTargetList.Items) -join ','
    Check 'WPF SCCM tab: the pick list shows distribution points or groups, as chosen' ($dps -eq 'dp01.contoso.com,dp02.contoso.com' -and $grps -eq 'All DPs')
    $nw12 = [System.IO.Path]::Combine($root11, $kmsDef.Folder, 'NEWWIM'); New-Item -ItemType Directory -Force $nw12 | Out-Null
    Update-SccmLastRun; $none12 = $script:SccmLastRun.Text
    [void](Save-RunResult -Paths @{ NewWim = $nw12 } -OsName 'KMS' -Build '10.0.19044.6456' -Gate 'FAILED' -Install 'x' -Media '' -ChangeLog '')
    Update-SccmLastRun
    Check 'WPF SCCM tab: the latest run line says what would be imported, and that a FAILED run will not be' ($none12 -like 'No finished run yet*' -and $script:SccmLastRun.Text -like 'Latest run: build 10.0.19044.6456, validation gate FAILED*will not be imported.')
    Remove-Item $saved12 -Force -ErrorAction SilentlyContinue

    # Run config files (2026-09-28): the engine's defaults must equal the window's, and the window saves what it shows
    $diff13 = @($script:SettingOptionNames | Where-Object { [bool]$script:OptionDefaults[$_] -ne [bool]$script:DefaultChecks[$_] })
    Check 'a config''s default for every option equals the window''s own default tick' ($diff13.Count -eq 0 -and @($script:OptionDefaults.Keys).Count -eq @($script:SettingOptionNames).Count) ($diff13 -join ',')
    $menu13 = $win.FindName('SaveRunConfigItem')
    Check 'Tools menu: Save run config...' ($null -ne $menu13 -and @($win.FindName('ToolsButton').ContextMenu.Items) -contains $menu13)
    $fm = [regex]::Match($src, "(?s)function Save-CurrentRunConfig \{.*?\r?\n\}\r?\n"); Invoke-Expression $fm.Value
    $script:OsCombo.SelectedItem = 'Windows 10 Enterprise LTSC 2021 (KMS)'; Set-OsSettings
    $script:ChkNetFx3.IsChecked = $true; $script:ChkBuildMedia.IsChecked = $true
    foreach ($item in $script:LanguageList.Items) { $item.IsSelected = @('fr-fr') -contains [string]$item.Tag }
    $script:SccmSiteServer.Text = 'cm02.contoso.com'
    $rcFile13 = Save-CurrentRunConfig -File (Join-Path $PWD 'tst_settings\run13.json')
    $rc13 = Read-RunConfig -File $rcFile13 -Definitions $script:OsDefinitions -LanguageList $script:LanguageOptions
    Check 'WPF: Save run config writes exactly what the window shows, and it reads back cleanly' ($rc13.OsName -eq 'Windows 10 Enterprise LTSC 2021 (KMS)' -and $rc13.Root -eq $root11 -and $rc13.Options['NetFx3'] -and $rc13.Options['BuildMedia'] -and (@($rc13.Languages) -join ',') -eq 'fr-fr' -and $rc13.Sccm['siteServer'] -eq 'cm02.contoso.com')

    # Patch boot.wim is tied to the media (2026-09-27): the real window's checkbox, the real handler wiring
    Invoke-Expression ([regex]::Match($src, "(?s)function Update-BootOption \{.*?\r?\n\}\r?\n").Value)
    Invoke-Expression ([regex]::Match($src, 'foreach \(\$chk in @\(\$script:ChkBuildMedia, \$script:ChkBuildIso, \$script:ChkBoot\)\)[^\r\n]*').Value)
    $script:ChkBuildMedia.IsChecked = $false; $script:ChkBuildIso.IsChecked = $false; Update-BootOption
    $kids = $script:ChkBoot.Parent.Children
    Check 'under the media option: the ISO, then Patch boot.wim (ticked by default); both unavailable without media' ([string]$script:ChkBoot.Content -like 'Patch boot.wim (WinPE and Setup)*not used by SCCM*' -and $script:DefaultChecks['Boot'] -and -not $script:ChkBoot.IsEnabled -and -not $script:ChkBuildIso.IsEnabled -and $kids.IndexOf($script:ChkBuildIso) -eq $kids.IndexOf($script:ChkBuildMedia) + 1 -and $kids.IndexOf($script:ChkBoot) -eq $kids.IndexOf($script:ChkBuildMedia) + 2 -and $script:ChkBuildIso.Margin.Left -eq $script:ChkBoot.Margin.Left -and $script:ChkBoot.Margin.Left -gt 0)
    $script:ChkBuildMedia.IsChecked = $true
    $en1 = $script:ChkBoot.IsEnabled -and $script:ChkBuildIso.IsEnabled; $script:ChkBuildMedia.IsChecked = $false
    Check 'ticking the media folder makes the ISO and Patch boot.wim available; unticking it greys both out again' ($en1 -and -not $script:ChkBoot.IsEnabled -and -not $script:ChkBuildIso.IsEnabled)
    Check 'the CA 2023 option sits under Patch boot.wim, unticked by default, and is saved with the other options' ([string]$script:ChkMedia2023.Content -like "Also build CA 2023 media alongside it*Windows UEFI CA 2023*" -and -not $script:DefaultChecks['Media2023'] -and $script:SettingOptionNames -contains 'Media2023' -and $script:ChkMedia2023.Parent.Children.IndexOf($script:ChkMedia2023) -eq $script:ChkMedia2023.Parent.Children.IndexOf($script:ChkBoot) + 1)
    $script:ChkBoot.IsChecked = $true; $script:ChkBuildMedia.IsChecked = $true; $c1 = $script:ChkMedia2023.IsEnabled
    $script:ChkBoot.IsChecked = $false; $c2 = $script:ChkMedia2023.IsEnabled
    $script:ChkBoot.IsChecked = $true; $script:ChkBuildMedia.IsChecked = $false; $c3 = $script:ChkMedia2023.IsEnabled
    Check 'CA 2023 is available only with media and Patch boot.wim both ticked' ($c1 -and -not $c2 -and -not $c3)
    $auto14 = $win.FindName('ChkAutoDownload')
    Check 'Updates and Features: "Download the latest patches before the run" is there, off by default, and saved per OS (step 14)' ($null -ne $auto14 -and -not $script:DefaultChecks['AutoDownload'] -and $script:SettingOptionNames -contains 'AutoDownload' -and [string]$auto14.Content.Text -like 'Download the latest patches before the run (only what is missing)*use the patches already in the folders.')

    # Instructions tab (TODO 10b): the real window's tab and the real guide rendered as a FlowDocument
    foreach ($fn in 'Add-MarkdownInlines', 'New-InstructionsDocument', 'Update-InstructionsTab') {
        $fm = [regex]::Match($src, "(?s)function $fn \{.*?\r?\n\}\r?\n"); Invoke-Expression $fm.Value
    }
    $tabNames = @(($win.FindName('LogBox').Parent.Parent.Items) | ForEach-Object { [string]$_.Header })
    Check 'the Instructions tab sits between Log and General Settings, with Reload and the file path' (($tabNames -join ',') -eq 'Source and Targets,Updates and Features,Languages,Apps,SCCM,Log,Instructions,General Settings' -and $null -ne $win.FindName('ReloadInstructionsButton') -and $win.FindName('InstructionsViewer') -is [System.Windows.Controls.FlowDocumentScrollViewer]) ($tabNames -join ',')
    $script:InstructionsViewer = $win.FindName('InstructionsViewer'); $script:InstructionsSource = $win.FindName('InstructionsSource')
    $savedProfilesDir = $script:ProfilesDir; $savedRootText = $script:RootText.Text
    $script:ProfilesDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'Profiles'; $script:RootText.Text = ''
    if (Test-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'INSTRUCTIONS.md')) {
        Update-InstructionsTab
        $doc = $script:InstructionsViewer.Document
        $heads = @($doc.Blocks | Where-Object { $_ -is [System.Windows.Documents.Paragraph] -and $_.FontWeight -eq [System.Windows.FontWeights]::SemiBold } | ForEach-Object { (New-Object System.Windows.Documents.TextRange($_.ContentStart, $_.ContentEnd)).Text })
        $lists = @($doc.Blocks | Where-Object { $_ -is [System.Windows.Documents.List] })
        $nested = @($lists | ForEach-Object { $_.ListItems } | ForEach-Object { $_.Blocks } | Where-Object { $_ -is [System.Windows.Documents.List] })
        $numbered = @($lists | Where-Object { $_.MarkerStyle -eq [System.Windows.TextMarkerStyle]::Decimal })
        $deeper = @($nested | ForEach-Object { $_.ListItems } | ForEach-Object { $_.Blocks } | Where-Object { $_ -is [System.Windows.Documents.List] })   # CA 2023 under Patch boot.wim
        Check 'WPF: the real guide renders: headings, bullet lists, nested lists and the numbered order of work' ($heads -contains 'WimForge - operator guide' -and $heads -contains 'Where the logs are' -and $lists.Count -gt 10 -and $nested.Count -ge 2 -and $deeper.Count -ge 1 -and $numbered.Count -ge 1 -and @($numbered[0].ListItems).Count -eq 6) "headings $($heads.Count), lists $($lists.Count), nested $($nested.Count), numbered $($numbered.Count)"
        Check 'WPF: the path line shows which file was read' ($script:InstructionsSource.Text -like "*INSTRUCTIONS.md   (read at *")
    } else { Write-Host 'SKIP  real INSTRUCTIONS.md rendering (file not found)' }
    $noScript = Join-Path $PWD 'tst_instr\app'; $instrRoot = Join-Path $PWD 'tst_instr\root'
    if (Test-Path (Join-Path $PWD 'tst_instr')) { Remove-Item (Join-Path $PWD 'tst_instr') -Recurse -Force }
    New-Item -ItemType Directory -Force $noScript, $instrRoot | Out-Null
    $script:ProfilesDir = Join-Path $noScript 'Profiles'; $script:RootText.Text = $instrRoot
    Update-InstructionsTab
    $missingText = (New-Object System.Windows.Documents.TextRange($script:InstructionsViewer.Document.ContentStart, $script:InstructionsViewer.Document.ContentEnd)).Text
    Check 'WPF: a missing INSTRUCTIONS.md is shown as a message naming both folders searched, not an error' ($missingText -match 'INSTRUCTIONS\.md was not found in ' -and $missingText -match [regex]::Escape($noScript) -and $missingText -match [regex]::Escape($instrRoot) -and $script:InstructionsSource.Text -like 'INSTRUCTIONS.md not found in *')
    # the file appears while the window is open (in the root folder, lower-case extension): opening the tab picks it up
    [System.IO.File]::WriteAllText((Join-Path $instrRoot 'instructions.MD'), "# Copied in later`n`nText.")
    Update-InstructionsTab -IfChanged
    $laterText = (New-Object System.Windows.Documents.TextRange($script:InstructionsViewer.Document.ContentStart, $script:InstructionsViewer.Document.ContentEnd)).Text
    Check 'WPF: a file copied in later is picked up when the tab is opened (root folder, any letter case)' ($laterText -match 'Copied in later' -and $script:InstructionsSource.Text -like "*instructions.MD   (read at *")
    $script:InstructionsViewer.Document = New-InstructionsDocument '# placeholder'
    Update-InstructionsTab -IfChanged
    $sameText = (New-Object System.Windows.Documents.TextRange($script:InstructionsViewer.Document.ContentStart, $script:InstructionsViewer.Document.ContentEnd)).Text
    Check 'WPF: opening the tab again with the file unchanged does not re-read it' ($sameText -match 'placeholder')
    Check 'the Instructions tab is named, so opening it can re-read the file' ($null -ne $win.FindName('InstructionsTab') -and $src -match 'InstructionsTab\.AddHandler\(\[System\.Windows\.Controls\.Primitives\.Selector\]::SelectedEvent')
    $script:ProfilesDir = $savedProfilesDir; $script:RootText.Text = $savedRootText

    # Colour schemes (General Settings tab) on the real window
    $script:ThemedStyleXaml = [regex]::Match($src, "(?s)\`$script:ThemedStyleXaml = @'\r?\n(.*?)\r?\n'@").Groups[1].Value
    foreach ($fn in 'New-SchemeBrush', 'Set-TitleBarDark', 'Set-ColorScheme', 'Add-LogText') {
        $fm = [regex]::Match($src, "(?s)function $fn\b.*?\r?\n\}\r?\n"); Invoke-Expression $fm.Value
    }
    $window = $win; $script:ThemedStyles = $null; $script:ColorSchemes = Get-ColorSchemes
    $script:SchemeSwatches = $win.FindName('SchemeSwatches'); $script:LogBox = $win.FindName('LogBox')
    Check 'the General Settings tab has the scheme picker, swatches and a rich-text Log' ($null -ne $win.FindName('ColorSchemeCombo') -and $null -ne $script:SchemeSwatches -and $script:LogBox -is [System.Windows.Controls.RichTextBox])
    $threw = $null; try { $parsed = [Windows.Markup.XamlReader]::Parse($script:ThemedStyleXaml) } catch { $threw = $_.Exception.Message }
    Check 'the dark-scheme control styles load in WPF' ($null -eq $threw -and $parsed.Count -ge 10) $threw
    $tools = $win.FindName('ToolsButton'); $cleanItem = $win.FindName('CleanupMountsItem')
    Check 'the header has a Tools button whose menu holds Cleanup Mountpoints' ($null -ne $tools -and $null -ne $cleanItem -and @($tools.ContextMenu.Items) -contains $cleanItem -and [string]$cleanItem.Header -eq 'Cleanup Mountpoints...')
    Check 'the dark-scheme styles cover the Tools menu (ContextMenu and MenuItem)' ($parsed.Contains([System.Windows.Controls.ContextMenu]) -and $parsed.Contains([System.Windows.Controls.MenuItem]))
    $col = { param($k) $win.FindResource($k).Color.ToString().Substring(3) }   # '#AARRGGBB' -> 'RRGGBB'
    [void](Set-ColorScheme 'Industrial Forge')
    Check 'WPF: a dark scheme sets its brushes and adds the control styles' ((& $col 'WF.WindowBg') -eq '2B2B2B' -and (& $col 'WF.Accent') -eq 'FF6A00' -and $win.Resources.MergedDictionaries.Count -eq 2 -and $script:SchemeSwatches.Children.Count -eq 5)
    $script:LogBox.Document.Blocks.FirstBlock.Inlines.Clear()
    Add-LogText ("10:00:00 [INFO] Adding LCU x.msu`r`n10:00:01 [WARN] careful`r`n10:00:02 [ERROR] broken`r`n10:00:03 [INFO] VALIDATION GATE: PASSED`r`n")
    $runs = @($script:LogBox.Document.Blocks.FirstBlock.Inlines | Where-Object { $_ -is [System.Windows.Documents.Run] })
    $fg = { param($r) $r.Foreground.Color.ToString().Substring(3) }
    Check 'WPF: log lines are added one per line, coloured by level (Industrial Forge)' ($runs.Count -eq 4 -and (& $fg $runs[0]) -eq 'FFC14A' -and (& $fg $runs[1]) -eq 'FF6A00' -and (& $fg $runs[2]) -eq 'FF4D4D' -and (& $fg $runs[3]) -eq 'FFC14A') (($runs | ForEach-Object { & $fg $_ }) -join ',')
    [void](Set-ColorScheme 'Minimalist Forge')
    Check 'WPF: switching scheme recolours lines already in the log (Minimalist Forge errors in Forge Red)' ((& $fg $runs[0]) -eq 'B8B8B8' -and (& $fg $runs[2]) -eq 'D7263D')
    [void](Set-ColorScheme 'Modern Sysadmin')
    Check 'WPF: Modern Sysadmin success lines in Lime Signal' ((& $fg $runs[3]) -eq 'A4E400' -and (& $fg $runs[0]) -eq 'D0D0D0')
    $back = Set-ColorScheme 'Default'
    Check 'WPF: Default drops the control styles and restores the original colours' ($back -eq 'Default' -and $win.Resources.MergedDictionaries.Count -eq 1 -and (& $col 'WF.WindowBg') -eq 'F4F6F8' -and (& $col 'WF.LogBg') -eq '111827' -and (& $fg $runs[2]) -eq 'E5E7EB')
    Check 'WPF: an unknown scheme name falls back to Default' ((Set-ColorScheme 'No Such Scheme') -eq 'Default')
    $win.Close()
}
Write-Host "`nRESULT: $pass passed, $fail failed"
