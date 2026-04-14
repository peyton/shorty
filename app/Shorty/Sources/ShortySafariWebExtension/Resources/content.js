const API = globalThis.browser ?? globalThis.chrome;

(() => {
  let lastHref = location.href;

  function notifyIfChanged() {
    if (location.href === lastHref) return;
    lastHref = location.href;
    API.runtime.sendMessage({
      type: "domain_changed_from_content",
      url: location.href,
    });
  }

  const originalPushState = history.pushState;
  const originalReplaceState = history.replaceState;

  history.pushState = function (...args) {
    originalPushState.apply(this, args);
    notifyIfChanged();
  };

  history.replaceState = function (...args) {
    originalReplaceState.apply(this, args);
    notifyIfChanged();
  };

  window.addEventListener("popstate", notifyIfChanged);
  notifyIfChanged();
})();
