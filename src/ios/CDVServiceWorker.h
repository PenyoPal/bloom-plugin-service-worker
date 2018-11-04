/* -*- mode: objc -*- */
#import <Cordova/CDVPlugin.h>
@import JavaScriptCore;

@protocol WebRequest <NSObject>

- (NSURL*)URL;
- (NSString*)HTTPMethod;
- (NSDictionary*)allHTTPHeaderFields;

@end

@interface CDVServiceWorker: CDVPlugin

@property (nonatomic,strong) JSContext *jsContext;

// For interoperating with GCDServer
+ (instancetype)sharedInstance;
- (BOOL)shouldHandleRequestWithHeaders:(NSDictionary*)requestHeaders;
- (void)handleFetchEvent:(id<WebRequest>)request complete:(void (^)(NSDictionary *response))complete;

@end
