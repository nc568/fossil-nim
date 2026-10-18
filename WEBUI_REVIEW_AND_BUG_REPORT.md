# 📋 Ре-вью и Аудит WebUI: Отчёт об ошибках и руководство по устранению для разработчика

> **Кому:** Агентному разработчику / Инженеру реализации  
> **От:** Рецензента (Reviewer / Code Auditor)  
> **Проект:** Fossil-Nim (WebUI & REST API)  
> **Статус:** ⚠️ Критические дефекты фронтенда и API интерфейса  
> **Обязательное требование к исполнителю:** **После внесения правок разработчик ОБЯЗАН лично запустить сервер `bin/fossil server --port 8080`, зайти в браузер (или через headless browser/curl) и вручную прокликать абсолютно все вкладки и страницы интерфейса, проверяя отсутствие ошибок в консоли разработчика (F12 DevTools Console & Network).**

---

## 🎯 Общая сводка проблем

При ручном тестировании WebUI пользователем были выявлены критические проблемы:
1. **Бесконечная загрузка (вечный спиннер)** на страницах **Files**, **Graph**, **Wiki**, **Tickets**, **Forum**.
2. **Чат не отправляет сообщения** («В чате не отправляется», висит ошибка авторизации 401).
3. **Кракозябры / искажение кодировки на странице Login** (`рџ”ђ Login`, `вЂў Token expires in 1h`, `в†ђ Back to Home`).

Ниже приведён детальный технический анализ каждой проблемы, точные места в коде с номерами строк и готовые решения.

---

## 🔍 Детальный анализ багов и пошаговые инструкции

### 1. Синтаксические ошибки JS, ломающие загрузку компонентов

При запуске статического синтаксического анализатора (`node -c`) выявлены две фатальные синтаксические ошибки в компонентах:

#### 1.1. Ошибка в `web_new/js/components/forum.js` (строка 36)
* **Файл:** [`web_new/js/components/forum.js:36`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/web_new/js/components/forum.js#L36)
* **Симптом:** `SyntaxError: Unexpected token '<'`
* **Причина:** Внутри шаблонной строки (template literal) вложена конструкция `${...}` внутри одинарных кавычек:
  ```javascript
  // ОШИБКА:
  ${p.attachment?'<div class="mt-4"><small>📎 Attachment: <a href="'+p.attachment+'" target="_blank">'+p.attachment+'</a> ${p.attachment.match(/\\.(jpg|jpeg|png|gif|webp)$/i)?'<br><img src="'+p.attachment+'" style="max-width:200px; max-height:200px; border-radius:4px; margin-top:4px">':''}</small></div>':''}
  ```
  Неэкранированные одинарные кавычки разрывают строку внутри интерполяции.
* **Что нужно сделать разработчику:**
  Заменить вложенную тернарную конструкцию на корректную конкатенацию или вспомогательную функцию:
  ```javascript
  ${p.attachment ? `
    <div class="mt-4"><small>📎 Attachment: <a href="${p.attachment}" target="_blank">${p.attachment}</a>
    ${p.attachment.match(/\.(jpg|jpeg|png|gif|webp)$/i) ? `<br><img src="${p.attachment}" style="max-width:200px; max-height:200px; border-radius:4px; margin-top:4px">` : ''}
    </small></div>
  ` : ''}
  ```

#### 1.2. Ошибка в `web_new/js/components/wiki.js` (строка 82)
* **Файл:** [`web_new/js/components/wiki.js:82`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/web_new/js/components/wiki.js#L82)
* **Симптом:** `SyntaxError: Invalid or unexpected token`
* **Причина:** Метод `render()` возвращает шаблонную строку в обратных кавычках `` `...` ``. На строке 82 вставлены неэкранированные тройные обратные кавычки:
  ```javascript
  // ОШИБКА:
  <button onclick="insertMd('\\n```\\n','\\n```\\n','code block')">CB</button>
  ```
  Символы ``` ` ``` досрочно закрывают шаблонную строку, и оставшийся JS-код становится невалидным.
* **Что нужно сделать разработчику:**
  Экранировать обратные кавычки:
  ```javascript
  <button onclick="insertMd('\\n\\`\\`\\`\\n','\\n\\`\\`\\`\\n','code block')">CB</button>
  ```
  Проверить валидность с помощью: `node -c web_new/js/components/wiki.js`.

---

### 2. Почему возникает бесконечная загрузка (Infinite Spinner Loop)

* **Файл:** [`web_new/js/app.js:127-165`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/web_new/js/app.js#L127-L165)
* **Механика бага:**
  1. Когда компонент падает с синтаксической ошибкой при подключении скрипта в HTML, он не регистрируется в реестре `window.components`.
  2. В `app.js` метод `loadRoute` сначала устанавливает спиннер:
     `main.innerHTML = '<div class="loading"><div class="spinner"></div></div>'`.
  3. Если `window.components[componentName]` отсутствует, срабатывает fallback:
     ```javascript
     const res = await fetch(path, {headers: {'X-Requested-With': 'xhttp'}});
     const text = await res.text();
     const doc = parser.parseFromString(text, 'text/html');
     const mainContent = doc.getElementById('main') || doc.body;
     html = mainContent.innerHTML;
     main.innerHTML = html;
     ```
  4. На сервере (`rest.nim`) для SPA-путей (`/forum`, `/wiki`, `/file` и т.д.) настроена отдача `web_new/index.html`.
  5. В `index.html` элемент `<main id="main">` по умолчанию содержит... `<div class="loading"><div class="spinner"></div></div>`!
  6. Скрипт парсит `index.html`, извлекает из него этот же спиннер и снова вставляет его в `main.innerHTML`. В итоге пользователь видит вечную загрузку без сообщений об ошибке.
* **Что нужно сделать разработчику:**
  1. Исправить регистрацию компонентов (устранить синтаксические ошибки).
  2. В `app.js` в fallback блоке `else` проверять, не возвращает ли сервер SPA-оболочку (`text.includes('id="navbar"')` или `mainContent.querySelector('.spinner')`). Если возвращает, вызывать `this.renderNotFound(path, componentName)` с понятной плашкой ошибки, а не перезаписывать спиннер спиннером.

---

### 3. Несоответствие роутинга и навигации (`/forum`, `/ticket`)

* **Файлы:**
  - [`web_new/index.html:43-46`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/web_new/index.html#L43-L46)
  - [`web_new/js/app.js:30-35`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/web_new/js/app.js#L30-L35)
  - [`web_new/js/components/ticket.js:4-8`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/web_new/js/components/ticket.js#L4-L8)
  - [`web_new/js/components/forum.js:5-10`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/web_new/js/components/forum.js#L5-L10)

* **Проблема с Tickets:**
  - Ссылка в навбаре: `<a href="/ticket">Tickets</a>`.
  - В `app.routes`: `'/ticket': { component: 'ticket' }`.
  - Компонент `'ticket'` предназначен для отображения **одного конкретного тикета** и хардкодит ID: `const id = query.id || '0'`.
  - Тикета `'0'` в репозитории нет! `api.ticketGet('0')` возвращает 404 `ticket not found`, промис падает с ошибкой.
  - Пользователь нажимает «Tickets» во множественном числе и ждет список задач, а не просмотр несуществующего тикета #0.
  - **Решение:**
    В `ticket.js` компонент `ticket` должен проверять: если `id` не передан, загружать и отображать список тикетов (`api.ticketList()`), либо в `app.routes` связать `'/ticket'` с `component: 'ticket-list'`.

* **Проблема с Forum:**
  - Ссылка в навбаре: `<a href="/forum">Forum</a>`.
  - В `app.routes`: `'/forum': { component: 'forum' }`.
  - Компонент `'forum'` предназначен для просмотра одного треда (`query.id || query.threadId`). Если ID нет, `fetch()` возвращает `null`, и в рендере падает обращение к `data.posts`.
  - **Решение:**
    Связать `'/forum'` с `component: 'forum-list'` (список всех тредов форума), а переход в конкретный тред делать по `/forum?id=...`.

---

### 4. Ошибка файлового браузера `/file` (400 Bad Request)

* **Файлы:**
  - [`web_new/js/components/file.js:6-16`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/web_new/js/components/file.js#L6-L16)
  - [`web_new/js/api.js:55-60`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/web_new/js/api.js#L55-L60)
  - [`src/fossil/api/rest.nim:231-238`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/src/fossil/api/rest.nim#L231-L238)

* **Проблема:**
  - При переходе на `/file` компонент вызывает `api.fileList()`, который шлет `GET /api/v1/file`.
  - На бэкенде в `handleFile`:
    ```nim
    let path = params.getOrDefault("path", "")
    if path=="": return jsonError("path required")
    ```
  - Бэкенд возвращает статус `400 Bad Request` и JSON `{"ok":false,"error":"path required"}`!
  - Клиентский `api.js` выбрасывает исключение `Error: path required`, загрузка прерывается.
  - При этом в API уже есть готовый эндпоинт `/api/v1/tree`, возвращающий дерево файлов и директорий (`{"files":["README.md"], "dirs":["src"]}`).
  - Кроме того, в `api.fileGet(name)` фронтенд шлет параметр `?name=...`, тогда как бэкенд ждет `?path=...`.
* **Что нужно сделать разработчику:**
  1. В `src/fossil/api/rest.nim` в `handleFile` поддержать оба параметра:
     `let path = params.getOrDefault("path", params.getOrDefault("name", ""))`.
  2. Если `path==""`, не возвращать 400, а вызывать `handleTree` для отдачи корневого списка файлов.
  3. В `web_new/js/components/file.js` для списка файлов использовать `/api/v1/tree` или обновленный `/api/v1/file`.

---

### 5. Отсутствие эндпоинта `/api/v1/graph` (404 Not Found)

* **Файлы:**
  - [`web_new/js/components/graph.js:4-8`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/web_new/js/components/graph.js#L4-L8)
  - [`web_new/js/api.js:138-140`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/web_new/js/api.js#L138-L140)
  - [`src/fossil/api/rest.nim:1880-1955`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/src/fossil/api/rest.nim#L1880-L1955)

* **Проблема:**
  - При открытии `/graph` фронтенд вызывает `api.graph()`, отправляющий запрос на `GET /api/v1/graph`.
  - В таблице роутов сервера роут `/api/v1/graph` вообще не зарегистрирован! Сервер возвращает 404.
  - Затем в коде `graph.js:30` выполняется fallback:
    `fetch('/graph?branch=...')` — но этот запрос возвращает `index.html` (SPA), в котором нет элемента `#graph`, в результате чего в DOM снова подставляется спиннер.
* **Что нужно сделать разработчику:**
  Зарегистрировать на бэкенде эндпоинт `GET /api/v1/graph`, который возвращает данные графа коммитов (узлы, связи, ветки) в формате JSON, либо отдавать SVG-граф коммитов репозитория.

---

### 6. Чат не отправляет сообщения («В чате не отправляется»)

* **Файлы:**
  - [`src/fossil/api/rest.nim:1906`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/src/fossil/api/rest.nim#L1906)
  - [`web_new/js/components/chat.js:152-164`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/web_new/js/components/chat.js#L152-L164)

* **Проблема:**
  - На скриншоте 2 пользователь находится в чате неавторизованным (кнопка `Login` в шапке зеленая).
  - Эндпоинт `/api/v1/chat/send` зарегистрирован с флагом `requiresAuth: true`.
  - Так как авторизационный токен или сессионная кука отсутствуют, бэкенд возвращает `401 Unauthorized`. Сообщение отклоняется.
  - В интерфейсе чата нет предупреждения о том, что для отправки требуется авторизация.
  - Кроме того, комната по умолчанию `#main` изначально пуста (демо-данные были созданы в `#general`).
* **Что нужно сделать разработчику:**
  1. Разрешить отправку сообщений гостям с именем `web` / `anonymous` (как в классическом Fossil для открытых репозиториев: `requiresAuth: false` в `server.routes.add ApiRoute(meth: "POST", path: "/api/v1/chat/send", ...)`), **ЛИБО**
  2. Если чат строго закрытый, в `chat.js` явно блокировать поле ввода и выводить плашку:
     `"🔒 Для отправки сообщений необходимо войти в систему"` со ссылкой на `/login`.
  3. В демо-данных по умолчанию наполнять комнату `main`, чтобы при первом открытии пользователь сразу видел сообщения.

---

### 7. Искажение кодировки (кракозябры) на странице логина

* **Скриншот:** `media_1792268649961_b43be16d.png`
* **Файлы:**
  - [`src/fossil/web/pages/login_page.nim:226`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/src/fossil/web/pages/login_page.nim#L226)
  - [`src/fossil/api/rest.nim:110-137`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/src/fossil/api/rest.nim#L110-L137)

* **Проблема:**
  - На странице логина отображается: `рџ”ђ Login`, `вЂў Token expires in 1h`, `в†ђ Back to Home`.
  - В HTML-шаблоне `renderLoginPage` внутри `<head>` отсутствует метатег `<meta charset="UTF-8">`.
  - В функции `secHeaders` заголовок `Content-Type` задан как `"text/html"`, без указания `charset=utf-8`.
  - Браузер интерпретирует UTF-8 поток байтов в кодировке Windows-1251 или ISO-8859-1.
* **Что нужно сделать разработчику:**
  1. В `src/fossil/api/rest.nim` в `secHeaders`:
     Задать заголовок с явной кодировкой: `("Content-Type", contentType & "; charset=utf-8")`.
  2. В `src/fossil/web/pages/login_page.nim`:
     В тег `<head>` добавить первой строкой `<meta charset="UTF-8">`.

---

## 📌 Чек-лист для агентного разработчика перед сдачей

Разработчик должен последовательно пройти следующие шаги:

1. [ ] Запустить проверку синтаксиса всех JS-файлов:
   ```bash
   for f in web_new/js/*.js web_new/js/lib/*.js web_new/js/components/*.js; do node -c "$f"; done
   ```
   Должно быть **0 синтаксических ошибок**.
2. [ ] Пересобрать проект: `make build`.
3. [ ] Запустить локальный сервер:
   ```bash
   ./bin/fossil server --port 8080 --bind 0.0.0.0
   ```
4. [ ] **Лично открыть браузер и кликнуть по каждому пункту:**
   - [ ] `http://localhost:8080/timeline` — коммиты отображаются без спиннера.
   - [ ] `http://localhost:8080/file` — дерево файлов отображается, файл кликается и читается.
   - [ ] `http://localhost:8080/graph` — граф веток отображается.
   - [ ] `http://localhost:8080/wiki` — страница `Home` и список страниц рендерятся.
   - [ ] `http://localhost:8080/ticket` — список тикетов загружается, открытие тикета работает.
   - [ ] `http://localhost:8080/forum` — список тредов форума виден, можно зайти в тред.
   - [ ] `http://localhost:8080/chat` — видны сообщения, отправка сообщения проходит успешно.
   - [ ] `http://localhost:8080/login` — эмодзи 🔐 и стрелки отображаются корректно, нет кракозябр, форма логина входит под `admin` / `admin123`.
5. [ ] Убедиться, что в консоли F12 DevTools нет `Uncaught SyntaxError` и `404/400 (Bad Request)` на базовых роутах.
