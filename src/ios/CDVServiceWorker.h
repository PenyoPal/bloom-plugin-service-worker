/* -*- mode: objc -*- */
#import <Cordova/CDVPlugin.h>
#import <JavascriptCore/JSContext.h>
#import "ServiceWorkerContext.h"

@interface CDVServiceWorker: CDVPlugin

@property (nonatomic,strong) JSContext *jsContext;
@property (nonatomic,strong) ServiceWorkerContext* swContext;

@end
