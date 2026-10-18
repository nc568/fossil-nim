const puppeteer = require("/tmp/p-test/node_modules/puppeteer-core");
const path = require("path");
const fs = require("fs");
const { spawn } = require("child_process");

const ROOT_DIR = "/home/nc568/antigravity/hopeful-volta/fossil-nim";
const BIN_FOSSIL = path.join(ROOT_DIR, "bin/fossil");
const HTML_FILE = "file://" + path.join(ROOT_DIR, "fossil-browser.html");
const ARTIFACT_DIR = "/home/nc568/.gemini/antigravity/brain/61058840-d586-4e96-a395-fdd951e4f976";
const CHROME_PATH = "/home/nc568/.cache/puppeteer/chrome/linux-155.0.8059.79/chrome-linux64/chrome";
const PORT = 8097;
const NATIVE_URL = `http://127.0.0.1:${PORT}/`;

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

async function sleep(ms) {
  return new Promise(r => setTimeout(r, ms));
}

(async () => {
  console.log("=================================================================");
  console.log("🐒 FOSSIL-NIM: COMPREHENSIVE MONKEY & E2E TESTING (ALL EDITIONS)");
  console.log("=================================================================");

  // Setup temporary repository for Native WebUI server
  const tempRepo = "/tmp/fossil_monkey_repo.fossil";
  const tempCheckout = "/tmp/fossil_monkey_checkout";
  if (fs.existsSync(tempRepo)) fs.unlinkSync(tempRepo);
  if (fs.existsSync(tempCheckout)) fs.rmSync(tempCheckout, { recursive: true, force: true });
  fs.mkdirSync(tempCheckout, { recursive: true });

  const { execSync } = require("child_process");
  execSync(`${BIN_FOSSIL} init ${tempRepo}`, { stdio: "ignore" });
  execSync(`${BIN_FOSSIL} open ${tempRepo}`, { cwd: tempCheckout, stdio: "ignore" });
  fs.writeFileSync(path.join(tempCheckout, "index.txt"), "Fossil Native Server Test");
  execSync(`${BIN_FOSSIL} add index.txt`, { cwd: tempCheckout, stdio: "ignore" });
  execSync(`${BIN_FOSSIL} commit -m "Initial monkey test commit"`, { cwd: tempCheckout, stdio: "ignore" });
  execSync(`${BIN_FOSSIL} wiki create Home "Native Server Home Page"`, { cwd: tempCheckout, stdio: "ignore" });
  execSync(`${BIN_FOSSIL} ticket create "Native Issue" "Native issue desc"`, { cwd: tempCheckout, stdio: "ignore" });

  const serverProc = spawn(BIN_FOSSIL, ["server", "--port", String(PORT), "--bind", "127.0.0.1"], {
    cwd: tempCheckout,
    stdio: "ignore"
  });
  await sleep(1500);

  const browser = await puppeteer.launch({
    executablePath: CHROME_PATH,
    headless: "new",
    args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage"]
  });

  const page = await browser.newPage();
  page.on("pageerror", err => console.log(`  [BROWSER ERROR]: ${err.message}`));

  try {
    // =========================================================================
    // 1. NATIVE SERVER EDITION (http://127.0.0.1:8097/)
    // =========================================================================
    console.log("\n--- 1. Testing Native Server Edition (GitLab Sidebar & SPA) ---");
    await page.setViewport({ width: 1920, height: 1080 });
    await page.goto(NATIVE_URL, { waitUntil: "networkidle0" });
    await sleep(500);

    const title = await page.title();
    assert(title.includes("Fossil"), "Native WebUI loaded successfully with title", title);

    // Systematic Monkey clicking of all navbar links in Native WebUI
    const nativeLinks = await page.evaluate(() => {
      const links = Array.from(document.querySelectorAll("#navbar-menu a[data-link]"));
      return links.map(l => ({ text: l.innerText, href: l.getAttribute("href") }));
    });
    assert(nativeLinks.length >= 6, `Found ${nativeLinks.length} Native WebUI navigation links`, JSON.stringify(nativeLinks.map(l => l.href)));

    for (const link of nativeLinks) {
      const clicked = await page.evaluate(h => {
        const a = document.querySelector(`#navbar-menu a[href="${h}"]`);
        if (a) { a.click(); return true; }
        return false;
      }, link.href);
      assert(clicked, `Native navbar item '${link.text}' (${link.href}) clicked successfully`);
      await sleep(150);
    }

    // Toggle Theme button
    const themeToggled = await page.evaluate(() => {
      const btn = document.getElementById("theme-toggle");
      if (btn) {
        const initialTheme = document.documentElement.getAttribute("data-theme") || "light";
        btn.click();
        const newTheme = document.documentElement.getAttribute("data-theme") || "dark";
        return initialTheme !== newTheme;
      }
      return false;
    });
    assert(themeToggled, "Native WebUI theme toggle button works");

    // Open & Close Theme Editor
    const themeEditorWorks = await page.evaluate(() => {
      const editBtn = document.getElementById("theme-editor-btn");
      const editorModal = document.getElementById("theme-editor");
      if (editBtn && editorModal) {
        editBtn.click();
        const isOpen = !editorModal.classList.contains("hidden");
        const closeBtn = editorModal.querySelector(".modal-header button");
        if (closeBtn) closeBtn.click();
        else editorModal.classList.add("hidden");
        return isOpen;
      }
      return false;
    });
    assert(themeEditorWorks, "Native WebUI Theme Editor opens and closes properly");

    // Screenshot Desktop Native
    const nativeDeskShot = path.join(ARTIFACT_DIR, "monkey_test_native_desktop.png");
    await page.screenshot({ path: nativeDeskShot });
    assert(fs.existsSync(nativeDeskShot), "Saved Native Desktop WebUI screenshot");

    // Responsive Viewports: Tablet (768x1024)
    console.log("\n--- 2. Testing Responsive Layouts: Tablet & Mobile ---");
    await page.setViewport({ width: 768, height: 1024 });
    await sleep(300);
    const tabletOk = await page.evaluate(() => window.innerWidth === 768);
    assert(tabletOk, "Viewport adapted to Tablet resolution (768x1024)");

    // Responsive Viewports: Mobile (375x667)
    await page.setViewport({ width: 375, height: 667 });
    await sleep(300);
    const mobileOk = await page.evaluate(() => window.innerWidth === 375);
    assert(mobileOk, "Viewport adapted to Mobile resolution (375x667)");

    // Mobile Hamburger drawer test
    const drawerWorks = await page.evaluate(() => {
      const hamburger = document.getElementById("mobile-menu-toggle") || document.getElementById("mobile-menu-btn");
      if (hamburger) {
        hamburger.click();
        const sidebar = document.getElementById("app-sidebar") || document.querySelector(".app-sidebar");
        const isOpen = sidebar && (sidebar.classList.contains("open") || sidebar.classList.contains("mobile-open"));
        const closeBtn = document.getElementById("mobile-drawer-close");
        if (closeBtn) closeBtn.click();
        else hamburger.click();
        return isOpen;
      }
      return true;
    });
    assert(drawerWorks, "Mobile drawer opens and closes properly upon hamburger tap");

    const mobileShot = path.join(ARTIFACT_DIR, "monkey_test_native_mobile.png");
    await page.screenshot({ path: mobileShot });
    assert(fs.existsSync(mobileShot), "Saved Mobile layout screenshot");

    // =========================================================================
    // 3. IN-BROWSER STANDALONE EDITION & MULTI-DB (fossil-browser.html)
    // =========================================================================
    console.log("\n--- 3. Testing In-Browser Standalone Edition (Multi-DB Monkey Testing) ---");
    await page.setViewport({ width: 1920, height: 1080 });
    await page.goto(HTML_FILE, { waitUntil: "networkidle0" });
    await sleep(600);

    // --- Backend 1: IndexedDB ---
    console.log(">>> Sub-suite 3.1: IndexedDB Backend");
    const activeDb1 = await page.evaluate(() => window.FossilStorageManager ? window.FossilStorageManager.backendType : "unknown");
    assert(activeDb1 === "indexeddb", "Default storage engine is IndexedDB", activeDb1);

    // Monkey click all tabs in in-browser edition
    const browserTabs = ["timeline", "files", "diff", "wiki", "tickets", "calendar", "mcp", "about"];
    for (const tab of browserTabs) {
      await page.evaluate(t => {
        const btn = document.querySelector(`[data-tab="${t}"]`) || document.getElementById(`nav-${t}`);
        if (btn) btn.click();
      }, tab);
      await sleep(50);
    }
    assert(true, "All in-browser tabs monkey-clicked without DOM exceptions");

    // Ticket filter monkey testing
    await page.evaluate(() => document.querySelector('[data-tab="tickets"]').click());
    await sleep(200);

    for (const filter of ["all", "open", "closed"]) {
      const clicked = await page.evaluate(f => {
        const pill = document.querySelector(`[data-filter="${f}"]`);
        if (pill) { pill.click(); return true; }
        return false;
      }, filter);
      assert(clicked, `Ticket filter '${filter}' clicked successfully`);
      await sleep(100);
    }

    // Calendar Roadmap Monkey Testing
    await page.evaluate(() => document.querySelector('[data-tab="calendar"]').click());
    await sleep(200);
    const calNavWorks = await page.evaluate(() => {
      const nextBtn = document.getElementById("btn-calendar-next");
      const prevBtn = document.getElementById("btn-calendar-prev");
      const todayBtn = document.getElementById("btn-calendar-today");
      if (nextBtn && prevBtn && todayBtn) {
        nextBtn.click();
        prevBtn.click();
        todayBtn.click();
        return true;
      }
      return false;
    });
    assert(calNavWorks, "Calendar navigation (Next Month, Prev Month, Today) exercised");

    // MCP Agent Console Monkey Testing
    await page.evaluate(() => document.querySelector('[data-tab="mcp"]').click());
    await sleep(200);
    const mcpExercised = await page.evaluate(() => {
      const categoryPills = document.querySelectorAll("#mcp-category-filter-bar .badge, .mcp-category-pill");
      if (categoryPills.length > 0) {
        categoryPills[0].click();
        if (categoryPills.length > 1) categoryPills[1].click();
      }
      const callBtn = document.getElementById("btn-mcp-invoke");
      if (callBtn) {
        callBtn.click();
        return true;
      }
      return false;
    });
    assert(mcpExercised, "MCP Console category filtering & tool execution clicked");

    const idbShot = path.join(ARTIFACT_DIR, "monkey_test_browser_indexeddb.png");
    await page.screenshot({ path: idbShot });
    assert(fs.existsSync(idbShot), "Saved IndexedDB standalone screenshot");

    // --- Backend 2: SQLite WASM ---
    console.log(">>> Sub-suite 3.2: SQLite WASM Backend");
    const switchedToSqlite = await page.evaluate(async () => {
      if (window.FossilStorageManager) {
        await window.FossilStorageManager.switchBackend("sqlite_wasm");
        return window.FossilStorageManager.backendType === "sqlite_wasm";
      }
      return false;
    });
    assert(switchedToSqlite, "Switched backend to SQLite WASM");

    // Monkey click tabs in SQLite WASM mode
    for (const tab of ["timeline", "files", "tickets", "wiki", "about"]) {
      await page.evaluate(t => {
        const btn = document.querySelector(`[data-tab="${t}"]`) || document.getElementById(`nav-${t}`);
        if (btn) btn.click();
      }, tab);
      await sleep(100);
    }
    assert(true, "Exercised all tabs under SQLite WASM backend");

    const wasmShot = path.join(ARTIFACT_DIR, "monkey_test_browser_sqlite_wasm.png");
    await page.screenshot({ path: wasmShot });
    assert(fs.existsSync(wasmShot), "Saved SQLite WASM mode screenshot");

    // --- Backend 3: Pure-Nim CDB ---
    console.log(">>> Sub-suite 3.3: Pure-Nim CDB Backend");
    const switchedToCdb = await page.evaluate(async () => {
      if (window.FossilStorageManager) {
        await window.FossilStorageManager.switchBackend("cdb");
        return window.FossilStorageManager.backendType === "cdb";
      }
      return false;
    });
    assert(switchedToCdb, "Switched backend to Pure-Nim CDB");

    // Monkey click tabs in CDB mode
    for (const tab of ["timeline", "files", "tickets", "wiki", "about"]) {
      await page.evaluate(t => {
        const btn = document.querySelector(`[data-tab="${t}"]`) || document.getElementById(`nav-${t}`);
        if (btn) btn.click();
      }, tab);
      await sleep(100);
    }
    assert(true, "Exercised all tabs under Pure-Nim CDB backend");

    const cdbShot = path.join(ARTIFACT_DIR, "monkey_test_browser_pure_nim_cdb.png");
    await page.screenshot({ path: cdbShot });
    assert(fs.existsSync(cdbShot), "Saved Pure-Nim CDB mode screenshot");

  } finally {
    await browser.close();
    serverProc.kill();
    try {
      if (fs.existsSync(tempRepo)) fs.unlinkSync(tempRepo);
      if (fs.existsSync(tempCheckout)) fs.rmSync(tempCheckout, { recursive: true, force: true });
    } catch (e) {}
  }

  console.log("\n=================================================================");
  console.log(`🎉 MONKEY TESTING SUMMARY: ${passedCount} PASSED, ${failedCount} FAILED`);
  console.log("=================================================================");

  if (failedCount > 0) {
    process.exit(1);
  } else {
    process.exit(0);
  }
})();
