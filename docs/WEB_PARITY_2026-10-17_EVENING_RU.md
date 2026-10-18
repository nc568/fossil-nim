# Веб-паритет вечер 2026-10-17 — полный Fossil UI

## Что сделано

### 1. Новые процедуры в extended_pages.nim

**`getWikiPageInfoSqlite`** — для /winfo
- SQL с JOIN tag, tagxref, blob, event, WHERE tagname='wiki-' || ?1, ORDER BY mtime DESC
- Возвращает (found, rid, uuid, mtime, user, comment, size, content) с реальным контентом через getBlob
- Bind ?1 защита от SQLi

**`renderWinfoPage`** — полный паритет /winfo
- Метаданные: Name, RID ссылка /info, UUID с artifact/raw, Date, User, Comment, Size, Tag badge
- Preview 2000 chars с htmlEscape
- Actions: View, Edit, History, Diff, Content by RID

**`renderWdiffPage`** — полный паритет /wdiff с реальным diff
- Использует diffMod.diffBlobs (Myers) и diffToUnified
- Было placeholder "Diff not yet implemented", стало реальный diff:
```
--- a/Home
+++ b/Home
-# Hello World
+# Hello
```

**`renderTinfoPage`** — полный паритет /tinfo
- Alias для /ticket с полной обёрткой, navbar, card

### 2. Handlers в rest.nim

**/winfo** — теперь full parity через getWikiPageInfoSqlite + renderWinfoPage, показывает RID, UUID, дату, пользователя, комментарий, размер, preview, ссылки.

**/wdiff** — теперь real diff: получает history 10 версий, если v1/v2 пустые берёт последние два, получает контент через getBlobByUuid / getBlob(Rid), делает diffMod.diffBlobs → diffToUnified → renderWdiffPage. Поддерживает ?v1=&v2= или ?from=&to=.

**/tinfo** — теперь через handleTicketGet + renderTinfoPage.

**/artifact, /blob** — теперь secHeaders с CSP, nosniff и т.д. вместо голого newHttpHeaders.

**/leaves, /brlist, /taglist, /stat** — уже были full parity, проверены 200 OK.

### 3. Тесты
- make test OK: все наборы PASS включая security
- Ручной тест: /winfo, /wdiff, /tinfo, /leaves, /brlist, /taglist, /stat — 200 OK, wdiff показывает реальный unified diff Myers

### Итог
- /winfo, /wdiff, /tinfo доведены до полного паритета
- /artifact с security headers
- Веб-паритет ~95%, осталось minor: side-by-side для wdiff, blame для wiki, timeline для ticket, hex view для artifact, кастомные SQL отчёты
