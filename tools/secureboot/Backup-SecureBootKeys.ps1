#Requires -RunAsAdministrator
# GPL-2.0-only. Full read-only backup of PK, KEK, db and dbx; changes no setting. Run in an administrator PowerShell.
param([string]$Out=(Join-Path (Get-Location).Path ('sb-backup-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'SecureBootKeys.ps1')
if(Test-Path -LiteralPath $Out){throw "Destination already exists: $Out"}
New-Item -ItemType Directory $Out | Out-Null
$s=Read-GuSecureBootState
$meta=[ordered]@{Time=$s.Time;SecureBootOn=$s.SecureBootOn;SetupMode=$s.SetupMode;Vars=[ordered]@{}}
foreach($n in $GuKeyNames) {
 [IO.File]::WriteAllBytes((Join-Path $Out "$n.bin"),$s.Vars[$n])
 $back=[IO.File]::ReadAllBytes((Join-Path $Out "$n.bin"))
 if((Get-GuSha $back) -ne (Get-GuSha $s.Vars[$n])){throw "$n readback after write does not match"}
 $meta.Vars[$n]=[ordered]@{Bytes=$s.Vars[$n].Length;Sha256=(Get-GuSha $s.Vars[$n]);Entries=(Get-GuEslEntries $s.Vars[$n]).Count}
}
$meta | ConvertTo-Json -Depth 4 | Out-File -Encoding utf8 (Join-Path $Out 'state.json')
"Backup written: $Out"
"Secure Boot on: $($s.SecureBootOn)   SetupMode: $($s.SetupMode)"
foreach($n in $GuKeyNames){'{0,-4} {1,6} bytes  {2,4} entries  {3}' -f $n,$meta.Vars[$n].Bytes,$meta.Vars[$n].Entries,$meta.Vars[$n].Sha256.Substring(0,16)}
