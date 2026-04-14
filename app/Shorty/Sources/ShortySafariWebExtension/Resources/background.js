const API = globalThis.browser ?? globalThis.chrome;
const NATIVE_APPLICATION = "app.peyton.shorty";
const REPORT_ALL_DOMAINS = false;
const SUPPORTED_DOMAINS = [
  "notion.so",
  "slack.com",
  "mail.google.com",
  "docs.google.com",
  "figma.com",
  "linear.app",
];

let lastSentDomain = undefined;

function normalizeSupportedDomain(hostname) {
  const cleaned = hostname.toLowerCase().replace(/^\.+|\.+$/g, "");
  const withoutWWW = cleaned.startsWith("www.") ? cleaned.slice(4) : cleaned;

  for (const domain of SUPPORTED_DOMAINS) {
    if (withoutWWW === domain || withoutWWW.endsWith(`.${domain}`)) {
      if (domain === "mail.google.com" || domain === "docs.google.com") {
        return withoutWWW === domain ? domain : null;
      }
      return domain;
    }
  }

  return REPORT_ALL_DOMAINS ? withoutWWW : null;
}

function extractDomain(url) {
  try {
    return new URL(url).hostname;
  } catch {
    return null;
  }
}

function postNativeMessage(message) {
  try {
    return API.runtime.sendNativeMessage(NATIVE_APPLICATION, message);
  } catch {
    return Promise.resolve();
  }
}

function sendDomain(domain) {
  if (!domain || domain === lastSentDomain) return;
  lastSentDomain = domain;
  postNativeMessage({
    type: "domain_changed",
    domain,
  });
}

function sendClearDomain() {
  if (lastSentDomain === null) return;
  lastSentDomain = null;
  postNativeMessage({
    type: "domain_cleared",
  });
}

function sendDomainFromUrl(url) {
  const domain = extractDomain(url);
  const supportedDomain = domain ? normalizeSupportedDomain(domain) : null;
  if (supportedDomain) {
    sendDomain(supportedDomain);
  } else {
    sendClearDomain();
  }
}

async function sendActiveTabDomain() {
  try {
    const [tab] = await API.tabs.query({
      active: true,
      currentWindow: true,
    });
    if (tab?.url) sendDomainFromUrl(tab.url);
  } catch {}
}

API.tabs.onActivated.addListener(async (activeInfo) => {
  try {
    const tab = await API.tabs.get(activeInfo.tabId);
    if (tab.url) sendDomainFromUrl(tab.url);
  } catch {}
});

API.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.url && tab.active) {
    sendDomainFromUrl(changeInfo.url);
  }
});

API.windows.onFocusChanged.addListener(async (windowId) => {
  if (windowId === API.windows.WINDOW_ID_NONE) return;
  try {
    const [tab] = await API.tabs.query({ active: true, windowId });
    if (tab?.url) sendDomainFromUrl(tab.url);
  } catch {}
});

API.runtime.onMessage.addListener((message) => {
  if (message?.type === "domain_changed_from_content" && message.url) {
    sendDomainFromUrl(message.url);
    return;
  }

  if (message?.type === "domain_changed_from_content" && message.domain) {
    const supportedDomain = normalizeSupportedDomain(message.domain);
    if (supportedDomain) {
      sendDomain(supportedDomain);
    } else {
      sendClearDomain();
    }
  }
});

sendActiveTabDomain();
