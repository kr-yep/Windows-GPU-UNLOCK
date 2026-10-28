# GPL-2.0-only. Dot-sourced helpers: read Secure Boot variables, parse EFI_SIGNATURE_LIST streams, compare snapshots.
$GuKeyNames=@('PK','KEK','db','dbx')

function Get-GuSha([byte[]]$Bytes){
 if(!$Bytes){return ''}
 ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()
}

function Read-GuSecureBootState {
 $state=[ordered]@{Time=(Get-Date).ToString('o');SecureBootOn=[bool](Confirm-SecureBootUEFI);SetupMode=(Get-SecureBootUEFI -Name SetupMode).Bytes[0];Vars=[ordered]@{}}
 foreach($n in $GuKeyNames){$state.Vars[$n]=[byte[]](Get-SecureBootUEFI -Name $n).Bytes}
 $state
}

# Returns one row per signature: type GUID, owner GUID and data, as text, in stream order.
function Get-GuEslEntries([byte[]]$Bytes) {
 $rows=New-Object System.Collections.Generic.List[string];$o=0
 if(!$Bytes){return ,$rows}
 while($o -lt $Bytes.Length) {
  if($Bytes.Length-$o -lt 28){throw "Truncated signature list at offset $o"}
  $type=[guid]::new([byte[]]$Bytes[$o..($o+15)])
  $size=[BitConverter]::ToUInt32($Bytes,$o+16);$header=[BitConverter]::ToUInt32($Bytes,$o+20);$sig=[BitConverter]::ToUInt32($Bytes,$o+24)
  if($size -lt 28 -or $o+$size -gt $Bytes.Length -or $sig -lt 16 -or ($size-28-$header)%$sig){throw "Malformed signature list at offset $o"}
  for($p=$o+28+$header;$p -lt $o+$size;$p+=$sig) {
   $owner=[guid]::new([byte[]]$Bytes[$p..($p+15)])
   $rows.Add("$type|$owner|"+[BitConverter]::ToString($Bytes,$p+16,$sig-16).Replace('-',''))
  }
  $o+=$size
 }
 ,$rows
}

# Old/New: hashtables name->byte[]. Esl: the appended list, or $null when New must equal Old.
# Returns @{Ok=bool; Lines=string[]}.
function Compare-GuSecureBoot($Old,$New,[byte[]]$Esl) {
 $lines=@();$ok=$true
 foreach($n in @('PK','KEK','dbx')) {
  $same=(Get-GuSha $Old[$n]) -eq (Get-GuSha $New[$n])
  $lines+=('{0,-4} {1}' -f $n,$(if($same){'unchanged'}else{'CHANGED'}));if(!$same){$ok=$false}
 }
 $oldDb=[byte[]]$Old['db'];$newDb=[byte[]]$New['db']
 if($null -eq $Esl) {
  $same=(Get-GuSha $oldDb) -eq (Get-GuSha $newDb)
  $lines+=('db   {0}' -f $(if($same){'identical to the backup'}else{'DIFFERS from the backup'}));if(!$same){$ok=$false}
 } else {
  $before=Get-GuEslEntries $oldDb;$after=Get-GuEslEntries $newDb;$added=Get-GuEslEntries $Esl
  $expected=[Collections.Generic.HashSet[string]]::new([string[]]$before);foreach($e in $added){[void]$expected.Add($e)}
  $actual=[Collections.Generic.HashSet[string]]::new([string[]]$after)
  $missing=@($expected|Where-Object{!$actual.Contains($_)});$extra=@($actual|Where-Object{!$expected.Contains($_)})
  $prefix=$newDb.Length -ge $oldDb.Length -and (Get-GuSha $oldDb) -eq (Get-GuSha ([byte[]]$newDb[0..($oldDb.Length-1)]))
  $lines+=('db   entries before {0}, now {1}, in the appended list {2}' -f $before.Count,$after.Count,$added.Count)
  $lines+=('db   missing {0}, unexpected {1} (both must be 0)' -f $missing.Count,$extra.Count)
  $lines+=('db   original content kept as prefix: {0}' -f $(if($prefix){'yes'}else{'no (firmware reordered the lists; the line above decides)'}))
  if($missing.Count -or $extra.Count -or $after.Count -ne $before.Count+$added.Count){$ok=$false}
 }
 @{Ok=$ok;Lines=$lines}
}
