<#
.SYNOPSIS
    Search a local VisionMaster CHM and print short excerpts.

.DESCRIPTION
    Decompiles one .chm with Windows hh.exe into a directory under $env:TEMP,
    prints short plain-text excerpts, then deletes that directory.
    Refuses to extract into a Git repository or into this skill repository.
    Does not copy manuals into the skill repo or a business repo.

.PARAMETER Chm
    Full path of a .chm on this machine. Use a path printed by find-vm-install.ps1.

.PARAMETER Query
    Literal text to find, such as a module name or error code. Omit it to list
    HTML paths only.

.PARAMETER MaxMatches
    Maximum excerpts to print. Clamped to 1..30.

.PARAMETER Context
    Characters of plain text to keep on each side of a match. Clamped to 40..400.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\lookup-chm.ps1 -Chm "D:\VisionMaster\Applications\Help\CH\VisionMasterHelp.chm" -Query "模块名称"
#>
[CmdletBinding()]
param(
    [string]$Chm,
    [string]$Query,
    [int]$MaxMatches = 12,
    [int]$Context = 160
)

$ErrorActionPreference = 'Continue'
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
}

$script:VmChmExitCode = 2

function Test-IsUnderPath {
    param(
        [string]$Child,
        [string]$Parent
    )
    if ([string]::IsNullOrWhiteSpace($Child) -or [string]::IsNullOrWhiteSpace($Parent)) {
        return $false
    }
    try {
        $childFull = [System.IO.Path]::GetFullPath($Child)
        $parentFull = [System.IO.Path]::GetFullPath($Parent)
    } catch {
        return $false
    }
    $childFull = $childFull.TrimEnd('\', '/')
    $parentFull = $parentFull.TrimEnd('\', '/')
    if ($childFull.Equals($parentFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $prefix = $parentFull + [System.IO.Path]::DirectorySeparatorChar
    return $childFull.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-VmSkillRoot {
    $scripts = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scripts)) {
        return $null
    }
    $parent = Split-Path -Parent $scripts
    if ([string]::IsNullOrWhiteSpace($parent)) {
        return $null
    }
    return $parent
}

function Find-GitRootContaining {
    param([string]$Path)
    $current = $Path
    if ([string]::IsNullOrWhiteSpace($current)) {
        return $null
    }
    try {
        $current = [System.IO.Path]::GetFullPath($current)
    } catch {
        return $null
    }
    if (Test-Path -LiteralPath $current -PathType Leaf) {
        $current = Split-Path -Parent $current
    }
    for ($i = 0; $i -lt 12 -and -not [string]::IsNullOrWhiteSpace($current); $i++) {
        $git = Join-Path $current '.git'
        if (Test-Path -LiteralPath $git) {
            return $current
        }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) {
            break
        }
        $current = $parent
    }
    return $null
}

function Test-VmChmExtractAllowed {
    param([string]$Directory)
    if ([string]::IsNullOrWhiteSpace($Directory) -or [string]::IsNullOrWhiteSpace($env:TEMP)) {
        return $false
    }
    if (-not (Test-IsUnderPath -Child $Directory -Parent $env:TEMP)) {
        return $false
    }
    $skillRoot = Get-VmSkillRoot
    if (-not [string]::IsNullOrWhiteSpace($skillRoot) -and (Test-IsUnderPath -Child $Directory -Parent $skillRoot)) {
        return $false
    }
    $gitRoot = Find-GitRootContaining $Directory
    if (-not [string]::IsNullOrWhiteSpace($gitRoot)) {
        return $false
    }
    $leaf = [System.IO.Path]::GetFileName($Directory.TrimEnd('\', '/'))
    if ($leaf -notlike 'vm-help-lookup-*') {
        return $false
    }
    return $true
}

function Test-VmWindowsHost {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        return [bool]$IsWindows
    }
    return $true
}

function ConvertTo-VmHelpPlainText {
    param([string]$Html)
    if ([string]::IsNullOrEmpty($Html)) {
        return ''
    }
    $text = [regex]::Replace($Html, '(?is)<script[^>]*>.*?</script>', ' ')
    $text = [regex]::Replace($text, '(?is)<style[^>]*>.*?</style>', ' ')
    $text = [regex]::Replace($text, '(?is)<[^>]+>', ' ')
    try {
        $text = [System.Net.WebUtility]::HtmlDecode($text)
    } catch {
    }
    $text = [regex]::Replace($text, '\s+', ' ')
    return $text.Trim()
}

function Find-VmHelpSnippets {
    param(
        [string]$Text,
        [string]$Query,
        [int]$Context = 160,
        [int]$Limit = 12
    )
    $found = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Query) -or $Limit -lt 1) {
        return @()
    }
    $start = 0
    while ($found.Count -lt $Limit) {
        $index = $Text.IndexOf($Query, $start, [System.StringComparison]::OrdinalIgnoreCase)
        if ($index -lt 0) {
            break
        }
        $from = $index - $Context
        if ($from -lt 0) {
            $from = 0
        }
        $to = $index + $Query.Length + $Context
        if ($to -gt $Text.Length) {
            $to = $Text.Length
        }
        $snippet = $Text.Substring($from, $to - $from).Trim()
        $found.Add($snippet)
        $start = $index + $Query.Length
        if ($start -le $index) {
            break
        }
    }
    return @($found.ToArray())
}

function Read-VmHelpFile {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    $headLength = $bytes.Length
    if ($headLength -gt 4096) {
        $headLength = 4096
    }
    $head = [System.Text.Encoding]::ASCII.GetString($bytes, 0, $headLength)
    if ($head -match '(?i)charset\s*=\s*["'']?\s*(gb18030|gbk|gb2312|big5|utf-8|utf8)') {
        $charset = $Matches[1].ToLowerInvariant()
        if ($charset -eq 'gb2312' -or $charset -eq 'gbk') {
            $charset = 'gb18030'
        }
        if ($charset -eq 'utf8') {
            $charset = 'utf-8'
        }
        try {
            return [System.Text.Encoding]::GetEncoding($charset).GetString($bytes)
        } catch {
        }
    }
    $utf8Strict = New-Object System.Text.UTF8Encoding $false, $true
    try {
        return $utf8Strict.GetString($bytes)
    } catch {
        try {
            return [System.Text.Encoding]::GetEncoding('gb18030').GetString($bytes)
        } catch {
            return [System.Text.Encoding]::UTF8.GetString($bytes)
        }
    }
}

function Get-VmHelpRelativePath {
    param(
        [string]$Root,
        [string]$Path
    )
    try {
        $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
        $pathFull = [System.IO.Path]::GetFullPath($Path)
    } catch {
        return $Path
    }
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    if ($pathFull.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $pathFull.Substring($prefix.Length)
    }
    return $pathFull
}

function Get-VmHelpContentFiles {
    param([string]$Root)
    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    $allowed = @{
        '.html' = $true
        '.htm'  = $true
        '.hhc'  = $true
        '.hhk'  = $true
    }
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        $children = @()
        try {
            $children = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop)
        } catch {
            continue
        }
        foreach ($child in $children) {
            $attrs = 0
            try {
                $attrs = [int]$child.Attributes
            } catch {
                continue
            }
            $isDirectory = ($attrs -band [int][System.IO.FileAttributes]::Directory) -ne 0
            $isLink = ($attrs -band [int][System.IO.FileAttributes]::ReparsePoint) -ne 0
            if ($isDirectory) {
                if (-not $isLink) {
                    $stack.Push($child.FullName)
                }
                continue
            }
            $extension = $child.Extension.ToLowerInvariant()
            if ($allowed.ContainsKey($extension) -and $child.Length -le 2MB) {
                $files.Add($child)
            }
        }
    }
    return ,$files
}

function Remove-VmHelpExtractDirectory {
    param([string]$Directory)
    if ([string]::IsNullOrWhiteSpace($Directory) -or [string]::IsNullOrWhiteSpace($env:TEMP)) {
        return
    }
    $full = $null
    try {
        $full = [System.IO.Path]::GetFullPath($Directory)
    } catch {
        return
    }
    $leaf = [System.IO.Path]::GetFileName($full.TrimEnd('\', '/'))
    if ($leaf -notlike 'vm-help-lookup-*') {
        return
    }
    if (-not (Test-IsUnderPath -Child $full -Parent $env:TEMP)) {
        return
    }
    if (-not (Test-Path -LiteralPath $full -PathType Container)) {
        return
    }
    $dirs = New-Object System.Collections.Generic.Stack[string]
    $dirs.Push($full)
    $allDirs = New-Object System.Collections.Generic.List[string]
    while ($dirs.Count -gt 0) {
        $dir = $dirs.Pop()
        $allDirs.Add($dir)
        $children = @()
        try {
            $children = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop)
        } catch {
            continue
        }
        foreach ($child in $children) {
            $attrs = 0
            try {
                $attrs = [int]$child.Attributes
            } catch {
                continue
            }
            $isDirectory = ($attrs -band [int][System.IO.FileAttributes]::Directory) -ne 0
            $isLink = ($attrs -band [int][System.IO.FileAttributes]::ReparsePoint) -ne 0
            if ($isDirectory) {
                if (-not $isLink) {
                    $dirs.Push($child.FullName)
                }
                continue
            }
            try {
                Remove-Item -LiteralPath $child.FullName -Force -ErrorAction SilentlyContinue
            } catch {
            }
        }
    }
    for ($i = $allDirs.Count - 1; $i -ge 0; $i--) {
        try {
            Remove-Item -LiteralPath $allDirs[$i] -Force -ErrorAction SilentlyContinue
        } catch {
        }
    }
}

function Invoke-VmChmDecompile {
    param(
        [string]$ChmPath,
        [string]$Destination
    )
    $hh = Join-Path $env:SystemRoot 'hh.exe'
    if (-not (Test-Path -LiteralPath $hh -PathType Leaf)) {
        return $false
    }
    # A trailing backslash before a closing quote is parsed as an escaped quote.
    # "\." still names this directory and keeps the argument intact.
    $destArg = $Destination.TrimEnd('\', '/') + '\.'
    $quotedDest = '"' + $destArg.Replace('"', '') + '"'
    $quotedChm = '"' + $ChmPath.Replace('"', '') + '"'
    $argumentString = '-decompile ' + $quotedDest + ' ' + $quotedChm
    $proc = Start-Process -FilePath $hh -ArgumentList $argumentString -PassThru -WindowStyle Hidden
    $stable = 0
    $lastCount = -1
    $deadline = (Get-Date).AddSeconds(60)
    do {
        Start-Sleep -Milliseconds 300
        $count = @(Get-ChildItem -LiteralPath $Destination -Recurse -File -Force -ErrorAction SilentlyContinue).Count
        if ($count -gt 0 -and $count -eq $lastCount) {
            $stable++
        } else {
            $stable = 0
            $lastCount = $count
        }
        if ($stable -ge 3) {
            break
        }
    } while ((Get-Date) -lt $deadline)
    if (-not $proc.HasExited) {
        try {
            $proc.WaitForExit(5000) | Out-Null
        } catch {
        }
    }
    $finalCount = @(Get-ChildItem -LiteralPath $Destination -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    return ($finalCount -gt 0)
}

function Invoke-VmChmLookup {
    param(
        [string]$Chm,
        [string]$Query,
        [int]$MaxMatches = 12,
        [int]$Context = 160
    )
    $script:VmChmExitCode = 2
    if ([string]::IsNullOrWhiteSpace($Chm)) {
        Write-Output 'Pass -Chm with the full path printed by find-vm-install.ps1.'
        return
    }
    $chmFull = $null
    try {
        $chmFull = [System.IO.Path]::GetFullPath($Chm.Trim().Trim('"'))
    } catch {
        Write-Output ('CHM path is not valid: ' + $Chm)
        return
    }
    if (-not $chmFull.EndsWith('.chm', [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Output ('Not a CHM file: ' + $chmFull)
        return
    }
    if (-not (Test-Path -LiteralPath $chmFull -PathType Leaf)) {
        Write-Output ('CHM file was not found: ' + $chmFull)
        return
    }
    if ($MaxMatches -lt 1) {
        $MaxMatches = 1
    }
    if ($MaxMatches -gt 30) {
        $MaxMatches = 30
    }
    if ($Context -lt 40) {
        $Context = 40
    }
    if ($Context -gt 400) {
        $Context = 400
    }
    if (-not [string]::IsNullOrWhiteSpace($Query) -and $Query.Trim().Length -lt 2) {
        Write-Output 'Pass a -Query of at least 2 characters, such as the module name shown in the VisionMaster UI.'
        return
    }

    if ([string]::IsNullOrWhiteSpace($env:TEMP)) {
        Write-Output 'TEMP is not set. Refusing to unpack CHM help into the current directory.'
        return
    }
    $dest = Join-Path $env:TEMP ('vm-help-lookup-' + [guid]::NewGuid().ToString('n'))
    if (-not (Test-VmChmExtractAllowed $dest)) {
        Write-Output 'Refusing to unpack CHM help. The temp directory must be outside this skill repository and outside every Git work tree.'
        Write-Output 'Set TEMP to a normal user temp directory, then run the lookup again. Do not unpack help into a repository.'
        return
    }

    if (-not (Test-VmWindowsHost)) {
        $script:VmChmExitCode = 3
        Write-Output 'CHM lookup needs Windows hh.exe. Run this script on the computer where VisionMaster is installed.'
        Write-Output 'Open the CHM with the local help viewer there. Do not copy the CHM or unpacked HTML into a repository.'
        return
    }
    $hh = Join-Path $env:SystemRoot 'hh.exe'
    if (-not (Test-Path -LiteralPath $hh -PathType Leaf)) {
        $script:VmChmExitCode = 3
        Write-Output ('hh.exe was not found at ' + $hh + '. Open the CHM with the local help viewer. Do not copy it into a repository.')
        return
    }

    try {
        [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
    } catch {
    }

    $created = $false
    try {
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        $created = $true
        $unpacked = Invoke-VmChmDecompile -ChmPath $chmFull -Destination $dest
        if (-not $unpacked) {
            $script:VmChmExitCode = 3
            Write-Output ('Could not unpack CHM: ' + $chmFull)
            Write-Output 'Open it with: hh.exe "<path>" and search there. The temporary folder was removed. Do not copy the CHM into a repository.'
            return
        }

        $contentFiles = Get-VmHelpContentFiles -Root $dest
        $fileList = @($contentFiles)
        Write-Output '本机临时检索，解包目录在结束时删除。不要把帮助页面复制进仓库。'
        Write-Output ('chm: ' + $chmFull)
        if ([string]::IsNullOrWhiteSpace($Query)) {
            $shown = 0
            Write-Output ('html-files: ' + $fileList.Count + ' (showing up to 100 paths, no page text)')
            foreach ($file in $fileList) {
                if ($shown -ge 100) {
                    break
                }
                Write-Output ('  ' + (Get-VmHelpRelativePath -Root $dest -Path $file.FullName))
                $shown++
            }
            $script:VmChmExitCode = 0
            return
        }

        Write-Output ('query: ' + $Query.Trim())
        $printed = 0
        foreach ($file in $fileList) {
            if ($printed -ge $MaxMatches) {
                break
            }
            $raw = ''
            try {
                $raw = Read-VmHelpFile -Path $file.FullName
            } catch {
                continue
            }
            $plain = ConvertTo-VmHelpPlainText $raw
            $remaining = $MaxMatches - $printed
            foreach ($snippet in @(Find-VmHelpSnippets -Text $plain -Query $Query.Trim() -Context $Context -Limit $remaining)) {
                if ([string]::IsNullOrWhiteSpace($snippet)) {
                    continue
                }
                $printed++
                Write-Output ''
                Write-Output ('[' + $printed + '] ' + (Get-VmHelpRelativePath -Root $dest -Path $file.FullName))
                Write-Output ('    ' + $snippet)
                if ($printed -ge $MaxMatches) {
                    break
                }
            }
        }
        Write-Output ''
        if ($printed -eq 0) {
            $script:VmChmExitCode = 1
            Write-Output 'matches: 0'
            Write-Output 'No excerpt matched. Try the next application-help CHM in the locator list, or another query.'
        } else {
            $script:VmChmExitCode = 0
            Write-Output ('matches: ' + $printed)
        }
    } finally {
        if ($created) {
            Remove-VmHelpExtractDirectory -Directory $dest
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-VmChmLookup -Chm $Chm -Query $Query -MaxMatches $MaxMatches -Context $Context
    exit $script:VmChmExitCode
}
