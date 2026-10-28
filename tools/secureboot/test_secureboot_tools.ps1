# GPL-2.0-only. Qualification for make_db_esl.py and Compare-GuSecureBoot: synthetic data, no admin, no firmware access.
# -Images: unsigned EFI files to hash. -OsslSignCode/-Key/-Cert: optional cross-check of the Authenticode hash.
param([Parameter(Mandatory)][string[]]$Images,[string]$Python='python',[string]$OsslSignCode,[string]$Key,[string]$Cert)
$ErrorActionPreference='Stop'
$Images=@($Images | ForEach-Object {$_ -split ','})
. (Join-Path $PSScriptRoot 'SecureBootKeys.ps1')
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('sbtest-'+[guid]::NewGuid());New-Item -ItemType Directory $tmp | Out-Null
$checks=0
function Expect($cond,$name){if(!$cond){throw "FAIL $name"};$script:checks++}
function Rand([int]$n){$b=New-Object byte[] $n;[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b);,$b}
# One synthetic signature list: $count entries of $data bytes each, random owners and data.
function List([string]$type,[int]$count,[int]$data){
 $sig=16+$data;$size=28+$sig*$count
 $out=[Collections.Generic.List[byte]]::new();$out.AddRange([byte[]]([guid]$type).ToByteArray())
 foreach($v in @($size,0,$sig)){$out.AddRange([byte[]][BitConverter]::GetBytes([uint32]$v))}
 for($i=0;$i -lt $count;$i++){$out.AddRange([byte[]](Rand 16));$out.AddRange([byte[]](Rand $data))};,$out.ToArray()
}
try {
 # 1. ESL from the real images; structure matches what the F4 parser accepts.
 $esl=Join-Path $tmp 'db-append.esl'
 & $Python -I (Join-Path $PSScriptRoot 'make_db_esl.py') $esl @Images | Out-Null
 Expect ($LASTEXITCODE -eq 0) 'make_db_esl exit'
 $meta=Get-Content -Raw "$esl.json" | ConvertFrom-Json;$bytes=[IO.File]::ReadAllBytes($esl)
 $rows=Get-GuEslEntries $bytes
 Expect ($rows.Count -eq $Images.Count -and $bytes.Length -eq 28+48*$Images.Count) 'ESL entry count and size'
 Expect ([BitConverter]::ToUInt32($bytes,20) -eq 0) 'SignatureHeaderSize is zero'
 for($i=0;$i -lt $Images.Count;$i++){Expect ($rows[$i].Split('|')[2] -eq $meta.images[$i].authenticodeSha256.ToUpperInvariant()) "entry $i data"}
 Expect ($rows[0].Split('|')[0] -eq 'c1c41626-504c-4092-aca9-41f936934328') 'SHA256 signature type'
 # 2. Authenticode hash agrees with osslsigncode's calculated digest of a signed copy.
 if($OsslSignCode) {
  for($i=0;$i -lt $Images.Count;$i++) {
   $signed=Join-Path $tmp "signed-$i.efi"
   $ErrorActionPreference='Continue'  # native tools write warnings to stderr; exit codes decide
   & $OsslSignCode sign -h sha256 -key $Key -certs $Cert -in $Images[$i] -out $signed 2>&1 | Out-Null
   Expect ($LASTEXITCODE -eq 0) "osslsigncode sign $i"
   $v=(& $OsslSignCode verify -CAfile $Cert -in $signed 2>&1) -join "`n"
   $calc=[regex]::Match($v,'Calculated message digest\s*:\s*([0-9A-Fa-f ]+)').Groups[1].Value.Replace(' ','')
   Expect ($calc -and $calc.ToLowerInvariant() -eq $meta.images[$i].authenticodeSha256) "authenticode cross-check $i"
   & $Python -I (Join-Path $PSScriptRoot 'make_db_esl.py') (Join-Path $tmp "refuse-$i.esl") $signed 2>&1 | Out-Null
   Expect ($LASTEXITCODE -ne 0) "signed image refused $i"
   $ErrorActionPreference='Stop'
  }
 }
 # 3. Snapshot comparison.
 $x509='a5c059a1-94e4-4aa7-87b5-ab155c2bf072';$sha='c1c41626-504c-4092-aca9-41f936934328'
 $db=[byte[]]((List $x509 1 900)+(List $x509 1 1100)+(List $sha 2 32))
 $old=@{PK=(Rand 810);KEK=(Rand 3884);db=$db;dbx=(List $sha 3 32)}
 function Copy-State($s){$c=@{};foreach($k in $s.Keys){$c[$k]=[byte[]]$s[$k].Clone()};$c}
 $new=Copy-State $old
 Expect (Compare-GuSecureBoot $old $new $null).Ok 'unchanged without ESL'
 Expect (!(Compare-GuSecureBoot $old $new $bytes).Ok) 'ESL expected but not added'
 $new.db=[byte[]]($old.db+$bytes);Expect (Compare-GuSecureBoot $old $new $bytes).Ok 'appended at end'
 Expect (!(Compare-GuSecureBoot $old $new $null).Ok) 'added list detected without ESL'
 $new.db=[byte[]]($bytes+$old.db);$r=Compare-GuSecureBoot $old $new $bytes
 Expect ($r.Ok -and ($r.Lines -join "`n") -match 'prefix: no') 'reordered db accepted, prefix reported'
 $new.db=[byte[]]($old.db+$bytes+(List $x509 1 700));Expect (!(Compare-GuSecureBoot $old $new $bytes).Ok) 'extra list refused'
 $new.db=[byte[]]((List $x509 1 900)+$bytes)
 Expect (!(Compare-GuSecureBoot $old $new $bytes).Ok) 'lost existing entries refused'
 foreach($k in @('PK','KEK','dbx')){$new=Copy-State $old;$new.db=[byte[]]($old.db+$bytes);$new[$k][5]=$new[$k][5] -bxor 1
  Expect (!(Compare-GuSecureBoot $old $new $bytes).Ok) "$k change refused"}
 $bad=[byte[]]$bytes.Clone();$bad[16]=$bad[16]+1;$threw=$false;try{Get-GuEslEntries $bad|Out-Null}catch{$threw=$true}
 Expect $threw 'malformed list size refused'
 "PASS $checks secure-boot tool checks; synthetic snapshots, no firmware access."
} finally {Remove-Item -Recurse -Force $tmp}
