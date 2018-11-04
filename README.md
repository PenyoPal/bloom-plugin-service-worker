# bloom-plugin-service-worker

A Cordova plugin to add a fake ServiceWorker to WKWebView.

Requirements:
 - Using cordova-plugin-ionic-webview & the associated GCDWebServer
 - Have a preference set for RemoteServerUrl in config.xml that
   indicates the backend server you want the requests to go to.

Still a work in progress

Notes: after implementing the integration with GCDWebServer, it seems like the postMessage immediately finishes & sends the message back, but the webview doesn't seem to actual recieve the message & keep going. Something going wrong at some point along the way now?
Did recently change how the request that gets handed to the fetch handler works, because the headers needs to be an actual Header object, not just a plain Object; did that break something?
