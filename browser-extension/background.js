// Polish — adds "Rewrite with AI", "Reply with AI" and "Read with AI" to the
// right-click menu on selected text and
// hands the selection to the local `polish` popup via native messaging.
const HOST = "com.voicer.text_polish";
const STYLES = [
  ["proofread", "Proofread"],
  ["tweet", "Tweet (≤ 280 chars)"],
  ["casual", "Casual"],
  ["punchy", "Punchy"],
  ["concise", "Concise"],
  ["detailed", "Detailed"],
  ["formal", "Formal"],
  ["witty", "Witty"],
];
const READ = [
  ["summarize", "Summarize"],
  ["keypoints", "Key points"],
  ["explain", "Explain simply"],
  ["translate", "Translate"],
];

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({ id: "polish", title: "Rewrite with AI", contexts: ["selection"] });
    for (const [key, label] of STYLES) {
      chrome.contextMenus.create({ id: `polish:${key}`, parentId: "polish", title: label, contexts: ["selection"] });
    }
    // Draft a reply to the selected message; the tone comes from the site (apps.conf).
    chrome.contextMenus.create({ id: "reply:auto", title: "Reply with AI", contexts: ["selection"] });
    // Understand text you're reading: summary, key points or a plain explanation.
    chrome.contextMenus.create({ id: "read", title: "Read with AI", contexts: ["selection"] });
    for (const [key, label] of READ) {
      chrome.contextMenus.create({ id: `read:${key}`, parentId: "read", title: label, contexts: ["selection"] });
    }
  });
});

// The context menu's selectionText collapses line breaks, so read the real
// selection (including inside <input>/<textarea>) from the frame that was clicked.
function readSelection() {
  const el = document.activeElement;
  if (el && (el.tagName === "TEXTAREA" || (el.tagName === "INPUT" && /^(text|search|url|email|)$/i.test(el.type)))) {
    const { selectionStart: s, selectionEnd: e } = el;
    if (typeof s === "number" && e > s) return el.value.slice(s, e);
  }
  return String(window.getSelection() || "");
}

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  const id = String(info.menuItemId);
  let style, mode;
  if (id.startsWith("polish:")) { style = id.slice("polish:".length); mode = "rewrite"; }
  else if (id === "reply:auto") { style = "auto"; mode = "reply"; }
  else if (id.startsWith("read:")) { style = id.slice("read:".length); mode = "read"; }
  else return;
  let text = info.selectionText || "";
  try {
    const target = { tabId: tab.id, frameIds: [info.frameId ?? 0] };
    const [res] = await chrome.scripting.executeScript({ target, func: readSelection });
    if (res && res.result && res.result.trim()) text = res.result;
  } catch (_) { /* restricted page: fall back to selectionText */ }
  const url = info.pageUrl || (tab && tab.url) || "";
  chrome.runtime.sendNativeMessage(HOST, { text, style, mode, url, editable: !!info.editable }, (reply) => {
    if (chrome.runtime.lastError) console.error("Polish:", chrome.runtime.lastError.message);
  });
});
