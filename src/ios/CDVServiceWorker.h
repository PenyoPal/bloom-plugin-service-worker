/* -*- mode: objc -*- */
#import <Cordova/CDVPlugin.h>
#import <JavascriptCore/JSContext.h>

@interface CDVServiceWorker: CDVPlugin

@property (nonatomic,strong) JSContext *jsContext;

@end
