#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "JccChains.h"
#import "JTWalletManager.h"
#import "BaseWallet.h"
#import "JingtumWallet.h"

FOUNDATION_EXPORT double jcc_oc_base_libVersionNumber;
FOUNDATION_EXPORT const unsigned char jcc_oc_base_libVersionString[];

