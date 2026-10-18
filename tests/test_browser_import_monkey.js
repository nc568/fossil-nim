const puppeteer = require("/tmp/p-test/node_modules/puppeteer-core");
const fs = require("fs");
const path = require("path");

const ARTIFACT_DIR = "/home/nc568/.gemini/antigravity/brain/61058840-d586-4e96-a395-fdd951e4f976";
const HTML_FILE = "file:///home/nc568/antigravity/hopeful-volta/fossil-nim/fossil-browser.html";
const CHROME_PATH = "/home/nc568/.cache/puppeteer/chrome/linux-155.0.8059.79/chrome-linux64/chrome";

let testLog = [];
let passedCount = 0;
let failedCount = 0;

function assert(condition, testName, details = "") {
  if (condition) {
    console.log(`  ✅ [PASS] ${testName}`);
    testLog.push({ name: testName, status: "PASS", details });
    passedCount++;
  } else {
    console.error(`  ❌ [FAIL] ${testName}: ${details}`);
    testLog.push({ name: testName, status: "FAIL", details });
    failedCount++;
  }
}

(async () => {
  console.log("=" .repeat(65));
  console.log("📥 FOSSIL-NIM IMPORT/EXPORT VERIFICATION & MONKEY STRESS TEST");
  console.log("=" .repeat(65));

  const browser = await puppeteer.launch({
    executablePath: CHROME_PATH,
    headless: true,
    args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage", "--window-size=1280,950"]
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 950 });

  let pageErrors = [];
  page.on("pageerror", err => {
    console.error("  [BROWSER ERROR]:", err.message);
    pageErrors.push(err.message);
  });

  page.on("console", msg => {
    if (msg.type() === "error") {
      console.warn("  [BROWSER CONSOLE ERROR]:", msg.text());
    }
  });

  // Handle standard dialogs
  page.on("dialog", async dialog => {
    await dialog.accept("Monkey Test Input");
  });

  console.log(`\nLoading ${HTML_FILE}...`);
  await page.goto(HTML_FILE, { waitUntil: "networkidle0" });
  await new Promise(r => setTimeout(r, 600));

  // =========================================================================
  // 1. MCP Server Tool Export & Import Testing
  // =========================================================================
  console.log("\n--- 1. Testing MCP Server: storage_export_file & storage_import_file ---");

  // 1.1 Test storage_export_file tool
  const mcpExportRes = await page.evaluate(async () => {
    return await window.fossilMcp.callTool("storage_export_file", {});
  });
  assert(mcpExportRes.success === true, "MCP storage_export_file succeeds", `Backend: ${mcpExportRes.backend}`);
  assert(mcpExportRes.data && mcpExportRes.data.format === "fossil-nim-bundle", "MCP export returned valid fossil-nim-bundle format");
  const initialBundle = mcpExportRes.data;

  // 1.2 Modify repo via MCP
  await page.evaluate(async () => {
    await window.fossilMcp.callTool("vcs_commit", { comment: "Commit before MCP import", files: ["mcp_local.txt"] });
    await window.fossilMcp.callTool("wiki_create", { name: "LocalWikiPage", content: "Locally created wiki content" });
  });

  // 1.3 Test storage_import_file in MERGE mode
  const externalBundleToMerge = {
    format: "fossil-nim-bundle",
    version: "1.0",
    events: [
      {
        id: "ci-ext-merge-1",
        uuid: "aabbcc1122334455",
        comment: "Imported Continuation Commit from Peer Repo",
        user: "peer_agent",
        branch: "trunk",
        mtime: Date.now() - 3600000,
        files: ["imported_feature.js"]
      }
    ],
    files: [
      { path: "imported_feature.js", content: "console.log('Imported feature works!');\n", mtime: Date.now() }
    ],
    wiki: [
      { name: "ImportedGuide", text: "# Imported Documentation\nMerged seamlessly without losing local pages.", author: "peer", mtime: Date.now() }
    ],
    tickets: [
      { id: "tkt-mcp-99", title: "Imported MCP Ticket", desc: "Ticket imported via MCP merge", status: "Open", priority: "High" }
    ]
  };

  const t0Merge = Date.now();
  const mcpImportMergeRes = await page.evaluate(async (bundle) => {
    return await window.fossilMcp.callTool("storage_import_file", {
      data: JSON.stringify(bundle),
      format: "json",
      mode: "merge"
    });
  }, externalBundleToMerge);
  const mergeDuration = Date.now() - t0Merge;

  assert(mcpImportMergeRes.success === true, "MCP storage_import_file in merge mode succeeds");
  assert(mcpImportMergeRes.mode === "merge", "Import mode reported as merge");
  console.log(`  ⚡ MCP Merge completed in ${mergeDuration}ms`);

  // Verify that both local and imported wiki pages exist
  const wikiListAfterMerge = await page.evaluate(async () => {
    const res = await window.fossilMcp.callTool("wiki_list", {});
    return res.pages.map(p => p.name);
  });
  assert(wikiListAfterMerge.includes("ImportedGuide"), "Merged bundle wiki page 'ImportedGuide' is present");
  assert(wikiListAfterMerge.includes("Home"), "Existing wiki page 'Home' is preserved");

  // 1.4 Test storage_import_file in REPLACE mode
  const cleanSlateBundle = {
    format: "fossil-nim-bundle",
    version: "1.0",
    events: [
      {
        id: "ci-clean-01",
        uuid: "9988776655443322",
        comment: "Clean Slate Initial Commit Only",
        user: "root",
        branch: "trunk",
        mtime: Date.now(),
        files: ["clean.txt"]
      }
    ],
    files: [
      { path: "clean.txt", content: "Clean slate file content", mtime: Date.now() }
    ],
    wiki: [
      { name: "CleanWikiOnly", text: "# Clean Wiki Page\nOnly this wiki should exist.", author: "root", mtime: Date.now() }
    ],
    tickets: [
      { id: "tkt-clean-1", title: "Only Ticket", desc: "Clean ticket", status: "Closed", priority: "Low" }
    ]
  };

  const t0Replace = Date.now();
  const mcpImportReplaceRes = await page.evaluate(async (bundle) => {
    return await window.fossilMcp.callTool("storage_import_file", {
      data: JSON.stringify(bundle),
      format: "json",
      mode: "replace"
    });
  }, cleanSlateBundle);
  const replaceDuration = Date.now() - t0Replace;

  assert(mcpImportReplaceRes.success === true, "MCP storage_import_file in replace mode succeeds");
  assert(mcpImportReplaceRes.mode === "replace", "Import mode reported as replace");
  console.log(`  ⚡ MCP Replace completed in ${replaceDuration}ms`);

  const wikiListAfterReplace = await page.evaluate(async () => {
    const res = await window.fossilMcp.callTool("wiki_list", {});
    return res.pages.map(p => p.name);
  });
  assert(wikiListAfterReplace.includes("CleanWikiOnly"), "Clean replacement wiki is present");
  assert(!wikiListAfterReplace.includes("ImportedGuide"), "Previously merged wiki was cleanly replaced");

  // =========================================================================
  // 2. WebUI Interactive Import & Modal Conflict Flow Testing
  // =========================================================================
  console.log("\n--- 2. Testing WebUI Import Flow & Smart Conflict Dialog ---");

  // 2.1 Verify UI Import Button & Hidden File Input exist
  const importBtnExists = await page.$("#btn-import-repo") !== null;
  const fileInputExists = await page.$("#file-import-input") !== null;
  const modalExists = await page.$("#modal-import-confirm") !== null;
  assert(importBtnExists, "Navbar contains #btn-import-repo");
  assert(fileInputExists, "Page contains #file-import-input for file uploads");
  assert(modalExists, "Page contains #modal-import-confirm conflict resolution dialog");

  // 2.2 Trigger Import Flow using Puppeteer's native file upload on #file-import-input
  const testBundlePath = "/tmp/test_bundle_merge.json";
  fs.writeFileSync(testBundlePath, JSON.stringify(externalBundleToMerge, null, 2));

  const fileInputEl = await page.$("#file-import-input");
  await fileInputEl.uploadFile(testBundlePath);

  await new Promise(r => setTimeout(r, 400));
  const isModalOpen = await page.$eval("#modal-import-confirm", el => !el.classList.contains("hidden"));
  assert(isModalOpen, "Smart Conflict Modal opened when importing over existing project data");

  // Capture screenshot of Conflict Modal
  const shotModal = path.join(ARTIFACT_DIR, "browser_import_conflict_modal.png");
  await page.screenshot({ path: shotModal });
  console.log(`  📸 Saved screenshot: ${shotModal}`);

  // Check radio options
  const radioMergeChecked = await page.$eval("input[name='import-mode-choice'][value='merge']", el => el.checked);
  assert(radioMergeChecked, "Default selected conflict mode is 'merge' (safe continuation)");

  // 2.3 Execute Merge via Modal button
  await page.click("#btn-import-confirm-execute");
  await new Promise(r => setTimeout(r, 600));

  const isModalClosed = await page.$eval("#modal-import-confirm", el => el.classList.contains("hidden"));
  assert(isModalClosed, "Modal closes automatically upon confirmation");

  // Verify UI updated
  await page.click(".tab-btn[data-tab='timeline']");
  await new Promise(r => setTimeout(r, 300));
  const timelineCount = await page.$$eval("#timeline-list .card", els => els.length);
  assert(timelineCount >= 2, "Timeline updated in UI with imported continuation check-ins", `Count: ${timelineCount}`);

  // Verify Files in UI
  await page.click(".tab-btn[data-tab='files']");
  await new Promise(r => setTimeout(r, 300));
  const fileItems = await page.$$eval("#files-tree .file-tree-item", els => els.map(e => e.innerText.trim()));
  assert(fileItems.some(f => f.includes("imported_feature.js")), "Imported file 'imported_feature.js' visible in file tree");
  assert(fileItems.some(f => f.includes("clean.txt")), "Previously existing file 'clean.txt' retained in merge mode");

  // 2.4 Test Clean Overwrite via Modal
  const testCleanPath = "/tmp/test_bundle_clean.json";
  fs.writeFileSync(testCleanPath, JSON.stringify(cleanSlateBundle, null, 2));

  await fileInputEl.uploadFile(testCleanPath);
  await new Promise(r => setTimeout(r, 400));

  // Switch to Replace radio
  await page.click("input[name='import-mode-choice'][value='replace']");
  await new Promise(r => setTimeout(r, 100));
  await page.click("#btn-import-confirm-execute");
  await new Promise(r => setTimeout(r, 600));

  await page.click(".tab-btn[data-tab='files']");
  await new Promise(r => setTimeout(r, 300));
  const filesAfterReplace = await page.$$eval("#files-tree .file-tree-item", els => els.map(e => e.innerText.trim()));
  assert(filesAfterReplace.some(f => f.includes("clean.txt")), "Replacement file 'clean.txt' is present");
  assert(!filesAfterReplace.some(f => f.includes("imported_feature.js")), "Merged file 'imported_feature.js' was cleaned in replace mode");

  // =========================================================================
  // 3. Multi-Backend Import Testing (SQLite WASM & CDB)
  // =========================================================================
  console.log("\n--- 3. Testing Import across Multi-Storage Backends ---");

  // 3.1 SQLite WASM import
  console.log("  Testing SQLite WASM Backend import...");
  await page.select("#storage-backend-select", "sqlite_wasm");
  await page.waitForFunction(() => window.FossilStorageManager.sqliteWasm && window.FossilStorageManager.sqliteWasm.db !== null, { timeout: 10000 });
  await new Promise(r => setTimeout(r, 300));

  const sqliteImportRes = await page.evaluate(async (bundle) => {
    return await window.FossilStorageManager.importRepo(bundle, "repo.json", "merge");
  }, externalBundleToMerge);
  assert(sqliteImportRes.success === true, "SQLite WASM importBundle succeeds with SQL transaction");

  // Check SQL count
  const sqliteEventCount = await page.evaluate(() => {
    const rows = window.FossilStorageManager.sqliteWasm.exec("SELECT count(*) as c FROM event;");
    return rows && rows.length > 0 ? rows[0].c : 0;
  });
  assert(sqliteEventCount >= 2, "SQLite WASM event table populated by import", `Count: ${sqliteEventCount}`);

  // 3.2 Pure-Nim CDB import
  console.log("  Testing Pure-Nim CDB Backend import...");
  await page.select("#storage-backend-select", "cdb");
  await page.waitForFunction(() => window.FossilStorageManager.cdb && window.FossilStorageManager.cdb.handle !== 0, { timeout: 10000 });
  await new Promise(r => setTimeout(r, 300));

  const cdbImportRes = await page.evaluate(async (bundle) => {
    return await window.FossilStorageManager.importRepo(bundle, "repo.json", "merge");
  }, externalBundleToMerge);
  assert(cdbImportRes.success === true, "Pure-Nim CDB importBundle succeeds in memory");

  const cdbFileVal = await page.evaluate(() => {
    return window.FossilStorageManager.cdb.get("file:imported_feature.js");
  });
  assert(cdbFileVal && cdbFileVal.includes("Imported feature works"), "Pure-Nim CDB retrieved imported file via hash map");

  // =========================================================================
  // 4. Chaotic Monkey Stress Test (Fast Navigation & User Interactions)
  // =========================================================================
  console.log("\n--- 4. Running Chaotic Monkey Test (Fast Clicks & Rapid State Switches) ---");

  const tabs = ["timeline", "files", "diff", "wiki", "tickets", "mcp", "storage"];
  for (let i = 0; i < 40; i++) {
    const tab = tabs[i % tabs.length];
    await page.click(`.tab-btn[data-tab='${tab}']`);
    if (i % 6 === 0) {
      await page.click("#btn-export-repo").catch(() => {});
    }
    if (i % 8 === 0) {
      await page.click("#theme-toggle-btn").catch(() => {});
    }
    await new Promise(r => setTimeout(r, 60));
  }
  await new Promise(r => setTimeout(r, 500));

  // Reset theme and select timeline
  await page.click(".tab-btn[data-tab='timeline']");
  await new Promise(r => setTimeout(r, 200));

  // Final screenshot
  const finalShot = path.join(ARTIFACT_DIR, "browser_import_monkey_completed.png");
  await page.screenshot({ path: finalShot, fullPage: true });
  console.log(`  📸 Saved screenshot: ${finalShot}`);

  // Zero errors check
  assert(pageErrors.length === 0, "Zero unhandled runtime errors during monkey stress test", `Errors: ${pageErrors.join("; ")}`);

  console.log("\n" + "=".repeat(65));
  console.log(`IMPORT & MONKEY TEST RESULTS: ${passedCount} PASSED, ${failedCount} FAILED`);
  console.log("=".repeat(65));

  await browser.close();
  process.exit(failedCount > 0 ? 1 : 0);
})();
