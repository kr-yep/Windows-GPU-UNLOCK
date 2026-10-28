#pragma once
#include "port.h"
EFI_STATUS GuIoOpen(EFI_HANDLE Image,EFI_SYSTEM_TABLE *Table);
EFI_STATUS GuIoClose(VOID);
EFI_STATUS GuLoadAssets(VOID);
VOID GuReleaseAssets(VOID);
BOOLEAN GuLogReady(VOID);
VOID GuConsole(const char *Text);
#ifdef GU_PRODUCTION_BOOT
#if !defined(GU_AUTOMATIC_BOOT) || !defined(GU_HEADLESS_RESEARCH) || !defined(GU_USB_MEDIA)
#error GU_PRODUCTION_BOOT is the headless USB automatic child only
#endif
/* Production writes no log, so log health is not an authorization input. */
#define GuLogGate() TRUE
VOID GuRecordFailure(const char *Stage,EFI_STATUS Status);
#else
#define GuLogGate() GuLogReady()
#endif
