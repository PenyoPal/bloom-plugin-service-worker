# bloom-plugin-service-worker

A Cordova plugin to add a fake ServiceWorker to WKWebView.

Requirements:
 - Using cordova-plugin-ionic-webview & the associated GCDWebServer
 - Have a preference set for RemoteServerUrl in config.xml that
   indicates the backend server you want the requests to go to.

Still a work in progress

## TODO

Make the cache actually save results locally; currently using an in-memory dictionary for testing
