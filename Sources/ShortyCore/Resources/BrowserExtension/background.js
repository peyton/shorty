/**
 * Shorty Browser Extension – Background Service Worker
 *
 * Maintains a persistent connection to the Shorty native messaging host
 * and forwards tab domain changes so Shorty can select the correct
 * web-app adapter.
 *
 * Protocol: length-prefixed JSON over stdin/stdout (Chrome handles framing).
 * Messages TO host:   { "type": "domain_changed", "domain": "slack.com" }
 * Messages FROM host: { "type": "ack" } (or future commands)
 */

const NATIVE_HOST = "com.shorty.browser_bridge";

let port = null;

// Connect to native messaging host
function connectToHost() {
  try {
    port = chrome.runtime.connectNative(NATIVE_HOST);

    port.onMessage.addListener((msg) => {
      // Future: host could send commands back (e.g., "inject shortcut hint")
      console.log("[Shorty] Message from host:", msg);
    });

    port.onDisconnect.addListener(() => {
      console.log("[Shorty] Disconnected from host:", chrome.runtime.lastError?.message);
      port = null;
      // Retry after a delay
      setTimeout(connectToHost, 5000);
    });
  } catch (e) {
    console.error("[Shorty] Failed to connect:", e);
    setTimeout(connectToHost, 5000);
  }
}

// Send the current domain to the native host
function sendDomain(domain) {
  if (port) {
    port.postMessage({
      type: "domain_changed",
      domain: domain,
    });
  }
}

// Extract the effective domain from a URL
function extractDomain(url) {
  try {
    const u = new URL(url);
    return u.hostname;
  } catch {
    return null;
  }
}

// Track the active tab's domain
chrome.tabs.onActivated.addListener(async (activeInfo) => {
  try {
    const tab = await chrome.tabs.get(activeInfo.tabId);
    if (tab.url) {
      const domain = extractDomain(tab.url);
      if (domain) sendDomain(domain);
    }
  } catch (e) {
    // Tab may have been closed
  }
});

// Track URL changes within a tab
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.url && tab.active) {
    const domain = extractDomain(changeInfo.url);
    if (domain) sendDomain(domain);
  }
});

// Track window focus changes
chrome.windows.onFocusChanged.addListener(async (windowId) => {
  if (windowId === chrome.windows.WINDOW_ID_NONE) return;
  try {
    const [tab] = await chrome.tabs.query({ active: true, windowId });
    if (tab?.url) {
      const domain = extractDomain(tab.url);
      if (domain) sendDomain(domain);
    }
  } catch (e) {
    // Window may have been closed
  }
});

// Start connection
connectToHost();
