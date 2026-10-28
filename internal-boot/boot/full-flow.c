/* GPL-2.0-only. No retry, fallback or Windows after a release/unlock failure. */
#include "full-flow.h"
EFI_STATUS GuFullFlow(const GU_FULL_FLOW_OPS *o) {
#ifdef GU_PRODUCTION_BOOT
  /* Production has no diagnostic graph capture; Capture must be absent. */
  if(!o || !o->Prepare || !o->Choose || o->Capture || !o->Release || !o->VerifyCold || !o->Unlock || !o->WindowsSkip || !o->WindowsAfter || !o->Record)return EFI_INVALID_PARAMETER;
#else
  if(!o || !o->Prepare || !o->Choose || !o->Capture || !o->Release || !o->VerifyCold || !o->Unlock || !o->WindowsSkip || !o->WindowsAfter || !o->Record)return EFI_INVALID_PARAMETER;
#endif
  EFI_STATUS s=o->Prepare(o->Context);if(s!=EFI_SUCCESS)return s;
  BOOLEAN skip=FALSE;s=o->Choose(o->Context,&skip);if(s!=EFI_SUCCESS)return s;
  if(skip) {
    s=o->Record(o->Context,"full-unlock-skipped-no-driver-release",EFI_SUCCESS);
    if(s==EFI_SUCCESS)s=o->WindowsSkip(o->Context);
    return s==EFI_SUCCESS?EFI_ABORTED:s;
  }
#ifndef GU_PRODUCTION_BOOT
  s=o->Capture(o->Context);if(s!=EFI_SUCCESS)return s;
#endif
  EFI_STATUS released=o->Release(o->Context);
#ifndef GU_PRODUCTION_BOOT
  EFI_STATUS captured=o->Capture(o->Context);
#endif
  s=o->Record(o->Context,"full-preparation-result",released);
  if(released!=EFI_SUCCESS)return released;
#ifndef GU_PRODUCTION_BOOT
  if(captured!=EFI_SUCCESS)return captured;
#endif
  if(s!=EFI_SUCCESS)return s;
#ifdef GU_AUTOMATIC_BOOT
  s=o->Record(o->Context,"automatic-unlock-start-Esc-cancels",EFI_SUCCESS);if(s!=EFI_SUCCESS)return s;
#else
  s=o->Record(o->Context,"original-unlock-start-manual-U-required",EFI_SUCCESS);if(s!=EFI_SUCCESS)return s;
#endif
  s=o->VerifyCold(o->Context);if(s!=EFI_SUCCESS)return s;
  s=o->Unlock(o->Context);
  EFI_STATUS recorded=o->Record(o->Context,"original-unlock-return",s);
  if(s!=EFI_SUCCESS)return s;
  if(recorded!=EFI_SUCCESS)return recorded;
  s=o->Record(o->Context,"full-windows-start",EFI_SUCCESS);if(s!=EFI_SUCCESS)return s;
  s=o->WindowsAfter(o->Context);
  return s==EFI_SUCCESS?EFI_ABORTED:s;
}
