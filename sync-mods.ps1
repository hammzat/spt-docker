<#
.SYNOPSIS
  Mirrors local SPT server mods to the Docker server and restarts it.

.DESCRIPTION
  Uploads only new/changed files (by size and modification time) and deletes files that
  no longer exist locally. mods/fika-server is managed by the container and is never touched.

.EXAMPLE
  $p = @{ Source = 'C:\SPT\SPT_Runtime\user\mods'; Server = 'root@203.0.113.10' }
  .\sync-mods.ps1 @p               # sync and restart
  .\sync-mods.ps1 @p -DryRun       # only show what would change
  .\sync-mods.ps1 @p -NoRestart    # sync without restarting the server
#>
param(
    # Local SPT server mods folder (SPT_Runtime\user\mods)
    [Parameter(Mandatory)][string]$Source,
    # SSH target of the Docker host, e.g. root@203.0.113.10
    [Parameter(Mandatory)][string]$Server,
    [string]$RemoteDir = '/opt/spt/mods',
    [switch]$DryRun,
    [switch]$NoRestart
)
$ErrorActionPreference = 'Stop'
$Exclude = 'fika-server'
# Windows tar.exe (bsdtar) mangles non-ASCII names in file lists; Git's GNU tar does not.
$Tar = 'C:\Program Files\Git\usr\bin\tar.exe'
if (-not (Test-Path $Tar)) { throw "GNU tar not found at $Tar (install Git for Windows)" }

[Console]::OutputEncoding = [Text.Encoding]::UTF8
$utf8 = [Text.UTF8Encoding]::new($false)
$Source = (Resolve-Path $Source).Path.TrimEnd('\')

function Write-LfFile($path, $lines) {
    [IO.File]::WriteAllText($path, (($lines | ForEach-Object { $_ }) -join "`n") + "`n", $utf8)
}

Write-Host "Scanning $Source ..."
$local = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
Get-ChildItem -LiteralPath $Source -Recurse -File -Force | ForEach-Object {
    $rel = $_.FullName.Substring($Source.Length + 1).Replace('\', '/')
    if ($rel -notlike "$Exclude/*") {
        $local[$rel] = @{ Size = $_.Length; Time = [DateTimeOffset]::new($_.LastWriteTimeUtc).ToUnixTimeSeconds() }
    }
}

Write-Host "Reading server state ..."
$remote = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
$lines = ssh $Server "mkdir -p '$RemoteDir' && cd '$RemoteDir' && find . -type f -not -path './$Exclude/*' -printf '%P\t%s\t%T@\n'"
if ($LASTEXITCODE -ne 0) { throw "ssh failed" }
foreach ($l in $lines) {
    $p = $l.Split("`t")
    if ($p.Count -eq 3) {
        $remote[$p[0]] = @{ Size = [long]$p[1]; Time = [long][math]::Floor([double]::Parse($p[2], [Globalization.CultureInfo]::InvariantCulture)) }
    }
}

$upload = @($local.Keys | Where-Object {
    $r = $remote[$_]
    -not $r -or $r.Size -ne $local[$_].Size -or [math]::Abs($r.Time - $local[$_].Time) -gt 2
} | Sort-Object)
$delete = @($remote.Keys | Where-Object { -not $local.ContainsKey($_) } | Sort-Object)
$bytes = ($upload | ForEach-Object { $local[$_].Size } | Measure-Object -Sum).Sum

Write-Host ("Upload: {0} files, {1:N1} MB   Delete: {2} files" -f $upload.Count, ($bytes / 1MB), $delete.Count)
if ($DryRun) {
    $upload | Select-Object -First 50 | ForEach-Object { "  + $_" }
    if ($upload.Count -gt 50) { "  ... and $($upload.Count - 50) more" }
    $delete | Select-Object -First 50 | ForEach-Object { "  - $_" }
    if ($delete.Count -gt 50) { "  ... and $($delete.Count - 50) more" }
    return
}

$tmp = New-TemporaryFile
try {
    if ($delete.Count) {
        Write-LfFile $tmp $delete
        cmd /c "ssh $Server `"cd '$RemoteDir' && xargs -d '\n' rm -f -- && find . -mindepth 1 -type d -empty -not -path './$Exclude*' -delete`" < `"$tmp`""
        if ($LASTEXITCODE -ne 0) { throw "delete failed" }
    }
    if ($upload.Count) {
        Write-Host "Uploading ..."
        Write-LfFile $tmp $upload
        cmd /c "`"$Tar`" --force-local -cf - -C `"$Source`" -T `"$tmp`" | ssh $Server `"tar -xf - -C '$RemoteDir'`""
        if ($LASTEXITCODE -ne 0) { throw "upload failed" }
    }
} finally { Remove-Item $tmp -ErrorAction SilentlyContinue }

if (-not $NoRestart -and ($upload.Count -or $delete.Count)) {
    Write-Host "Restarting server ..."
    ssh $Server "cd /opt/spt && docker compose restart spt"
}
Write-Host "Done."
