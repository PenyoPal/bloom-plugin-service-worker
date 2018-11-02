#import "CDVServiceWorker.h"

@interface CDVServiceWorker ()

@property (nonatomic,strong) dispatch_semaphore_t workerReadySemaphore;
@property (nonatomic,strong) NSString *scriptUrl;
@property (nonatomic,strong) NSString *scope;

@end

@implementation CDVServiceWorker

- (void)pluginInitialize
{
    NSLog(@"Initing service worker plugin");
    self.workerReadySemaphore = dispatch_semaphore_create(0);
    [self prepareJavascriptContext];
}

#pragma mark - Caching stuff

- (JSValue*)requestFromCache:(JSValue*)requestOrURL {
    return [JSValue valueWithUndefinedInContext:self.jsContext];
}

- (JSValue*)performFetch:(id)request {
    return [JSValue valueWithUndefinedInContext:self.jsContext];
}

#pragma mark - "Service Worker" context

typedef void(^JSPromiseCallback)(JSValue *resolve, JSValue *reject);

typedef void(^JSCallback)(JSValue* val);

- (JSValue*)wrapInPromise:(void (^)(JSCallback onResolve, JSCallback onReject))block {
    JSValue* promiseClass = self.jsContext[@"Promise"];
    JSPromiseCallback cb = ^(JSValue* resolveVal, JSValue *rejectVal) {
        JSCallback onResolve = ^(JSValue *val) {
            [resolveVal callWithArguments:@[val]];
        };
        JSCallback onReject = ^(JSValue *val) {
            [rejectVal callWithArguments:@[val]];
        };
        block(onResolve, onReject);
    };
    JSValue *respPromise = [promiseClass constructWithArguments:@[cb]];
    return respPromise;
}

- (void)prepareJavascriptContext
{
    self.jsContext = [[JSContext alloc] init];
    self.jsContext.name = @"fake Service Worker";
    NSString *shimScript = [NSString stringWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"service_worker_shim" withExtension:@"js"]
                                                    encoding:NSUTF8StringEncoding
                                                       error:nil];
    [self.jsContext evaluateScript:shimScript];
    self.jsContext[@"fetch"] = ^(JSValue *request) {
        // TODO
    };
    self.jsContext[@"cache"][@"match"] = ^(JSValue* requestOrURL){
        NSLog(@"SW: CHECKING FOR MATCH WITH %@", requestOrURL);
        return [self wrapInPromise:^(JSCallback onResolve, JSCallback onReject) {
            [self.commandDelegate runInBackground:^{
                JSValue *resp = [self requestFromCache:requestOrURL];
                onResolve(resp);
            }];
        }];
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
    // TODO: have ports array replaced with some sort of identifier,
    // put corresponding objects int he array with a `postMessage`
    // method that will let us keep track of what was posted, then
    // return that to the invoked command, so it can handle it on that
    // side
    [self.commandDelegate runInBackground:^{
        NSDictionary *event = @{@"data": [command argumentAtIndex:0],
                                @"ports": [command argumentAtIndex:1]};

        JSValue* messageHandler = self.jsContext[@"self"][@"handlers"][@"message"];

        [messageHandler callWithArguments:@[event]];
    }];

}

@end
