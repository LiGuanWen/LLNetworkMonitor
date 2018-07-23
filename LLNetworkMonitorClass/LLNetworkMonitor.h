//
//  LLNetworkMonitor.h
//  Pods-LLNetworkMonitor
//
//  Created by Lilong on 2018/7/23.
//

#import <Foundation/Foundation.h>
extern NSString * const LLNetworkMonitorChangedNotification;

typedef NS_ENUM(NSUInteger, LLNetworkAccessibleState) {
    LLNetworkUnknown     = 0,   //未知
    LLNetworkAccessible  ,      //可进入的
    LLNetworkRestricted  ,     // 受限制的
};

typedef NS_ENUM(NSInteger, LLNetworkType) {
    LLNetworkTypeUnknown ,             //未知
    LLNetworkTypeOffline ,             //关闭
    LLNetworkTypeWiFi    ,             //WiFi
    LLNetworkTypeCellularData ,        //数据流量
};

typedef void (^NetworkAccessibleStateNotifier)(LLNetworkAccessibleState state);

@interface LLNetworkMonitor : NSObject
/**
 开启网络监测
 */
+ (void)beginUseNetworkMonitor;
/**
 当判断网络状态为 LLNetworkRestricted 时，提示用户开启网络权限
 */

+ (void)setAlertEnable:(BOOL)setAlertEnable;

/**
 监控网络权限变化，等网络权限发生变化时回调。
 */

+ (void)monitor:(void (^)(LLNetworkAccessibleState))block;

/**
 检查网络状态，若弹出系统级别的 Alert，用户未处理则会等到用户处理完毕后才回调，改方法只会回调一次。
 */

+ (void)checkState:(void (^)(LLNetworkAccessibleState))block;

/**
 返回的是最近一次的网络状态检查结果，若距离上一次检测结果短时间内网络授权状态发生变化，该值可能会不准确，
 想获得更为准确的结果，请调用 checkState 这个异步方法。
 */
+ (LLNetworkAccessibleState)currentState;

/**
 获取当前网络
 
 @param block 网络类型
 */
+ (void)getCurrNetworkType:(void(^)(LLNetworkType networkType))block ;

@end
