const puppeteer = require("/tmp/p-test/node_modules/puppeteer-core");
const path = require("path");
const fs = require("fs");

const HTML_FILE = "file:///home/nc568/antigravity/hopeful-volta/fossil-nim/fossil-browser.html";
const ARTIFACT_DIR = "/home/nc568/.gemini/antigravity/brain/61058840-d586-4e96-a395-fdd951e4f976";
const CHROME_PATH = "/home/nc568/.cache/puppeteer/chrome/linux-155.0.8059.79/chrome-linux64/chrome";

let passedCount = 0;
let failedCount = 0;

function assert(cond, name, details = "") {
  if (cond) {
    console.log(`  ✅ [PASS] ${name}`);
    passedCount++;
  } else {
    console.error(`  ❌ [FAIL] ${name} ${details ? "(" + details + ")" : ""}`);
    failedCount++;
  }
}

(async () => {
  console.log("=================================================================");
  console.log("🛠️ FOSSIL-NIM: VERIFYING USER ISSUES FIXES & MULTI-DB FILES");
  console.log("=================================================================");

  const browser = await puppeteer.launch({
    executablePath: CHROME_PATH,
    headless: "new",
    args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage"]
  });

  const page = await browser.newPage();
  const browserErrors = [];
  page.on("pageerror", err => {
    console.error("  [BROWSER ERROR]:", err.message);
    browserErrors.push(err.message);
  });

  await page.setViewport({ width: 1440, height: 900 });
  await page.goto(HTML_FILE, { waitUntil: "networkidle0" });
  await new Promise(r => setTimeout(r, 600));

  // =========================================================================
  // 1. Check No Duplicate Emojis in Sidebar
  // =========================================================================
  console.log("\n--- 1. Testing No Duplicate Emojis in Sidebar ---");
  const sidebarLinks = await page.$$eval("#app-sidebar .sidebar-link", els => {
    return els.map(el => {
      const icon = el.querySelector(".sidebar-icon") ? el.querySelector(".sidebar-icon").innerText.trim() : "";
      const text = el.querySelector(".sidebar-text") ? el.querySelector(".sidebar-text").innerText.trim() : "";
      const full = el.innerText.trim();
      return { icon, text, full };
    });
  });

  for (const item of sidebarLinks) {
    // text should NOT start with the icon or any emoji
    const emojiRegex = /^[\p{Extended_Pictographic}\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/u;
    const hasDoubleEmoji = emojiRegex.test(item.text);
    assert(!hasDoubleEmoji, `Link text '${item.text}' does not contain duplicate emoji prefix`, `Full: '${item.full}'`);
  }

  // =========================================================================
  // 2. Check Redundant Top Tabs Bar is Removed
  // =========================================================================
  console.log("\n--- 2. Testing Redundant Horizontal Tabs Bar is Removed ---");
  const topTabsNavExists = await page.$eval(".tabs-nav", el => el !== null).catch(() => false);
  assert(!topTabsNavExists, "Redundant .tabs-nav strip is completely removed from DOM and layout");

  // =========================================================================
  // 3. Test Compare Diff in Files Editor
  // =========================================================================
  console.log("\n--- 3. Testing '⚡ Сравнить Diff' in Files Editor ---");
  await page.click("#app-sidebar .sidebar-link[data-tab='files']");
  await new Promise(r => setTimeout(r, 300));

  // Type modification in editor
  await page.evaluate(() => {
    const ta = document.getElementById("code-editor-text");
    if (ta) {
      ta.value = ta.value + "\n\n// Added new test feature for diff verification\nproc testDiff(): bool = true\n";
    }
  });

  // Click compare diff button
  await page.click("#btn-editor-diff");
  await new Promise(r => setTimeout(r, 200));

  const diffPreviewVisible = await page.$eval("#editor-diff-preview", el => !el.classList.contains("hidden"));
  const diffContent = await page.$eval("#editor-diff-preview", el => el.innerText.trim());
  assert(diffPreviewVisible, "Myers diff preview opened in editor");
  assert(diffContent.includes("testDiff") && (diffContent.includes("+++") || diffContent.includes("+proc")), "Diff output contains added lines and unified chunks", diffContent.substring(0, 80));

  const shotEditorDiff = path.join(ARTIFACT_DIR, "ui_editor_diff_working.png");
  await page.screenshot({ path: shotEditorDiff });
  console.log(`  📸 Saved editor diff screenshot: ${shotEditorDiff}`);

  // Test Standalone Myers Diff Tab
  console.log("  Testing Standalone Myers Diff Tab...");
  await page.click("#app-sidebar .sidebar-link[data-tab='diff']");
  await new Promise(r => setTimeout(r, 200));
  await page.click("#btn-run-standalone-diff");
  await new Promise(r => setTimeout(r, 200));
  const standaloneResult = await page.$eval("#standalone-diff-result", el => el.innerText.trim());
  assert(standaloneResult.includes("Computed in") && standaloneResult.includes("+++"), "Standalone Myers diff computes unified diff cleanly", standaloneResult.substring(0, 60));

  // =========================================================================
  // 4. Test Multi-DB File Creation & Reading (IndexedDB, SQLite WASM, CDB)
  // =========================================================================
  console.log("\n--- 4. Testing Multi-DB File Creation, Listing & Reading ---");

  // A. SQLite WASM Backend
  console.log("  Switching to SQLite WASM...");
  await page.select("#storage-backend-select", "sqlite_wasm");
  await page.waitForFunction(() => window.FossilStorageManager.sqliteWasm && window.FossilStorageManager.sqliteWasm.db !== null, { timeout: 10000 });
  await new Promise(r => setTimeout(r, 300));

  const writeSqlRes = await page.evaluate(async () => {
    return await window.fossilMcp.callTool("vcs_file_write", {
      path: "src/sqlite_feature.nim",
      content: "# Written in SQLite WASM engine!\necho \"Hello from SQLite!\"\n"
    });
  });
  assert(writeSqlRes && writeSqlRes.success, "vcs_file_write succeeded in SQLite WASM");

  const listSqlRes = await page.evaluate(async () => {
    return await window.fossilMcp.callTool("vcs_file_list", {});
  });
  const hasSqlFile = listSqlRes.filePaths && listSqlRes.filePaths.includes("src/sqlite_feature.nim");
  assert(hasSqlFile, "vcs_file_list returns newly created file in SQLite WASM", JSON.stringify(listSqlRes.filePaths));

  const readSqlRes = await page.evaluate(async () => {
    return await window.fossilMcp.callTool("vcs_file_read", { path: "src/sqlite_feature.nim" });
  });
  assert(readSqlRes && readSqlRes.content && readSqlRes.content.includes("Hello from SQLite"), "vcs_file_read retrieved file content from SQLite WASM");

  // B. Pure-Nim CDB Backend
  console.log("  Switching to Pure-Nim CDB...");
  await page.select("#storage-backend-select", "cdb");
  await new Promise(r => setTimeout(r, 300));

  const writeCdbRes = await page.evaluate(async () => {
    return await window.fossilMcp.callTool("vcs_file_write", {
      path: "src/cdb_fast.nim",
      content: "# Written in Pure-Nim CDB RAM!\nconst FAST_KV = true\n"
    });
  });
  assert(writeCdbRes && writeCdbRes.success, "vcs_file_write succeeded in Pure-Nim CDB");

  const listCdbRes = await page.evaluate(async () => {
    return await window.fossilMcp.callTool("vcs_file_list", {});
  });
  const hasCdbFile = listCdbRes.filePaths && listCdbRes.filePaths.includes("src/cdb_fast.nim");
  assert(hasCdbFile, "vcs_file_list returns newly created file in Pure-Nim CDB", JSON.stringify(listCdbRes.filePaths));

  const readCdbRes = await page.evaluate(async () => {
    return await window.fossilMcp.callTool("vcs_file_read", { path: "src/cdb_fast.nim" });
  });
  assert(readCdbRes && readCdbRes.content && readCdbRes.content.includes("FAST_KV"), "vcs_file_read retrieved file content from Pure-Nim CDB");

  // Return to IndexedDB
  await page.select("#storage-backend-select", "indexeddb");
  await new Promise(r => setTimeout(r, 200));

  // =========================================================================
  // 5. Test Right Action Menu Toggle on Mobile / Small Screens
  // =========================================================================
  console.log("\n--- 5. Testing Right Action Menu Toggle on Mobile (<1100px) ---");
  await page.setViewport({ width: 500, height: 750, isMobile: true });
  await new Promise(r => setTimeout(r, 300));

  const rightToggleBtn = await page.$("#btn-mobile-menu");
  assert(rightToggleBtn !== null, "#btn-mobile-menu toggle exists");

  let isActionsOpen = await page.$eval(".navbar-actions", el => el.classList.contains("open"));
  assert(!isActionsOpen, "Navbar actions dropdown initially closed");

  // Click right toggle button to open
  await page.click("#btn-mobile-menu");
  await new Promise(r => setTimeout(r, 250));

  isActionsOpen = await page.$eval(".navbar-actions", el => el.classList.contains("open"));
  const actionsRect = await page.$eval(".navbar-actions", el => {
    const r = el.getBoundingClientRect();
    return { top: r.top, bottom: r.bottom, height: r.height, width: r.width, right: r.right };
  });

  assert(isActionsOpen, "Navbar actions dropdown opens upon clicking right toggle button");
  assert(actionsRect.height > 100 && actionsRect.width > 200, "Navbar actions dropdown has valid visible dimensions (not clipped)", `h=${actionsRect.height}, w=${actionsRect.width}`);

  const shotMobileActions = path.join(ARTIFACT_DIR, "ui_mobile_right_menu_open.png");
  await page.screenshot({ path: shotMobileActions });
  console.log(`  📸 Saved mobile right actions menu screenshot: ${shotMobileActions}`);

  // Click outside to close
  await page.mouse.click(50, 400);
  await new Promise(r => setTimeout(r, 250));
  isActionsOpen = await page.$eval(".navbar-actions", el => el.classList.contains("open"));
  assert(!isActionsOpen, "Navbar actions dropdown closes cleanly on outside click");

  // =========================================================================
  // Summary
  // =========================================================================
  await browser.close();

  console.log("\n" + "=".repeat(65));
  console.log(`USER ISSUES VERIFICATION RESULTS: ${passedCount} PASSED, ${failedCount} FAILED, ${browserErrors.length} BROWSER ERRORS`);
  console.log("=".repeat(65));

  if (failedCount > 0 || browserErrors.length > 0) {
    process.exit(1);
  }
})();
