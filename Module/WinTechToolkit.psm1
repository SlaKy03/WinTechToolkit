# WinTech Toolkit - main module.
# The functions live in Functions\*.ps1 and are all loaded in the same scope,
# so they can call each other, also inside the GUI runspaces.

$script:WTModuleRoot = $PSScriptRoot

# Other users' folders may deny access: Test-Path must return $false, not an error
$PSDefaultParameterValues = @{ 'Test-Path:ErrorAction' = 'SilentlyContinue' }

$code = New-Object Text.StringBuilder
foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot 'Functions') -Filter '*.ps1' | Sort-Object Name) {
    . $file.FullName
    [void]$code.AppendLine([IO.File]::ReadAllText($file.FullName))
}
# Sent to remote computers by Invoke-WTRemote: kept in memory, the files may be gone by then
$script:WTModuleCode = $code.ToString()
Remove-Variable code, file

# Folder the toolkit runs from (often %TEMP%\WinTechToolkit_* with the exe or irm | iex):
# the cleanup and delete functions must never touch it while it is running
$script:WTToolkitRoot = ConvertTo-WTLongPath (Split-Path $PSScriptRoot -Parent)

Export-ModuleMember -Function '*-WT*' -Alias 'T'
