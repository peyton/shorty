/**
 * Shorty Browser Extension – Content Script
 *
 * Injected into every page. Detects SPA navigation (URL changes without
 * full page loads) and notifies the background worker so it can update
 * the native host with the new domain.
 *
 * Also detects well-known web app frameworks (React Router, Next.js,
 * Angular) by observing `popstate` and `pushState`/`replaceState`.
 */

(() => {
  let lastDomain = location.hostname;

  function checkDomain() {
    const current = location.hostname;
    if (current !== lastDomain) {
      lastDomain = current;
      chrome.runtime.sendMessage({
        type: "domain_changed_from_content",
        domain: current,
      });
    }
  }

  // Monkey-patch History API to catch SPA navigations
  const origPushState = history.pushState;
  const origReplaceState = history.replaceState;

  history.pushState = function (...args) {
    origPushState.apply(this, args);
    checkDomain();
  };

  history.replaceState = function (...args) {
    origReplaceState.apply(this, args);
    checkDomain();
  };

  // Catch browser back/forward
  window.addEventListener("popstate", checkDomain);

  // Initial check
  checkDomain();
})();
