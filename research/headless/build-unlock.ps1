# GPL-2.0-only. Isolated exact-platform headless unlock wrapper/child package.
# -Production builds the daily-boot pair for a dedicated ESP (no Esc waits, captures or success
# logs) into build/headless-production; a local profile builds only that variant.
param([string]$Clang='clang',[string]$LldLink='lld-link',[string]$Python='python',[ValidateSet('b650m-3090fe','b660m-3070ti','b660m-3090ti','local')][string]$HardwareProfile='b650m-3090fe',[switch]$Production)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $repo 'internal-boot/install/headless-package.ps1')
. (Join-Path $repo 'internal-boot/unlock/local-profile.ps1')
if($HardwareProfile -eq 'local'){
 if(!$Production){throw 'A local profile builds only the daily-boot (-Production) ESP package'}
 $local=Get-LocalProfile $repo;$localEvidence=Assert-LocalProfileEvidence $repo
 $localEvidenceSha=Get-GuSha256 (Join-Path $repo 'research/profile/local/test-results.json')
 $hwDefine=$local.Define;$hwName=$local.Name
}else{
 $hwDefine=switch($HardwareProfile){'b660m-3070ti'{'-DGU_PROFILE_B660M_3070TI'}'b660m-3090ti'{'-DGU_PROFILE_B660M_3090TI'}default{'-DGU_PROFILE_B650M_3090FE'}}
 $hwName=switch($HardwareProfile){'b660m-3070ti'{'ASUS-TUF-GAMING-B660M-E-D4-4003-RTX3070TI'}'b660m-3090ti'{'ASUS-TUF-GAMING-B660M-E-D4-4003-RTX3090TI'}default{'ASUS-TUF-B650M-PLUS-WIFI-3057-RTX3090-FE'}}
}
$null=Assert-HeadlessLocalConfig $repo
$beforeInputs=Get-HeadlessInputInventory $repo
$unlock=Join-Path $repo 'internal-boot/unlock'
& (Join-Path $unlock 'build.ps1') -ExperimentalUnlock -StockProfile entryLatchedSs1Full -InternalBoot -AutomaticBoot -HeadlessResearch -Production:$Production -Clang $Clang -LldLink $LldLink -Python $Python -HardwareProfile $HardwareProfile
if(!$?){throw 'Headless child build failed'}
$child=Join-Path $repo (Get-HeadlessChildPath -Production:$Production)
$childMode=if($Production){'production-headless-esp-automatic-exact-card-unlock'}else{'headless-research-automatic-internal-exact-card-unlock'}
$cm=Get-Content (Join-Path (Split-Path $child) 'build-manifest.json') -Raw | ConvertFrom-Json
$hash=(Get-FileHash -LiteralPath $child).Hash.ToLowerInvariant()
if($cm.Mode -ne $childMode -or $cm.EfiSha256 -ne $hash -or $cm.StockProfile -ne 'entryLatchedSs1Full' -or !$cm.CanArm -or $cm.HardwareProfile -ne $hwName){throw 'Headless child contract mismatch'}
$hl=if($Production){'build/headless-production'}else{'build/headless'}
Push-Location (Join-Path $repo 'internal-boot/boot')
try {
 [void][IO.Directory]::CreateDirectory((Join-Path $PWD $hl))
 @('/* Local headless child contract; GPL-2.0-only. */',('#define GU_UNLOCK_SHA256 "'+$hash+'"'),('#define GU_UNLOCK_BYTES '+(Get-Item $child).Length)) | Set-Content "$hl/child-contract.h" -Encoding ascii
 $sources=@('handoff.c','full-release.c','full-flow.c')+$(if($Production){@()}else{@('diagnostic.c')})+@('../unlock/checks.c','../unlock/sha256.c','../efi_runtime.c')
 $wrapperDefines=@('-DGU_HEADLESS_RESEARCH','-DGU_SINGLE_RTX_CONSOLE','-DGU_FULL_UNLOCK','-DGU_AUTOMATIC_BOOT')+$(if($Production){@('-DGU_PRODUCTION_BOOT')}else{@()})
 $objects=@()
 foreach($source in $sources) {
  $obj="$hl/"+[IO.Path]::GetFileNameWithoutExtension($source)+'.obj'
  & $Clang -target x86_64-pc-windows-msvc -std=c11 -ffreestanding -fno-builtin -fno-stack-protector -mno-red-zone -fshort-wchar -Os -Wall -Wextra -Werror @wrapperDefines $hwDefine -I ../../deps/edk2/MdePkg/Include -I ../../deps/edk2/MdePkg/Include/X64 -c $source -o $obj
  if($LASTEXITCODE -ne 0){throw "Headless wrapper compile failed: $source"};$objects+=$obj
 }
 & $LldLink /nologo /nodefaultlib /subsystem:efi_application /entry:efi_main /machine:x64 /base:0 /dynamicbase /nxcompat /timestamp:0 /opt:ref /opt:icf "/map:$hl/HEADLESS.map" "/out:$hl/HEADLESS.EFI" @objects
 if($LASTEXITCODE -ne 0){throw 'Headless wrapper link failed'}
 & $Python ../unlock/verify_pe.py "$hl/HEADLESS.EFI" "$hl/HEADLESS.map" --output "$hl/pe-verification.json"
 if($LASTEXITCODE -ne 0){throw 'Headless wrapper PE verification failed'}
 $afterInputs=Get-HeadlessInputInventory $repo
 if(($beforeInputs | ConvertTo-Json -Depth 4 -Compress) -cne ($afterInputs | ConvertTo-Json -Depth 4 -Compress)){throw 'Inputs changed while building; no package manifest will be published'}
 $m=[ordered]@{Format=2;HardwareProfile=$hwName;Mode=$(if($Production){'production-single-rtx-headless-unlock-then-windows'}else{'single-rtx-headless-unlock-then-windows'});CanUnlock=$true;RequiresHumanKey=$false;HardwareTested=$false;ChildSha256=$hash;ChildBytes=(Get-Item $child).Length;ChildManifestSha256=(Get-FileHash -LiteralPath (Join-Path (Split-Path $child) 'build-manifest.json')).Hash;EfiSha256=(Get-FileHash -LiteralPath "$hl/HEADLESS.EFI").Hash;EfiBytes=(Get-Item "$hl/HEADLESS.EFI").Length;Inputs=(Get-HeadlessInputInventory $repo -WithContract -Production:$Production);BuiltUtc=[DateTime]::UtcNow.ToString('o')}
 if($HardwareProfile -eq 'local'){
  $currentEvidence=Assert-LocalProfileEvidence $repo
  if($currentEvidence.TreeSha256 -cne $localEvidence.TreeSha256 -or (Get-LocalProfile $repo).HeaderSha256 -cne $local.HeaderSha256 -or
     (Get-GuSha256 (Join-Path $repo 'research/profile/local/test-results.json')) -cne $localEvidenceSha){throw 'Local build inputs or evidence changed while packaging; rerun tests and rebuild'}
  $m.LocalProfileHeaderSha256=$local.HeaderSha256;$m.LocalProfileTreeSha256=$localEvidence.TreeSha256;$m.LocalProfileEvidenceSha256=$localEvidenceSha
 }
 $m | ConvertTo-Json -Depth 6 | Set-Content "$hl/manifest.json" -Encoding utf8
 $null=Assert-HeadlessPackage $repo -Production:$Production
} finally {Pop-Location}
