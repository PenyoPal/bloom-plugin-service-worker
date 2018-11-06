# bloom-plugin-service-worker

A Cordova plugin to add a fake ServiceWorker to WKWebView.

Requirements:
 - Using cordova-plugin-ionic-webview & the associated GCDWebServer
 - Have a preference set for RemoteServerUrl in config.xml that
   indicates the backend server you want the requests to go to.

Still a work in progress

To integrate with the webserver, you'll need to have something like the below in `viewDidLoad` of your `MainViewController`

```objc
        SEL sel_webServer = NSSelectorFromString(@"webServer");
        GCDWebServer *server = [self.webViewEngine performSelector:sel_webServer];

        // We can't add handlers while the server is running
        BOOL restart = [server isRunning];
        if (restart) { [server stop]; }

        // ... add some other handlers


        // This should be the last handler added, so it has the highest priority
        [server addHandlerWithMatchBlock:^GCDWebServerRequest * (NSString *  requestMethod, NSURL *  requestURL, NSDictionary *  requestHeaders, NSString *  urlPath, NSDictionary *  urlQuery) {
            if ([requestMethod isEqualToString:@"GET"] &&
                [[CDVServiceWorker sharedInstance] shouldHandleRequestWithHeaders:requestHeaders]) {
                return [[GCDWebServerRequest alloc]
                        initWithMethod:requestMethod url:requestURL
                        headers:requestHeaders path:urlPath query:urlQuery];
            }
            return nil;
        } asyncProcessBlock:^(__kindof GCDWebServerRequest * request, GCDWebServerCompletionBlock completionBlock) {
            [[CDVServiceWorker sharedInstance] handleFetchEvent:request complete:^(NSDictionary *response) {
                NSHTTPURLResponse* httpResp = [[NSHTTPURLResponse alloc]
                                               initWithURL:request.URL
                                               statusCode:[response[@"status"] integerValue]
                                               HTTPVersion:@"1.1"
                                               headerFields:response[@"headers"]];
                // Assuming you've created some subclass of GCDWebServerResponse that can have data
                completionBlock([[MyServerResponse alloc] initWithData:response[@"body"]
                                                              response:httpResp]);
            }];
        }];

        // After adding the handlers we want to not only restart the
        // server, but make sure it has all the options that
        // CDVWkWebView plugin has set, so use that method to start it
        if (restart) {
            SEL sel_startServer = NSSelectorFromString(@"startServer");
            [self.webViewEngine performSelector:sel_startServer];
        }
```

## TODO

Make the cache actually save results locally; currently using an in-memory dictionary for testing
