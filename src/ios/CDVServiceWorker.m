#import "CDVServiceWorker.h"

@interface CDVServiceWorker ()

@property (nonatomic,strong) JSContext *jsContext;
@property (nonatomic,strong) dispatch_semaphore_t workerReadySemaphore;
@property (nonatomic,strong) NSString *scriptUrl;
@property (nonatomic,strong) NSString *scope;
@property (nonatomic,strong) NSMutableDictionary<NSURL*, JSValue*>* cache;
@property (nonatomic,strong) NSURL *rootURL;
@property (nonatomic,strong) NSString *fetchingHeader;
@property (nonatomic,strong) NSURL *cacheDirectory;

@end

@implementation CDVServiceWorker

static CDVServiceWorker *instance;

+ (instancetype)sharedInstance {
    return instance;
}

- (void)pluginInitialize
{
    NSLog(@"Initing service worker plugin");
    self.cacheDirectory = [[[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                                   inDomains:NSUserDomainMask]
                            firstObject] URLByAppendingPathComponent:@"sw_cache"];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.cacheDirectory
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    self.fetchingHeader = @"fake-service-worker-request";
    self.rootURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%@",
                                         self.commandDelegate.settings[@"wkport"]]];
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
        JSValue* (^handleResponse)(JSValue *response) = ^JSValue*(JSValue *response) {
            NSDictionary *respDict = response.toDictionary;
            complete(@{@"headers": respDict[@"headers"],
                       @"status": respDict[@"status"],
                       @"body": [[NSData alloc] initWithBase64EncodedString:respDict[@"body"]
                                                                    options:0]});
            return [self.jsContext[@"Promise"] invokeMethod:@"resolve" withArguments:@[response]];
        };
        [responsePromise invokeMethod:@"then" withArguments:@[^JSValue* (JSValue *response) {
                    if ([response isInstanceOf:self.jsContext[@"Promise"]]) {
                        return [[response
                                 invokeMethod:@"then" withArguments:@[handleResponse]]
                                invokeMethod:@"catch" withArguments:@[^(JSValue *failure) {
                            complete(@{@"headers": @{},
                                       @"status": @(500),
                                       @"body": @""});
                        }]];
                    } else  {
                        return handleResponse(response);
                    }
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
            NSMutableDictionary* headers = [resp.allHeaderFields mutableCopy];
            headers[@"Content-Encoding"] = @"identity";
            headers[@"Content-Length"] = [NSString stringWithFormat:@"%lu", (unsigned long)data.length];
            complete(@{@"status": @(resp.statusCode),
                       @"headers": headers,
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

- (NSURL*)cachePathForRequest:(NSURLRequest*)request
{
    NSString* urlName = [[[request.URL.absoluteString
                           dataUsingEncoding:NSUTF8StringEncoding]
                          base64EncodedStringWithOptions:0]
                         stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    return urlName ? [self.cacheDirectory URLByAppendingPathComponent:urlName] : nil;
}

- (JSValue*)requestFromCache:(JSValue*)requestOrURL {
    NSURLRequest* req = [self requestFromJSValue:requestOrURL];
    NSURL *cacheURL = [self cachePathForRequest:req];
    if (cacheURL && [[NSFileManager defaultManager] fileExistsAtPath:cacheURL.path]) {
        NSDictionary* respDict = [NSDictionary dictionaryWithContentsOfURL:cacheURL];
        return [JSValue valueWithObject:respDict inContext:self.jsContext];
    } else {
        return [JSValue valueWithUndefinedInContext:self.jsContext];
    }
}

- (void)setCacheResponse:(JSValue*)response forRequest:(JSValue*)requestOrURL
{
    NSURLRequest* req = [self requestFromJSValue:requestOrURL];
    NSError *err = nil;
    NSOutputStream *stream = [NSOutputStream
                              outputStreamWithURL:[self cachePathForRequest:req]
                              append:NO];
    [stream open];
    if([NSPropertyListSerialization
        writePropertyList:response.toDictionary
        toStream:stream
        format:NSPropertyListBinaryFormat_v1_0
        options:0
        error:&err] == 0) {
        NSLog(@"ERROR WRITING TO CACHE: %@", err.localizedDescription);
    }
    [stream close];
}

#pragma mark - "Service Worker" context

- (JSValue*)performFetch:(JSValue*)request {
    return [self wrapInPromise:^(JSCallback onResolve, JSCallback onReject) {
        NSMutableURLRequest *req = [[self requestFromJSValue:request] mutableCopy];
        [req setValue:@"1" forHTTPHeaderField:self.fetchingHeader];
        NSURLSessionTask *fetchTask =
        [[NSURLSession sharedSession]
         dataTaskWithRequest:req
         completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
             if (error != nil) {
                 onReject([JSValue valueWithObject:error.localizedDescription inContext:self.jsContext]);
                 return;
             }

             NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
             NSMutableDictionary* headers = [httpResponse.allHeaderFields mutableCopy];
             headers[@"Content-Encoding"] = @"identity";
             headers[@"Content-Length"] = [NSString stringWithFormat:@"%lu", (unsigned long)data.length];
             JSValue *jsResp = [self.jsContext[@"Response"]
                                constructWithArguments:@[@(httpResponse.statusCode),
                                                         headers,
                                                         [data base64EncodedStringWithOptions:0]]];
             onResolve(jsResp);
         }];
        [fetchTask resume];
    }];
}

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
        return [welf performFetch:request];
    };

    self.jsContext[@"cache"][@"match"] = ^(JSValue* requestOrURL){
        return [welf wrapInPromise:^(JSCallback onResolve, JSCallback onReject) {
            JSValue *resp = [welf requestFromCache:requestOrURL];
            onResolve(resp);
        }];
    };

    self.jsContext[@"cache"][@"put"] = ^(JSValue* requestOrURL, JSValue* response) {
        [self setCacheResponse:response forRequest:requestOrURL];
    };

    self.jsContext[@"cache"][@"add"] = ^JSValue* (JSValue* requestOrURL){
        JSValue *fetchPromise = [self performFetch:requestOrURL];
        return [fetchPromise invokeMethod:@"then" withArguments:@[^JSValue*(JSValue *response){
            if (response[@"ok"].toBool) {
                [self setCacheResponse:response forRequest:requestOrURL];
                return [self.jsContext[@"Promise"] invokeMethod:@"resolve"
                                                  withArguments:@[response]];
            } else {
                return [self.jsContext[@"Promise"] invokeMethod:@"reject"
                                                  withArguments:@[[JSValue valueWithUndefinedInContext:self.jsContext]]];
            }
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
                CDVPluginResult* result =
                [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                              messageAsDictionary:@{@"port": handle,
                                                    @"msg": msg}];
                result.keepCallback = @(YES);
                // TODO: need to have a way of indicating with this is done so the callbacks can be freed cordova-side; this is currently leaking memory
                [self.commandDelegate
                 sendPluginResult:result
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
