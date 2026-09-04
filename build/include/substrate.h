/* Minimal substrate.h — provides the CydiaSubstrate/ElleKit hooking symbols.
 * On iOS 16.5 + TrollStore the real implementation is supplied by ElleKit at
 * load time, so we only need the compile-time declarations here.
 * Linked with -undefined dynamic_lookup. */
#ifndef SUBSTRATE_H
#define SUBSTRATE_H

#import <objc/runtime.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Hook an instance method. result receives the original IMP. */
void MSHookMessageEx(Class _class, SEL _selector, IMP _imp, IMP *result);

/* Hook a C function (unused by WeChatGroupSummary, declared for completeness). */
void MSHookFunction(void *symbol, void *replace, void **result);

#ifdef __cplusplus
}
#endif

#endif /* SUBSTRATE_H */
