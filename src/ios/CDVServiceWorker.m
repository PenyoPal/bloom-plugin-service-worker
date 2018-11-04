#import "CDVServiceWorker.h"

@interface CDVServiceWorker ()

@property (nonatomic,strong) dispatch_semaphore_t workerReadySemaphore;
@property (nonatomic,strong) NSString *scriptUrl;
@property (nonatomic,strong) NSString *scope;
@property (nonatomic,strong) NSMutableDictionary<NSDictionary*, NSDictionary*>* cache;
@property (nonatomic,strong) NSURL *rootURL;
@property (nonatomic,strong) NSString *fetchingHeader;

@end

@implementation CDVServiceWorker

static CDVServiceWorker *instance;

+ (instancetype)sharedInstance {
    return instance;
}

- (void)pluginInitialize
{
    NSLog(@"Initing service worker plugin");
    self.fetchingHeader = @"fake-service-worker-request";
    self.rootURL = [NSURL URLWithString:self.commandDelegate.settings[@"remoteserverurl"]];
    self.workerReadySemaphore = dispatch_semaphore_create(0);
    [self prepareJavascriptContext];
    self.cache = [[NSMutableDictionary alloc] init];
    instance = self;
}

#pragma mark - Interoperating with GCDServer

- (NSURLRequest*)toNSURLRequest:(id<WebRequest>)request
{
    if ([request isKindOfClass:[NSURLRequest class]]) {
        return (NSURLRequest*)request;
    }
    NSMutableURLRequest *urlRequest = [[NSMutableURLRequest alloc] initWithURL:request.URL];
    urlRequest.HTTPMethod = request.HTTPMethod;
    for (NSString *field in request.allHTTPHeaderFields) {
        [urlRequest setValue:request.allHTTPHeaderFields[field] forHTTPHeaderField:field];
    }
    return urlRequest;
}

- (BOOL)shouldHandleRequestWithHeaders:(NSDictionary*)requestHeaders
{
    return requestHeaders[self.fetchingHeader] == nil &&
            !(self.jsContext[@"self"][@"handlers"][@"fetch"].isUndefined);
}

- (void)handleFetchEvent:(id<WebRequest>)request complete:(void (^)(NSDictionary *response))complete
{
    JSValue* fetchHandler = self.jsContext[@"self"][@"handlers"][@"fetch"];
    JSValue* __block responsePromise = nil;
    [fetchHandler callWithArguments:
                     @[@{@"request": [self jsRequestFromUrlRequest:[self toNSURLRequest:request]],
                       @"respondWith": ^(JSValue* response) { responsePromise = response; }}]];
    if (responsePromise == nil) {
        // handler doesn't want to deal with it
        [self forwardRequest:request complete:complete];
    } else {
        [responsePromise invokeMethod:@"then" withArguments:@[^(JSValue *response) {
                    NSDictionary *respDict = response.toDictionary;
                    complete(@{@"headers": respDict[@"headers"],
                                @"status": respDict[@"status"],
                                @"body": [[NSData alloc] initWithBase64EncodedString:respDict[@"body"]
                                                                             options:0]});
                }]];
    }
}

- (void)forwardRequest:(id<WebRequest>)request complete:(void (^)(NSDictionary*response))complete
{
    NSMutableURLRequest *urlRequest = [[self toNSURLRequest:request] mutableCopy];
    [urlRequest setValue:@"1" forHTTPHeaderField:self.fetchingHeader];
    NSURLSessionTask *task = [[NSURLSession sharedSession]
                                 dataTaskWithRequest:urlRequest
                                   completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
            if (error != nil) {
                NSLog(@"Error forwarding request: %@", error.localizedDescription);
                complete(@{@"status": @(500),
                           @"headers": @{},
                           @"body": [[NSData alloc] init]});
                return;
            }
            NSHTTPURLResponse *resp = (NSHTTPURLResponse *)response;
            complete(@{@"status": @(resp.statusCode),
                       @"headers": resp.allHeaderFields,
                       @"body": data});
        }];
    [task resume];
}

#pragma mark - Helpers

- (id)jsRequestFromUrlRequest:(NSURLRequest*)request
{
    // TODO: include body in the request as well?
    NSDictionary* headers = request.allHTTPHeaderFields;
    return @{@"url": request.URL.absoluteString,
             @"method": request.HTTPMethod,
             @"headers": [self.jsContext[@"Headers"]
                             constructWithArguments:@[ headers ? headers : [NSNull null] ]]};
}

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
            NSDictionary *headers = requestOrURL[@"headers"][@"vals"].toDictionary;
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
    return @{@"url": request.URL.absoluteString,
             @"method": request.HTTPMethod,
             @"headers": headers ? headers : [NSNull null]};
}

#pragma mark - Caching stuff

- (JSValue*)requestFromCache:(JSValue*)requestOrURL {
    NSLog(@"Looking up cache for %@", requestOrURL);
    NSDictionary* req = [self dictFromRequest:[self requestFromJSValue:requestOrURL]];
    NSDictionary *resp;
    if (req != nil && (resp = self.cache[req]) != nil) {
        NSLog(@"Cache hit!");
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
        NSMutableURLRequest *req = [[self requestFromJSValue:request] mutableCopy];
        [req setValue:@"1" forHTTPHeaderField:self.fetchingHeader];
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
    NSString *shimScript = [NSString stringWithContentsOfURL:
                                         [[NSBundle mainBundle]
                                             URLForResource:@"service_worker_shim" withExtension:@"js"]
                                                   encoding:NSUTF8StringEncoding
                                                      error:nil];
    [self.jsContext evaluateScript:shimScript];

    __weak CDVServiceWorker* welf = self;

    self.jsContext[@"fetch"] = ^(JSValue *request) {
        NSLog(@"Fetching %@", request);
        return [welf performFetch:request];
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
        return [fetchPromise invokeMethod:@"then" withArguments:@[^(JSValue *response){
                    [self setCacheResponse:response forRequest:requestOrURL];
                }]];
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
