$ErrorActionPreference = 'Stop'

$executable = Join-Path -Path $PSScriptRoot -ChildPath 'tomoread.exe'
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw "TomoRead executable was not found at $executable"
}

$classesRoot = 'HKCU:\Software\Classes'
$programId = 'TomoRead.Book'
$programKey = Join-Path -Path $classesRoot -ChildPath $programId
$command = '"{0}" "%1"' -f $executable

New-Item -Path $programKey -Force | Out-Null
Set-Item -Path $programKey -Value 'TomoRead document'
New-Item -Path (Join-Path $programKey 'DefaultIcon') -Force | Out-Null
Set-Item -Path (Join-Path $programKey 'DefaultIcon') -Value ('"{0}",0' -f $executable)
New-Item -Path (Join-Path $programKey 'shell\open\command') -Force | Out-Null
Set-Item -Path (Join-Path $programKey 'shell\open\command') -Value $command

$associations = @{
    '.epub' = 'application/epub+zip'
    '.pdf' = 'application/pdf'
    '.txt' = 'text/plain'
    '.md' = 'text/markdown'
    '.markdown' = 'text/markdown'
}

foreach ($entry in $associations.GetEnumerator()) {
    $extensionKey = Join-Path -Path $classesRoot -ChildPath $entry.Key
    New-Item -Path $extensionKey -Force | Out-Null
    Set-Item -Path $extensionKey -Value $programId
    New-ItemProperty -Path $extensionKey -Name 'Content Type' -Value $entry.Value -PropertyType String -Force | Out-Null
}

Write-Host 'Registered TomoRead file associations for the current user.'
