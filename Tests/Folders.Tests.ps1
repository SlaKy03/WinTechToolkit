# Remove-WTFolder and the checks behind it: the last line of defense of every folder deletion.
# Test-Path, the profile list and the log are mocked: nothing outside TestDrive is touched.
#   Invoke-Pester .\Tests   (Pester 5, see Build\Test-Pester.ps1)

BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'Module\WinTechToolkit.psm1') -Force -DisableNameChecking
    $PSDefaultParameterValues['Mock:ModuleName'] = 'WinTechToolkit'
    $PSDefaultParameterValues['Should:ModuleName'] = 'WinTechToolkit'
    $PSDefaultParameterValues['InModuleScope:ModuleName'] = 'WinTechToolkit'
    $global:WTLanguage = 'en'
    $global:WTQueue = $null
}

Describe 'Test-WTProtectedName' {
    It 'protects <Name>' -TestCases @(
        @{ Name = 'Microsoft' }, @{ Name = 'Windows' }, @{ Name = 'Common Files' }, @{ Name = 'WindowsApps' },
        @{ Name = 'Users' }, @{ Name = 'Documents' }, @{ Name = 'Temp' }, @{ Name = 'Data' },
        @{ Name = 'Microsoft Teams' }, @{ Name = 'Windows Something New' }, @{ Name = '' }, @{ Name = '   ' }
    ) {
        Test-WTProtectedName $Name | Should -BeTrue
    }

    It 'does not protect <Name>' -TestCases @(@{ Name = 'ZoomVideoApps' }, @{ Name = 'Contoso Widget' }, @{ Name = 'WindowsXYZ' }) {
        Test-WTProtectedName $Name | Should -BeFalse
    }
}

Describe 'Test-WTProtectedPath' {
    BeforeAll {
        $profiles = @('C:\Users\alice', 'C:\Users\bob')
    }
    BeforeEach {
        Mock Get-WTProfilesDirectory { 'C:\Users' }
    }

    It 'protects system folders: <Path>' -TestCases @(
        @{ Path = $env:windir }, @{ Path = "$env:windir\System32" }, @{ Path = "$env:windir\Temp\Contoso" },
        @{ Path = $env:ProgramFiles }, @{ Path = $env:ProgramData }, @{ Path = 'C:\Users' }, @{ Path = 'C:\' }, @{ Path = '' }
    ) {
        Test-WTProtectedPath -Path $Path -ProfileFolders $profiles | Should -BeTrue
    }

    It 'protects the profile folder and its personal folders: <Path>' -TestCases @(
        @{ Path = 'C:\Users\alice' }, @{ Path = 'C:\Users\alice\' }, @{ Path = 'C:\Users\alice\AppData' },
        @{ Path = 'C:\Users\alice\AppData\Roaming' }, @{ Path = 'C:\Users\bob\AppData\Local' },
        @{ Path = 'C:\Users\bob\AppData\Local\Programs' }, @{ Path = 'C:\Users\bob\Desktop' },
        @{ Path = 'C:\Users\bob\Documents' }, @{ Path = 'C:\Users\bob\Downloads' }
    ) {
        Test-WTProtectedPath -Path $Path -ProfileFolders $profiles | Should -BeTrue
    }

    It 'protects a folder with a generic name: <Path>' -TestCases @(
        @{ Path = "$env:ProgramFiles\Common Files" }, @{ Path = 'C:\Users\alice\AppData\Local\Microsoft' },
        @{ Path = 'C:\Users\alice\AppData\Local\Temp' }, @{ Path = "$env:ProgramData\Packages" }
    ) {
        Test-WTProtectedPath -Path $Path -ProfileFolders $profiles | Should -BeTrue
    }

    It 'protects the folder the toolkit runs from' {
        $toolkit = InModuleScope -ScriptBlock { $script:WTToolkitRoot }
        Test-WTProtectedPath -Path $toolkit -ProfileFolders $profiles | Should -BeTrue
    }

    It 'allows the folder of an application: <Path>' -TestCases @(
        @{ Path = 'C:\Users\alice\AppData\Local\Contoso Widget' }, @{ Path = "$env:ProgramFiles\Contoso Widget" }
    ) {
        Test-WTProtectedPath -Path $Path -ProfileFolders $profiles | Should -BeFalse
    }
}

Describe 'Remove-WTFolder' {
    BeforeEach {
        Mock Get-WTProfilesDirectory { 'C:\Users' }
        Mock Get-WTProfileFolders { @('C:\Users\alice', 'C:\Users\bob') }
        Mock Write-WTLog { }
    }

    Context 'refuses protected folders before touching anything' {
        BeforeEach {
            # every path "exists": a refusal must come from the protections, not from a missing folder
            Mock Test-Path { $true }
            Mock Get-Item { throw 'Get-Item reached: the folder was about to be deleted' }
        }

        It 'refuses <Path>' -TestCases @(
            @{ Path = 'C:\' }, @{ Path = 'C:' }, @{ Path = 'D:\' },
            @{ Path = $env:windir }, @{ Path = "$env:windir\" }, @{ Path = "$env:windir\System32" }, @{ Path = "$env:windir\SysWOW64" },
            @{ Path = $env:ProgramFiles }, @{ Path = ${env:ProgramFiles(x86)} }, @{ Path = $env:ProgramData },
            @{ Path = "$env:ProgramFiles\Common Files" }, @{ Path = 'C:\Users' }, @{ Path = $env:PUBLIC }
        ) {
            Remove-WTFolder -Path $Path | Should -BeFalse
            Should -Invoke Get-Item -Times 0 -Exactly
            Should -Invoke Write-WTLog -ParameterFilter { $Level -eq 'Error' } -Times 1 -Exactly
        }

        It 'refuses the personal folder <Path>, even with -AllowProfileRoot' -TestCases @(
            @{ Path = 'C:\Users\alice\Documents' }, @{ Path = 'C:\Users\alice\Desktop' }, @{ Path = 'C:\Users\alice\Downloads' },
            @{ Path = 'C:\Users\alice\Pictures' }, @{ Path = 'C:\Users\alice\Music' }, @{ Path = 'C:\Users\alice\Videos' },
            @{ Path = 'C:\Users\alice\OneDrive' }, @{ Path = 'C:\Users\alice\AppData' }, @{ Path = 'C:\Users\bob\AppData\Local' },
            @{ Path = 'C:\Users\bob\AppData\LocalLow' }, @{ Path = 'C:\Users\bob\AppData\Roaming' }, @{ Path = 'C:\Users\bob\AppData\Local\Programs' },
            @{ Path = 'c:\users\ALICE\documents' }, @{ Path = 'C:\Users\alice\Documents\' }
        ) {
            Remove-WTFolder -Path $Path | Should -BeFalse
            Remove-WTFolder -Path $Path -AllowProfileRoot | Should -BeFalse
            Should -Invoke Get-Item -Times 0 -Exactly
        }

        It 'refuses a whole profile folder without -AllowProfileRoot' {
            Remove-WTFolder -Path 'C:\Users\alice' | Should -BeFalse
            Remove-WTFolder -Path 'C:\Users\alice\' -Simulate | Should -BeFalse
            Should -Invoke Get-Item -Times 0 -Exactly
        }

        It 'refuses the profile Windows uses for itself: <Name>, even with -AllowProfileRoot' -TestCases @(
            @{ Name = 'defaultuser0' }, @{ Name = 'defaultuser100000' }, @{ Name = 'WsiAccount' }
        ) {
            Remove-WTFolder -Path "C:\Users\$Name" -AllowProfileRoot | Should -BeFalse
            Should -Invoke Get-Item -Times 0 -Exactly
        }

        It 'refuses the folder the toolkit runs from, its parent and its subfolders' {
            $toolkit = InModuleScope -ScriptBlock { $script:WTToolkitRoot }
            Remove-WTFolder -Path $toolkit | Should -BeFalse
            Remove-WTFolder -Path (Split-Path $toolkit -Parent) | Should -BeFalse
            Remove-WTFolder -Path (Join-Path $toolkit 'Module') | Should -BeFalse
            Should -Invoke Get-Item -Times 0 -Exactly
        }

        It 'refuses another running copy in a Temp folder' {
            Remove-WTFolder -Path 'C:\Users\alice\AppData\Local\Temp\WinTechToolkit_0123456789' | Should -BeFalse
            Should -Invoke Get-Item -Times 0 -Exactly
        }

        It 'refuses <Path>: it is a protected folder written another way' -TestCases @(
            @{ Path = 'C:\Users\alice\Documents\..' }, @{ Path = 'C:\Users\alice\Documents\..\' },
            @{ Path = 'C:\Users\alice\Desktop\..\Documents' }, @{ Path = 'C:\Users\alice\.\Documents' },
            @{ Path = 'C:/Users/alice/Documents' }, @{ Path = 'C:\Users\\alice\Documents' },
            @{ Path = 'C:\Program Files\Contoso\..\..\Windows' }, @{ Path = 'C:\Windows\.' }, @{ Path = 'C:\Windows\System32\..' },
            @{ Path = 'C:\Users\defaultuser0\Desktop\..' }
        ) {
            Remove-WTFolder -Path $Path | Should -BeFalse
            Should -Invoke Get-Item -Times 0 -Exactly
        }

        It 'refuses a path that is not a full local path: <Path>' -TestCases @(
            @{ Path = 'Windows' }, @{ Path = '..\..' }, @{ Path = '.' }, @{ Path = 'C:Windows' },
            @{ Path = '\Windows' }, @{ Path = '\\server\share\folder' }, @{ Path = '\\?\C:\Windows' }, @{ Path = '\\.\C:\Windows' }
        ) {
            Remove-WTFolder -Path $Path | Should -BeFalse
            Remove-WTFolder -Path $Path -AllowProfileRoot | Should -BeFalse
            Should -Invoke Get-Item -Times 0 -Exactly
        }

        It 'refuses a personal folder written in 8.3 form (C:\Users\ALICE~1\Documents)' {
            Mock ConvertTo-WTLongPath { if ($Path -eq 'C:\Users\ALICE~1\Documents') { 'C:\Users\alice\Documents' } else { $Path } }
            Remove-WTFolder -Path 'C:\Users\ALICE~1\Documents' | Should -BeFalse
            Should -Invoke Get-Item -Times 0 -Exactly
        }
    }

    Context 'with -Simulate' {
        BeforeEach {
            Mock Test-Path { $true }
            Mock Get-Item { throw 'Get-Item reached in a simulation' }
        }

        It 'accepts the folder of an application and deletes nothing' {
            Remove-WTFolder -Path "$env:ProgramFiles\Contoso Widget" -Simulate | Should -BeTrue
            Should -Invoke Get-Item -Times 0 -Exactly
            Should -Invoke Write-WTLog -ParameterFilter { $Message -like '*SIMULATION*Contoso Widget*' } -Times 1 -Exactly
        }

        It 'accepts a whole profile folder only with -AllowProfileRoot' {
            Remove-WTFolder -Path 'C:\Users\alice' -Simulate -AllowProfileRoot | Should -BeTrue
            Should -Invoke Get-Item -Times 0 -Exactly
        }

        It 'works on the normalized path' {
            Remove-WTFolder -Path "$env:ProgramFiles\Contoso\..\Contoso Widget\" -Simulate | Should -BeTrue
            Should -Invoke Write-WTLog -ParameterFilter { $Message -like "*: $env:ProgramFiles\Contoso Widget" } -Times 1 -Exactly
        }
    }

    It 'returns $true without deleting when the folder does not exist' {
        Mock Test-Path { $false }
        Mock Get-Item { throw 'Get-Item reached for a missing folder' }
        Remove-WTFolder -Path "$env:ProgramFiles\Contoso Widget" | Should -BeTrue
        Should -Invoke Get-Item -Times 0 -Exactly
    }

    Context 'real deletion inside TestDrive' {
        It 'deletes the folder with its content and leaves a sibling folder alone' {
            $target = Join-Path $TestDrive 'ContosoApp'
            $sibling = Join-Path $TestDrive 'ContosoApp_Sibling'
            New-Item -ItemType Directory -Path (Join-Path $target 'sub'), $sibling -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $target 'sub\a.txt') -Value 'x'
            Set-Content -LiteralPath (Join-Path $sibling 'keep.txt') -Value 'x'

            Remove-WTFolder -Path $target | Should -BeTrue
            Test-Path -LiteralPath $target | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $sibling 'keep.txt') | Should -BeTrue
        }

        It 'removes only the link of a junction, never the files it points to' {
            $data = Join-Path $TestDrive 'RealData'
            $link = Join-Path $TestDrive 'ContosoLink'
            New-Item -ItemType Directory -Path $data -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $data 'keep.txt') -Value 'x'
            New-Item -ItemType Junction -Path $link -Value $data | Out-Null

            Remove-WTFolder -Path $link | Should -BeTrue
            Test-Path -LiteralPath $link | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $data 'keep.txt') | Should -BeTrue
        }

        It 'deletes the content of a folder but not the files behind a junction inside it' {
            $data = Join-Path $TestDrive 'OtherData'
            $target = Join-Path $TestDrive 'ContosoWithLink'
            New-Item -ItemType Directory -Path $data, $target -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $data 'keep.txt') -Value 'x'
            New-Item -ItemType Junction -Path (Join-Path $target 'link') -Value $data | Out-Null

            Remove-WTFolder -Path $target | Should -BeTrue
            Test-Path -LiteralPath $target | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $data 'keep.txt') | Should -BeTrue
        }
    }
}

Describe 'Register-WTDeleteAtReboot' {
    BeforeEach {
        Mock Get-WTProfilesDirectory { 'C:\Users' }
        Mock Get-WTProfileFolders { @('C:\Users\alice') }
        Mock Write-WTLog { }
        Mock Test-Path { $true }
    }

    It 'refuses <Path>' -TestCases @(
        @{ Path = $env:windir }, @{ Path = $env:ProgramFiles }, @{ Path = 'C:\Users\alice' }, @{ Path = 'C:\Users\alice\Documents' },
        @{ Path = 'C:\Users\alice\Documents\..' }, @{ Path = 'C:\Users\defaultuser0' }, @{ Path = '\\server\share' }
    ) {
        Register-WTDeleteAtReboot -Path $Path | Should -BeFalse
        Should -Invoke Write-WTLog -ParameterFilter { $Level -eq 'Error' } -Times 1 -Exactly
    }

    It 'schedules nothing for a folder that is already gone' {
        Mock Test-Path { $false }
        Register-WTDeleteAtReboot -Path "$env:ProgramFiles\Contoso Widget" | Should -BeTrue
        Should -Invoke Write-WTLog -Times 0 -Exactly
    }
}
