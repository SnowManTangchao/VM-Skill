<#
.SYNOPSIS
    Locate a local VisionMaster install and print help, CHM, and assembly paths.

.DESCRIPTION
    Searches VM_SDK_DIR, the uninstall registry, and VisionMaster* folders on
    fixed drives. Does not start VisionMaster and does not check a license.
    Official manuals stay on this machine; this script only prints paths.

    Application help may be HTML WebHelp (index.html) or CHM files under
    Applications\Help. SDK development guides are reported separately.
    ImportRef.exe and log4net.config are discovered under Development;
    a missing ImportRef.exe is not treated as a broken help install.

    Registry discovery reads InstallLocation, InstallPath, and DisplayIcon.
    Some installs leave InstallLocation empty and store the root in InstallPath.

.PARAMETER ExtraRoot
    An install root, or any directory inside one. Also accepts a path that
    is not in the default search locations.

.PARAMETER Json
    Write one JSON object to stdout instead of the text report.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\find-vm-install.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\find-vm-install.ps1 -ExtraRoot D:\VisionMaster4.4.0 -Json
#>
[CmdletBinding()]
param(
    [string]$ExtraRoot,
    [switch]$Json
)

$ErrorActionPreference = 'Continue'
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
}

$script:Searched = New-Object System.Collections.Generic.List[string]
$script:Notes = New-Object System.Collections.Generic.List[string]
$script:VmInstallExitCode = 1

function Add-Note {
    param([string]$Text)
    if (-not [string]::IsNullOrWhiteSpace($Text)) {
        $script:Notes.Add($Text)
    }
}

function Normalize-Directory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }
    $trimmed = $Path.Trim().Trim('"').Trim("'")
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return $null
    }
    try {
        $full = [System.IO.Path]::GetFullPath($trimmed)
    } catch {
        return $null
    }
    return $full.TrimEnd('\', '/')
}

function Join-VmPath {
    param(
        [string]$Root,
        [string]$Relative
    )
    $path = $Root
    $parts = @($Relative -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($part in $parts) {
        $path = Join-Path $path $part
    }
    return $path
}

function Test-Directory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    try {
        return (Test-Path -LiteralPath $Path -PathType Container -ErrorAction Stop)
    } catch {
        return $false
    }
}

function Test-File {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    try {
        return (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction Stop)
    } catch {
        return $false
    }
}

function Get-VmHelpSortKey {
    param([string]$Path)
    $normalized = ($Path -replace '/', '\').ToLowerInvariant()
    $marker = '\applications\help\'
    $rest = $normalized
    $markerIndex = $normalized.IndexOf($marker)
    if ($markerIndex -ge 0) {
        $rest = $normalized.Substring($markerIndex + $marker.Length)
    }
    $parts = @($rest -split '\\' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $language = ''
    if ($parts.Count -ge 2) {
        $language = [string]$parts[0]
    }
    $languageRank = 9
    if ($language -eq 'ch') {
        $languageRank = 0
    } elseif ($language -eq 'en') {
        $languageRank = 1
    }
    $leaf = ''
    if ($parts.Count -gt 0) {
        $leaf = [string]$parts[$parts.Count - 1]
    }
    $nameRank = 9
    if ($leaf -eq 'index.html') {
        $nameRank = 0
    } elseif ($leaf -eq 'visionmasterhelp.chm') {
        $nameRank = 1
    } elseif ($leaf -eq 'hikvisionmasterhelp.chm') {
        $nameRank = 2
    }
    return ('{0:D2}-{1:D2}-{2}' -f $languageRank, $nameRank, $rest)
}

function Sort-VmHelpPaths {
    param([string[]]$Paths)
    $items = @($Paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($items.Count -eq 0) {
        return
    }
    $items | Sort-Object { Get-VmHelpSortKey $_ } | ForEach-Object { $_ }
}

function Test-AppHelpMarker {
    param([string]$Path)
    foreach ($relative in @(
            'Applications/Help/CH/index.html',
            'Applications/Help/EN/index.html',
            'Applications/Help/index.html'
        )) {
        if (Test-File (Join-VmPath $Path $relative)) {
            return $true
        }
    }
    foreach ($relative in @('Applications/Help/CH', 'Applications/Help/EN', 'Applications/Help')) {
        $dir = Join-VmPath $Path $relative
        if (-not (Test-Directory $dir)) {
            continue
        }
        $chmFiles = @()
        try {
            $chmFiles = @(Get-ChildItem -LiteralPath $dir -Filter '*.chm' -File -ErrorAction SilentlyContinue)
        } catch {
            $chmFiles = @()
        }
        if ($chmFiles.Count -gt 0) {
            return $true
        }
    }
    return $false
}

function Test-VmRoot {
    param([string]$Path)
    if (-not (Test-Directory $Path)) {
        return $false
    }
    $name = Split-Path -Leaf $Path
    $hasApplications = Test-Directory (Join-VmPath $Path 'Applications')
    $hasDevelopment = Test-Directory (Join-VmPath $Path 'Development')
    if (Test-AppHelpMarker $Path) {
        return $true
    }
    if ($hasApplications -and $hasDevelopment) {
        return $true
    }
    if ($name -like 'VisionMaster*' -and ($hasApplications -or $hasDevelopment)) {
        return $true
    }
    return $false
}

function Find-VmRootFromPath {
    param([string]$Start)
    $current = Normalize-Directory $Start
    if ([string]::IsNullOrWhiteSpace($current)) {
        return $null
    }
    if (Test-Path -LiteralPath $current -PathType Leaf) {
        $current = Normalize-Directory (Split-Path -Parent $current)
    }
    for ($i = 0; $i -lt 8 -and -not [string]::IsNullOrWhiteSpace($current); $i++) {
        if (Test-VmRoot $current) {
            return $current
        }
        $parent = Normalize-Directory (Split-Path -Parent $current)
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) {
            break
        }
        $current = $parent
    }
    return $null
}

function Add-CandidatePath {
    param(
        [System.Collections.Generic.List[string]]$Target,
        [string]$Path
    )
    $root = Find-VmRootFromPath $Path
    if ([string]::IsNullOrWhiteSpace($root)) {
        return
    }
    foreach ($existing in $Target) {
        if ($existing.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }
    }
    $Target.Add($root)
}

function Add-DriveFolders {
    param(
        [System.Collections.Generic.List[string]]$Target,
        [string]$Directory
    )
    if (-not (Test-Directory $Directory)) {
        return
    }
    try {
        $dirs = Get-ChildItem -LiteralPath $Directory -Directory -Filter 'VisionMaster*' -ErrorAction SilentlyContinue
    } catch {
        Add-Note ("Could not list " + $Directory + ": " + $_.Exception.Message)
        return
    }
    foreach ($dir in @($dirs)) {
        Add-CandidatePath -Target $Target -Path $dir.FullName
    }
}

function Get-RegistryInstallHints {
    param($Item)
    $hints = New-Object System.Collections.Generic.List[string]
    foreach ($propertyName in @('InstallLocation', 'InstallPath')) {
        $value = [string]$Item.$propertyName
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $hints.Add($value.Trim().Trim('"').Trim("'"))
        }
    }
    if ($Item.DisplayIcon) {
        $icon = ([string]$Item.DisplayIcon).Split(',')[0].Trim().Trim('"').Trim("'")
        if (-not [string]::IsNullOrWhiteSpace($icon)) {
            try {
                $parent = Split-Path -Parent $icon
            } catch {
                $parent = $null
            }
            if (-not [string]::IsNullOrWhiteSpace($parent)) {
                $hints.Add($parent)
            }
        }
    }
    return @($hints.ToArray())
}

function Add-UninstallCandidates {
    param(
        $Item,
        [System.Collections.Generic.List[string]]$Target
    )
    $displayName = [string]$Item.DisplayName
    if ($displayName -notmatch 'VisionMaster') {
        return
    }
    foreach ($hint in @(Get-RegistryInstallHints -Item $Item)) {
        Add-CandidatePath -Target $Target -Path $hint
    }
}

function Get-UninstallRoots {
    param([object[]]$Items)
    $roots = New-Object System.Collections.Generic.List[string]
    $searched = 'Uninstall registry (DisplayName contains VisionMaster; InstallLocation, InstallPath, DisplayIcon)'
    if ($PSBoundParameters.ContainsKey('Items')) {
        foreach ($item in @($Items)) {
            if ($null -eq $item) {
                continue
            }
            Add-UninstallCandidates -Item $item -Target $roots
        }
        $script:Searched.Add($searched)
        return $roots
    }

    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $sawRegistry = $false
    foreach ($key in $keys) {
        $entries = @()
        try {
            $entries = @(Get-ItemProperty -Path $key -ErrorAction Stop)
            $sawRegistry = $true
        } catch {
            continue
        }
        foreach ($entry in $entries) {
            Add-UninstallCandidates -Item $entry -Target $roots
        }
    }
    if ($sawRegistry) {
        $script:Searched.Add($searched)
    } else {
        $script:Searched.Add('Uninstall registry unavailable on this host')
    }
    return $roots
}

function Find-Files {
    param(
        [string]$Root,
        [string]$Suffix,
        [string[]]$ExactNames,
        [int]$MaxDepth = 6,
        [int]$Limit = 30
    )
    $found = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Directory $Root)) {
        return @()
    }
    $wanted = @{}
    if ($ExactNames) {
        foreach ($name in $ExactNames) {
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                $wanted[$name.ToLowerInvariant()] = $true
            }
        }
    }
    $suffixText = ''
    if (-not [string]::IsNullOrWhiteSpace($Suffix)) {
        $suffixText = $Suffix.ToLowerInvariant()
    }

    $start = Get-Item -LiteralPath $Root -ErrorAction SilentlyContinue
    if ($null -eq $start) {
        return @()
    }
    $stack = New-Object System.Collections.Generic.Stack[object]
    $stack.Push([pscustomobject]@{ Directory = $start; Depth = 0 })

    while ($stack.Count -gt 0 -and $found.Count -lt $Limit) {
        $frame = $stack.Pop()
        $directory = $frame.Directory
        $depth = [int]$frame.Depth
        $children = @()
        try {
            $children = @($directory.GetFileSystemInfos())
        } catch {
            continue
        }
        foreach ($child in $children) {
            if ($found.Count -ge $Limit) {
                break
            }
            $isDirectory = $false
            $isLink = $false
            try {
                $attrs = [int]$child.Attributes
                $isDirectory = ($attrs -band [int][System.IO.FileAttributes]::Directory) -ne 0
                $isLink = ($attrs -band [int][System.IO.FileAttributes]::ReparsePoint) -ne 0
            } catch {
                continue
            }
            if ($isDirectory) {
                if ($isLink) {
                    continue
                }
                if ($depth -lt $MaxDepth) {
                    $stack.Push([pscustomobject]@{ Directory = $child; Depth = ($depth + 1) })
                }
                continue
            }
            $key = $child.Name.ToLowerInvariant()
            $match = $false
            if ($wanted.ContainsKey($key)) {
                $match = $true
            } elseif ($suffixText -and $key.EndsWith($suffixText)) {
                $match = $true
            }
            if ($match) {
                $found.Add($child.FullName)
            }
        }
    }
    return @($found.ToArray())
}

function Get-AssemblyMap {
    param([string]$DevelopmentRoot)
    $names = @(
        'VM.Core.dll',
        'VM.PlatformSDKCS.dll',
        'VMControls.Winform.Release.dll',
        'VMControls.WPF.Release.dll',
        'VMControls.Interface.dll'
    )
    $files = @(Find-Files -Root $DevelopmentRoot -ExactNames $names -MaxDepth 7 -Limit 40)
    $map = [ordered]@{}
    foreach ($name in $names) {
        $hits = New-Object System.Collections.Generic.List[string]
        foreach ($file in @($files)) {
            if ([string]::IsNullOrWhiteSpace($file)) {
                continue
            }
            if ((Split-Path -Leaf $file).Equals($name, [System.StringComparison]::OrdinalIgnoreCase)) {
                $hits.Add($file)
            }
        }
        $map[$name] = @($hits.ToArray())
    }
    return ,$map
}

function Get-AppHelp {
    param([string]$Root)
    $html = New-Object System.Collections.Generic.List[string]
    $chm = New-Object System.Collections.Generic.List[string]
    $helpRoot = Join-VmPath $Root 'Applications/Help'
    if (Test-Directory $helpRoot) {
        $rootIndex = Join-Path $helpRoot 'index.html'
        if (Test-File $rootIndex) {
            try {
                $html.Add([System.IO.Path]::GetFullPath($rootIndex))
            } catch {
                $html.Add($rootIndex)
            }
        }
        $languageDirs = @()
        try {
            $languageDirs = @(Get-ChildItem -LiteralPath $helpRoot -Directory -ErrorAction SilentlyContinue)
        } catch {
            $languageDirs = @()
        }
        foreach ($dir in $languageDirs) {
            $index = Join-Path $dir.FullName 'index.html'
            if (Test-File $index) {
                try {
                    $html.Add([System.IO.Path]::GetFullPath($index))
                } catch {
                    $html.Add($index)
                }
            }
        }
        foreach ($file in @(Find-Files -Root $helpRoot -Suffix '.chm' -MaxDepth 2 -Limit 30)) {
            if (-not [string]::IsNullOrWhiteSpace($file)) {
                $chm.Add($file)
            }
        }
    }
    $result = [ordered]@{
        html = @(Sort-VmHelpPaths @($html.ToArray()))
        chm  = @(Sort-VmHelpPaths @($chm.ToArray()))
    }
    return ,$result
}

function New-Candidate {
    param([string]$Root)
    $development = Join-VmPath $Root 'Development'
    $appHelp = Get-AppHelp -Root $Root
    $chmRoots = New-Object System.Collections.Generic.List[string]
    foreach ($relative in @('Development', 'Documentation', 'Document', 'Doc')) {
        $path = Join-VmPath $Root $relative
        if (Test-Directory $path) {
            $chmRoots.Add($path)
        }
    }
    $chm = New-Object System.Collections.Generic.List[string]
    foreach ($chmRoot in $chmRoots) {
        foreach ($file in @(Find-Files -Root $chmRoot -Suffix '.chm' -MaxDepth 6 -Limit 20)) {
            if (-not [string]::IsNullOrWhiteSpace($file)) {
                $chm.Add($file)
            }
            if ($chm.Count -ge 20) {
                break
            }
        }
        if ($chm.Count -ge 20) {
            break
        }
    }
    $assemblies = Get-AssemblyMap -DevelopmentRoot $development
    $importRef = @(Find-Files -Root $development -ExactNames @('ImportRef.exe') -MaxDepth 12 -Limit 20)
    # File name match is case-insensitive, so log4Net.config is included.
    $log4net = @(Find-Files -Root $development -ExactNames @('log4net.config') -MaxDepth 12 -Limit 20)

    $coreCount = @($assemblies['VM.Core.dll']).Count
    $sdkCount = @($assemblies['VM.PlatformSDKCS.dll']).Count
    $htmlCount = @($appHelp.html | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
    $appChmCount = @($appHelp.chm | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
    if ($htmlCount -eq 0 -and $appChmCount -eq 0) {
        Add-Note ($Root + ': application help was not found under Applications\Help (no index.html and no CHM). Install or repair the help component.')
    } elseif ($htmlCount -eq 0 -and $appChmCount -gt 0) {
        Add-Note ($Root + ': application help is installed as CHM under Applications\Help. Use the app-help chm paths for module parameters, defaults, and ranges.')
    }
    if ($chm.Count -eq 0) {
        Add-Note ($Root + ': no SDK CHM was found under Development or Documentation. Confirm the development guide is installed.')
    }
    if ($coreCount -eq 0 -or $sdkCount -eq 0) {
        Add-Note ($Root + ': VM.Core.dll or VM.PlatformSDKCS.dll was not found. Confirm the development assemblies are installed.')
    }
    if (@($importRef | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -eq 0) {
        Add-Note ($Root + ': ImportRef.exe was not found under Development. Add SDK references manually from the assembly paths in this report.')
    }

    $candidate = [ordered]@{
        installRoot   = $Root
        appHelp       = $appHelp
        sdkChm        = @($chm.ToArray())
        assemblies    = $assemblies
        importRef     = @($importRef)
        log4netConfig = @($log4net)
    }
    return ,$candidate
}

function Get-Candidates {
    param([string]$ExtraRoot)
    $roots = New-Object System.Collections.Generic.List[string]

    $sdkDir = [Environment]::GetEnvironmentVariable('VM_SDK_DIR')
    if ([string]::IsNullOrWhiteSpace($sdkDir)) {
        $script:Searched.Add('VM_SDK_DIR is not set')
    } else {
        $script:Searched.Add('VM_SDK_DIR=' + $sdkDir)
        Add-CandidatePath -Target $roots -Path $sdkDir
        if (-not (Find-VmRootFromPath $sdkDir)) {
            Add-Note ('VM_SDK_DIR does not point at a VisionMaster install: ' + $sdkDir)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ExtraRoot)) {
        $script:Searched.Add('ExtraRoot=' + $ExtraRoot)
        if (-not (Test-Path -LiteralPath $ExtraRoot)) {
            Add-Note ('ExtraRoot does not exist: ' + $ExtraRoot)
        } else {
            Add-CandidatePath -Target $roots -Path $ExtraRoot
            if (-not (Find-VmRootFromPath $ExtraRoot)) {
                Add-Note ('ExtraRoot is not inside a VisionMaster install: ' + $ExtraRoot)
            }
        }
    }

    foreach ($root in @(Get-UninstallRoots)) {
        Add-CandidatePath -Target $roots -Path $root
    }

    $drives = @()
    try {
        $drives = @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -eq [System.IO.DriveType]::Fixed })
    } catch {
        Add-Note ('Could not list drives: ' + $_.Exception.Message)
    }
    $script:Searched.Add('Fixed drives: VisionMaster* at the drive root, Program Files, and Program Files (x86)')
    foreach ($drive in $drives) {
        $driveRoot = $drive.RootDirectory.FullName
        Add-DriveFolders -Target $roots -Directory $driveRoot
        Add-DriveFolders -Target $roots -Directory (Join-VmPath $driveRoot 'Program Files')
        Add-DriveFolders -Target $roots -Directory (Join-VmPath $driveRoot 'Program Files (x86)')
    }

    $candidates = @()
    foreach ($root in @($roots)) {
        $candidates += ,(New-Candidate -Root $root)
    }
    return @($candidates)
}

function Write-PathList {
    param(
        [string]$Indent,
        $Paths
    )
    $items = @($Paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($items.Count -eq 0) {
        Write-Output ($Indent + '(none)')
        return
    }
    foreach ($path in $items) {
        Write-Output ($Indent + $path)
    }
}

function Invoke-FindVmInstall {
    param(
        [string]$ExtraRoot,
        [switch]$Json
    )
    $script:Searched = New-Object System.Collections.Generic.List[string]
    $script:Notes = New-Object System.Collections.Generic.List[string]

    $candidates = @(Get-Candidates -ExtraRoot $ExtraRoot)
    $found = $false
    foreach ($candidate in @($candidates)) {
        if ($null -ne $candidate -and -not [string]::IsNullOrWhiteSpace($candidate.installRoot)) {
            $found = $true
            break
        }
    }

    $payload = [ordered]@{
        found      = $found
        candidates = @($candidates | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace($_.installRoot) })
        searched   = @($script:Searched.ToArray())
        notes      = @($script:Notes.ToArray())
    }

    $script:VmInstallExitCode = 1
    if ($found) {
        $script:VmInstallExitCode = 0
    }

    if ($Json) {
        $payload | ConvertTo-Json -Depth 8
    } elseif ($found) {
        Write-Output ('找到 {0} 个 VisionMaster 安装目录。下面是候选路径。手册留在本机，不要复制进仓库。' -f @($payload.candidates).Count)
        Write-Output ''
        $index = 1
        foreach ($candidate in @($payload.candidates)) {
            Write-Output ('[{0}] {1}' -f $index, $candidate.installRoot)
            Write-Output '    app-help:'
            Write-Output '      html:'
            Write-PathList -Indent '        ' -Paths $candidate.appHelp.html
            Write-Output '      chm:'
            Write-PathList -Indent '        ' -Paths $candidate.appHelp.chm
            Write-Output '    sdk-chm:'
            Write-PathList -Indent '      ' -Paths $candidate.sdkChm
            Write-Output '    assemblies:'
            foreach ($name in @($candidate.assemblies.Keys)) {
                $hits = @($candidate.assemblies[$name] | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                if ($hits.Count -eq 0) {
                    Write-Output ('      {0}: (none)' -f $name)
                } else {
                    foreach ($path in $hits) {
                        Write-Output ('      {0}: {1}' -f $name, $path)
                    }
                }
            }
            Write-Output '    import-ref:'
            Write-PathList -Indent '      ' -Paths $candidate.importRef
            Write-Output '    log4net-config:'
            Write-PathList -Indent '      ' -Paths $candidate.log4netConfig
            Write-Output ''
            $index++
        }
        if (@($payload.notes).Count -gt 0) {
            Write-Output 'notes:'
            foreach ($note in @($payload.notes)) { Write-Output ('  - ' + $note) }
        }
    } else {
        Write-Output '没有找到 VisionMaster 安装目录。'
        Write-Output 'No VisionMaster installation was found.'
        Write-Output ''
        Write-Output 'Searched:'
        foreach ($item in @($payload.searched)) { Write-Output ('  - ' + $item) }
        if (@($payload.notes).Count -gt 0) {
            Write-Output 'Notes:'
            foreach ($note in @($payload.notes)) { Write-Output ('  - ' + $note) }
        }
        Write-Output ''
        Write-Output 'Install VisionMaster with the application help and development components, set VM_SDK_DIR, or pass -ExtraRoot <InstallRoot>.'
        Write-Output 'This script only looks for files. It does not start VisionMaster and it does not check a license.'
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-FindVmInstall -ExtraRoot $ExtraRoot -Json:$Json
    exit $script:VmInstallExitCode
}
