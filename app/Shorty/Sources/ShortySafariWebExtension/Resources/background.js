const API = globalThis.browser ?? globalThis.chrome;
const NATIVE_APPLICATION = "app.peyton.shorty";
const REPORT_ALL_DOMAINS = false;
const PROTOCOL_VERSION = 1;
// Keep this list in sync with DomainNormalizer.supportedWebAppDomains.
const SUPPORTED_DOMAINS = [
  "calendar.google.com",
  "chatgpt.com",
  "claude.ai",
  "docs.google.com",
  "drive.google.com",
  "figma.com",
  "github.com",
  "linear.app",
  "mail.google.com",
  "meet.google.com",
  "notion.so",
  "sheets.google.com",
  "slack.com",
  "slides.google.com",
  "whatsapp.com",
];
const EXACT_DOMAINS = new Set([
  "calendar.google.com",
  "docs.google.com",
  "drive.google.com",
  "mail.google.com",
  "meet.google.com",
  "sheets.google.com",
  "slides.google.com",
]);

let lastSentDomain = undefined;

function normalizeSupportedDomain(hostname) {
  const cleaned = hostname.toLowerCase().replace(/^\.+|\.+$/g, "");
  const withoutWWW = cleaned.startsWith("www.") ? cleaned.slice(4) : cleaned;

  for (const domain of SUPPORTED_DOMAINS) {
    if (withoutWWW === domain || withoutWWW.endsWith(`.${domain}`)) {
      if (EXACT_DOMAINS.has(domain)) {
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

function sendDomain(domain, context = {}) {
  if (!domain || domain === lastSentDomain) return;
  lastSentDomain = domain;
  postNativeMessage({
    type: "domain_changed",
    protocol_version: PROTOCOL_VERSION,
    source: context.source ?? "safari-extension",
    domain,
    tab_id: context.tabId ?? null,
    window_id: context.windowId ?? null,
    title: context.title ?? null,
  });
}

function sendClearDomain() {
  if (lastSentDomain === null) return;
  lastSentDomain = null;
  postNativeMessage({
    type: "domain_cleared",
  });
}

function sendDomainFromUrl(url, context = {}) {
  const domain = extractDomain(url);
  const supportedDomain = domain ? normalizeSupportedDomain(domain) : null;
  if (supportedDomain) {
    sendDomain(supportedDomain, context);
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
    if (tab?.url) {
      sendDomainFromUrl(tab.url, {
        source: "active-tab",
        tabId: tab.id,
        windowId: tab.windowId,
        title: tab.title,
      });
    }
  } catch {}
}

API.tabs.onActivated.addListener(async (activeInfo) => {
  try {
    const tab = await API.tabs.get(activeInfo.tabId);
    if (tab.url) {
      sendDomainFromUrl(tab.url, {
        source: "tab-activated",
        tabId: tab.id,
        windowId: tab.windowId,
        title: tab.title,
      });
    }
  } catch {}
});

API.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.url && tab.active) {
    sendDomainFromUrl(changeInfo.url, {
      source: "tab-updated",
      tabId,
      windowId: tab.windowId,
      title: tab.title,
    });
  }
});

API.windows.onFocusChanged.addListener(async (windowId) => {
  if (windowId === API.windows.WINDOW_ID_NONE) return;
  try {
    const [tab] = await API.tabs.query({ active: true, windowId });
    if (tab?.url) {
      sendDomainFromUrl(tab.url, {
        source: "window-focused",
        tabId: tab.id,
        windowId: tab.windowId,
        title: tab.title,
      });
    }
  } catch {}
});

API.runtime.onMessage.addListener((message) => {
  if (message?.type === "domain_changed_from_content" && message.url) {
    sendDomainFromUrl(message.url, { source: "content-script" });
    return;
  }

  if (message?.type === "domain_changed_from_content" && message.domain) {
    const supportedDomain = normalizeSupportedDomain(message.domain);
    if (supportedDomain) {
      sendDomain(supportedDomain, { source: "content-script" });
    } else {
      sendClearDomain();
    }
  }
});

sendActiveTabDomain();
