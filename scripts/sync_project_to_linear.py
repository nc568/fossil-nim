#!/usr/bin/env python3
"""
Full Project Sync to Linear.app
Uploads the Fossil-Nim project, milestones, documentation library, issues, and release archives.
"""

import os
import sys
import json
import urllib.request
import urllib.error

API_KEY = os.environ.get("LINEAR_API_KEY", "")
TEAM_ID = os.environ.get("LINEAR_TEAM_ID", "ea04b736-3dc3-4166-9e07-75bd115c34d0")
PROJECT_ID = os.environ.get("LINEAR_PROJECT_ID", "60b46a42-0777-4191-a6d0-02cd76b08f8a")
ROOT_DIR = os.environ.get("PROJECT_ROOT", os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

# Workflow state IDs
STATES = {
    "Backlog": "89643697-0b02-4c5a-9d08-a17fd2449995",
    "Todo": "b3f654af-9b19-4d72-b0b6-603cbc4c0449",
    "In Progress": "e310874c-a932-4140-88cd-d7bfc8883713",
    "Done": "00913def-b8ef-4e2e-bb76-d46c06dbf03a",
    "Canceled": "cf4d263b-a3cb-4848-b2ea-dd77465b9364"
}

def linear_graphql(query, variables=None):
    payload = {"query": query}
    if variables:
        payload["variables"] = variables
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        "https://api.linear.app/graphql",
        data=data,
        headers={
            "Content-Type": "application/json",
            "Authorization": API_KEY,
            "User-Agent": "FossilNim-Sync/1.0"
        }
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        err_msg = e.read().decode("utf-8")
        print(f"HTTP Error {e.code}: {err_msg}")
        return {"errors": [{"message": err_msg}]}
    except Exception as e:
        print(f"Request Error: {e}")
        return {"errors": [{"message": str(e)}]}

def get_existing_project_data():
    q = """
    query GetProject($id: String!) {
      project(id: $id) {
        projectMilestones { nodes { id name } }
        documents { nodes { id title } }
        issues { nodes { id identifier title } }
      }
    }
    """
    res = linear_graphql(q, {"id": PROJECT_ID})
    proj = (res.get("data") or {}).get("project") or {}
    milestones = {m["name"]: m["id"] for m in (proj.get("projectMilestones") or {}).get("nodes", [])}
    documents = {d["title"]: d["id"] for d in (proj.get("documents") or {}).get("nodes", [])}
    issues = {i["title"]: i["id"] for i in (proj.get("issues") or {}).get("nodes", [])}
    return milestones, documents, issues

def create_milestone(name, description, target_date, existing_milestones):
    if name in existing_milestones:
        print(f"  [Milestone] Already exists: {name} ({existing_milestones[name]})")
        return existing_milestones[name]

    q = """
    mutation CreateMilestone($input: ProjectMilestoneCreateInput!) {
      projectMilestoneCreate(input: $input) {
        success
        projectMilestone { id name }
      }
    }
    """
    res = linear_graphql(q, {
        "input": {
            "name": name,
            "description": description,
            "projectId": PROJECT_ID,
            "targetDate": target_date
        }
    })
    data = res.get("data") or {}
    ms = (data.get("projectMilestoneCreate") or {}).get("projectMilestone")
    if ms:
        print(f"  [Milestone] Created: {ms['name']} ({ms['id']})")
        existing_milestones[name] = ms['id']
        return ms['id']
    else:
        print(f"  [Milestone] Warning: {res.get('errors')}")
        return None

def create_document(title, content, existing_documents):
    if title in existing_documents:
        print(f"  [Document] Already exists: {title}")
        return existing_documents[title]

    if len(content) > 90000:
        content = content[:90000] + "\n\n*(Truncated due to Linear document size limits)*"
    q = """
    mutation CreateDoc($input: DocumentCreateInput!) {
      documentCreate(input: $input) {
        success
        document { id title }
      }
    }
    """
    res = linear_graphql(q, {
        "input": {
            "title": title,
            "content": content,
            "projectId": PROJECT_ID
        }
    })
    data = res.get("data") or {}
    doc = (data.get("documentCreate") or {}).get("document")
    if doc:
        print(f"  [Document] Created: {doc['title']} ({doc['id']})")
        existing_documents[title] = doc['id']
        return doc['id']
    else:
        print(f"  [Document] Error: {res.get('errors')}")
        return None

def create_issue(title, description, priority, state_name, due_date=None, milestone_id=None, existing_issues=None):
    if existing_issues and title in existing_issues:
        print(f"  [Issue] Already exists: {title}")
        return existing_issues[title]

    q = """
    mutation CreateIssue($input: IssueCreateInput!) {
      issueCreate(input: $input) {
        success
        issue { id identifier title url }
      }
    }
    """
    inp = {
        "teamId": TEAM_ID,
        "projectId": PROJECT_ID,
        "title": title,
        "description": description,
        "priority": priority,
        "stateId": STATES.get(state_name, STATES["Todo"])
    }
    if due_date:
        inp["dueDate"] = due_date
    if milestone_id:
        inp["projectMilestoneId"] = milestone_id

    res = linear_graphql(q, {"input": inp})
    data = res.get("data") or {}
    iss = (data.get("issueCreate") or {}).get("issue")
    if iss:
        print(f"  [Issue] Created {iss['identifier']}: {iss['title']} -> {iss['url']}")
        if existing_issues is not None:
            existing_issues[title] = iss['id']
        return iss
    else:
        print(f"  [Issue] Error creating '{title}': {res.get('errors')}")
        return None

def main():
    print("=" * 65)
    print("🚀 SYNCING FOSSIL-NIM PROJECT TO LINEAR.APP")
    print("=" * 65)

    existing_milestones, existing_documents, existing_issues = get_existing_project_data()
    print(f"  [INFO] Found {len(existing_milestones)} milestones, {len(existing_documents)} documents, {len(existing_issues)} issues in Linear.")

    # 1. Create Project Milestones
    print("\n--- 1. Syncing Milestones ---")
    m1 = create_milestone("M1: VCS Core Engine & Myers Diff", "Deterministic delta compression, Myers diff, ARC memory model, and manifest parsing.", "2026-10-14", existing_milestones)
    m2 = create_milestone("M2: Multi-DB Storage Architecture", "Modular storage engine supporting IndexedDB, SQLite WASM, and Pure-Nim CDB.", "2026-10-16", existing_milestones)
    m3 = create_milestone("M3: In-Browser MCP Platform (89 Tools)", "Full Model Context Protocol server exposing 89 typed tools for AI agents.", "2026-10-17", existing_milestones)
    m4 = create_milestone("M4: GitLab-Style WebUI & i18n Themes", "Modern Vanilla JS SPA, collapsible sidebar, theme customizer, and language configs.", "2026-10-18", existing_milestones)
    m5 = create_milestone("M5: Linear Gantt Timeline & Calendar", "Continuous task timeline, priority gradients, deadline pins, click-to-jump, and empty state.", "2026-10-18", existing_milestones)
    m6 = create_milestone("M6: Security Audit & Minimalist Browsers", "Timing attack prevention, path traversal checks, QBE cproc compiler, and Surf compatibility.", "2026-10-18", existing_milestones)

    # 2. Upload Project Documents
    print("\n--- 2. Uploading Project Documents ---")
    doc_files = [
        ("🦖 Fossil-Nim Project Overview & Architecture", "README.md"),
        ("🏗️ Architecture & VCS Engine Specification", "docs/ARCHITECTURE_RU.md"),
        ("💾 Multi-DB Storage Backends (IndexedDB, SQLite WASM, CDB)", "docs/STORAGE_BACKENDS_RU.md"),
        ("🤖 MCP 89 Tools Reference & AI Integration Guide", "docs/MCP_API_RU.md"),
        ("🔒 Security Audit & CVE Hardening Report", "docs/SECURITY_AUDIT_REPORT_RU.md"),
        ("📈 Linear Gantt Timeline & Roadmap Specification", "docs/TIMELINE_STATUS_JUMP_REPORT_RU.md"),
        ("🌐 WebUI & Responsive GitLab Sidebar Specification", "docs/UI_NEW_RU.md"),
        ("⚡ API, QBE cproc & Minimalist Browsers (Surf/Netsurf) Review", "docs/API_MCP_QBE_WEBUI_REVIEW_REPORT_RU.md"),
        ("📦 Release Manifest & Compressed Archives (<25MB)", "README.md")
    ]

    for title, rel_path in doc_files:
        full_p = os.path.join(ROOT_DIR, rel_path)
        if os.path.exists(full_p):
            with open(full_p, "r", encoding="utf-8") as f:
                content = f.read()
            create_document(title, content, existing_documents)
        else:
            print(f"  [Document] File not found: {full_p}")

    # 3. Create Project Issues & Tasks
    print("\n--- 3. Creating Project Issues & Roadmap Tasks ---")
    tasks = [
        {
            "title": "[tkt-101] Реализовать интерактивный таймлайн-календарь",
            "desc": "Добавить отображение дедлайнов задач на линейной шкале Gantt с визуализацией приоритетов, статусов и фильтрацией.\n\n- Связан с Pull Request #pr-101\n- Линейная протяженность от создания до дедлайна\n- Автопереход к дате старта",
            "priority": 1, # Critical
            "state": "Done",
            "due": "2026-10-22",
            "ms": m5
        },
        {
            "title": "[tkt-102] Оптимизация Myers diff для больших файлов",
            "desc": "Улучшить скорость вычисления разницы в WebAssembly до субмиллисекундного времени для файлов 10K+ строк.\n\n- Myers O(ND) алгоритм с эвристикой средней точки\n- Дельта-компрессия Fossil с циклическим хешем Adler-32\n- Тесты производительности в `benchmarks/storage_bench`",
            "priority": 2, # High
            "state": "Done",
            "due": "2026-10-16",
            "ms": m1
        },
        {
            "title": "[tkt-103] Полная документация и примеры 89 MCP инструментов",
            "desc": "Сформировать полную интерактивную документацию и тестовые вызовы для каждого из 89 MCP инструментов.\n\n- Категории: VCS Core, Files, Wiki, Tickets, PR, Storage, Search\n- Поддержка параметров и возвращаемых типов\n- Интерактивная консоль тестирования в WebUI",
            "priority": 3, # Medium
            "state": "Done",
            "due": "2026-10-17",
            "ms": m3
        },
        {
            "title": "[tkt-104] Интернационализация WebUI (RU, EN) и конфиги тем",
            "desc": "Создать гибкую систему i18n и конфигурации стилей оформления:\n\n- Поддержка русского и английского языков с возможностью расширения\n- Редактор цветовых палитр (CSS variables) прямо в интерфейсе\n- Темы Dark, Light, Nord, Monokai",
            "priority": 3, # Medium
            "state": "Done",
            "due": "2026-10-18",
            "ms": m4
        },
        {
            "title": "[tkt-105] Адаптивный дизайн в стиле GitLab (боковая панель, мобильные устройства)",
            "desc": "Переработать интерфейс в профессиональный инструмент:\n\n- Складная боковая панель с SVG-иконками\n- Модальное окно «О проекте» с динамическими переменными времени выполнения (версия, активная БД, счётчик 89 MCP)\n- Адаптивность для смартфонов (скрытие дублирующих ссылок, мобильный drawer)",
            "priority": 2, # High
            "state": "Done",
            "due": "2026-10-18",
            "ms": m4
        },
        {
            "title": "[tkt-106] Поддержка минималистичных браузеров (surf, netsurf)",
            "desc": "Обеспечить чистый Vanilla JS без полифилов и сторонних фреймворков для безупречной работы в suckless surf и netsurf.\n\n- Полная работоспособность интерфейса без тяжелых библиотек\n- Скриншот-тестирование рендеринга",
            "priority": 3, # Medium
            "state": "Done",
            "due": "2026-10-18",
            "ms": m6
        },
        {
            "title": "[tkt-107] Сборка QBE cproc для супер-легковесных сред",
            "desc": "Адаптировать Си-код компилятора под чистый C11 стандарт без расширений GCC и скомпилировать сверхкомпактный бинарник с бэкендом QBE.",
            "priority": 2, # High
            "state": "Done",
            "due": "2026-10-18",
            "ms": m6
        },
        {
            "title": "[tkt-108] Аудит безопасности и защита от timing-атак",
            "desc": "Провести комплексный аудит безопасности:\n\n- Constant-time сравнение токенов аутентификации (timing attack protection)\n- Валидация путей (path traversal prevention)\n- Проверка CSRF токенов и экранирование XSS в WebUI\n- Подготовлен подробный отчет `docs/SECURITY_AUDIT_REPORT_RU.md`",
            "priority": 1, # Critical
            "state": "Done",
            "due": "2026-10-18",
            "ms": m6
        },
        {
            "title": "[tkt-109] Исправление отображения линейного таймлайна и фильтрация дат",
            "desc": "Устранение бага сжатия полос из скриншота пользователя:\n\n- Реализована фильтрация пересечения временного окна (`overlaps`)\n- Задачи из других месяцев больше не сжимаются в нулевую точку на 1-м числе чужого месяца\n- Реализован Empty State с умной кнопкой перехода к месяцу с задачами",
            "priority": 1, # Critical
            "state": "Done",
            "due": "2026-10-18",
            "ms": m5
        },
        {
            "title": "[tkt-110] Автоматическое перемещение в календаре к дате старта задачи при клике",
            "desc": "При клике на любую задачу из списка со сроками:\n\n- Календарь автоматически перемещается на дату её старта (`created` / `mtime`)\n- Горизонтальный плавный скролл центрирует полосу задачи\n- Полоса и карточка подсвечиваются пульсирующей анимацией `.timeline-highlight-pulse`\n- На карточке добавлена кнопка `✏️` для прямого открытия окна редактирования",
            "priority": 2, # High
            "state": "Done",
            "due": "2026-10-18",
            "ms": m5
        },
        {
            "title": "[tkt-111] Отображение статусов тикетов на таймлайне и карточках",
            "desc": "Вывод статусов задач (Open, In_Process, Closed, Deferred, Fixed):\n\n- Цветовые бейджи статуса в левой колонке задач\n- Компактный тег статуса `.timeline-bar-status-tag` внутри самой полосы Gantt\n- Отображение статусов в боковой панели и во всплывающей подсказке (Tooltip)",
            "priority": 3, # Medium
            "state": "Done",
            "due": "2026-10-18",
            "ms": m5
        },
        {
            "title": "[tkt-112] Сверхсильное сжатие дистрибутива (<25 МБ)",
            "desc": "Создание релизных сжатых архивов для удобной отправки:\n\n- `fossil-nim-complete.tar.xz` — 21.2 МБ (LZMA2 extreme `-9e`)\n- `fossil-nim-complete.tar.zst` — 23.0 МБ (Zstandard `-19`)\n- `fossil-nim-app-and-docs.zip` — 8.7 МБ (исходный код, тесты, документация, бандл)",
            "priority": 2, # High
            "state": "Done",
            "due": "2026-10-18",
            "ms": m2
        },
        {
            "title": "[pr-101] Feat: Интерактивный линейный таймлайн-календарь (Gantt & Roadmap)",
            "desc": "Добавлен таб линейного таймлайна с масштабированием, визуализацией протяженности задач, градиентами приоритетов и маркерами дедлайна.\n\n- Связан с тикетом #tkt-101\n- Ветка: `feature/calendar-timeline` -> `trunk`\n- Статус: Смерджен",
            "priority": 2, # High
            "state": "Done",
            "due": "2026-10-18",
            "ms": m5
        },
        {
            "title": "[pr-102] Docs: Спецификация 89 MCP инструментов и интерактивная консоль",
            "desc": "Полная типизированная документация, схемы JSON-RPC и примеры параметров для всех 89 MCP инструментов.\n\n- Связан с тикетом #tkt-103\n- Ветка: `docs/mcp-spec` -> `trunk`\n- Статус: Смерджен",
            "priority": 3, # Medium
            "state": "Done",
            "due": "2026-10-17",
            "ms": m3
        }
    ]

    for t in tasks:
        create_issue(
            title=t["title"],
            description=t["desc"],
            priority=t["priority"],
            state_name=t["state"],
            due_date=t["due"],
            milestone_id=t["ms"],
            existing_issues=existing_issues
        )

    print("\n" + "=" * 65)
    print("🎉 FULL SYNC TO LINEAR COMPLETE!")
    print(f"Project URL: https://linear.app/k9l/project/fossil-nim-distributed-vcs-webui-and-mcp-platform-9ec1ab7cbbc6")
    print("=" * 65)

if __name__ == "__main__":
    main()
