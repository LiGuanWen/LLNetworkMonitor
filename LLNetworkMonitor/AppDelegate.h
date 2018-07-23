//
//  AppDelegate.h
//  LLNetworkMonitor
//
//  Created by Lilong on 2018/7/23.
//  Copyright © 2018年 diqidaimu. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property (readonly, strong) NSPersistentContainer *persistentContainer;

- (void)saveContext;


@end

