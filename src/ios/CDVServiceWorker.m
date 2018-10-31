#import "CDVServiceWorker.h"

@implementation CDVServiceWorker

- (void)pluginInitialize
{
  [self prepareJavascriptContext];
}

#pragma mark - "Service Worker" context

- (void)prepareJavascriptContext
{
  self.jsContext = [[JSContext alloc] init];
  self.swContext = [[ServiceWorkerContext alloc] init]
    self.jsContext[@"self"] = self.swContext;
}

#pragma mark - Methods called from javascript client

- (void)register:(CDVInvokedUrlCommand*)command
{

}

- (void)serviceWorkerReady:(CDVInvokedUrlCommand*)command
{

}

- (void)postMessage:(CDVInvokedUrlCommand*)command
{

}

@end
