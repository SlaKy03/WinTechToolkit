# Deletion of registry keys: Remove-WTRegistryKey exports a .reg backup before deleting.
# Test-Path, the backup and Remove-Item are mocked: no key is read or deleted.
#   Invoke-Pester .\Tests   (Pester 5, see Build\Test-Pester.ps1)

BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'Module\WinTechToolkit.psm1') -Force -DisableNameChecking
    $PSDefaultParameterValues['Mock:ModuleName'] = 'WinTechToolkit'
    $PSDefaultParameterValues['Should:ModuleName'] = 'WinTechToolkit'
    $PSDefaultParameterValues['InModuleScope:ModuleName'] = 'WinTechToolkit'
    $global:WTLanguage = 'en'
    $global:WTQueue = $null
    $key = 'HKEY_CURRENT_USER\Software\Contoso Widget'
}

Describe 'Remove-WTRegistryKey' {
    BeforeEach {
        $global:WTPesterOrder = New-Object Collections.Generic.List[string]
        Mock Write-WTLog { }
        Mock Test-Path { $true }
        Mock Backup-WTRegistryKey { [void]$global:WTPesterOrder.Add('backup'); 'C:\ProgramData\WinTechToolkit\Backup\20260101\x.reg' }
        Mock Remove-Item { [void]$global:WTPesterOrder.Add('delete') }
    }
    AfterEach {
        Remove-Variable -Name WTPesterOrder -Scope Global -ErrorAction SilentlyContinue
    }

    It 'does nothing for a key that does not exist' {
        Mock Test-Path { $false }
        Remove-WTRegistryKey -Key $key | Should -BeTrue
        Should -Invoke Backup-WTRegistryKey -Times 0 -Exactly
        Should -Invoke Remove-Item -Times 0 -Exactly
    }

    It 'with -Simulate neither backs up nor deletes' {
        Remove-WTRegistryKey -Key $key -Simulate | Should -BeTrue
        Should -Invoke Backup-WTRegistryKey -Times 0 -Exactly
        Should -Invoke Remove-Item -Times 0 -Exactly
        Should -Invoke Write-WTLog -Times 1 -Exactly -ParameterFilter { $Message -like '*SIMULATION*Contoso Widget' }
    }

    It 'exports the .reg backup before deleting the key' {
        Remove-WTRegistryKey -Key $key | Should -BeTrue
        ($global:WTPesterOrder -join ' > ') | Should -Be 'backup > delete'
        Should -Invoke Backup-WTRegistryKey -Times 1 -Exactly -ParameterFilter { $Key -eq 'HKEY_CURRENT_USER\Software\Contoso Widget' }
    }

    It 'deletes exactly that key, with its subkeys, through the Registry provider' {
        Remove-WTRegistryKey -Key $key | Out-Null
        Should -Invoke Remove-Item -Times 1 -Exactly -ParameterFilter {
            "$LiteralPath" -eq 'Registry::HKEY_CURRENT_USER\Software\Contoso Widget' -and $Recurse -and -not $Path
        }
        Should -Invoke Write-WTLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'OK' -and $Message -like '*backup: x.reg*' }
    }

    It 'returns $false and logs the error when the key cannot be deleted' {
        Mock Remove-Item { throw 'Access denied' }
        Remove-WTRegistryKey -Key $key | Should -BeFalse
        Should -Invoke Write-WTLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'Error' -and $Message -like '*Access denied*' }
    }
}
