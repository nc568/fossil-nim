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
  console.log("=================================================================");
  console.log("🐒 MONKEY TEST: LINEAR TIMELINE, STATUSES, CLICK-TO-JUMP & MULTI-DB");
  console.log("=================================================================");

  const browser = await puppeteer.launch({
    executablePath: CHROME_PATH,
    headless: "new",
    args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-gpu"]
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 1440, height: 900 });

  page.on("console", msg => {
    if (msg.type() === "error") {
      console.log(`  [Browser Error] ${msg.text()}`);
    }
  });

  try {
    console.log("\n--- PHASE 1: Loading In-Browser Fossil UI & Navigating to Timeline Calendar ---");
    await page.goto(HTML_FILE, { waitUntil: "networkidle0" });
    await sleep(600);

    // Switch to calendar tab
    await page.click('button[data-tab="calendar"]');
    await sleep(600);

    const isCalendarVisible = await page.$eval('#tab-calendar', el => el.classList.contains('active'));
    assert(isCalendarVisible, "Timeline Calendar tab is active");

    console.log("\n--- PHASE 2: Verifying Status Badges Display ---");
    // Check status tags inside timeline bars
    const barStatusTags = await page.$$eval('.timeline-bar-status-tag', els => els.map(e => e.innerText.trim()));
    assert(barStatusTags.length > 0, `Timeline bars display status tags (${barStatusTags.length} tags found: ${barStatusTags.slice(0, 3).join(', ')})`);

    // Check status badges in left tasks list
    const taskStatusBadges = await page.$$eval('.timeline-task-item .badge[class*="badge-status-"]', els => els.map(e => e.innerText.trim()));
    assert(taskStatusBadges.length > 0, `Left task items display status badges (${taskStatusBadges.length} badges found)`);

    // Check side panel scheduled tab
    const sideSchedTabBtn = await page.$('#btn-side-tab-scheduled');
    assert(!!sideSchedTabBtn, "Side panel has '📅 С дедлайном' tab button");
    await page.click('#btn-side-tab-scheduled');
    await sleep(300);

    const isSchedContentVisible = await page.$eval('#side-tab-scheduled-content', el => el.style.display !== 'none');
    assert(isSchedContentVisible, "Side panel switched to scheduled tickets view");

    const sideStatusBadges = await page.$$eval('#calendar-scheduled-list .badge[class*="badge-status-"]', els => els.map(e => e.innerText.trim()));
    assert(sideStatusBadges.length > 0, `Side panel scheduled tickets display status badges (${sideStatusBadges.length} found: ${sideStatusBadges.slice(0, 3).join(', ')})`);

    console.log("\n--- PHASE 3: Testing Date Overlap Filtering & Empty State (Fixing User Screenshot Issue) ---");
    // In user screenshot, navigating to July 2027 caused 2026 tasks to be drawn squished on day 1
    // Navigate 9 months ahead to July 2027
    for (let i = 0; i < 9; i++) {
      await page.click('#btn-calendar-next');
      await sleep(100);
    }
    await sleep(400);

    const monthLabel2027 = await page.$eval('#calendar-month-label', el => el.innerText.trim());
    console.log(`  [INFO] Navigated to month: ${monthLabel2027}`);

    // In July 2027, there should be NO squished 2026 tasks in the visible timeline!
    const barsInJuly2027 = await page.$$eval('.timeline-bar', els => els.length);
    assert(barsInJuly2027 === 0, `Out-of-range 2026 tasks are NOT drawn in ${monthLabel2027} (got 0 squished bars, was bugged previously)`);

    // Check empty state
    const hasEmptyState = await page.$eval('#timeline-tasks-list', el => el.innerText.includes('В этом периоде нет задач'));
    assert(hasEmptyState, `Empty state correctly displayed in ${monthLabel2027}: 'В этом периоде нет задач'`);

    // Check smart jump button
    const jumpBtn = await page.$('.btn-jump-to-month');
    assert(!!jumpBtn, "Smart jump button is present in empty state");
    const jumpBtnText = await page.$eval('.btn-jump-to-month', el => el.innerText.trim());
    console.log(`  [INFO] Smart Jump Button text: "${jumpBtnText}"`);

    // Click smart jump button -> must jump directly back to the active month with tasks!
    await page.click('.btn-jump-to-month');
    await sleep(500);

    const restoredMonthLabel = await page.$eval('#calendar-month-label', el => el.innerText.trim());
    const restoredBars = await page.$$eval('.timeline-bar', els => els.length);
    assert(restoredBars > 0, `Smart jump returned to active month (${restoredMonthLabel}) with ${restoredBars} tasks rendered`);

    console.log("\n--- PHASE 4: Testing Click-to-Jump to Task Start Date ---");
    // Switch to July 2027 again
    await page.click('#btn-calendar-next');
    await page.click('#btn-calendar-next');
    await sleep(300);

    // Now in side panel 'С дедлайном', click on a ticket
    const firstSchedTicket = await page.$('#calendar-scheduled-list .ticket-card');
    assert(!!firstSchedTicket, "Ticket found in side panel scheduled list");
    const targetTicketId = await firstSchedTicket.evaluate(el => el.getAttribute('data-id'));
    console.log(`  [INFO] Clicking on ticket #${targetTicketId} in scheduled list to test auto-jump...`);

    await firstSchedTicket.click();
    await sleep(600);

    // Verify calendar automatically navigated to the start month of that ticket
    const jumpedBars = await page.$$eval('.timeline-bar', els => els.length);
    assert(jumpedBars > 0, `Clicking scheduled ticket auto-navigated calendar to task start month (${jumpedBars} tasks visible)`);

    // Verify pulse highlight was added to the bar
    const isPulsing = await page.$eval(`.timeline-bar[data-id="${targetTicketId}"]`, el => el.classList.contains('timeline-highlight-pulse')).catch(() => false);
    assert(isPulsing, `Target task bar #${targetTicketId} received vibrant .timeline-highlight-pulse animation`);

    // Test clicking left column task item to jump / center
    const leftItem = await page.$(`.timeline-task-item[data-id="${targetTicketId}"]`);
    assert(!!leftItem, "Left column task item exists");
    await leftItem.click();
    await sleep(300);

    // Verify toast notification showed navigation info
    const toastText = await page.$eval('#toast-container', el => el.innerText).catch(() => '');
    assert(toastText.includes("Переход к дате начала задачи") || toastText.includes(targetTicketId), `Toast confirmed jump to start date: "${toastText.trim()}"`);

    // Test edit button on left task item
    const editBtn = await page.$(`.timeline-task-item[data-id="${targetTicketId}"] .btn-edit-ticket`);
    assert(!!editBtn, "Left column item has direct ✏️ edit button");
    await editBtn.click();
    await sleep(400);

    const isEditModalOpen = await page.$eval('#modal-ticket-edit', el => !el.classList.contains('hidden'));
    assert(isEditModalOpen, "Clicking ✏️ edit button opened ticket edit modal directly");
    await page.click('#btn-modal-ticket-edit-close');
    await sleep(300);

    console.log("\n--- PHASE 5: Monkey Testing Across All 3 Databases ---");
    const backends = ["indexeddb", "sqlite_wasm", "cdb"];

    for (const bType of backends) {
      console.log(`\n  >>> Testing Database Backend: [${bType.toUpperCase()}] <<<`);
      const switched = await page.evaluate(async (bt) => {
        if (window.FossilStorageManager) {
          await window.FossilStorageManager.switchBackend(bt);
          if (window.fossilUi) await window.fossilUi.refreshCalendar();
          return window.FossilStorageManager.backendType === bt;
        }
        return false;
      }, bType);
      assert(switched, `Successfully switched active storage to ${bType}`);
      await sleep(600);

      // Verify tasks and statuses rendered for this backend
      const backendBars = await page.$$eval('.timeline-bar', els => els.length);
      assert(backendBars > 0, `${bType}: linear timeline rendered ${backendBars} task bars`);

      const backendStatuses = await page.$$eval('.timeline-bar-status-tag', els => els.map(e => e.innerText.trim()));
      assert(backendStatuses.length > 0, `${bType}: status tags rendered: ${backendStatuses.slice(0, 2).join(', ')}`);

      // Test creating a new ticket with a deadline in this backend
      const newTitle = `MonkeyTask_${bType}_${Date.now().toString(36)}`;
      const res = await page.evaluate(async (title) => {
        const d = new Date();
        d.setDate(d.getDate() + 5);
        const deadlineStr = d.toISOString().split('T')[0];
        const r = await window.fossilMcp.callTool('ticket_create', {
          title,
          priority: 'High',
          status: 'Open',
          deadline: deadlineStr,
          desc: 'Automated monkey test task'
        });
        if (window.fossilUi) await window.fossilUi.refreshCalendar();
        return r;
      }, newTitle);

      assert(res.success && res.ticket, `${bType}: ticket_create succeeded (ID: ${res.ticket?.id})`);

      // Verify newly created ticket appears on timeline
      const newBar = await page.$(`.timeline-bar[data-id="${res.ticket.id}"]`);
      assert(!!newBar, `${bType}: newly created ticket #${res.ticket.id} appears on the timeline`);

      // Test status transition to Closed
      await page.evaluate(async (tId) => {
        await window.fossilMcp.callTool('ticket_close', { id: tId, resolution: 'Fixed by Monkey' });
        if (window.fossilUi) await window.fossilUi.refreshCalendar();
      }, res.ticket.id);
      await sleep(400);

      const updatedStatus = await page.$eval(`.timeline-bar[data-id="${res.ticket.id}"]`, el => el.getAttribute('data-status'));
      assert(updatedStatus === 'Closed', `${bType}: ticket status updated to Closed (got: ${updatedStatus})`);

      const hasClosedClass = await page.$eval(`.timeline-bar[data-id="${res.ticket.id}"]`, el => el.classList.contains('status-closed'));
      assert(hasClosedClass, `${bType}: bar visually styled as .status-closed (emerald green)`);

      // Test auto-jump to start date
      await page.evaluate(async (tId) => {
        if (window.fossilUi) await window.fossilUi.navigateToTicketStart(tId);
      }, res.ticket.id);
      await sleep(400);

      const isNewBarPulsing = await page.$eval(`.timeline-bar[data-id="${res.ticket.id}"]`, el => el.classList.contains('timeline-highlight-pulse'));
      assert(isNewBarPulsing, `${bType}: navigateToTicketStart triggered .timeline-highlight-pulse on #${res.ticket.id}`);

      // Capture screenshot for this backend
      const shotPath = path.join(ARTIFACT_DIR, `monkey_timeline_${bType}.png`);
      await page.screenshot({ path: shotPath, fullPage: false });
      console.log(`  📸 [SCREENSHOT] Saved ${bType} state: ${shotPath} (${fs.statSync(shotPath).size} bytes)`);
    }

  } catch (err) {
    console.error("Monkey test execution error:", err);
    failedCount++;
  } finally {
    await browser.close();
  }

  console.log("\n=================================================================");
  console.log(`📊 FINAL RESULT: ${passedCount} PASSED, ${failedCount} FAILED`);
  console.log("=================================================================");

  if (failedCount > 0) {
    process.exit(1);
  }
}

run();
