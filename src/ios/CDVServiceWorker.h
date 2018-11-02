/* -*- mode: objc -*- */
#import <Cordova/CDVPlugin.h>
@import JavascriptCore;

@interface CDVServiceWorker: CDVPlugin

@property (nonatomic,strong) JSContext *jsContext;

@end
