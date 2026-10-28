#Requires -RunAsAdministrator
# GPL-2.0-only. Compare the current PK, KEK, db and dbx with a backup (read-only). Run in an administrator PowerShell.
#  After a db Append: pass -Esl with the appended list; db must gain exactly those entries and nothing else may change.
#  After undoing it: omit -Esl; all four must equal the backup.
param([Parameter(Mandatory)][string]$Backup,[string]$Esl)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'SecureBootKeys.ps1')
$old=@{};foreach($n in $GuKeyNames){$old[$n]=[IO.File]::ReadAllBytes((Join-Path $Backup "$n.bin"))}
$meta=Get-Content -Raw (Join-Path $Backup 'state.json') | ConvertFrom-Json
foreach($n in $GuKeyNames){if((Get-GuSha $old[$n]) -ne $meta.Vars.$n.Sha256){throw "Backup file $n.bin does not match state.json; the backup may have been modified"}}
$s=Read-GuSecureBootState
$eslBytes=if($Esl){[IO.File]::ReadAllBytes($Esl)}else{$null}
$r=Compare-GuSecureBoot $old $s.Vars $eslBytes
"Secure Boot on: $($s.SecureBootOn)   SetupMode: $($s.SetupMode) (must be 0)"
$r.Lines
if($s.SetupMode -ne 0){$r.Ok=$false}
if($r.Ok){'Result: as expected'}else{'Result: NOT as expected. Make no further firmware changes; keep this output and the backup.';exit 1}
