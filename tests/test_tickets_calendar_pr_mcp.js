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
  console.log("🎯 FOSSIL-NIM: TICKETS, TIMELINE-CALENDAR, PRs & MCP CONSOLE TEST");
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
  // 1. TICKETS TAB OVERHAUL: Filter bar, priority styles, edit, close, history
  // =========================================================================
  console.log("\n--- 1. Testing Tickets Tab Overhaul ---");
  await page.click("#app-sidebar .sidebar-link[data-tab='tickets']");
  await new Promise(r => setTimeout(r, 400));

  const ticketsActive = await page.$eval("#tab-tickets", el => el.classList.contains("active"));
  assert(ticketsActive, "Tickets tab is active upon sidebar click");

  // Filter Bar tests
  const countAll = await page.$eval("#tkt-cnt-all", el => parseInt(el.textContent) || 0);
  const countOpen = await page.$eval("#tkt-cnt-open", el => parseInt(el.textContent) || 0);
  const countClosed = await page.$eval("#tkt-cnt-closed", el => parseInt(el.textContent) || 0);
  assert(countAll >= 3, `Filter counter 'All' has seeded tickets: ${countAll}`);
  assert(countOpen >= 1, `Filter counter 'Open' has tickets: ${countOpen}`);
  assert(countClosed >= 1, `Filter counter 'Closed' has tickets: ${countClosed}`);
  assert(countAll === countOpen + countClosed, "All tickets count equals open + closed");

  // Click Closed filter
  await page.click(".ticket-filter-btn[data-filter='closed']");
  await new Promise(r => setTimeout(r, 200));
  const visibleCardsClosed = await page.$$eval("#tickets-list .ticket-card", els => els.length);
  assert(visibleCardsClosed === countClosed, `Filter 'closed' displays only closed cards (${visibleCardsClosed})`);

  // Click Open filter
  await page.click(".ticket-filter-btn[data-filter='open']");
  await new Promise(r => setTimeout(r, 200));
  const visibleCardsOpen = await page.$$eval("#tickets-list .ticket-card", els => els.length);
  assert(visibleCardsOpen === countOpen, `Filter 'open' displays only open cards (${visibleCardsOpen})`);

  // Revert to All
  await page.click(".ticket-filter-btn[data-filter='all']");
  await new Promise(r => setTimeout(r, 200));

  // Check Priority Badges & Borders
  const priorityClasses = await page.$$eval("#tickets-list .ticket-card", els => els.map(el => {
    return Array.from(el.classList).find(c => c.startsWith("priority-"));
  }));
  assert(priorityClasses.some(c => c === "priority-critical"), "Critical priority styling exists on ticket cards");
  assert(priorityClasses.some(c => c === "priority-high"), "High priority styling exists on ticket cards");

  // Take screenshot of tickets view
  await page.screenshot({ path: path.join(ARTIFACT_DIR, "tickets_view_overhaul.png") });
  console.log("  📸 Saved tickets overhaul screenshot");

  // =========================================================================
  // 2. TICKET ACTIONS: Edit, Close, Reopen, History Audit Trail
  // =========================================================================
  console.log("\n--- 2. Testing Ticket Actions: Edit, Close, Reopen, History ---");

  // Find an open ticket and click "✓ Завершить"
  const firstOpenTicketId = await page.evaluate(() => {
    const card = document.querySelector("#tickets-list .ticket-card:not([style*='display: none'])");
    return card ? card.dataset.id : null;
  });
  assert(!!firstOpenTicketId, `Found target ticket: ${firstOpenTicketId}`);

  // Test Ticket History Modal BEFORE changes
  const historyBtn = await page.$(`#tickets-list .ticket-card[data-id='${firstOpenTicketId}'] .btn-ticket-action[data-action='history']`);
  assert(!!historyBtn, "Ticket card has '📜 История' button");
  await historyBtn.click();
  await new Promise(r => setTimeout(r, 300));

  const historyModalOpen = await page.$eval("#modal-ticket-history", el => !el.classList.contains("hidden"));
  assert(historyModalOpen, "History modal opens on button click");
  const initialHistoryItems = await page.$$eval("#ticket-history-list .history-item", els => els.length);
  assert(initialHistoryItems >= 1, `History timeline renders initial creation/audit event (${initialHistoryItems} items)`);

  // Close history modal
  await page.click("#btn-modal-ticket-history-close");
  await new Promise(r => setTimeout(r, 200));

  // Click "✓ Завершить" (Close ticket)
  const closeBtn = await page.$(`#tickets-list .ticket-card[data-id='${firstOpenTicketId}'] .btn-ticket-action[data-action='close']`);
  assert(!!closeBtn, "Open ticket has '✓ Завершить' action button");
  await closeBtn.click();
  await new Promise(r => setTimeout(r, 300));

  // Check that ticket status is now closed and button changed to "🔄 Открыть"
  const reopenBtn = await page.$(`#tickets-list .ticket-card[data-id='${firstOpenTicketId}'] .btn-ticket-action[data-action='reopen']`);
  assert(!!reopenBtn, "Closed ticket displays '🔄 Открыть' action button");

  // Reopen ticket
  await reopenBtn.click();
  await new Promise(r => setTimeout(r, 300));
  const closeBtnAgain = await page.$(`#tickets-list .ticket-card[data-id='${firstOpenTicketId}'] .btn-ticket-action[data-action='close']`);
  assert(!!closeBtnAgain, "Reopened ticket displays '✓ Завершить' button again");

  // Re-open history modal and check that close and reopen events are logged in audit trail
  const histBtnRecheck = await page.$(`#tickets-list .ticket-card[data-id='${firstOpenTicketId}'] .btn-ticket-action[data-action='history']`);
  await histBtnRecheck.click();
  await new Promise(r => setTimeout(r, 300));
  const auditEntriesText = await page.$$eval("#ticket-history-list .history-item", els => els.map(e => e.innerText));
  assert(auditEntriesText.some(t => t.includes("Завершён") || t.includes("closed")), "Audit history contains status change to closed");
  assert(auditEntriesText.some(t => t.includes("Переоткрыт") || t.includes("open")), "Audit history contains reopen event");

  await page.screenshot({ path: path.join(ARTIFACT_DIR, "ticket_history_modal.png") });
  console.log("  📸 Saved ticket history modal screenshot");
  await page.click("#btn-modal-ticket-history-close");
  await new Promise(r => setTimeout(r, 200));

  // =========================================================================
  // 3. TIMELINE CALENDAR & ROADMAP: Month Grid, Deadlines, Backlog Side Panel
  // =========================================================================
  console.log("\n--- 3. Testing Timeline Calendar & Roadmap Tab ---");
  await page.click("#app-sidebar .sidebar-link[data-tab='calendar']");
  await new Promise(r => setTimeout(r, 400));

  const calendarActive = await page.$eval("#tab-calendar", el => el.classList.contains("active"));
  assert(calendarActive, "Calendar tab is active upon sidebar click");

  // Check Calendar Side Panel
  const backlogCount = await page.$eval("#cal-backlog-count", el => parseInt(el.textContent) || 0);
  const upcomingCount = await page.$eval("#cal-upcoming-count", el => parseInt(el.textContent) || 0);
  assert(backlogCount >= 1, `Backlog side panel lists tickets without deadlines: ${backlogCount}`);
  assert(upcomingCount >= 1, `Upcoming panel lists tickets with deadlines: ${upcomingCount}`);

  // Check Calendar Grid
  const dayCells = await page.$$eval("#calendar-days-grid .calendar-cell", els => els.length);
  assert(dayCells >= 28 && dayCells <= 42, `Calendar grid rendered month day cells: ${dayCells}`);

  const todayCell = await page.$("#calendar-days-grid .calendar-day-today");
  assert(!!todayCell, "Calendar highlights current day with 'Сегодня' marker");

  // Check ticket pills inside calendar cells
  const eventPills = await page.$$eval("#calendar-days-grid .calendar-event-pill", els => els.length);
  assert(eventPills >= 1, `Calendar grid displays scheduled ticket event pills: ${eventPills}`);

  // Check Month Navigation
  const initialMonthText = await page.$eval("#calendar-month-label", el => el.textContent.trim());
  await page.click("#btn-calendar-next");
  await new Promise(r => setTimeout(r, 200));
  const nextMonthText = await page.$eval("#calendar-month-label", el => el.textContent.trim());
  assert(initialMonthText !== nextMonthText, `Month navigation Next worked (${initialMonthText} -> ${nextMonthText})`);

  await page.click("#btn-calendar-today");
  await new Promise(r => setTimeout(r, 200));
  const todayMonthText = await page.$eval("#calendar-month-label", el => el.textContent.trim());
  assert(todayMonthText === initialMonthText, "Clicking 'Сегодня' returns calendar to current month");

  await page.screenshot({ path: path.join(ARTIFACT_DIR, "calendar_roadmap_view.png") });
  console.log("  📸 Saved calendar roadmap view screenshot");

  // =========================================================================
  // 4. PULL REQUESTS: Creation, Link to Ticket, Merge Auto-Audit History
  // =========================================================================
  console.log("\n--- 4. Testing Pull Requests Linked to Tickets ---");

  // Go back to tickets tab
  await page.click("#app-sidebar .sidebar-link[data-tab='tickets']");
  await new Promise(r => setTimeout(r, 300));

  // Click "🔀 Pull Request" button on target ticket
  const prBtn = await page.$(`#tickets-list .ticket-card[data-id='${firstOpenTicketId}'] .btn-ticket-action[data-action='pr']`);
  assert(!!prBtn, "Ticket card has '🔀 Pull Request' quick link button");
  await prBtn.click();
  await new Promise(r => setTimeout(r, 300));

  const prModalOpen = await page.$eval("#modal-pr", el => !el.classList.contains("hidden"));
  assert(prModalOpen, "PR modal opened");

  const prefilledTicketId = await page.$eval("#pr-target-ticket-select", el => el.value);
  assert(prefilledTicketId === firstOpenTicketId, `PR modal pre-filled linked ticket ID: ${prefilledTicketId}`);

  // Create PR
  await page.type("#pr-title", "Feature: In-Browser Shared Worker Sync");
  await page.type("#pr-source-branch", "feat/shared-worker");
  await page.type("#pr-description", "Implements lock-free cross-tab state synchronization via SharedWorker");
  await page.click("#form-pr button[type='submit']");
  await new Promise(r => setTimeout(r, 400));

  // Check that the ticket card now displays linked PR pill
  const linkedPrsInCard = await page.$$eval(
    `#tickets-list .ticket-card[data-id='${firstOpenTicketId}'] .pr-badge`,
    els => els.map(e => e.innerText)
  );
  assert(linkedPrsInCard.length >= 1, `Ticket card displays linked PR badge: ${linkedPrsInCard.join(", ")}`);

  // Check ticket history: it should contain pr_linked event
  const historyBtnWithPr = await page.$(`#tickets-list .ticket-card[data-id='${firstOpenTicketId}'] .btn-ticket-action[data-action='history']`);
  await historyBtnWithPr.click();
  await new Promise(r => setTimeout(r, 300));
  const historyWithPr = await page.$$eval("#ticket-history-list .history-item", els => els.map(e => e.innerText));
  assert(historyWithPr.some(t => t.includes("Pull Request") || t.includes("pr_linked")), "Audit history records PR link event");
  await page.click("#btn-modal-ticket-history-close");
  await new Promise(r => setTimeout(r, 200));

  // =========================================================================
  // 5. MCP AGENT CONSOLE: Rich Information, Parameter Schemas & Live Execution
  // =========================================================================
  console.log("\n--- 5. Testing MCP Agent Console: Rich Specs & Execution ---");
  await page.click("#app-sidebar .sidebar-link[data-tab='mcp']");
  await new Promise(r => setTimeout(r, 400));

  const mcpActive = await page.$eval("#tab-mcp", el => el.classList.contains("active"));
  assert(mcpActive, "MCP tab is active upon sidebar click");

  // Category filter pills
  const categoriesCount = await page.$$eval("#mcp-category-filter-bar .btn", els => els.length);
  assert(categoriesCount >= 8, `Category filter pills rendered (${categoriesCount} categories)`);

  // Filter by 'Roadmap & Calendar'
  const calCatBtn = await page.$("#mcp-category-filter-bar .btn[data-cat='calendar']");
  assert(!!calCatBtn, "Roadmap & Calendar category filter exists");
  await calCatBtn.click();
  await new Promise(r => setTimeout(r, 200));

  const calFilteredCount = await page.$$eval("#mcp-tools-list .mcp-tool-item", els => els.length);
  assert(calFilteredCount >= 3, `Roadmap & Calendar filtered tools: ${calFilteredCount}`);

  // Select 'ticket_calendar_list'
  const calToolItem = await page.$("#mcp-tools-list .mcp-tool-item[data-tool='ticket_calendar_list']");
  assert(!!calToolItem, "Tool 'ticket_calendar_list' found in list");
  await calToolItem.click();
  await new Promise(r => setTimeout(r, 300));

  // Check active tool card rich specification
  const activeToolName = await page.$eval("#mcp-active-tool-name", el => el.textContent.trim());
  const activeToolCat = await page.$eval("#mcp-active-tool-cat-badge", el => el.textContent.trim());
  const activeToolDesc = await page.$eval("#mcp-active-tool-desc", el => el.textContent.trim());
  assert(activeToolName === "ticket_calendar_list", `Active tool name is ticket_calendar_list: ${activeToolName}`);
  assert(activeToolCat.includes("Roadmap") || activeToolCat.includes("Calendar"), `Category badge shows Roadmap/Calendar: ${activeToolCat}`);
  assert(activeToolDesc.length > 20, `Rich description displayed: ${activeToolDesc.substring(0, 40)}...`);

  // Parameters Schema Table
  const paramRows = await page.$$eval("#mcp-params-table-container table tbody tr", els => els.length);
  assert(paramRows >= 1, `Parameters schema table rendered rows: ${paramRows}`);

  // Test "Вставить пример"
  await page.click("#btn-mcp-load-sample");
  await new Promise(r => setTimeout(r, 200));
  const sampleParams = await page.$eval("#mcp-params-input", el => el.value);
  assert(sampleParams.length > 2 && sampleParams.includes("{"), `Pre-filled sample input loaded: ${sampleParams.trim()}`);

  // Invoke tool in active DB
  await page.click("#btn-mcp-invoke");
  await new Promise(r => setTimeout(r, 400));

  const mcpStatus = await page.$eval("#mcp-status-pill", el => el.textContent.trim());
  const mcpLatency = await page.$eval("#mcp-latency-pill", el => el.textContent.trim());
  const mcpOutput = await page.$eval("#mcp-output-json", el => el.textContent.trim());

  assert(mcpStatus === "200 OK", `Tool execution returned 200 OK: ${mcpStatus}`);
  assert(mcpLatency.includes("ms"), `Execution latency counter displayed: ${mcpLatency}`);
  const parsedRes = JSON.parse(mcpOutput);
  assert(Array.isArray(parsedRes.tickets) && parsedRes.tickets.length >= 1, `ticket_calendar_list returned calendar items: ${parsedRes.tickets.length}`);

  // Test PR MCP Tool: pr_list
  await page.click("#mcp-category-filter-bar .btn[data-cat='prs']");
  await new Promise(r => setTimeout(r, 200));
  await page.click("#mcp-tools-list .mcp-tool-item[data-tool='pr_list']");
  await new Promise(r => setTimeout(r, 200));
  await page.click("#btn-mcp-invoke");
  await new Promise(r => setTimeout(r, 400));

  const prListOutput = await page.$eval("#mcp-output-json", el => el.textContent.trim());
  const parsedPrs = JSON.parse(prListOutput);
  assert(Array.isArray(parsedPrs.pullRequests) && parsedPrs.pullRequests.length >= 2, `pr_list returned pull requests: ${parsedPrs.pullRequests.length}`);

  // Test Merging the PR via MCP Tool: pr_merge
  const prToMerge = parsedPrs.pullRequests.find(p => p.ticketId === firstOpenTicketId);
  assert(!!prToMerge, `Found PR linked to ${firstOpenTicketId}: ${prToMerge.id}`);

  await page.click("#mcp-tools-list .mcp-tool-item[data-tool='pr_merge']");
  await new Promise(r => setTimeout(r, 200));
  await page.$eval("#mcp-params-input", (el, prId) => {
    el.value = JSON.stringify({ prId: prId, author: "tester" }, null, 2);
  }, prToMerge.id);
  await page.click("#btn-mcp-invoke");
  await new Promise(r => setTimeout(r, 400));

  const mergeOutput = await page.$eval("#mcp-output-json", el => el.textContent.trim());
  const parsedMerge = JSON.parse(mergeOutput);
  assert(parsedMerge.status === "merged", `PR merged successfully: status=${parsedMerge.status}`);

  // Go verify that Ticket History now reflects the PR Merge
  await page.click("#app-sidebar .sidebar-link[data-tab='tickets']");
  await new Promise(r => setTimeout(r, 300));
  const histBtnAfterMerge = await page.$(`#tickets-list .ticket-card[data-id='${firstOpenTicketId}'] .btn-ticket-action[data-action='history']`);
  await histBtnAfterMerge.click();
  await new Promise(r => setTimeout(r, 300));
  const finalHistoryItems = await page.$$eval("#ticket-history-list .history-item", els => els.map(e => e.innerText));
  assert(finalHistoryItems.some(t => t.includes("pr_merged") || t.includes("Слит Pull Request")), "Ticket audit history automatically recorded PR merge!");

  await page.screenshot({ path: path.join(ARTIFACT_DIR, "ticket_history_pr_merged.png") });
  console.log("  📸 Saved ticket history with PR merge audit log screenshot");
  await page.click("#btn-modal-ticket-history-close");

  // =========================================================================
  // 6. MULTI-DB PARITY: Check SQLite WASM & CDB support for Tickets & PRs
  // =========================================================================
  console.log("\n--- 6. Testing Multi-DB Parity (SQLite WASM & Pure-Nim CDB) ---");

  // Switch to SQLite WASM
  await page.select("#storage-backend-select", "sqlite_wasm");
  await new Promise(r => setTimeout(r, 500));
  const wasmTickets = await page.$$eval("#tickets-list .ticket-card", els => els.length);
  assert(wasmTickets >= 3, `SQLite WASM loaded seeded tickets: ${wasmTickets}`);

  // Switch to Pure-Nim CDB
  await page.select("#storage-backend-select", "cdb");
  await new Promise(r => setTimeout(r, 500));
  const cdbTickets = await page.$$eval("#tickets-list .ticket-card", els => els.length);
  assert(cdbTickets >= 3, `Pure-Nim CDB loaded seeded tickets: ${cdbTickets}`);

  // Switch back to IndexedDB
  await page.select("#storage-backend-select", "indexeddb");
  await new Promise(r => setTimeout(r, 300));

  console.log("\n=================================================================");
  console.log(`VERIFICATION SUMMARY: ${passedCount} PASSED, ${failedCount} FAILED, ${browserErrors.length} BROWSER ERRORS`);
  console.log("=================================================================");

  await browser.close();

  if (failedCount > 0 || browserErrors.length > 0) {
    process.exit(1);
  } else {
    process.exit(0);
  }
})();
