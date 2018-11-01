self = {
  skipWaiting: function() {},
  clients: {claim: function() {}},
  handlers: {},
  addEventListener: function(eventName, fn) {
    this.handlers[eventName] = fn;
  }
};

cache = {match: null, add: null, put: null};

caches = {
  open: function(_name) {
      return new Promise(function(resolve, reject) { resolve(cache); });
  },
  match: function(request) {
      return cache.match(request);
  }
};
