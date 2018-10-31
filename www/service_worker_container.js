const exec = require('cordova/exec');

let ServiceWorkerContainer = {
  ready: new Promise(function(resolve, reject) {
    const innerResolve = function(result) {
      const onDeviceReady = () => {
        resolve(new ServiceWorkerRegistration(
          result.installing, result.waiting, new ServiceWorker(),
          result.registeringScriptUrl, result.scope));
      };
      document.addEventListener('deviceready', onDeviceReady, false);
    };
    exec(innerResolve, reject, "ServiceWorker", "serviceWorkerReady", []);
  }),

  register: function(url, opts) {
    return new Promise(function(resolve, reject) {
      const innerResolve = (result) => {
        resolve(new ServiceWorkerRegistration(
          result.installing, result.waiting, new ServiceWorker(),
          result.registeringScriptUrl, result.scope));
      };
      exec(innerResolve, reject, "ServiceWorker", "register", [url, opts]);
    });
  }
};

module.exports = ServiceWorkerContainer;
