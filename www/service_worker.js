const exec = require('cordova/exec');

let ServiceWorker = function() { };

ServiceWorker.prototype.postMessage = function(message, transfers) {
  // TODO: Need to translate messageports somehow?
  // or handle them here...
  // make the postMessage thing return a value & we can put it into
  // the port here.
  exec(null, null, "ServiceWorker", "postMessage", [message, transfers]);
};

module.exports = ServiceWorker;
