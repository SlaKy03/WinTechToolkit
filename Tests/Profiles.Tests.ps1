# Deletion of user profiles: which profiles are protected, what Remove-WTUserProfile deletes and
# which registry keys go with a profile. WMI, the registry and the deletions are mocked.
#   Invoke-Pester .\Tests   (Pester 5, see Build\Test-Pester.ps1)

BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'Module\WinTechToolkit.psm1') -Force -DisableNameChecking
    $PSDefaultParameterValues['Mock:ModuleName'] = 'WinTechToolkit'
    $PSDefaultParameterValues['Should:ModuleName'] = 'WinTechToolkit'
    $PSDefaultParameterValues['InModuleScope:ModuleName'] = 'WinTechToolkit'
    $global:WTLanguage = 'en'
    $global:WTQueue = $null

    $alice = 'S-1-5-21-1000-2000-3000-1001'
    $bob = 'S-1-5-21-1000-2000-3000-1002'

    # An object as returned by Get-WTUserProfile
    function New-FakeProfile {
        param([string]$Type = 'Profile', [string]$UserName = 'PC01\alice', [string]$Sid = 'S-1-5-21-1000-2000-3000-1001',
            [string]$Path = 'C:\Users\alice', [bool]$Protected = $false, [string]$ProtectReason = '')
        [pscustomobject]@{
            Type = $Type; TypeText = $Type; UserName = $UserName; SID = $Sid; KeyName = $Sid; Path = $Path
            Loaded = $false; Protected = $Protected; ProtectReason = $ProtectReason
        }
    }
}

Describe 'Test-WTSystemProfileName' {
    It 'recognizes the profile Windows uses for itself: <Name>' -TestCases @(
        @{ Name = 'defaultuser0' }, @{ Name = 'defaultuser100000' }, @{ Name = 'PC01\defaultuser0' }, @{ Name = 'WsiAccount' }
    ) {
        Test-WTSystemProfileName $Name | Should -BeTrue
    }

    It 'does not flag a normal account: <Name>' -TestCases @(
        @{ Name = 'mario.rossi' }, @{ Name = 'defaultuser' }, @{ Name = 'defaultuserX' }, @{ Name = 'Administrator' }, @{ Name = '' }
    ) {
        Test-WTSystemProfileName $Name | Should -BeFalse
    }
}

Describe 'Get-WTUserProfile' {
    BeforeAll {
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    }
    BeforeEach {
        Mock Get-WTProfilesDirectory { 'C:\Users' }
        Mock Resolve-WTSidName { $null }
        Mock Test-Path { $true }
        Mock Get-Item { [pscustomobject]@{ LastWriteTime = (Get-Date).AddDays(-3) } }
        # ProfileList: PSPath is the profile folder, so Get-ItemProperty can return it as ProfileImagePath
        Mock Get-ChildItem -ParameterFilter { "$Path" -like '*\ProfileList' } {
            $current = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            [pscustomobject]@{ PSChildName = $current; PSPath = 'C:\Users\me' }
            [pscustomobject]@{ PSChildName = 'S-1-5-21-1000-2000-3000-1002'; PSPath = 'C:\Users\bob' }
            [pscustomobject]@{ PSChildName = 'S-1-5-21-1000-2000-3000-1003'; PSPath = 'C:\Users\special' }
            [pscustomobject]@{ PSChildName = 'S-1-5-21-1000-2000-3000-1004'; PSPath = 'D:\Profiles\carol' }
            [pscustomobject]@{ PSChildName = 'S-1-5-21-1000-2000-3000-1005'; PSPath = 'C:\Users\dave' }
            [pscustomobject]@{ PSChildName = 'S-1-5-21-1000-2000-3000-1006'; PSPath = 'C:\Users\defaultuser0' }
            [pscustomobject]@{ PSChildName = 'S-1-5-21-1000-2000-3000-1007.bak'; PSPath = 'C:\Users\erin' }
            [pscustomobject]@{ PSChildName = 'S-1-5-18'; PSPath = 'C:\Windows\system32\config\systemprofile' }
        }
        Mock Get-ItemProperty { [pscustomobject]@{ ProfileImagePath = "$LiteralPath" } }
        Mock Get-CimInstance {
            [pscustomobject]@{ SID = 'S-1-5-21-1000-2000-3000-1002'; Loaded = $true; Special = $false; LastUseTime = Get-Date }
            [pscustomobject]@{ SID = 'S-1-5-21-1000-2000-3000-1003'; Loaded = $false; Special = $true; LastUseTime = Get-Date }
            [pscustomobject]@{ SID = 'S-1-5-21-1000-2000-3000-1005'; Loaded = $false; Special = $false; LastUseTime = (Get-Date).AddDays(-90) }
        }
        # Folders in C:\Users
        Mock Get-ChildItem -ParameterFilter { "$LiteralPath" -eq 'C:\Users' } {
            $dir = [IO.FileAttributes]::Directory
            foreach ($n in 'me', 'bob', 'dave', 'Public', 'Default', 'defaultuser100000', 'frank') {
                [pscustomobject]@{ Name = $n; FullName = "C:\Users\$n"; Attributes = $dir; LastWriteTime = Get-Date }
            }
            [pscustomobject]@{ Name = 'junction'; FullName = 'C:\Users\junction'; Attributes = $dir -bor [IO.FileAttributes]::ReparsePoint; LastWriteTime = Get-Date }
        }
        $list = @(Get-WTUserProfile)
    }

    It 'never lists the profiles Windows uses for itself or the system accounts' {
        @($list | Where-Object { $_.Path -like '*defaultuser*' }).Count | Should -Be 0
        @($list | Where-Object { $_.SID -eq 'S-1-5-18' -or $_.Path -like 'C:\Windows*' }).Count | Should -Be 0
    }

    It 'protects the account running the toolkit' {
        $p = @($list | Where-Object { $_.SID -eq $me })
        $p.Count | Should -Be 1
        $p[0].Protected | Should -BeTrue
    }

    It 'protects a loaded profile (user signed in)' {
        $p = $list | Where-Object { $_.SID -eq $bob }
        $p.Loaded | Should -BeTrue
        $p.Protected | Should -BeTrue
    }

    It 'protects a system profile' {
        ($list | Where-Object { $_.Path -eq 'C:\Users\special' }).Protected | Should -BeTrue
    }

    It 'protects a profile outside the profiles folder' {
        ($list | Where-Object { $_.Path -eq 'D:\Profiles\carol' }).Protected | Should -BeTrue
    }

    It 'does not protect a profile that is not in use' {
        $p = $list | Where-Object { $_.Path -eq 'C:\Users\dave' }
        $p.Protected | Should -BeFalse
        $p.DaysUnused | Should -BeGreaterOrEqual 89
    }

    It 'lists a .bak key as such' {
        ($list | Where-Object { $_.Path -eq 'C:\Users\erin' }).Type | Should -Be 'Backup .bak'
    }

    It 'lists as orphan only a real folder that no profile uses' {
        $orphans = @($list | Where-Object { $_.Type -eq 'Orphan folder' })
        $orphans.Count | Should -Be 1
        $orphans[0].Path | Should -Be 'C:\Users\frank'
    }

    It 'leaves nothing unprotected outside the profiles folder' {
        @($list | Where-Object { -not $_.Protected -and -not $_.Path.StartsWith('C:\Users\', [StringComparison]::OrdinalIgnoreCase) }).Count | Should -Be 0
    }
}

Describe 'Remove-WTUserProfile' {
    BeforeEach {
        Mock Get-WTProfilesDirectory { 'C:\Users' }
        Mock Write-WTLog { }
        Mock Remove-WTFolder { $true }
        Mock Remove-WTProfileRegistryResidue { }
        Mock Remove-CimInstance { } -RemoveParameterType InputObject
        Mock Get-CimInstance { [pscustomobject]@{ SID = 'S-1-5-21-1000-2000-3000-1001'; Loaded = $false } }
        Mock Get-ChildItem -ParameterFilter { "$Path" -like '*\ProfileList' } {
            [pscustomobject]@{ PSChildName = 'S-1-5-21-1000-2000-3000-1001'; PSPath = 'C:\Users\alice' }
            [pscustomobject]@{ PSChildName = 'S-1-5-21-1000-2000-3000-1001.bak'; PSPath = 'C:\Users\alice.PC01' }
            [pscustomobject]@{ PSChildName = 'S-1-5-21-1000-2000-3000-1002'; PSPath = 'C:\Users\bob' }
        }
        Mock Get-ItemProperty { [pscustomobject]@{ ProfileImagePath = "$LiteralPath" } }
    }

    It 'deletes nothing for a protected profile' {
        Remove-WTUserProfile -InputObject (New-FakeProfile -Protected $true -ProtectReason 'Profile loaded (user signed in)')
        Should -Invoke Remove-WTFolder -Times 0 -Exactly
        Should -Invoke Remove-WTProfileRegistryResidue -Times 0 -Exactly
        Should -Invoke Remove-CimInstance -Times 0 -Exactly
    }

    It 'deletes nothing for the Windows profile <UserName> [<Path>] even if it is not marked as protected' -TestCases @(
        @{ UserName = 'PC01\defaultuser0'; Path = 'C:\Users\defaultuser0' },
        @{ UserName = '(unresolved) x'; Path = 'C:\Users\defaultuser100000' },
        @{ UserName = 'PC01\WsiAccount'; Path = 'C:\Users\someone' }
    ) {
        Remove-WTUserProfile -InputObject (New-FakeProfile -UserName $UserName -Path $Path)
        Should -Invoke Remove-WTFolder -Times 0 -Exactly
        Should -Invoke Remove-WTProfileRegistryResidue -Times 0 -Exactly
        Should -Invoke Remove-CimInstance -Times 0 -Exactly
    }

    It 'deletes nothing when WMI says the profile is loaded at the time of the deletion' {
        Mock Get-CimInstance { [pscustomobject]@{ SID = 'S-1-5-21-1000-2000-3000-1001'; Loaded = $true } }
        Remove-WTUserProfile -InputObject (New-FakeProfile)
        Should -Invoke Remove-WTFolder -Times 0 -Exactly
        Should -Invoke Remove-WTProfileRegistryResidue -Times 0 -Exactly
        Should -Invoke Remove-CimInstance -Times 0 -Exactly
    }

    It 'with -Simulate goes through every step without deleting' {
        Remove-WTUserProfile -InputObject (New-FakeProfile) -Simulate
        Should -Invoke Remove-CimInstance -Times 0 -Exactly
        Should -Invoke Remove-WTFolder -Times 1 -Exactly -ParameterFilter { $Path -eq 'C:\Users\alice' -and $Simulate -and $AllowProfileRoot }
        Should -Invoke Remove-WTFolder -Times 2 -Exactly -ParameterFilter { $Simulate }
        Should -Invoke Remove-WTFolder -Times 2 -Exactly
        Should -Invoke Remove-WTProfileRegistryResidue -Times 1 -Exactly -ParameterFilter {
            $Sid -eq 'S-1-5-21-1000-2000-3000-1001' -and $Simulate -and $IncludeSidKeys -and
            $KeyNames.Count -eq 2 -and $KeyNames -contains 'S-1-5-21-1000-2000-3000-1001' -and $KeyNames -contains 'S-1-5-21-1000-2000-3000-1001.bak'
        }
    }

    It 'deletes the WMI profile, the folder of the profile and of its .bak key, and the keys of the SID' {
        Remove-WTUserProfile -InputObject (New-FakeProfile)
        Should -Invoke Remove-CimInstance -Times 1 -Exactly
        Should -Invoke Remove-WTFolder -Times 1 -Exactly -ParameterFilter { $Path -eq 'C:\Users\alice' -and -not $Simulate -and $AllowProfileRoot }
        Should -Invoke Remove-WTFolder -Times 1 -Exactly -ParameterFilter { $Path -eq 'C:\Users\alice.PC01' -and $AllowProfileRoot }
        Should -Invoke Remove-WTFolder -Times 2 -Exactly
        Should -Invoke Remove-WTProfileRegistryResidue -Times 1 -Exactly -ParameterFilter { $IncludeSidKeys -and -not $Simulate }
    }

    It 'never deletes the folder of another profile (bob)' {
        Remove-WTUserProfile -InputObject (New-FakeProfile)
        Should -Invoke Remove-WTFolder -Times 0 -Exactly -ParameterFilter { $Path -like '*bob*' }
    }

    It 'keeps a folder that another profile key still points to' {
        Mock Get-ChildItem -ParameterFilter { "$Path" -like '*\ProfileList' } {
            [pscustomobject]@{ PSChildName = 'S-1-5-21-1000-2000-3000-1001'; PSPath = 'C:\Users\alice' }
            [pscustomobject]@{ PSChildName = 'S-1-5-21-1000-2000-3000-1009'; PSPath = 'C:\Users\alice' }
        }
        Remove-WTUserProfile -InputObject (New-FakeProfile)
        Should -Invoke Remove-WTFolder -Times 0 -Exactly
        Should -Invoke Remove-WTProfileRegistryResidue -Times 1 -Exactly
    }

    It 'keeps a folder outside the profiles folder (<Folder>)' -TestCases @(
        @{ Folder = 'D:\Profiles\alice' }, @{ Folder = 'C:\Windows\ServiceProfiles\alice' }, @{ Folder = 'C:\Users' }, @{ Folder = 'C:\UsersOld\alice' }
    ) {
        Mock Get-ChildItem -ParameterFilter { "$Path" -like '*\ProfileList' } {
            [pscustomobject]@{ PSChildName = 'S-1-5-21-1000-2000-3000-1001'; PSPath = $Folder }
        }
        Remove-WTUserProfile -InputObject (New-FakeProfile -Path $Folder)
        Should -Invoke Remove-WTFolder -Times 0 -Exactly
    }

    It 'for a .bak entry deletes only the .bak key and its folder, not the profile' {
        Remove-WTUserProfile -InputObject (New-FakeProfile -Type 'Backup .bak' -Path 'C:\Users\alice.PC01')
        Should -Invoke Remove-CimInstance -Times 0 -Exactly
        Should -Invoke Remove-WTFolder -Times 1 -Exactly -ParameterFilter { $Path -eq 'C:\Users\alice.PC01' }
        Should -Invoke Remove-WTFolder -Times 1 -Exactly
        Should -Invoke Remove-WTProfileRegistryResidue -Times 1 -Exactly -ParameterFilter {
            -not $IncludeSidKeys -and $KeyNames.Count -eq 1 -and $KeyNames[0] -eq 'S-1-5-21-1000-2000-3000-1001.bak'
        }
    }

    Context 'orphan folders' {
        It 'deletes an orphan folder in the profiles folder' {
            Remove-WTUserProfile -InputObject (New-FakeProfile -Type 'Orphan folder' -UserName 'frank' -Sid '' -Path 'C:\Users\frank') -Simulate
            Should -Invoke Remove-WTFolder -Times 1 -Exactly -ParameterFilter { $Path -eq 'C:\Users\frank' -and $Simulate -and $AllowProfileRoot }
            Should -Invoke Remove-WTProfileRegistryResidue -Times 0 -Exactly
            Should -Invoke Remove-CimInstance -Times 0 -Exactly
        }

        It 'deletes nothing for an orphan folder outside the profiles folder: <Path>' -TestCases @(
            @{ Path = 'D:\Old\frank' }, @{ Path = 'C:\Users' }, @{ Path = 'C:\UsersBackup\frank' }, @{ Path = 'C:\Windows' }
        ) {
            Remove-WTUserProfile -InputObject (New-FakeProfile -Type 'Orphan folder' -UserName 'frank' -Sid '' -Path $Path)
            Should -Invoke Remove-WTFolder -Times 0 -Exactly
        }
    }

    It 'processes the unprotected profiles of a list and skips the protected ones' {
        $items = @(
            (New-FakeProfile -UserName 'PC01\bob' -Sid 'S-1-5-21-1000-2000-3000-1002' -Path 'C:\Users\bob' -Protected $true -ProtectReason 'Account running the toolkit'),
            (New-FakeProfile)
        )
        Remove-WTUserProfile -InputObject $items -Simulate
        Should -Invoke Remove-WTFolder -Times 0 -Exactly -ParameterFilter { $Path -like '*bob*' }
        Should -Invoke Remove-WTProfileRegistryResidue -Times 1 -Exactly
        Should -Invoke Remove-WTProfileRegistryResidue -Times 0 -Exactly -ParameterFilter { $Sid -eq 'S-1-5-21-1000-2000-3000-1002' }
    }
}

Describe 'Remove-WTProfileRegistryResidue' {
    BeforeEach {
        $global:WTPesterKeys = New-Object Collections.Generic.List[string]
        Mock Remove-WTRegistryKey { [void]$global:WTPesterKeys.Add($Key); $true }
        Mock Test-Path { $true }
        Mock Get-ChildItem -ParameterFilter { "$Path" -like '*\ProfileGuid' } {
            [pscustomobject]@{ PSChildName = '{11111111-1111-1111-1111-111111111111}'; PSPath = 'guid-alice' }
            [pscustomobject]@{ PSChildName = '{22222222-2222-2222-2222-222222222222}'; PSPath = 'guid-bob' }
        }
        Mock Get-ItemProperty {
            if ("$LiteralPath" -eq 'guid-alice') { [pscustomobject]@{ SidString = 'S-1-5-21-1000-2000-3000-1001' } }
            else { [pscustomobject]@{ SidString = 'S-1-5-21-1000-2000-3000-1002' } }
        }
    }
    AfterEach {
        Remove-Variable -Name WTPesterKeys -Scope Global -ErrorAction SilentlyContinue
    }

    It 'deletes the keys of the SID and nothing else' {
        Remove-WTProfileRegistryResidue -Sid $alice -KeyNames $alice, "$alice.bak" -IncludeSidKeys
        $nt = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $cv = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion'
        $expected = @(
            "$nt\ProfileList\$alice", "$nt\ProfileList\$alice.bak",
            "$cv\Group Policy\State\$alice", "$cv\Group Policy\DataStore\$alice", "$cv\Group Policy\$alice",
            "$cv\Appx\AppxAllUserStore\$alice", "$nt\ProfileGuid\{11111111-1111-1111-1111-111111111111}"
        )
        (@($global:WTPesterKeys | Sort-Object) -join ' | ') | Should -Be (@($expected | Sort-Object) -join ' | ')
    }

    It 'never deletes the ProfileGuid key of another SID' {
        Remove-WTProfileRegistryResidue -Sid $alice -KeyNames $alice -IncludeSidKeys
        @($global:WTPesterKeys | Where-Object { $_ -like '*2222*' -or $_ -like "*$bob*" }).Count | Should -Be 0
    }

    It 'without -IncludeSidKeys deletes only the ProfileList keys it is given' {
        Remove-WTProfileRegistryResidue -Sid $alice -KeyNames "$alice.bak"
        ($global:WTPesterKeys -join ' | ') | Should -Be "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$alice.bak"
        Should -Invoke Get-ChildItem -Times 0 -Exactly -ParameterFilter { "$Path" -like '*\ProfileGuid' }
    }

    It 'skips the keys that do not exist' {
        Mock Test-Path { $false }
        Remove-WTProfileRegistryResidue -Sid $alice -KeyNames $alice, "$alice.bak" -IncludeSidKeys
        $global:WTPesterKeys.Count | Should -Be 0
    }

    It 'passes -Simulate on to every key' {
        Remove-WTProfileRegistryResidue -Sid $alice -KeyNames $alice -IncludeSidKeys -Simulate
        Should -Invoke Remove-WTRegistryKey -Times 0 -Exactly -ParameterFilter { -not $Simulate }
        Should -Invoke Remove-WTRegistryKey -Times 6 -Exactly
    }
}
