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
    Check 'WPF: one list item per Languages.json entry, shown as "full name - code"' ($items.Count -eq 20 -and [string]$items[0].Content -eq 'Catalan (Spain) - ca-es' -and [string]$items[0].Tag -eq 'ca-es')
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
    foreach ($fn in 'Set-OsSettings', 'Get-SelectedSettings', 'Save-CurrentOsSettings', 'Reset-CurrentOsSettings') {
        $fm = [regex]::Match($src, "(?s)function $fn \{.*?\r?\n\}\r?\n"); Invoke-Expression $fm.Value
    }
    $script:SettingsDir = Join-Path $PWD 'tst_settings'; if (Test-Path $script:SettingsDir) { Remove-Item -Recurse -Force $script:SettingsDir }
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

    # Patch boot.wim is tied to the media (Terry, 2026-09-27): the real window's checkbox, the real handler wiring
    Invoke-Expression ([regex]::Match($src, "(?s)function Update-BootOption \{.*?\r?\n\}\r?\n").Value)
    Invoke-Expression ([regex]::Match($src, 'foreach \(\$chk in @\(\$script:ChkBuildMedia, \$script:ChkBuildIso, \$script:ChkBoot\)\)[^\r\n]*').Value)
    $script:ChkBuildMedia.IsChecked = $false; $script:ChkBuildIso.IsChecked = $false; Update-BootOption
    Check 'Patch boot.wim is below the media option, ticked by default, and unavailable without media' ([string]$script:ChkBoot.Content -like 'Patch boot.wim (WinPE and Setup)*not used by SCCM*' -and $script:DefaultChecks['Boot'] -and -not $script:ChkBoot.IsEnabled -and $script:ChkBoot.Parent.Children.IndexOf($script:ChkBoot) -eq $script:ChkBoot.Parent.Children.IndexOf($script:ChkBuildMedia) + 1)
    $script:ChkBuildMedia.IsChecked = $true
    $en1 = $script:ChkBoot.IsEnabled; $script:ChkBuildMedia.IsChecked = $false; $script:ChkBuildIso.IsChecked = $true
    $en2 = $script:ChkBoot.IsEnabled; $script:ChkBuildIso.IsChecked = $false
    Check 'ticking the media folder or the ISO makes Patch boot.wim available; unticking both greys it out again' ($en1 -and $en2 -and -not $script:ChkBoot.IsEnabled)
    Check 'the CA 2023 option sits under Patch boot.wim, unticked by default, and is saved with the other options' ([string]$script:ChkMedia2023.Content -like "Also build CA 2023 media alongside it*Windows UEFI CA 2023*" -and -not $script:DefaultChecks['Media2023'] -and $script:SettingOptionNames -contains 'Media2023' -and $script:ChkMedia2023.Parent.Children.IndexOf($script:ChkMedia2023) -eq $script:ChkMedia2023.Parent.Children.IndexOf($script:ChkBoot) + 1)
    $script:ChkBoot.IsChecked = $true; $script:ChkBuildMedia.IsChecked = $true; $c1 = $script:ChkMedia2023.IsEnabled
    $script:ChkBoot.IsChecked = $false; $c2 = $script:ChkMedia2023.IsEnabled
    $script:ChkBoot.IsChecked = $true; $script:ChkBuildMedia.IsChecked = $false; $c3 = $script:ChkMedia2023.IsEnabled
    Check 'CA 2023 is available only with media and Patch boot.wim both ticked' ($c1 -and -not $c2 -and -not $c3)

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
