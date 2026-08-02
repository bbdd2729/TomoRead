$ErrorActionPreference = 'Stop'

$classesRoot = 'HKCU:\Software\Classes'
$programId = 'TomoRead.Book'
$extensions = @('.epub', '.pdf', '.txt', '.md', '.markdown')

foreach ($extension in $extensions) {
    $extensionKey = Join-Path -Path $classesRoot -ChildPath $extension
    if ((Test-Path -LiteralPath $extensionKey) -and
        ((Get-Item -LiteralPath $extensionKey).GetValue('') -eq $programId)) {
        Remove-Item -LiteralPath $extensionKey -Recurse -Force
    }
}

$programKey = Join-Path -Path $classesRoot -ChildPath $programId
if (Test-Path -LiteralPath $programKey) {
    Remove-Item -LiteralPath $programKey -Recurse -Force
}

Write-Host 'Removed TomoRead file associations for the current user.'
