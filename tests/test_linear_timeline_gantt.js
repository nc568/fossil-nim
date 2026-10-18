const puppeteer = require("/tmp/p-test/node_modules/puppeteer-core");
const path = require("path");
const fs = require("fs");

const ROOT_DIR = "/home/nc568/antigravity/hopeful-volta/fossil-nim";
const HTML_FILE = "file://" + path.join(ROOT_DIR, "fossil-browser.html");
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

async function sleep(ms) {
  return new Promise(r => setTimeout(r, ms));
}

async function run() {
  console.log("=" * 65);
  console.log("📈 TESTING LINEAR TIMELINE CALENDAR & GANTT ROADMAP");
  console.log("=" * 65);

  const browser = await puppeteer.launch({
    executablePath: CHROME_PATH,
    headless: "new",
    args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-gpu"]
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 1440, height: 900 });

  page.on("console", msg => {
    if (msg.type() === "error") {
      console.log(`  [Browser Console Error] ${msg.text()}`);
    }
  });

  try {
    console.log("\n--- 1. Loading In-Browser Fossil UI & Navigating to Timeline Calendar ---");
    await page.goto(HTML_FILE, { waitUntil: "networkidle0" });
    await sleep(600);

    // Switch to calendar tab
    await page.click('button[data-tab="calendar"]');
    await sleep(600);

    const isCalendarVisible = await page.$eval('#tab-calendar', el => el.classList.contains('active'));
    assert(isCalendarVisible, "Timeline Calendar tab is active");

    console.log("\n--- 2. Verifying Linear Gantt Architecture ---");
    const dateCellsCount = await page.$$eval('.timeline-date-cell', els => els.length);
    assert(dateCellsCount >= 28, `Dates header rendered with ${dateCellsCount} day columns (>=28 days)`);

    const taskItemsCount = await page.$$eval('.timeline-task-item', els => els.length);
    assert(taskItemsCount > 0, `Left task list rendered ${taskItemsCount} scheduled tasks`);

    const ganttBarsCount = await page.$$eval('.timeline-bar', els => els.length);
    assert(ganttBarsCount === taskItemsCount, `Matching ${ganttBarsCount} horizontal Gantt bars rendered on timeline`);

    // Verify task bars stretch across multiple days
    const barWidths = await page.$$eval('.timeline-bar', els => els.map(el => {
      return {
        title: el.getAttribute('data-title'),
        span: Number(el.getAttribute('data-span')),
        widthPx: parseFloat(el.style.width),
        leftPx: parseFloat(el.style.left)
      };
    }));

    console.log("  [INFO] Inspecting task bar metrics:");
    for (const b of barWidths) {
      console.log(`    - ${b.title}: span=${b.span} days, width=${b.widthPx.toFixed(1)}px, left=${b.leftPx.toFixed(1)}px`);
    }

    const multiDayBars = barWidths.filter(b => b.span > 1 && b.widthPx > 50);
    assert(multiDayBars.length >= 3, `Visual task bars stretch across multiple days (${multiDayBars.length} multi-day bars verified)`);

    // Verify deadline pins
    const pinsCount = await page.$$eval('.timeline-deadline-pin', els => els.length);
    assert(pinsCount === ganttBarsCount, `All ${pinsCount} task bars have deadline pin markers at their end`);

    // Verify Today column highlighting
    const todayCellExists = await page.$eval('.timeline-date-cell.today-cell', el => !!el).catch(() => false);
    assert(todayCellExists, "Current day ('Сегодня') is prominently highlighted in date headers");

    const todayLineExists = await page.$eval('.timeline-grid-line.today-line', el => !!el).catch(() => false);
    assert(todayLineExists, "Today vertical guide line stretches across all task rows");

    // Take Desktop Screenshot
    const shot1 = path.join(ARTIFACT_DIR, "linear_timeline_desktop_month.png");
    await page.screenshot({ path: shot1, fullPage: false });
    console.log(`  📸 [SCREENSHOT] Saved month view: ${shot1} (${fs.statSync(shot1).size} bytes)`);

    console.log("\n--- 3. Testing Interactive Scale Selectors ---");
    // Switch to 2-weeks scale
    await page.click('#scale-2weeks');
    await sleep(400);

    const dateCells2w = await page.$$eval('.timeline-date-cell', els => els.length);
    assert(dateCells2w === 14, `2-Weeks scale rendered exactly 14 day columns (got ${dateCells2w})`);

    const shot2 = path.join(ARTIFACT_DIR, "linear_timeline_2weeks_scale.png");
    await page.screenshot({ path: shot2, fullPage: false });
    console.log(`  📸 [SCREENSHOT] Saved 2-weeks scale view: ${shot2} (${fs.statSync(shot2).size} bytes)`);

    // Switch to all tasks scale
    await page.click('#scale-all');
    await sleep(400);
    const dateCellsAll = await page.$$eval('.timeline-date-cell', els => els.length);
    assert(dateCellsAll >= 14, `All-tasks scale rendered full project span (${dateCellsAll} days)`);

    // Switch back to month
    await page.click('#scale-month');
    await sleep(400);

    console.log("\n--- 4. Testing Filter Controls & Backlog Toggle ---");
    // Toggle backlog collapse
    await page.click('#btn-toggle-backlog');
    await sleep(300);
    const isBacklogCollapsed = await page.$eval('#calendar-layout', el => el.classList.contains('backlog-collapsed'));
    assert(isBacklogCollapsed, "Backlog side panel successfully collapsed for widescreen Gantt view");

    await page.click('#btn-toggle-backlog');
    await sleep(300);
    const isBacklogRestored = await page.$eval('#calendar-layout', el => !el.classList.contains('backlog-collapsed'));
    assert(isBacklogRestored, "Backlog side panel restored");

    // Filter by priority: Critical
    await page.select('#cal-filter-priority', 'Critical');
    await sleep(300);
    const critTasksCount = await page.$$eval('.timeline-task-item', els => els.length);
    assert(critTasksCount >= 1, `Priority filter 'Critical' works: showing ${critTasksCount} critical task(s)`);

    // Reset priority filter
    await page.select('#cal-filter-priority', 'all');
    await sleep(300);

    console.log("\n--- 5. Testing Hover Tooltip on Task Bar ---");
    const activeBar = await page.$('.timeline-bar[data-id="tkt-101"]') || await page.$('.timeline-bar');
    if (activeBar) {
      await activeBar.evaluate(el => el.scrollIntoView({ block: 'center', inline: 'center' }));
      await sleep(300);
      const box = await activeBar.boundingBox();
      await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
      await sleep(400);

      const tooltipDisplay = await page.$eval('#timeline-tooltip', el => window.getComputedStyle(el).display);
      const tooltipText = await page.$eval('#timeline-tooltip', el => el.innerText);
      assert(tooltipDisplay === 'block', `Hovering over task bar triggers floating tooltip (display: ${tooltipDisplay})`);
      assert(tooltipText.includes("Сроки:"), `Tooltip displays task lifecycle metrics ("${tooltipText.replace(/\n/g, ' ')}")`);

      const shotTooltip = path.join(ARTIFACT_DIR, "linear_timeline_hover_tooltip.png");
      await page.screenshot({ path: shotTooltip, fullPage: false });
      console.log(`  📸 [SCREENSHOT] Saved hover tooltip view: ${shotTooltip} (${fs.statSync(shotTooltip).size} bytes)`);
    }

    console.log("\n--- 6. Testing Multi-Database Backends (SQLite WASM & CDB) ---");
    // Switch to SQLite WASM
    const switchedToSqlite = await page.evaluate(async () => {
      if (window.FossilStorageManager) {
        await window.FossilStorageManager.switchBackend("sqlite_wasm");
        if (window.fossilUi) await window.fossilUi.refreshCalendar();
        return window.FossilStorageManager.backendType === "sqlite_wasm";
      }
      return false;
    });
    assert(switchedToSqlite, "Switched backend to SQLite WASM");
    await sleep(600);

    const wasmGanttBars = await page.$$eval('.timeline-bar', els => els.length);
    assert(wasmGanttBars > 0, `SQLite WASM backend: linear timeline rendered ${wasmGanttBars} stretching task bars`);

    const shotWasm = path.join(ARTIFACT_DIR, "linear_timeline_sqlite_wasm.png");
    await page.screenshot({ path: shotWasm, fullPage: false });
    console.log(`  📸 [SCREENSHOT] Saved SQLite WASM linear timeline: ${shotWasm} (${fs.statSync(shotWasm).size} bytes)`);

    // Switch to Pure-Nim CDB
    const switchedToCdb = await page.evaluate(async () => {
      if (window.FossilStorageManager) {
        await window.FossilStorageManager.switchBackend("cdb");
        if (window.fossilUi) await window.fossilUi.refreshCalendar();
        return window.FossilStorageManager.backendType === "cdb";
      }
      return false;
    });
    assert(switchedToCdb, "Switched backend to Pure-Nim CDB");
    await sleep(600);

    const cdbGanttBars = await page.$$eval('.timeline-bar', els => els.length);
    assert(cdbGanttBars > 0, `Pure-Nim CDB backend: linear timeline rendered ${cdbGanttBars} stretching task bars`);

    const shotCdb = path.join(ARTIFACT_DIR, "linear_timeline_pure_nim_cdb.png");
    await page.screenshot({ path: shotCdb, fullPage: false });
    console.log(`  📸 [SCREENSHOT] Saved Pure-Nim CDB linear timeline: ${shotCdb} (${fs.statSync(shotCdb).size} bytes)`);

  } catch (err) {
    console.error("Test execution error:", err);
    failedCount++;
  } finally {
    await browser.close();
  }

  console.log("\n" + "=" * 65);
  console.log(`📊 SUMMARY: ${passedCount} PASSED, ${failedCount} FAILED`);
  console.log("=" * 65);

  if (failedCount > 0) {
    process.exit(1);
  }
}

run();
