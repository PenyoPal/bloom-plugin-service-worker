const exec = require('cordova/exec');

let ServiceWorker = function() { };

ServiceWorker.prototype.postMessage = function(message, transfers) {
  const responseHandles = [...Array(transfers.length).keys()];
  const cb = ({port, msg}) => {
    transfers[port].postMessage(msg);
  };
  // TODO: will this approach (assuming the cb can be invoked multiple
  // times for multiple messages) work in general?
  exec(cb, null, "ServiceWorker", "postMessage", [message, responseHandles]);
};

module.exports = ServiceWorker;
