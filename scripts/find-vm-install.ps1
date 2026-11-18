<#
.SYNOPSIS
    Locate a local VisionMaster install and print help, CHM, and assembly paths.

.DESCRIPTION
    Searches VM_SDK_DIR, the uninstall registry, and VisionMaster* folders on
    fixed drives. Does not start VisionMaster and does not check a license.
    Official manuals stay on this machine; this script only prints paths.

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
    return (Test-Path -LiteralPath $Path -PathType Container)
}

function Test-VmRoot {
    param([string]$Path)
    if (-not (Test-Directory $Path)) {
        return $false
    }
    $name = Split-Path -Leaf $Path
    $hasApplications = Test-Directory (Join-VmPath $Path 'Applications')
    $hasDevelopment = Test-Directory (Join-VmPath $Path 'Development')
    $hasChineseHelp = Test-Path -LiteralPath (Join-VmPath $Path 'Applications/Help/CH/index.html')
    if ($hasChineseHelp) {
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

function Get-UninstallRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $sawRegistry = $false
    foreach ($key in $keys) {
        $items = @()
        try {
            $items = @(Get-ItemProperty -Path $key -ErrorAction Stop)
            $sawRegistry = $true
        } catch {
            continue
        }
        foreach ($item in $items) {
            $displayName = [string]$item.DisplayName
            if ($displayName -notmatch 'VisionMaster') {
                continue
            }
            $location = [string]$item.InstallLocation
            if ([string]::IsNullOrWhiteSpace($location) -and $item.DisplayIcon) {
                $icon = ([string]$item.DisplayIcon).Split(',')[0].Trim().Trim('"')
                if (-not [string]::IsNullOrWhiteSpace($icon)) {
                    try {
                        $location = Split-Path -Parent $icon
                    } catch {
                        $location = $null
                    }
                }
            }
            Add-CandidatePath -Target $roots -Path $location
        }
    }
    if ($sawRegistry) {
        $script:Searched.Add('Uninstall registry (DisplayName contains VisionMaster)')
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

function Resolve-Existing {
    param([string]$Root, [string[]]$RelativePaths)
    $existing = New-Object System.Collections.Generic.List[string]
    foreach ($relative in @($RelativePaths)) {
        $path = Join-VmPath $Root $relative
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            try {
                $existing.Add([System.IO.Path]::GetFullPath($path))
            } catch {
                $existing.Add($path)
            }
        }
    }
    return @($existing.ToArray())
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

function New-Candidate {
    param([string]$Root)
    $development = Join-VmPath $Root 'Development'
    $appHelp = @(Resolve-Existing -Root $Root -RelativePaths @(
            'Applications/Help/CH/index.html',
            'Applications/Help/EN/index.html',
            'Applications/Help/index.html'
        ))
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
    $importRef = @(Find-Files -Root $development -ExactNames @('ImportRef.exe') -MaxDepth 7 -Limit 10)
    $log4net = @(Find-Files -Root $development -ExactNames @('log4net.config') -MaxDepth 8 -Limit 10)

    $coreCount = @($assemblies['VM.Core.dll']).Count
    $sdkCount = @($assemblies['VM.PlatformSDKCS.dll']).Count
    if ($appHelp.Count -eq 0) {
        Add-Note ($Root + ': application help index was not found. Install or repair the help component.')
    }
    if ($chm.Count -eq 0) {
        Add-Note ($Root + ': no SDK CHM was found under Development or Documentation. Confirm the development guide is installed.')
    }
    if ($coreCount -eq 0 -or $sdkCount -eq 0) {
        Add-Note ($Root + ': VM.Core.dll or VM.PlatformSDKCS.dll was not found. Confirm the development assemblies are installed.')
    }

    $candidate = [ordered]@{
        installRoot   = $Root
        appHelp       = @($appHelp)
        sdkChm        = @($chm.ToArray())
        assemblies    = $assemblies
        importRef     = @($importRef)
        log4netConfig = @($log4net)
    }
    return ,$candidate
}

function Get-Candidates {
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

$candidates = @(Get-Candidates)
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

if ($Json) {
    $payload | ConvertTo-Json -Depth 6
} elseif ($found) {
    Write-Output ('找到 {0} 个 VisionMaster 安装目录。下面是候选路径。手册留在本机，不要复制进仓库。' -f @($payload.candidates).Count)
    Write-Output ''
    $index = 1
    foreach ($candidate in @($payload.candidates)) {
        Write-Output ('[{0}] {1}' -f $index, $candidate.installRoot)
        Write-Output '    app-help:'
        if (@($candidate.appHelp).Count -eq 0) {
            Write-Output '      (none)'
        } else {
            foreach ($path in @($candidate.appHelp)) { Write-Output ('      ' + $path) }
        }
        Write-Output '    sdk-chm:'
        if (@($candidate.sdkChm).Count -eq 0) {
            Write-Output '      (none)'
        } else {
            foreach ($path in @($candidate.sdkChm)) { Write-Output ('      ' + $path) }
        }
        Write-Output '    assemblies:'
        foreach ($name in @($candidate.assemblies.Keys)) {
            $hits = @($candidate.assemblies[$name])
            if ($hits.Count -eq 0) {
                Write-Output ('      {0}: (none)' -f $name)
            } else {
                foreach ($path in $hits) {
                    Write-Output ('      {0}: {1}' -f $name, $path)
                }
            }
        }
        Write-Output '    import-ref:'
        if (@($candidate.importRef).Count -eq 0) {
            Write-Output '      (none)'
        } else {
            foreach ($path in @($candidate.importRef)) { Write-Output ('      ' + $path) }
        }
        Write-Output '    log4net-config:'
        if (@($candidate.log4netConfig).Count -eq 0) {
            Write-Output '      (none)'
        } else {
            foreach ($path in @($candidate.log4netConfig)) { Write-Output ('      ' + $path) }
        }
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

if ($found) {
    exit 0
}
exit 1
