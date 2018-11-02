#import "CDVServiceWorker.h"

@interface CDVServiceWorker ()

@property (nonatomic,strong) dispatch_semaphore_t workerReadySemaphore;
@property (nonatomic,strong) NSString *scriptUrl;
@property (nonatomic,strong) NSString *scope;
@property (nonatomic,strong) NSMutableDictionary<NSDictionary*, NSDictionary*>* cache;
@property (nonatomic,strong) NSURL *rootURL;

@end

@implementation CDVServiceWorker

- (void)pluginInitialize
{
    NSLog(@"Initing service worker plugin");
    self.rootURL = [NSURL URLWithString:self.commandDelegate.settings[@"remoteserverurl"]];
    self.workerReadySemaphore = dispatch_semaphore_create(0);
    [self prepareJavascriptContext];
    self.cache = [[NSMutableDictionary alloc] init];
}

#pragma mark - Helpers

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
        [self.commandDelegate runInBackground:^{
            block(onResolve, onReject);
        }];
    };
    JSValue *respPromise = [promiseClass constructWithArguments:@[cb]];
    return respPromise;
}

- (NSURLRequest*)requestFromJSValue:(JSValue*)requestOrURL {
    if ([requestOrURL isString]) {
        NSURL *url = [NSURL URLWithString:[requestOrURL toString] relativeToURL:self.rootURL];
        return [NSURLRequest requestWithURL:url];
    } else {
        NSMutableURLRequest* req = [[NSMutableURLRequest alloc] init];
        req.URL = [NSURL URLWithString:requestOrURL[@"url"].toString];
        if (![requestOrURL[@"method"] isUndefined]) {
            req.HTTPMethod = requestOrURL[@"method"].toString;
        } else {
            req.HTTPMethod = @"GET";
        }
        if (![requestOrURL[@"headers"] isUndefined]) {
            NSDictionary *headers = requestOrURL[@"headers"].toDictionary;
            for (NSString* key in headers) {
                [req setValue:headers[key] forHTTPHeaderField:key];
            }
        }
        if (![requestOrURL[@"body"] isUndefined]) {
            NSData *body = [requestOrURL[@"body"].toString dataUsingEncoding:NSUTF8StringEncoding];
            req.HTTPBody = body;
        }
        return req;
    }
}

- (NSDictionary*)dictFromRequest:(NSURLRequest*)request {
    if (request == nil) { return nil; }
    // TODO: include body in the request as well?
    NSDictionary* headers = request.allHTTPHeaderFields;
    return @{@"url": request.URL.standardizedURL,
             @"method": request.HTTPMethod,
             @"headers": headers ? headers : [NSNull null]};
}

#pragma mark - Caching stuff

- (JSValue*)requestFromCache:(JSValue*)requestOrURL {
    NSLog(@"Looking up cache for %@", requestOrURL);
    NSDictionary* req = [self dictFromRequest:[self requestFromJSValue:requestOrURL]];
    NSDictionary *resp;
    if (req != nil && (resp = self.cache[req]) != nil) {
        return [JSValue valueWithObject:resp inContext:self.jsContext];
    } else {
        return [JSValue valueWithUndefinedInContext:self.jsContext];
    }
}

- (void)setCacheResponse:(JSValue*)response forRequest:(JSValue*)requestOrURL
{
    NSDictionary* req = [self dictFromRequest:[self requestFromJSValue:requestOrURL]];
    NSDictionary* resp = response.toDictionary;
    self.cache[req] = resp;
}

- (JSValue*)performFetch:(JSValue*)request {
    return [self wrapInPromise:^(JSCallback onResolve, JSCallback onReject) {
        NSURLRequest *req = [self requestFromJSValue:request];
        NSURLSessionTask *fetchTask =
        [[NSURLSession sharedSession]
         dataTaskWithRequest:req
         completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
             if (error != nil) {
                 NSLog(@"Error running fetch for %@: %@", req, error.localizedDescription);
                 onReject([JSValue valueWithObject:error.localizedDescription inContext:self.jsContext]);
                 return;
             }

             NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
             NSDictionary *jsResp = @{@"headers": httpResponse.allHeaderFields,
                                      @"status": @(httpResponse.statusCode),
                                      @"body": [data base64EncodedStringWithOptions:0]};
             onResolve([JSValue valueWithObject:jsResp inContext:self.jsContext]);
         }];
        [fetchTask resume];
    }];
}

#pragma mark - "Service Worker" context


- (void)prepareJavascriptContext
{
    self.jsContext = [[JSContext alloc] init];
    self.jsContext.name = @"fake Service Worker";
    NSString *shimScript = [NSString stringWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"service_worker_shim" withExtension:@"js"]
                                                    encoding:NSUTF8StringEncoding
                                                       error:nil];
    [self.jsContext evaluateScript:shimScript];

    __weak CDVServiceWorker* welf = self;

    self.jsContext[@"fetch"] = ^(JSValue *request) {
        NSLog(@"Fetching %@", request);
        return [welf wrapInPromise:^(JSCallback onResolve, JSCallback onReject) {
            onReject([JSValue valueWithUndefinedInContext:welf.jsContext]);
        }];
    };

    self.jsContext[@"cache"][@"match"] = ^(JSValue* requestOrURL){
        NSLog(@"SW: CHECKING FOR MATCH WITH %@", requestOrURL);
        return [welf wrapInPromise:^(JSCallback onResolve, JSCallback onReject) {
            JSValue *resp = [welf requestFromCache:requestOrURL];
            onResolve(resp);
        }];
    };

    self.jsContext[@"cache"][@"put"] = ^(JSValue* requestOrURL, JSValue* response) {
        NSLog(@"SW: PUTTING %@ for %@", response, requestOrURL);
        [self setCacheResponse:response forRequest:requestOrURL];
    };

    self.jsContext[@"cache"][@"add"] = ^(JSValue* requestOrURL){
        NSLog(@"SW: ADDING request %@", requestOrURL);
        JSValue *fetchPromise = [welf performFetch:requestOrURL];
        return [fetchPromise invokeMethod:@"then" withArguments:@[self.jsContext[@"cache"][@"put"]]];
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
        NSArray<NSNumber*>* portHandles = [command argumentAtIndex:1];

        NSMutableArray* handlers = [@[] mutableCopy];
        for (NSNumber *handle in portHandles) {
            [handlers addObject:@{@"postMessage": ^(NSString *msg) {
                [self.commandDelegate
                 sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                messageAsDictionary:@{@"port": handle,
                                                                      @"msg": msg}]
                 callbackId:command.callbackId];
            }}];
        }

        NSDictionary *event = @{@"data": [command argumentAtIndex:0],
                                @"ports": handlers};

        JSValue* messageHandler = self.jsContext[@"self"][@"handlers"][@"message"];

        [messageHandler callWithArguments:@[event]];
    }];

}

@end
