// Polish — adds "Rewrite with AI" to the right-click menu on selected text and
// hands the selection to the local `polish` popup via native messaging.
const HOST = "com.voicer.text_polish";
const STYLES = [
  ["proofread", "Proofread"],
  ["casual", "Casual"],
  ["punchy", "Punchy"],
  ["concise", "Concise"],
  ["formal", "Formal"],
];

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({ id: "polish", title: "Rewrite with AI", contexts: ["selection"] });
    for (const [key, label] of STYLES) {
      chrome.contextMenus.create({ id: `polish:${key}`, parentId: "polish", title: label, contexts: ["selection"] });
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
  if (!String(info.menuItemId).startsWith("polish:")) return;
  const style = String(info.menuItemId).slice("polish:".length);
  let text = info.selectionText || "";
  try {
    const target = { tabId: tab.id, frameIds: [info.frameId ?? 0] };
    const [res] = await chrome.scripting.executeScript({ target, func: readSelection });
    if (res && res.result && res.result.trim()) text = res.result;
  } catch (_) { /* restricted page: fall back to selectionText */ }
  chrome.runtime.sendNativeMessage(HOST, { text, style, editable: !!info.editable }, (reply) => {
    if (chrome.runtime.lastError) console.error("Polish:", chrome.runtime.lastError.message);
  });
});
