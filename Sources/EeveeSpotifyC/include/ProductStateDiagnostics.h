#ifndef EEV_PRODUCT_STATE_DIAGNOSTICS_H
#define EEV_PRODUCT_STATE_DIAGNOSTICS_H
#import <Foundation/Foundation.h>
#import "NativeConfigDiagnostics.h"

NS_ASSUME_NONNULL_BEGIN
#ifdef __cplusplus
extern "C" {
#endif

// Observe values already available to the existing hooks. Never invoke extra
// getters, decode C++ objects, or modify account state for diagnostics.
void EEVStartProductStateDiagnostics(EEVConfigDiagnosticLogger logger);
void EEVProductStateDictionary(const char *event, id input, id output);
void EEVProductStateGetter(const char *event, NSString *key, id _Nullable value, BOOL forced);
void EEVProductStateAds(BOOL value, BOOL forced);
void EEVInstallProductStateBridgeProbe(void);
void EEVProductStateSummary(void);

#ifdef __cplusplus
}
#endif
NS_ASSUME_NONNULL_END
#endif
