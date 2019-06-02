//
//  AppDelegate.m
//  TokenBank
//
//  Created by MarcusWoo on 31/12/2017.
//  Copyright © 2017 MarcusWoo. All rights reserved.
//

#import "AppDelegate.h"
#import "TPOSTabBarController.h"
#import "TPOSNavigationController.h"
#import "TPOSGuideViewController.h"
#import "TPOSWeb3Handler.h"
#import "TPOSContext.h"
#import "TPOSProtocolViewController.h"
#import "TPOSMacro.h"
#import "TPOSWalletDao.h"
#import "TPOSForceCreateWalletViewController.h"
#import "UIColor+Hex.h"
#import "TPOSJTPayment.h"
#import "TPOSCommonInfoManager.h"
#import "TPOSEnterAuthViewController.h"
#import "WXApi.h"
#import <TencentOpenAPI/QQApiInterface.h>
#import <TencentOpenAPI/TencentOAuth.h>
#import "TPOSWalletModel.h"
#import "NSString+TPOS.h"
//#import "TPOSBackupAlert.h"

//#import "TPOSTransactionRecoderModel.h"

@import IQKeyboardManager;
@import AFNetworking;
@import SDWebImage;
@import Bugly;
@import SVProgressHUD;

@interface AppDelegate ()

@property (nonatomic, strong) TPOSWalletDao *walletDao;

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    [self rootViewController:^(UIViewController *viewController) {
        //初始化界面设置
        TPOSNavigationController *navigationController = [[TPOSNavigationController alloc] initWithRootViewController:viewController];
        self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        self.window.rootViewController = navigationController;
        [self.window makeKeyAndVisible];
    }];
    
    //设置IQKeyboard
    [[IQKeyboardManager sharedManager] setEnable:YES];
    [[IQKeyboardManager sharedManager] setShouldResignOnTouchOutside:YES];
    [[IQKeyboardManager sharedManager] setEnableAutoToolbar:NO];
    
    //设置SDWebImageCache
    [[SDImageCache sharedImageCache] setMaxMemoryCost:30 * 1024 * 1024]; //内存使用控制在30mb
    
    [SVProgressHUD setDefaultStyle:SVProgressHUDStyleDark];
    
    //图片无法加载问题
    NSString *userAgent = @"";
    userAgent = [NSString stringWithFormat:@"%@/%@ (%@; iOS %@; Scale/%0.2f)", [[[NSBundle mainBundle] infoDictionary] objectForKey:(__bridge NSString *)kCFBundleExecutableKey] ?: [[[NSBundle mainBundle] infoDictionary] objectForKey:(__bridge NSString *)kCFBundleIdentifierKey], [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] ?: [[[NSBundle mainBundle] infoDictionary] objectForKey:(__bridge NSString *)kCFBundleVersionKey], [[UIDevice currentDevice] model], [[UIDevice currentDevice] systemVersion], [[UIScreen mainScreen] scale]];
    
    if (userAgent) {
        if (![userAgent canBeConvertedToEncoding:NSASCIIStringEncoding]) {
            NSMutableString *mutableUserAgent = [userAgent mutableCopy];
            if (CFStringTransform((__bridge CFMutableStringRef)(mutableUserAgent), NULL, (__bridge CFStringRef)@"Any-Latin; Latin-ASCII; [:^ASCII:] Remove", false)) {
                userAgent = mutableUserAgent;
            }
        }
        [[SDWebImageDownloader sharedDownloader] setValue:userAgent forHTTPHeaderField:@"User-Agent"];
    }
    
    //启动Web3
    TPOSWeb3Handler *webHandler = [TPOSWeb3Handler sharedManager];
    __weak typeof(webHandler) weakHnadler = webHandler;
    [webHandler initWebEnviromentWithFinishCallback:^{
        [weakHnadler initWeb3WithProvider:nil callback:nil];
    } mnemonicCallback:^{
//        TPOSLog(@"mnemonicCallback");
    }];

    [[AFNetworkReachabilityManager sharedManager] startMonitoring];

    [[UINavigationBar appearance] setBarTintColor:[UIColor colorWithHex:0x2890FE]];
    [[UINavigationBar appearance] setBackgroundColor:[UIColor colorWithHex:0x2890FE]];
    
    UIColor *foregroundColor = [UIColor whiteColor];
    NSDictionary *titleTextAttributes = [NSDictionary dictionaryWithObjectsAndKeys:foregroundColor, NSForegroundColorAttributeName, [UIFont systemFontOfSize:18], NSFontAttributeName, nil];
    [[UINavigationBar appearance] setTitleTextAttributes:titleTextAttributes];

    //获取所有公链
    [[TPOSCommonInfoManager shareInstance] storeAllBlockchainInfos];
    
    //恢复数据
    [TPOSContext shareInstance];
    [self registerNotifications];
    //检查数据库更新
    [self checkDBVersion];
    
    NSLog(@"NSHomeDirectory:%@",NSHomeDirectory());
    
    return YES;
}

//数据库升级
- (void)checkDBVersion {
    NSMutableArray *shouldUpWallet = [NSMutableArray array];
    [self.walletDao findAllWithComplement:^(NSArray<TPOSWalletModel *> *walletModels) {
        [walletModels enumerateObjectsUsingBlock:^(TPOSWalletModel * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if (obj.dbVersion < 1) {
                obj.dbVersion = 1;
                if ([ethChain isEqualToString:obj.blockChainId]) {
                    if (obj.isBackup) {
                        obj.mnemonic = nil;
                    } else {
                        obj.mnemonic = [obj.mnemonic tb_encodeStringWithKey:obj.password];
                    }
                } else {
                    obj.backup = NO;
                }
                [shouldUpWallet addObject:obj];
            }
        }];
    }];
    __weak typeof(self) weakSelf = self;
    [shouldUpWallet enumerateObjectsUsingBlock:^(TPOSWalletModel *  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [weakSelf.walletDao updateWalletWithWalletModel:obj complement:nil];
    }];
}

- (void)registerNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(addWallet) name:kCreateWalletNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deleteWallet) name:kDeleteWalletNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAuthSuccess:) name:kAuthEnterAppSuccessNotification object:nil];
}

- (void)onAuthSuccess:(NSNotification *)notification {
    
    UINavigationController *nav = (UINavigationController *)self.window.rootViewController;
    __weak typeof(nav) weakNav = nav;
    __weak typeof(self) weakSelf = self;
    
    [self.walletDao findAllWithComplement:^(NSArray<TPOSWalletModel *> *walletModels) {
        if (walletModels.count == 0) {
            TPOSForceCreateWalletViewController *forceCreateWalletViewController = [[TPOSForceCreateWalletViewController alloc] init];
            [weakNav setViewControllers:@[forceCreateWalletViewController] animated:NO];
        } else {
            [weakNav setViewControllers:@[weakSelf.tabbarController] animated:NO];
        }
    }];
}

- (void)addWallet {
    TPOSNavigationController *nvc = (TPOSNavigationController *)self.window.rootViewController;
    if (![nvc.viewControllers.firstObject isKindOfClass:[TPOSTabBarController class]]) {
        [nvc setViewControllers:@[self.tabbarController] animated:YES];
    }
}

- (void)deleteWallet {
    __weak typeof(self) weakSelf = self;
    [self.walletDao findAllWithComplement:^(NSArray<TPOSWalletModel *> *walletModels) {
        if (walletModels.count == 0) {
            TPOSNavigationController *nvc = (TPOSNavigationController *)weakSelf.window.rootViewController;
            [nvc setViewControllers:@[[[TPOSForceCreateWalletViewController alloc] init]] animated:YES];
            weakSelf.tabbarController = nil;
        }
    }];
}

- (void)rootViewController:(void (^)(UIViewController *viewController))root {
    BOOL shouldCheckFingerprint = [[[NSUserDefaults standardUserDefaults] objectForKey:kAuthSwithOnStatusKey] boolValue];
    if (shouldCheckFingerprint) {
        //返回指纹验证的VC
        TPOSEnterAuthViewController *vc = [[TPOSEnterAuthViewController alloc] initWithNibName:@"TPOSEnterAuthViewController" bundle:nil];
        root(vc);
    } else {
        [self.walletDao findAllWithComplement:^(NSArray<TPOSWalletModel *> *walletModels) {
            if (walletModels.count == 0) {
                TPOSForceCreateWalletViewController *forceCreateWalletViewController = [[TPOSForceCreateWalletViewController alloc] init];
                root(forceCreateWalletViewController);
            } else {
                root(self.tabbarController);
            }
        }];
    }
}

- (TPOSWalletDao *)walletDao {
    if (!_walletDao) {
        _walletDao = [TPOSWalletDao new];
    }
    return _walletDao;
}

- (TPOSTabBarController *)tabbarController {
    if (!_tabbarController) {
        _tabbarController = [[TPOSTabBarController alloc] init];
    }
    return _tabbarController;
}

@end
