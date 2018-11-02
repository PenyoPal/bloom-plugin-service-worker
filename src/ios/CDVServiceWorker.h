/* -*- mode: objc -*- */
#import <Cordova/CDVPlugin.h>
@import JavaScriptCore;

@interface CDVServiceWorker: CDVPlugin

@property (nonatomic,strong) JSContext *jsContext;

@end
