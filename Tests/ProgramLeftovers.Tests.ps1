# Leftovers of uninstalled programs: what Find-WTProgramResidue may offer, and how
# Remove-WTResidue and Invoke-WTProgramRemoval delete them. The disk, the registry, services,
# tasks, processes and every deletion are mocked.
#   Invoke-Pester .\Tests   (Pester 5, see Build\Test-Pester.ps1)

BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'Module\WinTechToolkit.psm1') -Force -DisableNameChecking
    $PSDefaultParameterValues['Mock:ModuleName'] = 'WinTechToolkit'
    $PSDefaultParameterValues['Should:ModuleName'] = 'WinTechToolkit'
    $PSDefaultParameterValues['InModuleScope:ModuleName'] = 'WinTechToolkit'
    $global:WTLanguage = 'en'
    $global:WTQueue = $null

    # An object as returned by Get-WTInstalledProgram
    function New-FakeProgram {
        param([string]$DisplayName = 'Contoso Widget 2.1 (x64)', [string]$Publisher = 'Contoso Ltd', [string]$InstallLocation = '',
            [string]$UninstallString = '', [string]$ProductCode = $null,
            [string]$RegistryKey = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ContosoWidget')
        [pscustomobject]@{
            DisplayName = $DisplayName; Publisher = $Publisher; Version = '2.1'; InstallLocation = $InstallLocation
            UninstallString = $UninstallString; QuietUninstallString = ''; ProductCode = $(if ($ProductCode) { $ProductCode } else { $null })
            RegistryKey = $RegistryKey; InstallerType = 'EXE'
        }
    }

    # An object as returned by Find-WTProgramResidue
    function New-FakeResidue([string]$Type, [string]$Path) {
        [pscustomobject]@{ Type = $Type; TypeText = $Type; Path = $Path; Reason = 'test'; Program = 'Contoso Widget'; SizeBytes = [int64]0; SizeText = '' }
    }
}

Describe 'Name variants' {
    It 'Get-WTNameVariants strips version and architecture: <DisplayName>' -TestCases @(
        @{ DisplayName = 'Contoso Widget 2.1.3 (x64)'; Expected = 'Contoso Widget' },
        @{ DisplayName = 'Contoso Widget v12.0'; Expected = 'Contoso Widget' },
        @{ DisplayName = 'Contoso Widget x64 en-us'; Expected = 'Contoso Widget' },
        @{ DisplayName = 'Contoso Widget - Enterprise'; Expected = 'Contoso Widget' }
    ) {
        Get-WTNameVariants -DisplayName $DisplayName | Should -Contain $Expected
    }

    It 'Get-WTNameVariants also tries the name without spaces and without the publisher' {
        $v = Get-WTNameVariants -DisplayName 'Contoso Widget Studio' -Publisher 'Contoso Ltd'
        $v | Should -Contain 'ContosoWidgetStudio'
        $v | Should -Contain 'Widget Studio'
    }

    It 'Get-WTNameVariants never returns a generic or system name: <DisplayName>' -TestCases @(
        @{ DisplayName = 'Microsoft Visual C++ 2015 Redistributable' }, @{ DisplayName = 'Windows Driver Package' },
        @{ DisplayName = 'Data' }, @{ DisplayName = 'Tools 2.0' }, @{ DisplayName = 'AB' }, @{ DisplayName = '2024' }, @{ DisplayName = '' }
    ) {
        foreach ($v in @(Get-WTNameVariants -DisplayName $DisplayName)) {
            Test-WTProtectedName $v | Should -BeFalse
            $v.Length | Should -BeGreaterOrEqual 3
            $v | Should -Not -Match '^\d+$'
        }
        @(Get-WTNameVariants -DisplayName $DisplayName) | Should -Not -Contain 'Microsoft'
        @(Get-WTNameVariants -DisplayName $DisplayName) | Should -Not -Contain 'Windows'
    }

    It 'Get-WTPublisherVariants never returns Microsoft, Windows or a generic name: <Publisher>' -TestCases @(
        @{ Publisher = 'Microsoft Corporation' }, @{ Publisher = 'Microsoft' }, @{ Publisher = 'Intel Corporation' }, @{ Publisher = 'HP' },
        @{ Publisher = '' }, @{ Publisher = 'AB' }
    ) {
        @(Get-WTPublisherVariants -Publisher $Publisher).Count | Should -Be 0
    }

    It 'Get-WTPublisherVariants strips the company suffix' {
        Get-WTPublisherVariants -Publisher 'Contoso Software GmbH' | Should -Contain 'Contoso'
    }

    It 'Convert-WTGuidToPacked gives the Windows Installer form of a product code' {
        Convert-WTGuidToPacked '{90160000-008C-0000-0000-0000000FF1CE}' | Should -Be '00006109C80000000000000000F01FEC'
    }

    It 'Convert-WTGuidToPacked returns nothing for a malformed code: <Guid>' -TestCases @(@{ Guid = '' }, @{ Guid = '{1234}' }, @{ Guid = 'not-a-guid' }) {
        Convert-WTGuidToPacked $Guid | Should -BeNullOrEmpty
    }
}

Describe 'Find-WTProgramResidue' {
    BeforeEach {
        # the fake disk and registry: the paths in this list exist, nothing else does
        $global:WTPesterExisting = New-Object Collections.Generic.List[string]
        foreach ($p in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, 'C:\Users\alice\AppData\Roaming', 'C:\Users\alice\AppData\Local')) {
            if ($p) { $global:WTPesterExisting.Add($p) }
        }
        Mock Test-Path { $global:WTPesterExisting -contains "$LiteralPath" }
        Mock Write-WTLog { }
        Mock Get-WTProfilesDirectory { 'C:\Users' }
        Mock Get-WTProfileFolders { @('C:\Users\alice') }
        Mock Get-WTInstalledProgram { @() }
        Mock Get-WTFolderSize { [int64]0 }
        Mock Get-CimInstance { @() }
        Mock Get-ScheduledTask { @() }
        Mock Get-ChildItem { @() }
        Mock Get-Item { $null }
        # the search never deletes
        Mock Remove-WTFolder { throw 'Find-WTProgramResidue deleted a folder' }
        Mock Remove-WTRegistryKey { throw 'Find-WTProgramResidue deleted a key' }
        Mock Remove-Item { throw 'Find-WTProgramResidue deleted an item' }
        Mock Stop-Service { throw 'Find-WTProgramResidue stopped a service' }
        Mock Unregister-ScheduledTask { throw 'Find-WTProgramResidue deleted a task' }
        InModuleScope -ScriptBlock { $script:WTResidueCache = $null }
    }
    AfterEach {
        Remove-Variable -Name WTPesterExisting -Scope Global -ErrorAction SilentlyContinue
    }

    It 'finds the install folder, the folders and keys named after the program and the uninstall entry' {
        $prog = New-FakeProgram -InstallLocation "$env:ProgramFiles\Contoso Widget"
        $global:WTPesterExisting.AddRange([string[]]@(
                "$env:ProgramFiles\Contoso Widget", 'C:\Users\alice\AppData\Roaming\Contoso Widget',
                'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Contoso Widget', "Registry::$($prog.RegistryKey)"))
        $found = @(Find-WTProgramResidue -Program $prog)
        $paths = @($found | ForEach-Object { $_.Path })
        $paths | Should -Contain "$env:ProgramFiles\Contoso Widget"
        $paths | Should -Contain 'C:\Users\alice\AppData\Roaming\Contoso Widget'
        $paths | Should -Contain 'HKEY_LOCAL_MACHINE\SOFTWARE\Contoso Widget'
        $paths | Should -Contain $prog.RegistryKey
        # each leftover once, even when several rules find it
        @($paths | Where-Object { $_ -eq "$env:ProgramFiles\Contoso Widget" }).Count | Should -Be 1
    }

    It 'never offers a protected folder as install folder: <Location>' -TestCases @(
        @{ Location = $env:ProgramFiles }, @{ Location = $env:windir }, @{ Location = "$env:windir\System32" }, @{ Location = $env:ProgramData },
        @{ Location = 'C:\Users\alice\AppData\Local' }, @{ Location = 'C:\Users\alice' }, @{ Location = "$env:ProgramFiles\Common Files" }, @{ Location = 'C:\' }
    ) {
        $global:WTPesterExisting.Add($Location)
        $found = @(Find-WTProgramResidue -Program (New-FakeProgram -InstallLocation $Location))
        @($found | Where-Object { $_.Type -eq 'Folder' -and $_.Path.TrimEnd('\') -eq $Location.TrimEnd('\') }).Count | Should -Be 0
    }

    It 'never offers the folder of another installed program' {
        Mock Get-WTInstalledProgram {
            [pscustomobject]@{ DisplayName = 'Fabrikam Suite'; Publisher = 'Fabrikam'; InstallLocation = "$env:ProgramFiles\Contoso Widget\Plugins\Fabrikam"; RegistryKey = 'HKEY_LOCAL_MACHINE\Other' }
        }
        $global:WTPesterExisting.Add("$env:ProgramFiles\Contoso Widget")
        $found = @(Find-WTProgramResidue -Program (New-FakeProgram -InstallLocation "$env:ProgramFiles\Contoso Widget"))
        @($found | Where-Object { $_.Type -eq 'Folder' }).Count | Should -Be 0
    }

    It 'does not search a name that another installed program also uses' {
        Mock Get-WTInstalledProgram {
            [pscustomobject]@{ DisplayName = 'Contoso Widget 3.0'; Publisher = 'Contoso Ltd'; InstallLocation = ''; RegistryKey = 'HKEY_LOCAL_MACHINE\Other' }
        }
        $global:WTPesterExisting.AddRange([string[]]@("$env:ProgramFiles\Contoso Widget", 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Contoso Widget'))
        $found = @(Find-WTProgramResidue -Program (New-FakeProgram -RegistryKey ''))
        @($found | Where-Object { $_.Path -like '*\Contoso Widget' }).Count | Should -Be 0
    }

    It 'offers a publisher folder only when it would be left empty' {
        $global:WTPesterExisting.AddRange([string[]]@("$env:ProgramFiles\Contoso", "$env:ProgramFiles\Contoso\Contoso Widget"))
        Mock Get-ChildItem -ParameterFilter { "$LiteralPath" -eq "$env:ProgramFiles\Contoso" } {
            [pscustomobject]@{ FullName = "$env:ProgramFiles\Contoso\Contoso Widget" }
            [pscustomobject]@{ FullName = "$env:ProgramFiles\Contoso\Contoso Designer" }
        }
        $paths = @(Find-WTProgramResidue -Program (New-FakeProgram -RegistryKey '') | ForEach-Object { $_.Path })
        $paths | Should -Contain "$env:ProgramFiles\Contoso\Contoso Widget"
        $paths | Should -Not -Contain "$env:ProgramFiles\Contoso"

        Mock Get-ChildItem -ParameterFilter { "$LiteralPath" -eq "$env:ProgramFiles\Contoso" } {
            [pscustomobject]@{ FullName = "$env:ProgramFiles\Contoso\Contoso Widget" }
        }
        $paths = @(Find-WTProgramResidue -Program (New-FakeProgram -RegistryKey '') | ForEach-Object { $_.Path })
        $paths | Should -Contain "$env:ProgramFiles\Contoso"
    }

    It 'offers the folder of the uninstaller but never the one of msiexec' {
        $global:WTPesterExisting.AddRange([string[]]@("$env:ProgramFiles\CWSetup", "$env:windir\System32"))
        $a = @(Find-WTProgramResidue -Program (New-FakeProgram -RegistryKey '' -UninstallString "`"$env:ProgramFiles\CWSetup\uninstall.exe`" /S"))
        @($a | ForEach-Object { $_.Path }) | Should -Contain "$env:ProgramFiles\CWSetup"
        $b = @(Find-WTProgramResidue -Program (New-FakeProgram -RegistryKey '' -UninstallString "$env:windir\System32\msiexec.exe /x {90160000-008C-0000-0000-0000000FF1CE}"))
        @($b | Where-Object { $_.Type -eq 'Folder' }).Count | Should -Be 0
    }

    It 'finds the Windows Installer registration of an MSI product' {
        $global:WTPesterExisting.Add('Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Installer\Products\00006109C80000000000000000F01FEC')
        $found = @(Find-WTProgramResidue -Program (New-FakeProgram -RegistryKey '' -ProductCode '{90160000-008C-0000-0000-0000000FF1CE}'))
        @($found | ForEach-Object { $_.Path }) | Should -Contain 'HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Installer\Products\00006109C80000000000000000F01FEC'
    }

    It 'offers the services of the program, never svchost or a Windows service with the same name' {
        $global:WTPesterExisting.Add("$env:ProgramFiles\Contoso Widget")
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Service' } {
            [pscustomobject]@{ Name = 'ContosoSvc'; DisplayName = 'Contoso Service'; PathName = "`"$env:ProgramFiles\Contoso Widget\svc.exe`"" }
            [pscustomobject]@{ Name = 'Contoso Widget'; DisplayName = 'Contoso Widget'; PathName = "$env:windir\System32\cwsvc.exe" }
            [pscustomobject]@{ Name = 'ContosoHost'; DisplayName = 'Contoso Host'; PathName = "$env:windir\System32\svchost.exe -k netsvcs -p $env:ProgramFiles\Contoso Widget\x" }
        }
        $services = @(Find-WTProgramResidue -Program (New-FakeProgram -RegistryKey '') | Where-Object { $_.Type -eq 'Service' } | ForEach-Object { $_.Path })
        $services | Should -Be @('ContosoSvc')
    }

    It 'offers the scheduled tasks that run the program' {
        $global:WTPesterExisting.Add("$env:ProgramFiles\Contoso Widget")
        Mock Get-ScheduledTask {
            [pscustomobject]@{ TaskPath = '\'; TaskName = 'Updater'; Actions = @([pscustomobject]@{ Execute = "$env:ProgramFiles\Contoso Widget\update.exe"; Arguments = '' }) }
            [pscustomobject]@{ TaskPath = '\'; TaskName = 'Backup'; Actions = @([pscustomobject]@{ Execute = 'C:\Tools\backup.exe'; Arguments = '' }) }
        }
        $tasks = @(Find-WTProgramResidue -Program (New-FakeProgram -RegistryKey '') | Where-Object { $_.Type -eq 'Scheduled task' } | ForEach-Object { $_.Path })
        $tasks | Should -Be @('\Updater')
    }

    It 'finds nothing for a generic or system name, even when everything exists: <DisplayName>' -TestCases @(
        @{ DisplayName = 'Windows' }, @{ DisplayName = 'Microsoft' }, @{ DisplayName = 'Data' }, @{ DisplayName = 'Users' }, @{ DisplayName = 'Tools' }
    ) {
        Mock Test-Path { $true }
        $found = @(Find-WTProgramResidue -Program (New-FakeProgram -DisplayName $DisplayName -Publisher '' -RegistryKey '') -Partial)
        $found.Count | Should -Be 0
    }

    Context 'partial search' {
        BeforeEach {
            Mock Get-ChildItem -ParameterFilter { $Directory -and "$LiteralPath" -eq 'C:\Users\alice\AppData\Roaming' } {
                [pscustomobject]@{ Name = 'ZoomVideoApps'; FullName = 'C:\Users\alice\AppData\Roaming\ZoomVideoApps' }
                [pscustomobject]@{ Name = 'Windows Zoom Helper'; FullName = 'C:\Users\alice\AppData\Roaming\Windows Zoom Helper' }
                [pscustomobject]@{ Name = 'Contoso'; FullName = 'C:\Users\alice\AppData\Roaming\Contoso' }
            }
            Mock Get-ChildItem -ParameterFilter { "$LiteralPath" -eq 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE' } {
                [pscustomobject]@{ PSChildName = 'ZoomPlugins' }
                [pscustomobject]@{ PSChildName = 'Microsoft Zoom' }
                [pscustomobject]@{ PSChildName = 'Microsoft' }
            }
        }

        It 'finds folders and keys whose name contains the text, never protected ones' {
            $paths = @(Find-WTProgramResidue -Program (New-FakeProgram -DisplayName 'Zoom' -Publisher '' -RegistryKey '') -Partial | ForEach-Object { $_.Path })
            $paths | Should -Contain 'C:\Users\alice\AppData\Roaming\ZoomVideoApps'
            $paths | Should -Contain 'HKEY_LOCAL_MACHINE\SOFTWARE\ZoomPlugins'
            $paths | Should -Not -Contain 'C:\Users\alice\AppData\Roaming\Windows Zoom Helper'
            $paths | Should -Not -Contain 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft Zoom'
            $paths | Should -Not -Contain 'C:\Users\alice\AppData\Roaming\Contoso'
        }

        It 'skips a name shorter than 4 letters' {
            $found = @(Find-WTProgramResidue -Program (New-FakeProgram -DisplayName 'Zoo' -Publisher '' -RegistryKey '') -Partial)
            $found.Count | Should -Be 0
            Should -Invoke Get-ChildItem -Times 0 -Exactly -ParameterFilter { $Directory }
        }

        It 'is off unless asked' {
            $found = @(Find-WTProgramResidue -Program (New-FakeProgram -DisplayName 'Zoom' -Publisher '' -RegistryKey ''))
            $found.Count | Should -Be 0
        }
    }
}

Describe 'Remove-WTResidue' {
    BeforeEach {
        $global:WTPesterOrder = New-Object Collections.Generic.List[string]
        Mock Write-WTLog { }
        Mock Remove-WTFolder { [void]$global:WTPesterOrder.Add("Folder|$Path"); $true }
        Mock Remove-WTRegistryKey { [void]$global:WTPesterOrder.Add("Registry|$Key"); $true }
        Mock Remove-Item { [void]$global:WTPesterOrder.Add("Shortcut|$LiteralPath") }
        Mock Unregister-ScheduledTask { [void]$global:WTPesterOrder.Add("Task|$TaskPath$TaskName") }
        Mock Stop-Service { }
        Mock Stop-Process { }
        Mock Start-Sleep { }
        Mock Get-Process { @() }
        Mock Test-Path { $false }
    }
    AfterEach {
        Remove-Variable -Name WTPesterOrder -Scope Global -ErrorAction SilentlyContinue
    }

    It 'with -Simulate deletes nothing and returns every item' {
        $items = @(
            (New-FakeResidue 'Service' 'ContosoSvc'), (New-FakeResidue 'Scheduled task' '\Contoso\Updater'),
            (New-FakeResidue 'Shortcut' 'C:\Users\Public\Desktop\Contoso.lnk'), (New-FakeResidue 'Folder' "$env:ProgramFiles\Contoso Widget"),
            (New-FakeResidue 'Registry' 'HKEY_LOCAL_MACHINE\SOFTWARE\Contoso Widget')
        )
        $left = @(Remove-WTResidue -InputObject $items -Simulate)
        $left.Count | Should -Be 5
        Should -Invoke Stop-Service -Times 0 -Exactly
        Should -Invoke Unregister-ScheduledTask -Times 0 -Exactly
        Should -Invoke Remove-Item -Times 0 -Exactly
        Should -Invoke Stop-Process -Times 0 -Exactly
        Should -Invoke Get-Process -Times 0 -Exactly
        Should -Invoke Remove-WTFolder -Times 1 -Exactly -ParameterFilter { $Simulate }
        Should -Invoke Remove-WTRegistryKey -Times 1 -Exactly -ParameterFilter { $Simulate }
        Should -Invoke Remove-WTFolder -Times 0 -Exactly -ParameterFilter { -not $Simulate }
        Should -Invoke Remove-WTRegistryKey -Times 0 -Exactly -ParameterFilter { -not $Simulate }
    }

    It 'deletes tasks, shortcuts, folders (deepest first) and finally the registry' {
        $items = @(
            (New-FakeResidue 'Registry' 'HKEY_LOCAL_MACHINE\SOFTWARE\Contoso Widget'),
            (New-FakeResidue 'Folder' "$env:ProgramFiles\Contoso"),
            (New-FakeResidue 'Shortcut' 'C:\Users\Public\Desktop\Contoso.lnk'),
            (New-FakeResidue 'Folder' "$env:ProgramFiles\Contoso\Contoso Widget"),
            (New-FakeResidue 'Scheduled task' '\Contoso\Updater')
        )
        $left = @(Remove-WTResidue -InputObject $items)
        $left.Count | Should -Be 0
        ($global:WTPesterOrder -join ' > ') | Should -Be (@(
                'Task|\Contoso\Updater', 'Shortcut|C:\Users\Public\Desktop\Contoso.lnk',
                "Folder|$env:ProgramFiles\Contoso\Contoso Widget", "Folder|$env:ProgramFiles\Contoso",
                'Registry|HKEY_LOCAL_MACHINE\SOFTWARE\Contoso Widget') -join ' > ')
    }

    It 'goes through Remove-WTFolder and Remove-WTRegistryKey, which hold the protections and the .reg backup' {
        Remove-WTResidue -InputObject @((New-FakeResidue 'Folder' "$env:ProgramFiles\Contoso Widget"), (New-FakeResidue 'Registry' 'HKEY_CURRENT_USER\Software\Contoso')) | Out-Null
        Should -Invoke Remove-WTFolder -Times 1 -Exactly -ParameterFilter { $Path -eq "$env:ProgramFiles\Contoso Widget" -and -not $AllowProfileRoot }
        Should -Invoke Remove-WTRegistryKey -Times 1 -Exactly -ParameterFilter { $Key -eq 'HKEY_CURRENT_USER\Software\Contoso' }
        Should -Invoke Remove-Item -Times 0 -Exactly
    }

    It 'returns the items it could not delete' {
        Mock Remove-WTFolder { $false }
        $left = @(Remove-WTResidue -InputObject @((New-FakeResidue 'Folder' "$env:ProgramFiles\Contoso Widget"), (New-FakeResidue 'Registry' 'HKEY_CURRENT_USER\Software\Contoso')))
        $left.Count | Should -Be 1
        $left[0].Path | Should -Be "$env:ProgramFiles\Contoso Widget"
    }

    It 'closes only the processes that run from inside the folder' {
        Mock Get-Process {
            [pscustomobject]@{ ProcessName = 'widget'; Id = 101; Path = "$env:ProgramFiles\Contoso Widget\widget.exe" }
            [pscustomobject]@{ ProcessName = 'widgetpro'; Id = 102; Path = "$env:ProgramFiles\Contoso Widget Pro\widgetpro.exe" }
            [pscustomobject]@{ ProcessName = 'explorer'; Id = 103; Path = "$env:windir\explorer.exe" }
            [pscustomobject]@{ ProcessName = 'System'; Id = 4; Path = $null }
        }
        Remove-WTResidue -InputObject @(New-FakeResidue 'Folder' "$env:ProgramFiles\Contoso Widget") | Out-Null
        Should -Invoke Stop-Process -Times 1 -Exactly
        Should -Invoke Stop-Process -Times 1 -Exactly -ParameterFilter { $Id -eq 101 }
    }
}

Describe 'Invoke-WTProgramRemoval' {
    BeforeEach {
        Mock Write-WTLog { }
        Mock Find-WTProgramResidue { New-FakeResidue 'Folder' "$env:ProgramFiles\Contoso Widget" }
        Mock Complete-WTResidueCleanup { }
        Mock Remove-WTResidue { }
        Mock Remove-WTFolder { $true }
    }

    It 'deletes no leftover when the uninstall did not complete, and returns them for review' {
        Mock Uninstall-WTProgram { [pscustomobject]@{ Program = 'Contoso Widget'; ExitCode = 1603; Success = $false } }
        $r = @(Invoke-WTProgramRemoval -Program (New-FakeProgram))
        Should -Invoke Complete-WTResidueCleanup -Times 0 -Exactly
        Should -Invoke Remove-WTResidue -Times 0 -Exactly
        Should -Invoke Remove-WTFolder -Times 0 -Exactly
        $r.Count | Should -Be 1
        $r[0].Path | Should -Be "$env:ProgramFiles\Contoso Widget"
    }

    It 'cleans up the leftovers after a completed uninstall, passing -Simulate on' {
        Mock Uninstall-WTProgram { [pscustomobject]@{ Program = 'Contoso Widget'; ExitCode = 0; Success = $true } }
        Invoke-WTProgramRemoval -Program (New-FakeProgram) -Simulate | Out-Null
        Should -Invoke Complete-WTResidueCleanup -Times 1 -Exactly -ParameterFilter { $Simulate -and @($InputObject).Count -eq 1 -and -not $RestartReason }
    }

    It 'asks for a restart when the uninstaller did (exit code <Code>)' -TestCases @(@{ Code = 3010 }, @{ Code = 1641 }) {
        Mock Uninstall-WTProgram { [pscustomobject]@{ Program = 'Contoso Widget'; ExitCode = $Code; Success = $true } }
        Invoke-WTProgramRemoval -Program (New-FakeProgram) | Out-Null
        Should -Invoke Complete-WTResidueCleanup -Times 1 -Exactly -ParameterFilter { @($RestartReason).Count -eq 1 }
    }
}
