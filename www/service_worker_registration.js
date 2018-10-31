let ServiceWorkerRegistration = function(installing, waiting, active, scriptURL, scope) {
  this.installing = installing;
  this.waiting = waiting;
  this.active = active;
  this.scope = scope;
};

module.exports = ServiceWorkerRegistration;
