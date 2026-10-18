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
  console.log("🦊 FOSSIL-NIM GITLAB-STYLE SIDEBAR, ABOUT TAB & DYNAMIC STATUS TEST");
  console.log("=" .repeat(65));

  const browser = await puppeteer.launch({
    executablePath: CHROME_PATH,
    headless: true,
    args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage"]
  });

  const page = await browser.newPage();

  page.on("pageerror", err => console.error("  [BROWSER ERROR]:", err.message));
  page.on("dialog", async dialog => await dialog.accept("Test Input"));

  // =========================================================================
  // 1. Initial Desktop Load (1920x1080)
  // =========================================================================
  console.log("\n--- 1. Testing GitLab Layout & Sidebar Structure ---");
  await page.setViewport({ width: 1920, height: 1080 });
  await page.goto(HTML_FILE, { waitUntil: "networkidle0" });
  await new Promise(r => setTimeout(r, 600));

  const sidebarExists = await page.$("#app-sidebar") !== null;
  assert(sidebarExists, "Left sidebar #app-sidebar exists");

  const sidebarTabs = await page.$$eval("#app-sidebar .sidebar-link", els => els.map(e => e.getAttribute("data-tab")));
  console.log("  Sidebar tabs found:", sidebarTabs);
  assert(sidebarTabs.includes("timeline") && sidebarTabs.includes("files") && sidebarTabs.includes("about"), "Sidebar contains timeline, files, and about tabs");

  const shotSidebarExpanded = path.join(ARTIFACT_DIR, "gitlab_layout_desktop.png");
  await page.screenshot({ path: shotSidebarExpanded });
  console.log(`  📸 Saved GitLab layout screenshot: ${shotSidebarExpanded}`);

  // =========================================================================
  // 2. Desktop Sidebar Collapse & Expand Interaction
  // =========================================================================
  console.log("\n--- 2. Testing Sidebar Collapse / Expand (GitLab UX) ---");
  const initSidebarWidth = await page.$eval("#app-sidebar", el => el.getBoundingClientRect().width);
  assert(initSidebarWidth >= 200, "Sidebar initially expanded (~240px)", `Width: ${initSidebarWidth}px`);

  // Click collapse button in header
  await page.click("#btn-sidebar-collapse");
  await new Promise(r => setTimeout(r, 300));

  let collapsedWidth = await page.$eval("#app-sidebar", el => el.getBoundingClientRect().width);
  let isCollapsedClass = await page.$eval("#app", el => el.classList.contains("sidebar-collapsed"));
  assert(isCollapsedClass && collapsedWidth <= 70, "Sidebar collapses to compact icon-only mode (~60px)", `Width: ${collapsedWidth}px`);

  const shotSidebarCollapsed = path.join(ARTIFACT_DIR, "gitlab_sidebar_collapsed.png");
  await page.screenshot({ path: shotSidebarCollapsed });
  console.log(`  📸 Saved collapsed sidebar screenshot: ${shotSidebarCollapsed}`);

  // Click expand button in footer
  await page.click("#btn-sidebar-toggle");
  await new Promise(r => setTimeout(r, 300));

  let restoredWidth = await page.$eval("#app-sidebar", el => el.getBoundingClientRect().width);
  isCollapsedClass = await page.$eval("#app", el => el.classList.contains("sidebar-collapsed"));
  assert(!isCollapsedClass && restoredWidth >= 200, "Sidebar expands back smoothly on toggle", `Width: ${restoredWidth}px`);

  // =========================================================================
  // 3. Dynamic Variables in Top Bar & Reactive Checks (NO hardcoded text)
  // =========================================================================
  console.log("\n--- 3. Testing Dynamic Status Indicators (Reactive Variables) ---");

  // Version and runtime
  const dynVerText = await page.$eval("#dyn-version-label", el => el.innerText.trim());
  const dynRuntimeText = await page.$eval("#dyn-runtime-label", el => el.innerText.trim());
  assert(dynVerText.startsWith("v2."), "Dynamic version variable populated", dynVerText);
  assert(dynRuntimeText.includes("JS") || dynRuntimeText.includes("WASM"), "Dynamic runtime indicator populated", dynRuntimeText);

  // Active DB backend
  let dynDbText = await page.$eval("#dyn-backend-label", el => el.innerText.trim());
  assert(dynDbText.includes("IndexedDB"), "Initial active database dynamically reported as IndexedDB", dynDbText);

  // MCP tool counter
  const dynMcpCount = await page.$eval("#dyn-mcp-count", el => parseInt(el.innerText.trim()));
  const actualToolCount = await page.evaluate(() => window.fossilMcp.tools.length);
  assert(dynMcpCount === actualToolCount && actualToolCount >= 20, "Dynamic MCP tools counter matches actual registered tools", `Count: ${dynMcpCount}`);

  // Test dynamic database switch updates the pill automatically
  console.log("  Switching database to SQLite WASM...");
  await page.select("#storage-backend-select", "sqlite_wasm");
  await page.waitForFunction(() => window.FossilStorageManager.sqliteWasm && window.FossilStorageManager.sqliteWasm.db !== null, { timeout: 10000 });
  await new Promise(r => setTimeout(r, 400));

  dynDbText = await page.$eval("#dyn-backend-label", el => el.innerText.trim());
  assert(dynDbText.includes("SQLite WASM"), "Active DB pill dynamically updated on storage backend change", dynDbText);

  // Switch to CDB
  console.log("  Switching database to Pure-Nim CDB...");
  await page.select("#storage-backend-select", "cdb");
  await new Promise(r => setTimeout(r, 300));

  dynDbText = await page.$eval("#dyn-backend-label", el => el.innerText.trim());
  assert(dynDbText.includes("CDB"), "Active DB pill dynamically updated to Pure-Nim CDB", dynDbText);

  // Switch back to IndexedDB
  await page.select("#storage-backend-select", "indexeddb");
  await new Promise(r => setTimeout(r, 300));

  // =========================================================================
  // 4. Testing Dedicated "О проекте" (About Project) Tab
  // =========================================================================
  console.log("\n--- 4. Testing Dedicated 'О проекте' (About Project) Tab ---");

  // Verify working tabs have no banner cluttering their view
  await page.click(".tab-btn[data-tab='files']");
  await new Promise(r => setTimeout(r, 200));
  const filesTabVisible = await page.$eval("#tab-files", el => el.classList.contains("active"));
  const heroInFiles = await page.$eval("#tab-files #browser-hero", el => el !== null).catch(() => false);
  assert(filesTabVisible && !heroInFiles, "Files tab is completely clean without hero banner taking screen space");

  // Switch to About Tab
  await page.click(".tab-btn[data-tab='about']");
  await new Promise(r => setTimeout(r, 300));

  const aboutTabVisible = await page.$eval("#tab-about", el => el.classList.contains("active"));
  assert(aboutTabVisible, "Switched cleanly to 'О проекте' (tab-about)");

  const heroInAbout = await page.$eval("#tab-about #browser-hero", el => el !== null);
  assert(heroInAbout, "Hero banner is located cleanly inside 'О проекте' tab");

  // Check dynamic values inside About tab
  const aboutDynVer = await page.$eval("#about-dyn-version", el => el.innerText.trim());
  const aboutDynDb = await page.$eval("#about-dyn-db", el => el.innerText.trim());
  const aboutDynMcp = await page.$eval("#about-dyn-mcp-total", el => el.innerText.trim());
  const aboutDynWasm = await page.$eval("#about-dyn-wasm", el => el.innerText.trim());

  assert(aboutDynVer.includes("v2."), "About tab dynamic version verified", aboutDynVer);
  assert(aboutDynDb.includes("IndexedDB"), "About tab dynamic active DB verified", aboutDynDb);
  assert(aboutDynMcp.includes("Tools"), "About tab dynamic MCP tools counter verified", aboutDynMcp);
  assert(aboutDynWasm.includes("Supported") || aboutDynWasm.includes("Ready"), "About tab WebAssembly support verified", aboutDynWasm);

  const shotAboutTab = path.join(ARTIFACT_DIR, "gitlab_about_tab.png");
  await page.screenshot({ path: shotAboutTab });
  console.log(`  📸 Saved About tab screenshot: ${shotAboutTab}`);

  // =========================================================================
  // 5. Mobile Layout & Drawer Toggle (375x667)
  // =========================================================================
  console.log("\n--- 5. Testing Mobile Viewport & GitLab Drawer Navigation ---");
  await page.setViewport({ width: 375, height: 667, isMobile: true });
  await new Promise(r => setTimeout(r, 300));

  let hasHorizOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
  assert(!hasHorizOverflow, "Zero horizontal overflow on Mobile (375x667)");

  // Drawer initially closed
  let isDrawerOpen = await page.$eval("#app", el => el.classList.contains("sidebar-open"));
  assert(!isDrawerOpen, "Mobile sidebar drawer initially closed off-canvas");

  // Open drawer via sidebar toggle button
  await page.click("#btn-sidebar-collapse");
  await new Promise(r => setTimeout(r, 300));

  isDrawerOpen = await page.$eval("#app", el => el.classList.contains("sidebar-open"));
  assert(isDrawerOpen, "Mobile sidebar drawer slides out cleanly on menu click");

  const shotMobileDrawer = path.join(ARTIFACT_DIR, "gitlab_mobile_drawer.png");
  await page.screenshot({ path: shotMobileDrawer });
  console.log(`  📸 Saved mobile drawer screenshot: ${shotMobileDrawer}`);

  // Click backdrop to close
  await page.click("#sidebar-backdrop");
  await new Promise(r => setTimeout(r, 300));

  isDrawerOpen = await page.$eval("#app", el => el.classList.contains("sidebar-open"));
  assert(!isDrawerOpen, "Mobile sidebar drawer closes upon backdrop tap");

  // Re-open and click a tab
  await page.click("#btn-sidebar-collapse");
  await new Promise(r => setTimeout(r, 200));
  await page.click("#app-sidebar .sidebar-link[data-tab='timeline']");
  await new Promise(r => setTimeout(r, 300));

  isDrawerOpen = await page.$eval("#app", el => el.classList.contains("sidebar-open"));
  const timelineActive = await page.$eval("#tab-timeline", el => el.classList.contains("active"));
  assert(!isDrawerOpen && timelineActive, "Mobile drawer automatically closes upon navigating to tab");

  // =========================================================================
  // Final summary
  // =========================================================================
  await browser.close();

  console.log("\n" + "=" .repeat(65));
  console.log(`GITLAB SIDEBAR & ABOUT TAB TEST RESULTS: ${passedCount} PASSED, ${failedCount} FAILED`);
  console.log("=" .repeat(65));

  if (failedCount > 0) {
    process.exit(1);
  }
})();
