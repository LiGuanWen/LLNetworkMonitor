//
//  LLNetworkMonitor.m
//  Pods-LLNetworkMonitor
//
//  Created by Lilong on 2018/7/23.
//

#import "LLNetworkMonitor.h"
#import <UIKit/UIKit.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCellularData.h>
#import <SystemConfiguration/SystemConfiguration.h>

#import <netdb.h>
#import <sys/socket.h>
#import <netinet/in.h>

#import <RealReachability/RealReachability.h>


NSString * const LLNetworkMonitorChangedNotification = @"LLNetworkMonitorChangedNotification";

@interface LLNetworkMonitor(){
    SCNetworkReachabilityRef _reachabilityRef;
    CTCellularData *_cellularData;
    NSMutableArray *_checkingCallbacks;
    LLNetworkAccessibleState _previousState;
    UIAlertController *_alertController;
    BOOL _automaticallyAlert;
    NetworkAccessibleStateNotifier _networkAccessibleStateDidUpdateNotifier;
}
@end


@implementation LLNetworkMonitor

#pragma mark - Public

/**
 开启网络监测
 */
+ (void)beginUseNetworkMonitor{
    [LLNetworkMonitor sharedInstance];
}
+ (void)setAlertEnable:(BOOL)setAlertEnable {
    [self sharedInstance]->_automaticallyAlert = setAlertEnable;
}


+ (void)checkState:(void (^)(LLNetworkAccessibleState))block {
    [[self sharedInstance] checkNetworkAccessibleStateWithCompletionBlock:block];
}


+ (void)monitor:(void (^)(LLNetworkAccessibleState))block {
    [[self sharedInstance] monitorNetworkAccessibleStateWithCompletionBlock:block];
}

+ (LLNetworkAccessibleState)currentState {
    return [[self sharedInstance] currentState];
}

/**
 获取当前网络
 
 @param block 网络类型
 */
+ (void)getCurrNetworkType:(void(^)(LLNetworkType networkType))block {
    if ([[LLNetworkMonitor sharedInstance] isWiFiEnable]) {
        return block(LLNetworkTypeWiFi);
    }
    LLNetworkType type = [[LLNetworkMonitor sharedInstance] getNetworkTypeFromStatusBar];
    if (type == LLNetworkTypeWiFi) { // 这时候从状态栏拿到的是 Wi-Fi 说明状态栏没有刷新，延迟一会再获取
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[LLNetworkMonitor sharedInstance] getCurrentNetworkType:block];
        });
    } else {
        block(type);
    }
}

#pragma mark - Public entity method


+ (LLNetworkMonitor *)sharedInstance {
    static LLNetworkMonitor * instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}


- (void)setNetworkAccessibleStateDidUpdateNotifier:(NetworkAccessibleStateNotifier)networkAccessibleStateDidUpdateNotifier {
    _networkAccessibleStateDidUpdateNotifier = [networkAccessibleStateDidUpdateNotifier copy];
    [self startCheck];
}


- (void)checkNetworkAccessibleStateWithCompletionBlock:(void (^)(LLNetworkAccessibleState))block {
    [_checkingCallbacks addObject:[block copy]];
    [self startCheck];
}


- (void)monitorNetworkAccessibleStateWithCompletionBlock:(void (^)(LLNetworkAccessibleState))block {
    _networkAccessibleStateDidUpdateNotifier = [block copy];
}

- (LLNetworkAccessibleState)currentState {
    return _previousState;
}

#pragma mark - Life cycle


- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)init {
    if (self = [super init]) {
        _cellularData = [[CTCellularData alloc] init];
        __weak __typeof(self)weakSelf = self;
        // 利用 cellularDataRestrictionDidUpdateNotifier 的回调时机来进行首次检查，因为如果启动时就去检查 会得到 kCTCellularDataRestrictedStateUnknown 的结果
        _cellularData.cellularDataRestrictionDidUpdateNotifier = ^(CTCellularDataRestrictedState state) {
            __strong __typeof(weakSelf)strongSelf = weakSelf;
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf startCheck];
                // 只需要检查一遍
                strongSelf->_cellularData.cellularDataRestrictionDidUpdateNotifier = nil;
            });
        };
        // 监听网络变化状态
        _reachabilityRef = ({
            struct sockaddr_in zeroAddress;
            bzero(&zeroAddress, sizeof(zeroAddress));
            zeroAddress.sin_len = sizeof(zeroAddress);
            zeroAddress.sin_family = AF_INET;
            SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *) &zeroAddress);
        });
        _checkingCallbacks = [NSMutableArray array];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive) name:UIApplicationWillResignActiveNotification object:[UIApplication sharedApplication]];
        [self startNotifier];
    }
    return self;
}

#pragma mark - NSNotification
- (void)applicationWillResignActive {
    [self hideNetworkRestrictedAlert];
}

#pragma mark - Private


static void ReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void* info) {
    LLNetworkMonitor *networkAccessibity = (__bridge LLNetworkMonitor *)info;
    if (![networkAccessibity isKindOfClass: [LLNetworkMonitor class]]) {
        return;
    }
    [networkAccessibity startCheck];
}

// 监听用户从 Wi-Fi 切换到 蜂窝数据，或者从蜂窝数据切换到 Wi-Fi，另外当从授权到未授权，或者未授权到授权也会调用该方法
- (BOOL)startNotifier {
    BOOL returnValue = NO;
    SCNetworkReachabilityContext context = {0, (__bridge void *)(self), NULL, NULL, NULL};
    if (SCNetworkReachabilitySetCallback(_reachabilityRef, ReachabilityCallback, &context)){
        if (SCNetworkReachabilityScheduleWithRunLoop(_reachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode)){
            returnValue = YES;
        }
    }
    return returnValue;
}




- (void)startCheck {
    if ([UIDevice currentDevice].systemVersion.floatValue < 10.0 || [self currentReachable]) {
        /* iOS 10 以下 不够用检测默认通过 **/
        
        /* 先用 currentReachable 判断，若返回的为 YES 则说明：
         1. 用户选择了 「WALN 与蜂窝移动网」并处于其中一种网络环境下。
         2. 用户选择了 「WALN」并处于 WALN 网络环境下。
         
         此时是有网络访问权限的，直接返回 LLNetworkAccessible
         **/
        [self notiWithAccessibleState:LLNetworkAccessible];
        return;
    }
    CTCellularDataRestrictedState state = _cellularData.restrictedState;
    switch (state) {
        case kCTCellularDataRestricted: {// 系统 API 返回 无蜂窝数据访问权限
            [self getCurrentNetworkType:^(LLNetworkType type) {
                /*  若用户是通过蜂窝数据 或 WLAN 上网，走到这里来 说明权限被关闭**/
                if (type == LLNetworkTypeCellularData || type == LLNetworkTypeWiFi) {
                    [self notiWithAccessibleState:LLNetworkRestricted];
                } else {  // 可能开了飞行模式，无法判断
                    [self notiWithAccessibleState:LLNetworkUnknown];
                }
            }];
            break;
        }
        case kCTCellularDataNotRestricted: // 系统 API 访问有有蜂窝数据访问权限，那就必定有 Wi-Fi 数据访问权限
            [self notiWithAccessibleState:LLNetworkAccessible];
            break;
        case kCTCellularDataRestrictedStateUnknown:
            [self notiWithAccessibleState:LLNetworkUnknown];
            break;
        default:
            break;
    };
}


/**
 获取当前网络
 
 @param block 网络类型
 */
- (void)getCurrentNetworkType:(void(^)(LLNetworkType))block {
    
    if ([self isWiFiEnable]) {
        return block(LLNetworkTypeWiFi);
    }
    LLNetworkType type = [self getNetworkTypeFromStatusBar];
    if (type == LLNetworkTypeWiFi) { // 这时候从状态栏拿到的是 Wi-Fi 说明状态栏没有刷新，延迟一会再获取
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self getCurrentNetworkType:block];
        });
    } else {
        block(type);
    }
}

- (LLNetworkType)getNetworkTypeFromStatusBar {
    NSInteger type = 0;
    @try {
        GLobalRealReachability.hostForPing = @"www.baidu.com";
        [GLobalRealReachability startNotifier];
        //        RealStatusUnknown = -1,
        //        RealStatusNotReachable = 0,
        //        RealStatusViaWWAN = 1,
        //        RealStatusViaWiFi = 2
        ReachabilityStatus status = [GLobalRealReachability currentReachabilityStatus];
        //        LLNetworkTypeUnknown ,             //未知
        //        LLNetworkTypeOffline ,             //关闭
        //        LLNetworkTypeWiFi    ,             //WiFi
        //        LLNetworkTypeCellularData ,        //数据流量
        switch (status) {
            case RealStatusUnknown:
                return LLNetworkTypeUnknown;
                break;
            case RealStatusNotReachable:
                return LLNetworkTypeOffline;
                break;
            case RealStatusViaWWAN:
                return LLNetworkTypeCellularData;
                break;
            case RealStatusViaWiFi:
                return LLNetworkTypeWiFi;
                break;
            default:
                break;
        }
    } @catch (NSException *exception) {
        
    }
    return 0;
}


/**
 判断用户是否连接到 Wi-Fi
 */
- (BOOL)isWiFiEnable {
    NSArray *interfaces = (__bridge_transfer NSArray *)CNCopySupportedInterfaces();
    if (!interfaces) {
        return NO;
    }
    NSDictionary *info = nil;
    for (NSString *ifnam in interfaces) {
        info = (__bridge_transfer NSDictionary *)CNCopyCurrentNetworkInfo((__bridge CFStringRef)ifnam);
        if (info && [info count]) { break; }
    }
    return (info != nil);
}



- (BOOL)currentReachable {
    SCNetworkReachabilityFlags flags;
    if (SCNetworkReachabilityGetFlags(self->_reachabilityRef, &flags)) {
        if ((flags & kSCNetworkReachabilityFlagsReachable) == 0) {
            return NO;
        } else {
            return YES;
        }
    }
    return NO;
}



#pragma mark - Callback

- (void)notiWithAccessibleState:(LLNetworkAccessibleState)state {
    if (_automaticallyAlert) {
        if (state == LLNetworkRestricted) {
            [self showNetworkRestrictedAlert];
        } else {
            [self hideNetworkRestrictedAlert];
        }
    }
    
    if (state != _previousState) {
        _previousState = state;
    }
    
    if (_networkAccessibleStateDidUpdateNotifier) {
        _networkAccessibleStateDidUpdateNotifier(state);
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:LLNetworkMonitorChangedNotification object:nil];
    for (NetworkAccessibleStateNotifier block in _checkingCallbacks) {
        block(state);
    }
    [_checkingCallbacks removeAllObjects];
}

- (void)showNetworkRestrictedAlert {
    if (self.alertController.presentingViewController == nil && ![self.alertController isBeingPresented]) {
        if ([UIApplication sharedApplication].keyWindow.rootViewController) {
            [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:self.alertController animated:YES completion:nil];
        }
    }
}

- (void)hideNetworkRestrictedAlert {
    [_alertController dismissViewControllerAnimated:YES completion:nil];
}

- (UIAlertController *)alertController {
    if (!_alertController) {
        _alertController = [UIAlertController alertControllerWithTitle:@"网络连接失败" message:@"检测到网络权限可能未开启，您可以在“设置”中检查蜂窝移动网络" preferredStyle:UIAlertControllerStyleAlert];
        [_alertController addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            [self hideNetworkRestrictedAlert];
        }]];
        [_alertController addAction:[UIAlertAction actionWithTitle:@"设置" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSURL *settingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
            if([[UIApplication sharedApplication] canOpenURL:settingsURL]) {
                [[UIApplication sharedApplication] openURL:settingsURL];
            }
        }]];
    }
    return _alertController;
}

@end
