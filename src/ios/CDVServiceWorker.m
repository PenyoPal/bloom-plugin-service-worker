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
}

#pragma mark - Methods called from javascript client

- (void)register:(CDVInvokedUrlCommand*)command
{
  NSLog(@"Registering Service worker");
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
