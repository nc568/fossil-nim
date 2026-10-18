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
  console.log("🎨 FOSSIL-NIM RESPONSIVE WEBUI, I18N & CONFIG MONKEY TEST");
  console.log("=" .repeat(65));

  const browser = await puppeteer.launch({
    executablePath: CHROME_PATH,
    headless: true,
    args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage"]
  });

  const page = await browser.newPage();

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

  page.on("dialog", async dialog => {
    await dialog.accept("Monkey Test Input");
  });

  // =========================================================================
  // 1. Desktop & Ultrawide Testing (1920x1080)
  // =========================================================================
  console.log("\n--- 1. Testing Desktop Layout (1920x1080) ---");
  await page.setViewport({ width: 1920, height: 1080 });
  await page.goto(HTML_FILE, { waitUntil: "networkidle0" });
  await new Promise(r => setTimeout(r, 600));

  const title = await page.title();
  assert(title.includes("Fossil-Nim"), "Page loaded cleanly with valid title", title);

  const shotDesktop = path.join(ARTIFACT_DIR, "ui_desktop_1920.png");
  await page.screenshot({ path: shotDesktop });
  console.log(`  📸 Saved desktop screenshot: ${shotDesktop}`);

  // Check no horizontal scrollbar on body
  let hasHorizOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
  assert(!hasHorizOverflow, "No horizontal overflow on Desktop 1920x1080");

  // =========================================================================
  // 2. Tablet Viewport Testing (768x1024)
  // =========================================================================
  console.log("\n--- 2. Testing Tablet Layout (768x1024) ---");
  await page.setViewport({ width: 768, height: 1024 });
  await new Promise(r => setTimeout(r, 300));

  hasHorizOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
  assert(!hasHorizOverflow, "No horizontal overflow on Tablet 768x1024");

  const shotTablet = path.join(ARTIFACT_DIR, "ui_tablet_768.png");
  await page.screenshot({ path: shotTablet });
  console.log(`  📸 Saved tablet screenshot: ${shotTablet}`);

  // =========================================================================
  // 3. Mobile Viewport Testing (375x667 - iPhone SE)
  // =========================================================================
  console.log("\n--- 3. Testing Mobile Layout (375x667) ---");
  await page.setViewport({ width: 375, height: 667, isMobile: true });
  await new Promise(r => setTimeout(r, 300));

  hasHorizOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
  assert(!hasHorizOverflow, "No horizontal overflow on Mobile 375x667");

  // Test Mobile Hamburger Drawer
  const mobileMenuBtn = await page.$("#btn-mobile-menu");
  assert(mobileMenuBtn !== null, "Mobile hamburger menu toggle button present");

  let isNavOpen = await page.$eval(".navbar-actions", el => el.classList.contains("open"));
  assert(!isNavOpen, "Mobile navbar actions initially closed");

  await page.click("#btn-mobile-menu");
  await new Promise(r => setTimeout(r, 200));
  isNavOpen = await page.$eval(".navbar-actions", el => el.classList.contains("open"));
  assert(isNavOpen, "Mobile navbar drawer opened on click");

  await page.click("#btn-mobile-menu");
  await new Promise(r => setTimeout(r, 200));

  // Test Mobile Files Tree Toggle in editor
  await page.click(".tab-btn[data-tab='files']");
  await new Promise(r => setTimeout(r, 300));

  const toggleTreeBtn = await page.$("#btn-toggle-file-tree");
  assert(toggleTreeBtn !== null, "Mobile file tree toggle button exists in editor toolbar");
  await page.click("#btn-toggle-file-tree");
  await new Promise(r => setTimeout(r, 150));
  const isTreeCollapsed = await page.$eval(".file-tree", el => el.classList.contains("collapsed"));
  assert(isTreeCollapsed, "File tree collapses on mobile to grant full width to code editor");
  await page.click("#btn-toggle-file-tree");

  const shotMobile = path.join(ARTIFACT_DIR, "ui_mobile_375.png");
  await page.screenshot({ path: shotMobile });
  console.log(`  📸 Saved mobile screenshot: ${shotMobile}`);

  // =========================================================================
  // 4. Dynamic Window Resizing Stress Test
  // =========================================================================
  console.log("\n--- 4. Testing Dynamic Window Resize Continuity ---");
  const testWidths = [1920, 1440, 1024, 768, 540, 360, 320, 1280];
  let resizeOverflowCount = 0;
  for (const w of testWidths) {
    await page.setViewport({ width: w, height: 800 });
    await new Promise(r => setTimeout(r, 80));
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
    if (overflow) resizeOverflowCount++;
  }
  assert(resizeOverflowCount === 0, "Zero horizontal overflow bugs across 8 dynamic resize breakpoints");

  // Reset viewport to standard comfortable desktop
  await page.setViewport({ width: 1366, height: 850 });

  // =========================================================================
  // 5. Themes & Custom Palettes System Testing
  // =========================================================================
  console.log("\n--- 5. Testing Themes & Color Customization ---");
  const themesToTest = ["dark", "light", "nord", "dracula", "gruvbox", "cyberpunk", "monokai"];
  for (const th of themesToTest) {
    await page.evaluate((themeName) => {
      window.FossilUIConfig.save({ theme: themeName });
    }, th);
    await new Promise(r => setTimeout(r, 100));
    const appliedTheme = await page.evaluate(() => document.documentElement.getAttribute("data-theme"));
    assert(appliedTheme === th, `Theme switched to '${th}'`);
  }

  // Test Custom User Color Palette
  await page.evaluate(() => {
    window.FossilUIConfig.save({
      theme: "custom",
      customColors: {
        primary: "#ff007f",
        primaryHover: "#ff3399",
        bg: "#050510",
        bgCard: "#121226",
        border: "#2a2a50",
        text: "#ffffff"
      }
    });
  });
  await new Promise(r => setTimeout(r, 200));

  const customColorApplied = await page.evaluate(() => {
    return document.documentElement.style.getPropertyValue("--color-primary");
  });
  assert(customColorApplied.trim() === "#ff007f", "Custom user color palette applied live via CSS variables", customColorApplied);

  const shotCustomPalette = path.join(ARTIFACT_DIR, "ui_custom_palette_applied.png");
  await page.screenshot({ path: shotCustomPalette });
  console.log(`  📸 Saved custom palette screenshot: ${shotCustomPalette}`);

  // =========================================================================
  // 6. UI Density, Fonts, and Layout Modifiers
  // =========================================================================
  console.log("\n--- 6. Testing UI Density, Font Scaling & Layout Modifiers ---");

  // Test Density: Compact
  await page.evaluate(() => window.FossilUIConfig.save({ density: "compact", fontSize: "13px", radius: "0px" }));
  await new Promise(r => setTimeout(r, 100));
  let densityAttr = await page.evaluate(() => document.documentElement.getAttribute("data-density"));
  let radiusAttr = await page.evaluate(() => document.documentElement.getAttribute("data-radius"));
  assert(densityAttr === "compact" && radiusAttr === "0px", "Compact density and brutalist 0px radius applied");

  // Test Toggle Hero Banner
  let isHeroHidden = await page.$eval("#browser-hero", el => el.classList.contains("hidden"));
  assert(!isHeroHidden, "Hero banner initially visible");
  await page.evaluate(() => window.FossilUIConfig.save({ showHero: false }));
  await new Promise(r => setTimeout(r, 100));
  isHeroHidden = await page.$eval("#browser-hero", el => el.classList.contains("hidden"));
  assert(isHeroHidden, "Hero banner hidden via UI config");
  await page.evaluate(() => window.FossilUIConfig.save({ showHero: true, density: "comfortable", radius: "8px" }));
  await new Promise(r => setTimeout(r, 100));

  // =========================================================================
  // 7. i18n Localization & Custom Language Configs
  // =========================================================================
  console.log("\n--- 7. Testing i18n Localization Engine & Language Packs ---");

  // Default Russian
  await page.evaluate(() => window.FossilUIConfig.save({ lang: "ru" }));
  await new Promise(r => setTimeout(r, 100));
  let exportBtnText = await page.$eval("#btn-export-repo", el => el.innerText.trim());
  let timelineTabText = await page.$eval(".tab-btn[data-tab='timeline']", el => el.innerText.trim());
  assert(exportBtnText.includes("Экспорт") && timelineTabText.includes("Таймлайн"), "Russian localization active", `Btn: ${exportBtnText}`);

  // Switch to English via quick button
  await page.click("#btn-lang-toggle");
  await new Promise(r => setTimeout(r, 150));
  exportBtnText = await page.$eval("#btn-export-repo", el => el.innerText.trim());
  timelineTabText = await page.$eval(".tab-btn[data-tab='timeline']", el => el.innerText.trim());
  assert(exportBtnText.includes("Export") && timelineTabText.includes("Timeline"), "Switched dynamically to English without page reload", `Btn: ${exportBtnText}`);

  const shotEnglish = path.join(ARTIFACT_DIR, "ui_english_mode.png");
  await page.screenshot({ path: shotEnglish });
  console.log(`  📸 Saved English mode screenshot: ${shotEnglish}`);

  // Test Importing Custom Language Pack (e.g., Spanish)
  const spanishPack = {
    "tab.timeline": "📜 Cronología",
    "tab.files": "📁 Archivos",
    "nav.export": "💾 Exportar",
    "nav.import": "📥 Importar"
  };
  await page.evaluate((pack) => {
    window.FossilI18n.importLangPack("custom", pack);
  }, spanishPack);
  await new Promise(r => setTimeout(r, 150));

  const spanishTab = await page.$eval(".tab-btn[data-tab='timeline']", el => el.innerText.trim());
  const spanishExport = await page.$eval("#btn-export-repo", el => el.innerText.trim());
  assert(spanishTab.includes("Cronología") && spanishExport.includes("Exportar"), "Custom user language pack loaded and rendered live");

  // Switch back to Russian
  await page.evaluate(() => window.FossilUIConfig.save({ lang: "ru", theme: "dark" }));
  await new Promise(r => setTimeout(r, 100));

  // =========================================================================
  // 8. Full UI Configuration File Export & Import
  // =========================================================================
  console.log("\n--- 8. Testing Full UI Configuration Export & Import ---");

  const exportedConfigJson = await page.evaluate(() => window.FossilUIConfig.exportConfig());
  const parsedCfg = JSON.parse(exportedConfigJson);
  assert(parsedCfg.theme && parsedCfg.density && parsedCfg.lang, "Exported UI config contains theme, density, and language parameters");

  // Modify config and import it back
  parsedCfg.theme = "dracula";
  parsedCfg.density = "compact";
  parsedCfg.fontSize = "14px";
  const importResult = await page.evaluate((cfgStr) => {
    return window.FossilUIConfig.importConfig(cfgStr);
  }, JSON.stringify(parsedCfg));
  assert(importResult.success === true, "UI configuration imported successfully from JSON string");

  const activeThemeAfterImport = await page.evaluate(() => document.documentElement.getAttribute("data-theme"));
  const activeDensityAfterImport = await page.evaluate(() => document.documentElement.getAttribute("data-density"));
  assert(activeThemeAfterImport === "dracula" && activeDensityAfterImport === "compact", "Imported UI configuration applied instantaneously");

  // =========================================================================
  // 9. Interactive Settings Modal Testing
  // =========================================================================
  console.log("\n--- 9. Testing Interactive Settings Modal ---");
  await page.click("#btn-ui-settings");
  await new Promise(r => setTimeout(r, 200));

  let isSettingsOpen = await page.$eval("#modal-ui-settings", el => !el.classList.contains("hidden"));
  assert(isSettingsOpen, "Settings modal opened via #btn-ui-settings");

  // Switch tabs inside settings modal
  const settingsTabs = ["themes", "layout", "lang", "config"];
  for (const stab of settingsTabs) {
    await page.click(`.settings-tab-btn[data-tab='${stab}']`);
    await new Promise(r => setTimeout(r, 100));
    const isPaneActive = await page.$eval(`#settings-pane-${stab}`, el => el.classList.contains("active"));
    assert(isPaneActive, `Settings modal switched to '${stab}' tab`);
  }

  await page.click("#btn-settings-close");
  await new Promise(r => setTimeout(r, 200));
  isSettingsOpen = await page.$eval("#modal-ui-settings", el => !el.classList.contains("hidden"));
  assert(!isSettingsOpen, "Settings modal closed via #btn-settings-close");

  // =========================================================================
  // 10. Chaotic Monkey Stress Test across Viewports and Actions
  // =========================================================================
  console.log("\n--- 10. Running Chaotic Monkey Test (Fast Resizes, Rapid Tabs, Theme Flips) ---");

  const tabs = ["timeline", "files", "diff", "wiki", "tickets", "mcp", "storage"];
  const viewports = [
    { width: 1400, height: 900 },
    { width: 900, height: 700 },
    { width: 420, height: 800 },
    { width: 1200, height: 800 }
  ];

  for (let i = 0; i < 50; i++) {
    // Random Tab
    const tab = tabs[i % tabs.length];
    await page.click(`.tab-btn[data-tab='${tab}']`).catch(() => {});

    // Periodic viewport changes
    if (i % 10 === 0) {
      const vp = viewports[(i / 10) % viewports.length];
      await page.setViewport(vp);
    }

    // Periodic quick theme or lang flips
    if (i % 7 === 0) {
      await page.click("#theme-toggle-btn").catch(() => {});
    }
    if (i % 9 === 0) {
      await page.click("#btn-lang-toggle").catch(() => {});
    }
    await new Promise(r => setTimeout(r, 40));
  }

  // Restore stable desktop viewport & dark theme
  await page.setViewport({ width: 1440, height: 900 });
  await page.evaluate(() => window.FossilUIConfig.save({ theme: "dark", density: "comfortable", lang: "ru" }));
  await page.click(".tab-btn[data-tab='timeline']");
  await new Promise(r => setTimeout(r, 400));

  const shotFinal = path.join(ARTIFACT_DIR, "ui_monkey_test_final.png");
  await page.screenshot({ path: shotFinal, fullPage: true });
  console.log(`  📸 Saved final monkey test screenshot: ${shotFinal}`);

  // Zero unhandled errors
  assert(pageErrors.length === 0, "Zero unhandled runtime errors during responsive & monkey testing", `Errors: ${pageErrors.join("; ")}`);

  console.log("\n" + "=".repeat(65));
  console.log(`TEST RESULTS: ${passedCount} PASSED, ${failedCount} FAILED`);
  console.log("=".repeat(65));

  await browser.close();
  process.exit(failedCount > 0 ? 1 : 0);
})();
