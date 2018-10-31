const exec = require('cordova/exec');

let ServiceWorker = function() { };

ServiceWorker.prototype.postMessage = function(message, transfers) {
  exec(null, null, "ServiceWorker", "postMessage",
       [JSON.stringify(message), transfers]);
};

module.exports = ServiceWorker;
