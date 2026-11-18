<#
.SYNOPSIS
    Fixture tests for the VisionMaster install locator and CHM lookup guards.

.DESCRIPTION
    Builds fake install trees. Does not include official manuals or binaries.
    Run from the repo root or from this directory:

        pwsh -NoProfile -File .\tests\find-vm-install.tests.ps1
#>
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$locator = Join-Path $repoRoot 'scripts/find-vm-install.ps1'
$lookup = Join-Path $repoRoot 'scripts/lookup-chm.ps1'

. $locator
. $lookup
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($env:TEMP)) {
    $env:TEMP = [System.IO.Path]::GetTempPath()
}
$PSNativeCommandUseErrorActionPreference = $false

$hostName = 'pwsh'
if ($PSVersionTable.PSVersion.Major -lt 6) {
    $hostName = 'powershell.exe'
} elseif ($env:OS -eq 'Windows_NT') {
    $hostName = 'pwsh.exe'
}
$hostExe = Join-Path $PSHOME $hostName
if (-not (Test-Path -LiteralPath $hostExe)) {
    $hostExe = $hostName
}

$script:Failures = New-Object System.Collections.Generic.List[string]
$script:FixtureRoots = New-Object System.Collections.Generic.List[string]

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if ($Condition) {
        Write-Output ('ok: ' + $Message)
        return
    }
    $script:Failures.Add($Message)
    Write-Output ('FAIL: ' + $Message)
}

function Join-TestPath {
    param(
        [string]$Base,
        [string]$Relative
    )
    $path = $Base
    $parts = @($Relative -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($part in $parts) {
        $path = Join-Path $path $part
    }
    return $path
}

function New-FixtureFile {
    param([string]$Path)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Set-Content -LiteralPath $Path -Value 'vm-skill fixture' -Encoding ascii
}

function Reset-LocatorState {
    $script:Notes = New-Object System.Collections.Generic.List[string]
    $script:Searched = New-Object System.Collections.Generic.List[string]
}

function New-FakeInstall {
    param(
        [ValidateSet('html', 'chm', 'both', 'none')]
        [string]$Help = 'html',
        [switch]$WithImportRef,
        [switch]$WithLegacyLog4Net,
        [switch]$WithDeepLog4Net
    )
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('vm-skill-fixture-' + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path (Join-TestPath $root 'Applications') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-TestPath $root 'Development') -Force | Out-Null
    $script:FixtureRoots.Add($root)

    $assemblyDir = Join-TestPath $root 'Development/V4.x/ComControls/Assembly'
    foreach ($name in @(
            'VM.Core.dll',
            'VM.PlatformSDKCS.dll',
            'VMControls.Winform.Release.dll',
            'VMControls.WPF.Release.dll',
            'VMControls.Interface.dll'
        )) {
        New-FixtureFile (Join-Path $assemblyDir $name)
    }
    New-FixtureFile (Join-TestPath $root 'Development/V4.x/Doc/VmSdkGuide.chm')

    if ($Help -eq 'html' -or $Help -eq 'both') {
        New-FixtureFile (Join-TestPath $root 'Applications/Help/CH/index.html')
        New-FixtureFile (Join-TestPath $root 'Applications/Help/EN/index.html')
    }
    if ($Help -eq 'chm' -or $Help -eq 'both') {
        foreach ($relative in @(
                'Applications/Help/CH/VisionMasterHelp.chm',
                'Applications/Help/CH/HIKVisionMasterHelp.chm',
                'Applications/Help/EN/VisionMasterHelp.chm',
                'Applications/Help/EN/HIKVisionMasterHelp.chm'
            )) {
            New-FixtureFile (Join-TestPath $root $relative)
        }
    }
    if ($WithImportRef) {
        New-FixtureFile (Join-TestPath $root 'Development/CustomTools/ImportRef.exe')
    }
    if ($WithLegacyLog4Net) {
        New-FixtureFile (Join-TestPath $root 'Development/V4.x/ComControls/Assembly/3rdLib/Log4Net/log4net.config')
    }
    if ($WithDeepLog4Net) {
        New-FixtureFile (Join-TestPath $root 'Development/V4.x/ComControls/Assembly/Module(sp)/x64/Logic/ShellModule/log4Net.config')
    }
    return [System.IO.Path]::GetFullPath($root).TrimEnd('\', '/')
}

function Get-PathList {
    param($Value)
    return @($Value | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Test-EndsWithRelative {
    param(
        [string]$Full,
        [string]$Relative
    )
    $fullNorm = ($Full -replace '\\', '/').TrimEnd('/')
    $relativeNorm = ($Relative -replace '\\', '/').TrimStart('/')
    return $fullNorm.EndsWith($relativeNorm, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-NotesText {
    return (@($script:Notes) -join "`n")
}

function Assert-NoRepair {
    param([string]$Label)
    $notes = Get-NotesText
    Assert-True (-not $notes.Contains('Install or repair the help component')) ($Label + ': does not tell the user to repair help')
}

function Assert-Assemblies {
    param($Candidate, [string]$Label)
    foreach ($name in @(
            'VM.Core.dll',
            'VM.PlatformSDKCS.dll',
            'VMControls.Winform.Release.dll',
            'VMControls.WPF.Release.dll',
            'VMControls.Interface.dll'
        )) {
        $hits = @(Get-PathList $Candidate.assemblies[$name])
        Assert-True ($hits.Count -ge 1) ($Label + ': finds ' + $name)
    }
}

function Assert-SdkChmSeparate {
    param($Candidate, [string]$Label)
    $sdk = @(Get-PathList $Candidate.sdkChm)
    $sdkHit = @($sdk | Where-Object { Test-EndsWithRelative $_ 'Development/V4.x/Doc/VmSdkGuide.chm' })
    Assert-True ($sdkHit.Count -eq 1) ($Label + ': reports the SDK CHM')
    $leaked = @($sdk | Where-Object { $_ -match 'VisionMasterHelp\.chm' })
    Assert-True ($leaked.Count -eq 0) ($Label + ': keeps application CHM out of sdk-chm')
}

Write-Output 'dot-source did not scan the machine'
Assert-True ($script:Searched.Count -eq 0) 'locator load leaves the search log empty'

$sorted = @(Sort-VmHelpPaths @(
        'E:\VM\Applications\Help\EN\HIKVisionMasterHelp.chm',
        'E:\VM\Applications\Help\CH\Other.chm',
        'E:\VM\Applications\Help\CH\VisionMasterHelp.chm',
        'E:\VM\Applications\Help\EN\VisionMasterHelp.chm',
        'E:\VM\Applications\Help\CH\HIKVisionMasterHelp.chm',
        'E:\VM\Applications\Help\index.html'
    ))
$expectedOrder = @(
    'E:\VM\Applications\Help\CH\VisionMasterHelp.chm',
    'E:\VM\Applications\Help\CH\HIKVisionMasterHelp.chm',
    'E:\VM\Applications\Help\CH\Other.chm',
    'E:\VM\Applications\Help\EN\VisionMasterHelp.chm',
    'E:\VM\Applications\Help\EN\HIKVisionMasterHelp.chm',
    'E:\VM\Applications\Help\index.html'
)
$orderOk = ($sorted.Count -eq $expectedOrder.Count)
for ($i = 0; $i -lt $expectedOrder.Count; $i++) {
    if (-not $orderOk) { break }
    if ($sorted[$i] -ne $expectedOrder[$i]) { $orderOk = $false }
}
Assert-True $orderOk 'help paths sort CH before EN, VisionMasterHelp.chm first'

$htmlRoot = New-FakeInstall -Help html -WithImportRef -WithLegacyLog4Net
Reset-LocatorState
$htmlCandidate = New-Candidate -Root $htmlRoot
$htmlPages = @(Get-PathList $htmlCandidate.appHelp.html)
$htmlChm = @(Get-PathList $htmlCandidate.appHelp.chm)
Assert-True (Test-EndsWithRelative $htmlPages[0] 'Applications/Help/CH/index.html') 'HTML help lists CH index.html first'
Assert-True (Test-EndsWithRelative $htmlPages[1] 'Applications/Help/EN/index.html') 'HTML help also lists EN index.html'
Assert-True ($htmlChm.Count -eq 0) 'HTML-only install has no application CHM'
Assert-NoRepair 'HTML help'
Assert-True (-not (Get-NotesText).Contains('ImportRef.exe was not found')) 'HTML install with ImportRef does not ask for manual references'
$importHits = @(Get-PathList $htmlCandidate.importRef)
Assert-True ($importHits.Count -eq 1 -and (Test-EndsWithRelative $importHits[0] 'Development/CustomTools/ImportRef.exe')) 'ImportRef is discovered outside the documented Tool path'
$legacyLog = @(Get-PathList $htmlCandidate.log4netConfig | Where-Object { Test-EndsWithRelative $_ '3rdLib/Log4Net/log4net.config' })
Assert-True ($legacyLog.Count -eq 1) 'legacy log4net.config path is discovered'
Assert-Assemblies $htmlCandidate 'HTML help'
Assert-SdkChmSeparate $htmlCandidate 'HTML help'

$chmRoot = New-FakeInstall -Help chm -WithDeepLog4Net
Reset-LocatorState
$chmCandidate = New-Candidate -Root $chmRoot
Assert-True (Test-VmRoot $chmRoot) 'CHM-only tree is a VisionMaster root'
$chmPages = @(Get-PathList $chmCandidate.appHelp.html)
$chmFiles = @(Get-PathList $chmCandidate.appHelp.chm)
Assert-True ($chmPages.Count -eq 0) 'CHM-only install does not invent index.html'
$chmOrder = @(
    'Applications/Help/CH/VisionMasterHelp.chm',
    'Applications/Help/CH/HIKVisionMasterHelp.chm',
    'Applications/Help/EN/VisionMasterHelp.chm',
    'Applications/Help/EN/HIKVisionMasterHelp.chm'
)
$chmOrderOk = ($chmFiles.Count -eq $chmOrder.Count)
for ($i = 0; $i -lt $chmOrder.Count; $i++) {
    if (-not $chmOrderOk) { break }
    if (-not (Test-EndsWithRelative $chmFiles[$i] $chmOrder[$i])) { $chmOrderOk = $false }
}
Assert-True $chmOrderOk 'CHM application help is reported in lookup order'
Assert-NoRepair 'CHM help'
Assert-True ((Get-NotesText).Contains('application help is installed as CHM')) 'CHM help note points at app-help chm paths'
Assert-True ((Get-PathList $chmCandidate.importRef).Count -eq 0) 'missing ImportRef is reported as none'
Assert-True ((Get-NotesText).Contains('Add SDK references manually')) 'missing ImportRef tells the agent to add references from assembly paths'
$deepLog = @(Get-PathList $chmCandidate.log4netConfig)
Assert-True ($deepLog.Count -eq 1) 'deep log4net config is discovered'
Assert-True ((Split-Path -Leaf $deepLog[0]) -eq 'log4Net.config') 'discovered log4net path keeps log4Net.config casing'
Assert-True (Test-EndsWithRelative $deepLog[0] 'Module(sp)/x64/Logic/ShellModule/log4Net.config') 'deep log4net path is the ShellModule layout'
Assert-Assemblies $chmCandidate 'CHM help'
Assert-SdkChmSeparate $chmCandidate 'CHM help'

$bothRoot = New-FakeInstall -Help both -WithImportRef
Reset-LocatorState
$bothCandidate = New-Candidate -Root $bothRoot
Assert-True ((Get-PathList $bothCandidate.appHelp.html).Count -eq 2) 'install with both layouts still reports index.html'
Assert-True ((Get-PathList $bothCandidate.appHelp.chm).Count -eq 4) 'install with both layouts still reports CHM help'
Assert-NoRepair 'both help layouts'

$noneRoot = New-FakeInstall -Help none -WithImportRef
Reset-LocatorState
$noneCandidate = New-Candidate -Root $noneRoot
Assert-True ((Get-PathList $noneCandidate.appHelp.html).Count -eq 0) 'missing help has no index.html'
Assert-True ((Get-PathList $noneCandidate.appHelp.chm).Count -eq 0) 'missing help has no CHM'
Assert-True ((Get-NotesText).Contains('Install or repair the help component')) 'actually missing help still says to repair the help component'
Assert-Assemblies $noneCandidate 'missing help'

Reset-LocatorState
$emptyDir = Join-Path ([System.IO.Path]::GetTempPath()) ('vm-skill-empty-' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
$script:FixtureRoots.Add($emptyDir)
$fromInstallPath = @(Get-UninstallRoots -Items @(
        [pscustomobject]@{
            DisplayName     = 'VisionMaster 4.2.0'
            InstallLocation = ''
            InstallPath     = '"' + $chmRoot + '"'
            DisplayIcon     = ''
        }
    ))
Assert-True (@($fromInstallPath | Where-Object { $_ -eq $chmRoot }).Count -eq 1) 'registry InstallPath is used when InstallLocation is empty'

Reset-LocatorState
$fromBoth = @(Get-UninstallRoots -Items @(
        [pscustomobject]@{
            DisplayName     = 'VisionMaster 4.2.0'
            InstallLocation = $emptyDir
            InstallPath     = $chmRoot
            DisplayIcon     = ''
        }
    ))
Assert-True (@($fromBoth | Where-Object { $_ -eq $chmRoot }).Count -eq 1) 'InstallPath is still consulted when InstallLocation is not a VisionMaster root'

Reset-LocatorState
$icon = (Join-TestPath $chmRoot 'Applications/VisionMaster.exe') + ',0'
$fromIcon = @(Get-UninstallRoots -Items @(
        [pscustomobject]@{
            DisplayName     = 'VisionMaster 4.2.0'
            InstallLocation = ''
            InstallPath     = ''
            DisplayIcon     = '"' + $icon + '"'
        }
    ))
Assert-True (@($fromIcon | Where-Object { $_ -eq $chmRoot }).Count -eq 1) 'DisplayIcon still resolves the install root'

Reset-LocatorState
$fromLocation = @(Get-UninstallRoots -Items @(
        [pscustomobject]@{
            DisplayName     = 'VisionMaster 4.2.0'
            InstallLocation = $htmlRoot
            InstallPath     = ''
            DisplayIcon     = ''
        }
    ))
Assert-True (@($fromLocation | Where-Object { $_ -eq $htmlRoot }).Count -eq 1) 'InstallLocation still resolves the install root'

Reset-LocatorState
$ignored = @(Get-UninstallRoots -Items @(
        [pscustomobject]@{
            DisplayName     = 'Some Other Product'
            InstallLocation = ''
            InstallPath     = $chmRoot
            DisplayIcon     = ''
        }
    ))
Assert-True (@($ignored).Count -eq 0) 'registry entries whose DisplayName is not VisionMaster are ignored'

$locatorOutput = Join-Path ([System.IO.Path]::GetTempPath()) ('vm-skill-locator-' + [guid]::NewGuid().ToString('n') + '.json')
$script:FixtureRoots.Add($locatorOutput)
& $hostExe -NoProfile -File $locator -ExtraRoot $chmRoot -Json > $locatorOutput
$locatorExit = $LASTEXITCODE
Assert-True ($locatorExit -eq 0) 'locator exits 0 for a CHM-only ExtraRoot'
$locatorJson = Get-Content -LiteralPath $locatorOutput -Raw -Encoding UTF8 | ConvertFrom-Json
$locatorHit = @($locatorJson.candidates | Where-Object { $_.installRoot -eq $chmRoot })
Assert-True ($locatorHit.Count -eq 1) 'JSON report includes the CHM fixture'
$jsonChm = @(Get-PathList $locatorHit[0].appHelp.chm)
Assert-True ($jsonChm.Count -eq 4) 'JSON appHelp.chm lists the four application CHM files'
Assert-True ($null -eq $locatorHit[0].appHelp.html -or @(Get-PathList $locatorHit[0].appHelp.html).Count -eq 0) 'JSON appHelp.html is empty for CHM-only help'
$jsonSdk = @(Get-PathList $locatorHit[0].sdkChm | Where-Object { Test-EndsWithRelative $_ 'VmSdkGuide.chm' })
Assert-True ($jsonSdk.Count -eq 1) 'JSON still lists the SDK CHM'
Assert-True (@(Get-PathList $locatorHit[0].assemblies.'VM.Core.dll').Count -ge 1) 'JSON still lists VM.Core.dll'
$jsonNotes = @($locatorJson.notes) -join "`n"
Assert-True (-not $jsonNotes.Contains('Install or repair the help component')) 'JSON notes do not say to repair CHM help'

$textOutput = Join-Path ([System.IO.Path]::GetTempPath()) ('vm-skill-locator-' + [guid]::NewGuid().ToString('n') + '.txt')
$script:FixtureRoots.Add($textOutput)
& $hostExe -NoProfile -File $locator -ExtraRoot $chmRoot > $textOutput
$text = Get-Content -LiteralPath $textOutput -Raw -Encoding UTF8
Assert-True ($text.Contains('VisionMasterHelp.chm')) 'text report prints the application CHM path'
Assert-True ($text.Contains('app-help:')) 'text report has an app-help section'
Assert-True (-not $text.Contains('Install or repair the help component')) 'text report does not say to repair CHM help'
Assert-True ($text.Contains('Add SDK references manually')) 'text report tells the agent to add references when ImportRef is missing'

$padding = 'x' * 500
$plain = ConvertTo-VmHelpPlainText ('<html><style>.x{}</style><body><h1>FixtureModule</h1><p>' + $padding + ' threshold default 12 range 0-100 ' + $padding + '</p><script>var x=1</script></body></html>')
Assert-True ($plain.Contains('FixtureModule')) 'plain text keeps the module name'
Assert-True ($plain.Contains('threshold default 12')) 'plain text keeps the parameter sentence'
Assert-True (-not $plain.Contains('<h1>')) 'plain text strips tags'
Assert-True (-not $plain.Contains('var x=1')) 'plain text strips script blocks'
$snippets = @(Find-VmHelpSnippets -Text $plain -Query 'threshold' -Context 40 -Limit 3)
Assert-True ($snippets.Count -eq 1) 'snippet search returns one match'
Assert-True ($snippets[0].Contains('threshold') -and $snippets[0].Length -lt $plain.Length) 'snippet is shorter than the whole page'

$skillFile = Join-Path $repoRoot 'SKILL.md'
Assert-True (-not (Test-VmChmExtractAllowed $skillFile)) 'extract into the skill repo is refused'
$tempDest = Join-Path ([System.IO.Path]::GetTempPath()) ('vm-help-lookup-' + [guid]::NewGuid().ToString('n'))
Assert-True (Test-VmChmExtractAllowed $tempDest) 'extract under TEMP is allowed'
$gitRepo = Join-Path ([System.IO.Path]::GetTempPath()) ('vm-skill-git-' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $gitRepo -Force | Out-Null
$script:FixtureRoots.Add($gitRepo)
& git -C $gitRepo init -q
$gitDest = Join-Path $gitRepo ('vm-help-lookup-' + [guid]::NewGuid().ToString('n'))
Assert-True (-not (Test-VmChmExtractAllowed $gitDest)) 'extract into a Git work tree is refused'

$fakeChm = Join-TestPath $chmRoot 'Applications/Help/CH/VisionMasterHelp.chm'
$beforeTemp = @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Directory -Filter 'vm-help-lookup-*' -ErrorAction SilentlyContinue)
Invoke-VmChmLookup -Chm $fakeChm -Query 'FixtureModule'
Assert-True ($script:VmChmExitCode -eq 3) 'CHM lookup on a non-Windows host exits 3'
$afterTemp = @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Directory -Filter 'vm-help-lookup-*' -ErrorAction SilentlyContinue)
Assert-True ($afterTemp.Count -eq $beforeTemp.Count) 'failed CHM lookup does not leave an extract directory'

$oldTemp = $env:TEMP
try {
    $env:TEMP = $gitRepo
    Invoke-VmChmLookup -Chm $fakeChm -Query 'FixtureModule'
    Assert-True ($script:VmChmExitCode -eq 2) 'CHM lookup refuses TEMP inside a Git work tree'
} finally {
    $env:TEMP = $oldTemp
}
$gitFiles = @(Get-ChildItem -LiteralPath $gitRepo -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
Assert-True ($gitFiles.Count -eq 0) 'refused CHM lookup writes no help files into the Git work tree'

Invoke-VmChmLookup -Chm (Join-Path $chmRoot 'missing.chm') -Query 'FixtureModule'
Assert-True ($script:VmChmExitCode -eq 2) 'missing CHM exits 2'

foreach ($fixture in @($script:FixtureRoots)) {
    if ([string]::IsNullOrWhiteSpace($fixture)) { continue }
    if (Test-Path -LiteralPath $fixture) {
        Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($script:Failures.Count -gt 0) {
    Write-Output ''
    Write-Output ($script:Failures.Count.ToString() + ' failed')
    exit 1
}

Write-Output ''
Write-Output 'all checks passed'
exit 0
