# Экран входа SDDM без Hyprland — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Execute inline; use one independent review before system installation.

**Goal:** Подготовить и установить один local override SDDM, который выбирает X11 greeter и сохраняет Wayland/ShojiWM desktop session.

**Architecture:** Пользовательская установка dotfiles не меняется. Источник системного override и отдельная инструкция установки/отката проверяются в checkout; установка одного файла и применение на host выполняются отдельно, после готовности восстановления. Успех подготовительных проверок и успешный вход учитываются раздельно.

**Tech Stack:** SDDM 0.21.0-7, установленный Xorg, INI, Python 3 для чтения/проверки конфигураций, штатные install и cmp.

**Spec:** [Согласованная спецификация 1А](../specs/2026-10-10-independent-greeter-design.md).

## Global Constraints

- Рабочий стол не переводится на X11.
- Не изменять packaged defaults в `/usr/lib/sddm/`, существующие theme settings, автологин другого пользователя или global SessionCommand.
- Перезапуск SDDM не включается автоматически в установку.
- Пакеты Omarchy и Hyprland пока остаются доступными для отката.
- Пользовательский installer не получает неявных root-операций.
- Без этих условий можно подготовить source file, документацию и проверки, но нельзя переключать экран входа или считать часть 1А принятой.
- Перед установкой вычислить применимые значения с учётом всех конфигурационных директорий и `/etc/sddm.conf`, который имеет более высокий приоритет.
- Не включать существующие незакоммиченные изменения в коммиты этой части.
- Не публиковать частный backup manifest, имена других пользователей или локальные абсолютные пути.
- Desktop user остаётся без sudo; системные операции выполняются из существующей административной учётной записи без изменений групп и sudoers.

## Review Focus

1. `/etc/sddm.conf` или более поздний local override перекрывает X11: нельзя объявлять применение успешным по существованию нового файла.
2. Destination уже существует или является symlink: установка не должна молча перезаписать его без отдельной копии и проверки происхождения.
3. Snapshot устарел или выполнен из sandbox с изменённым ownership: сохранять текущие host metadata, не использовать видимые в sandbox UID/GID для chown.
4. Другой пользователь вошёл или использует autologin: backend изменяется общесистемно, application откладывается до согласованного окна.
5. Greeter работает, но ShojiWM не стартует: нельзя переводить desktop в X11 или заменять весь профиль ради устранения отдельного отказа.

---

## Границы исполнения

Задачи 1–2 выполняются в checkout и не затрагивают активную сессию. Задача 3
содержит host operations и живую приёмку: перед ней требуются подтверждение
входа в TTY, административных действий и согласованное время применения.
Время ожидания не заменяет эти подтверждения.

Если sandbox не позволяет записать `/etc`, подготовить точную инструкцию
для обычного терминала; не запрашивать запрещённую sandbox escalation и не
считать установленным файл, созданный только в checkout.

Системная транзакция не включает удаление пакетов, правку boot chain, PAM,
sleep handlers, user targets или autologin. Переход lifecycle относится к 1Б.

### Task 1: Источник одного greeter override

**Files:**
- Create: `dotfiles/system/sddm/zz-tab-stack-greeter.conf`.
- Read: `dotfiles/scripts/install.py` — убедиться, что новый system directory не устанавливается пользовательским installer автоматически.

**Interfaces:**
- Consumes: утверждённое содержимое из спецификации.
- Produces: файл с точными байтами `[General]\nDisplayServer=x11\n`, mode 644.

- [ ] Создать ровно указанный INI. Не добавлять Theme, Autologin, Wayland или SessionCommand секции.
- [ ] Проверить чтением Python: bytes равны указанному значению; единственная секция `General`; единственное значение `DisplayServer=x11`.
- [ ] Повторно прочитать installer component selection: отсутствие system component подтверждает, что обычное `install.py --apply` не меняет SDDM.
- [ ] Выполнить `git diff --check` и privacy scan точного staged INI по существующему publication checker.
- [ ] Коммитить только новый source file: `Add independent X11 greeter configuration`.

### Task 2: Проверка приоритета и точная инструкция восстановления

**Files:**
- Create: `dotfiles/docs/greeter.md`.
- Modify: `docs/migration/recovery.md` — ссылка на отдельную процедуру SDDM.
- Read: `docs/migration/dependency-register.md`, все действующие SDDM conf locations.

**Interfaces:**
- Consumes: INI из задачи 1 и selected-file snapshot этапа подготовки.
- Produces: последовательность preview → host backup → install → verify → apply → acceptance → rollback; никакого автоматического restart.

- [ ] Описать три области: конфигурация экрана входа общая, пользовательские session entries сохраняются, desktop ShojiWM остаётся Wayland.
- [ ] Описать приоритет: `/usr/lib/sddm/sddm.conf.d/*.conf`, `/etc/sddm.conf.d/*.conf` в порядке имён, затем `/etc/sddm.conf`. Прочитать действующие файлы и вычислить proposed effective DisplayServer при добавлении INI задачи 1; опубликовать только key/value и происхождение, без Autologin.User.
- [ ] Проверить приоритет на временных fixture-файлах: поздний local DisplayServer=wayland перекрывает candidate; `/etc/sddm.conf` перекрывает local directory; отсутствие conflicting keys даёт x11. Это проверка процедуры вычисления, не новая production helper library.
- [ ] Подготовить конкретные host команды: проверка destination file type, создание root-owned private backup directory, запись presence/absence и host modes/ownership, сохранение прежнего destination и relevant конфигураций перед записью.
- [ ] Разделить команды desktop user и административной учётной записи. Для чтения source из приватного home использовать абсолютный путь внутри разрешённой повышенной операции; не расширять mode home/backups и не копировать их целиком для другого пользователя.
- [ ] Для существующего destination предусмотреть отдельную копию; при symlink остановиться и разобрать его происхождение, не следовать ссылке при установке. Новая source-copy транзакция записывает только один regular файл с owner root:root и mode 644.
- [ ] Описать установку через `sudo install -o root -g root -m 644 --` с source path из checkout и destination `/etc/sddm.conf.d/zz-tab-stack-greeter.conf`. Установка не вызывает systemctl restart и не использует user installer.
- [ ] После установки сравнить destination/source через `cmp`, проверить mode и вновь вычислить effective DisplayServer. При конфликте оставить систему без restart и выполнить точечный rollback после проверки причины.
- [ ] Подготовить два точных rollback маршрута: новый destination удаляется только если его checksum совпадает с installed candidate и backup отмечает исходное отсутствие; прежний destination восстанавливается только из свежей host копии с подтверждёнными исходными modes/ownership. Не выполнять массовый restore.
- [ ] Объяснить, что общий snapshot — дополнительная копия, а не готовый пакетный/boot rollback; source_uid_visible_to_sandbox не применяется как host ownership.
- [ ] Записать условия application: проверенный TTY login/admin, сохранённая работа, знание активных сессий и согласованное окно. Не предлагать kill/restart как часть команды установки.
- [ ] Проверить ссылки, приватность, INI и `git diff --check`; коммитить только greeter guide и ссылку recovery: `Document independent greeter installation and rollback`.

### Task 3: Установка на host и живая приёмка

**Files:**
- Install on host: `/etc/sddm.conf.d/zz-tab-stack-greeter.conf`.
- Local private backup: root-owned directory, указанный в руководстве; содержимое не публикуется.
- Modify: `docs/migration/acceptance.md` и `docs/superpowers/specs/2026-10-10-independent-tab-stack-roadmap.md` — только подтверждённый результат.

**Interfaces:**
- Consumes: verified INI и процедура задачи 2; независимое review подготовленных source/doc changes; подтверждённые recovery prerequisites.
- Produces: installed config status отдельно от runtime acceptance; при отсутствии доступа — подготовленный source и точная пользовательская инструкция, без заявления об установке.

- [ ] Провести независимое review задач 1–2 до записи в `/etc`, исправить материальные замечания.
- [ ] Получить недостающие read-only host state результаты, включая активные сессии и SDDM; не печатать частные данные других пользователей.
- [ ] Проверить подтверждение TTY login/admin и актуальность backup. Если отсутствует хотя бы одно условие, остановить только host mutation и оставить результат «подготовлено, не установлено».
- [ ] Выполнить выбранную host backup/install/verify процедуру задачи 2 в разрешённом окружении; sandbox denial не считать успешной установкой и не обходить.
- [ ] Отдельно согласовать время применения. При согласованной перезагрузке или рестарте сохранить работу и учитывать другие сессии; не запускать действие автоматически сразу после install.
- [ ] Проверить greeter, ручной выбор ShojiWM, `XDG_SESSION_TYPE=wayland`, принадлежность display, отсутствие Hyprland greeter, logout/relogin и cold boot. Другие намеренно запущенные Hyprland sessions не выдавать за отказ greeter изменения.
- [ ] Проверить применимость и доступность rollback без искусственного разрушения working config; после application сохранять previous config до завершения проверки.
- [ ] Обновить acceptance/roadmap по фактам: подготовка, установка и runtime приёмка имеют отдельные статусы. Часть 1А не считать завершённой до живой приёмки.
- [ ] Коммитить только документированные результаты: `Record independent greeter verification status`. Не публиковать system backup или runtime журналы.

## Перед исполнением

Backend X11 выбран пользователем. Вход в TTY из другой учётной записи подтверждён;
desktop user не имеет sudo и не получит его в рамках этого этапа. Успешность
административных действий проверяется отдельно. План подготовлен для просмотра.
Предлагается тот же метод исполнения: native, один исполнитель и независимое
review подготовленных изменений до system install. Нужные подтверждения для
host application остаются отдельными от согласования плана.
