#import "CDVServiceWorker.h"

@interface CDVServiceWorker ()

@property (nonatomic,strong) NSOperationQueue *queue;
@property (nonatomic,strong) dispatch_semaphore_t workerReadySemaphore;
@property (nonatomic,strong) NSString *scriptUrl;
@property (nonatomic,strong) NSString *scope;

@end

@implementation CDVServiceWorker

- (void)pluginInitialize
{
    NSLog(@"Initing service worker plugin");
    self.workerReadySemaphore = dispatch_semaphore_create(0);
    self.queue = [[NSOperationQueue alloc] init];
    [self prepareJavascriptContext];
}

#pragma mark - Caching stuff

- (JSValue*)requestFromCache:(id)request {
    return [JSValue valueWithUndefinedInContext:self.jsContext];
}

- (JSValue*)performFetch:(id)request {
    return [JSValue valueWithUndefinedInContext:self.jsContext];
}

#pragma mark - "Service Worker" context

typedef void(^JSPromiseCallback)(JSValue *resolve, JSValue *reject);

- (void)prepareJavascriptContext
{
    self.jsContext = [[JSContext alloc] init];
    self.jsContext.name = @"fake Service Worker";
    NSString *shimScript = [NSString stringWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"service_worker_shim" withExtension:@"js"]
                                                    encoding:NSUTF8StringEncoding
                                                       error:nil];
    [self.jsContext evaluateScript:shimScript];
    self.jsContext[@"cache"][@"match"] = ^(id requestOrURL){
        NSLog(@"SW: CHECKING FOR MATCH WITH %@", requestOrURL);
        JSValue* promiseClass = self.jsContext[@"Promise"];
        JSPromiseCallback cb = ^(JSValue* resolve, JSValue *reject) {
            [self.commandDelegate runInBackground:^{
                JSValue *resp = [self requestFromCache:requestOrURL];
                [resolve callWithArguments:@[resp]];
            }];
        };
        JSValue *respPromise = [promiseClass constructWithArguments:@[cb]];
        return respPromise;
    };
    self.jsContext[@"cache"][@"add"] = ^(id requestOrURL){
        NSLog(@"SW: ADDING request %@", requestOrURL);
    };
    self.jsContext[@"cache"][@"put"] = ^(id requestOrURL, id response) {
        NSLog(@"SW: PUTTING %@ for %@", response, requestOrURL);
    };
}

#pragma mark - Methods called from javascript client

- (void)register:(CDVInvokedUrlCommand*)command
{
    NSLog(@"Registering Service worker");
    // TODO: check if a worker is already registered, signal error conditons
    [self.commandDelegate runInBackground:^{
        self.scriptUrl = [command argumentAtIndex:0];
        NSDictionary *options = [command argumentAtIndex:1];
        self.scope = options[@"scope"];

        NSURL *srcUrl = [[NSBundle mainBundle] URLForResource:self.scriptUrl withExtension:nil subdirectory:@"www"];

        NSLog(@"%@ scope %@ -> %@", self.scriptUrl, self.scope, srcUrl);

        NSString *script = [NSString stringWithContentsOfURL:srcUrl
                                                    encoding:NSUTF8StringEncoding
                                                       error:nil];
        [self.jsContext evaluateScript:script];
        [self.commandDelegate
         sendPluginResult:[CDVPluginResult
                           resultWithStatus:CDVCommandStatus_OK
                           messageAsDictionary:@{@"installing": [NSNull null],
                                                 @"waiting": [NSNull null],
                                                 @"active": @{@"scriptURL": self.scriptUrl},
                                                 @"registeringScriptURL": self.scriptUrl,
                                                 @"scope": self.scope}]
         callbackId:command.callbackId];
        dispatch_semaphore_signal(self.workerReadySemaphore);
    }];
}

- (void)serviceWorkerReady:(CDVInvokedUrlCommand*)command
{
    NSLog(@"Service worker ready");
    [self.commandDelegate runInBackground:^{
        dispatch_semaphore_wait(self.workerReadySemaphore, DISPATCH_TIME_FOREVER);

        [self.commandDelegate
         sendPluginResult:[CDVPluginResult
                           resultWithStatus:CDVCommandStatus_OK
                           messageAsDictionary:@{@"installing": [NSNull null],
                                                 @"waiting": [NSNull null],
                                                 @"active": @{@"scriptURL": self.scriptUrl},
                                                 @"registeringScriptURL": self.scriptUrl,
                                                 @"scope": self.scope}]
         callbackId:command.callbackId];
    }];
}

- (void)postMessage:(CDVInvokedUrlCommand*)command
{
    NSLog(@"Posting message");
    [self.commandDelegate runInBackground:^{
        NSDictionary *event = @{@"data": [command argumentAtIndex:0],
                                @"ports": [command argumentAtIndex:1]};

        JSValue* messageHandler = self.jsContext[@"self"][@"handlers"][@"message"];

        [messageHandler callWithArguments:@[event]];
    }];

}

@end
