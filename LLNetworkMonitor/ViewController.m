//
//  ViewController.m
//  LLNetworkMonitor
//
//  Created by Lilong on 2018/7/23.
//  Copyright © 2018年 diqidaimu. All rights reserved.
//

#import "ViewController.h"
#import "LLNetworkMonitor.h"
@interface ViewController ()
@property (strong, nonatomic) IBOutlet UILabel *networkLabel;

@property (strong, nonatomic) IBOutlet UILabel *authLabel;
@end

@implementation ViewController

-(void)dealloc{
    //销毁通知
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    //开启监测
    [LLNetworkMonitor beginUseNetworkMonitor];
     //允许弹窗
    [LLNetworkMonitor setAlertEnable:YES];
    //注册通知
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkChanged:) name:LLNetworkMonitorChangedNotification object:nil];

    // 发起一个网络请求以触发系统的弹框
    
    NSURL *url = [NSURL URLWithString:@"http://api.m.taobao.com/rest/api3.do?api=mtop.common.getTimestamp"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
    }] resume];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)networkChanged:(NSNotification *)notification {
    [LLNetworkMonitor getCurrNetworkType:^(LLNetworkType networkType) {
        NSString *status = nil;
        if (networkType == LLNetworkTypeOffline) {
            status = @"当前网络状态为：关闭";
        }else if (networkType == LLNetworkTypeWiFi){
            status = @"当前网络状态为：WiFi";
        }else if (networkType == LLNetworkTypeCellularData){
            status = @"当前网络状态为：数据流量";
        }else{
            status = @"当前网络状态为：位置";
        }
        self.networkLabel.text = status;
    }];
    NSString *authString = nil;
    LLNetworkAccessibleState state = [LLNetworkMonitor currentState];
    if (state == LLNetworkAccessible) {
        authString = @"当前网络授权状态为：可进入的";
    }else if (state == LLNetworkAccessible){
        authString = @"当前网络授权状态为：受限制的";
    }else{
        authString = @"当前网络授权状态为：未知";
    }
    self.authLabel.text = authString;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
