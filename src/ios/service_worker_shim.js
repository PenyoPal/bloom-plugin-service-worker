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
      return Promise.resolve(cache);
  },
  match: function(request) {
      return cache.match(request);
  }
};

Headers = function(vals) { this.vals = vals || {}; };
Headers.prototype.get = function(key) { return this.vals[key]; };

Response = function(status, headers, body) {
  this.status = status;
  this.headers = headers;
  this.body = body;
};
Response.prototype.clone = function() {
  return this;
};
Object.defineProperty(Response.prototype, 'ok', {get() {
  return (this.status >= 200) && (this.status <= 299);
}});
