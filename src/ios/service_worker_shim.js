let self = {
  skipWaiting: function() {},
  clients: {claim: function() {}},
  handlers: {},
  addEventListener: function(eventName, fn) {
    handlers[eventName] = fn;
  }
};

let caches = {
  open: function(name) {

  },
  match: function(request) {

  }
};