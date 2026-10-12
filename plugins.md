# Сторонние инструменты для tab-stack

Здесь собран каталог внешних плагинов и проектов для работы с агентами, исследования и автоматизации. Он вырос из каталога kisa-stack. Это список возможных подключений, а не перечень того, что сейчас установлено у Tabek.

Мой подход к рабочей среде — подключать инструмент под конкретную задачу. Для настройки tab-stack не требуется устанавливать весь каталог. Актуальные способы установки, зависимости и условия доступа смотрите в репозитории выбранного проекта.

## Исследование и проверка работы

| Проект | Назначение |
| --- | --- |
| [tavily-tools](https://github.com/fcakyon/claude-codex-settings) | Поиск и извлечение веб-контента через Tavily MCP |
| [Codex plugin for Claude Code](https://github.com/openai/codex-plugin-cc) | Работа с Codex из Claude Code, включая делегирование и ревью |
| [Agentation](https://github.com/benjitaylor/agentation) | Визуальные аннотации интерфейса для передачи замечаний агенту |
| [gstack](https://github.com/garrytan/gstack) | Набор инструментов и скиллов для разработки, ревью и QA |

## Организация разработки

| Проект | Назначение |
| --- | --- |
| [Ponytail](https://github.com/dietrichgebert/ponytail) | Работа с задачами в существующей кодовой базе |
| [gsd-core](https://github.com/open-gsd/gsd-core) | Разработка по спецификациям и организация этапов работы |
| [rtk](https://github.com/rtk-ai/rtk) | Фильтрация вывода команд перед передачей агенту |
| [Z.A.E.B.A.L.](https://github.com/howdeploy/Z.A.E.B.A.L) | Разбор ошибок агента |
| [Choirboy Prompt](https://github.com/howdeploy/choirboy-prompt) | Контекст для использования командных инструментов |
| [ObsidianDataWeave](https://github.com/howdeploy/ObsidianDataWeave) | Обработка заметок и ведение LLM Wiki; автор проекта — howdeploy |

Шаблоны [global-config](global-config/README.md) содержат опциональные блоки для Wiki и внешних инструментов. Их нужно адаптировать к своему процессу.

## Инструменты под отдельные задачи

| Проект | Назначение |
| --- | --- |
| [statusline-tools](https://github.com/fcakyon/claude-codex-settings) | Статусная строка Claude Code |
| [python-development](https://github.com/wshobson/agents) | Инструменты и агенты для Python-разработки |
| [security-scanning](https://github.com/wshobson/agents) | Проверки безопасности кода и зависимостей |
| [blockchain-web3](https://github.com/wshobson/agents) | Инструменты для Web3-разработки |
| [rust-analyzer-lsp](https://github.com/anthropics/claude-plugins-official) | LSP для Rust |
| [pyright-lsp](https://github.com/anthropics/claude-plugins-official) | LSP для Python |
| [ccproxy-tools](https://github.com/fcakyon/claude-codex-settings) | Инструменты для альтернативных подключений моделей |
| [Remotion](https://github.com/remotion-dev/remotion) | Создание видео средствами React |

## Звук и оформление работы агента

- [claude-typing-ambient](https://github.com/howdeploy/Claude-typing-ambient) — фоновые звуки клавиатуры; плагин howdeploy.
- [MTGA](https://github.com/howdeploy/MTGA) — стилизация ответов Claude Code; плагин howdeploy.
- [claudecode-sounds](https://github.com/newink/codingagents) — звуковые уведомления.
- [claude-code-spinner](https://github.com/i1kazantsev/claude-code-spinner) — набор фраз для индикатора работы Claude Code.

Эти проекты разрабатывают их собственные авторы. Упоминание в tab-stack не означает авторство Tabek, включение их кода в репозиторий или подтверждение совместимости каждой версии.
