# WinTech Toolkit - main module.
# The functions live in Functions\*.ps1 and are all loaded in the same scope,
# so they can call each other, also inside the GUI runspaces.

$script:WTModuleRoot = $PSScriptRoot

# Other users' folders may deny access: Test-Path must return $false, not an error
$PSDefaultParameterValues = @{ 'Test-Path:ErrorAction' = 'SilentlyContinue' }

foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot 'Functions') -Filter '*.ps1' | Sort-Object Name) {
    . $file.FullName
}

Export-ModuleMember -Function '*-WT*' -Alias 'T'
