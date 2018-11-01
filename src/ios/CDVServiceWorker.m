#import "CDVServiceWorker.h"

@implementation CDVServiceWorker

- (void)pluginInitialize
{
    NSLog(@"Initing service worker plugin");
    [self prepareJavascriptContext];
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
}

#pragma mark - Methods called from javascript client

- (void)register:(CDVInvokedUrlCommand*)command
{
    NSLog(@"Registering Service worker");
    [self.commandDelegate runInBackground:^{
        NSString *scriptUrl = [command argumentAtIndex:0];
        NSDictionary *options = [command argumentAtIndex:1];
        NSString *scope = options[@"scope"];

        NSURL *srcUrl = [[NSBundle mainBundle] URLForResource:scriptUrl withExtension:nil subdirectory:@"www"];

        NSLog(@"%@ scope %@ -> %@", scriptUrl, scope, srcUrl);

        NSString *script = [NSString stringWithContentsOfURL:srcUrl
                                                    encoding:NSUTF8StringEncoding
                                                       error:nil];
        [self.jsContext evaluateScript:script];

        [self.commandDelegate
         sendPluginResult:[CDVPluginResult
                           resultWithStatus:CDVCommandStatus_OK
                           messageAsDictionary:@{@"installing": [NSNull null],
                                                 @"waiting": [NSNull null],
                                                 @"active": @{@"scriptURL": scriptUrl},
                                                 @"registeringScriptURL": scriptUrl,
                                                 @"scope": scope}]
         callbackId:command.callbackId];
    }];
}

- (void)serviceWorkerReady:(CDVInvokedUrlCommand*)command
{
    NSLog(@"Service worker ready");
}

- (void)postMessage:(CDVInvokedUrlCommand*)command
{
    NSLog(@"Posting message");
}

@end
