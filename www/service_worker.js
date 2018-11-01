const exec = require('cordova/exec');

let ServiceWorker = function() { };

ServiceWorker.prototype.postMessage = function(message, transfers) {
  exec(null, null, "ServiceWorker", "postMessage", [message, transfers]);
};

module.exports = ServiceWorker;
