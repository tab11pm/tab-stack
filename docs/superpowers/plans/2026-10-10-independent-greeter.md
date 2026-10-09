# Экран входа SDDM без Hyprland — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking. Execute inline; use one independent review before system installation.

**Goal:** Подготовить и установить один local override SDDM, который выбирает X11 greeter и сохраняет Wayland/ShojiWM desktop session.

**Architecture:** Пользовательская установка dotfiles не меняется. Источник системного override и отдельная инструкция установки/отката проверяются в checkout; установка одного файла и применение на host выполняются отдельно, после готовности восстановления. Успех подготовительных проверок и успешный вход учитываются раздельно.

**Tech Stack:** SDDM 0.21.0-7, установленный Xorg, INI, Python 3 для чтения/проверки конфигураций, временный Qt6Core verifier для точного порядка SDDM, штатные install и cmp.

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

- [x] Создать ровно указанный INI. Не добавлять Theme, Autologin, Wayland или SessionCommand секции.
- [x] Проверить чтением Python: bytes равны указанному значению; единственная секция `General`; единственное значение `DisplayServer=x11`.
- [x] Повторно прочитать installer component selection: отсутствие system component подтверждает, что обычное `install.py --apply` не меняет SDDM.
- [x] Выполнить `git diff --check` и privacy scan точного staged INI по существующему publication checker.
- [x] Коммитить только новый source file: `Add independent X11 greeter configuration`.

### Task 2: Проверка приоритета и точная инструкция восстановления

**Files:**
- Create: `dotfiles/docs/greeter.md`.
- Modify: `docs/migration/recovery.md` — ссылка на отдельную процедуру SDDM.
- Read: `docs/migration/dependency-register.md`, все действующие SDDM conf locations.

**Interfaces:**
- Consumes: INI из задачи 1 и selected-file snapshot этапа подготовки.
- Produces: последовательность preview → host backup → install → verify → apply → acceptance → rollback; никакого автоматического restart.

- [x] Описать три области: конфигурация экрана входа общая, пользовательские session entries сохраняются, desktop ShojiWM остаётся Wayland.
- [x] Описать приоритет: все не скрытые файлы QDir::Files в `/usr/lib/sddm/sddm.conf.d` и `/etc/sddm.conf.d` с Qt LocaleAware sorting, затем `/etc/sddm.conf`. Проверка использует locale действующего SDDM; если недоступен, host preview остаётся неподтверждённым. Прочитать действующие файлы и вычислить proposed effective DisplayServer при добавлении INI задачи 1; опубликовать только key/value и происхождение, без Autologin.User.
- [x] Проверить приоритет на временных fixture-файлах: поздний local DisplayServer=wayland перекрывает candidate; `/etc/sddm.conf` перекрывает local directory; отсутствие conflicting keys даёт x11; non-conf файл также может перекрыть candidate. Это проверка процедуры вычисления с временным Qt ordering tool, не новая production helper library.
- [x] Подготовить конкретные host команды: проверка destination file type, создание root-owned private backup directory, запись presence/absence и host modes/ownership, сохранение прежнего destination и relevant конфигураций перед записью.
- [x] Разделить команды desktop user и административной учётной записи. Для чтения source из приватного home использовать абсолютный путь внутри разрешённой повышенной операции; не расширять mode home/backups и не копировать их целиком для другого пользователя.
- [x] Для существующего destination предусмотреть отдельную копию; при symlink остановиться и разобрать его происхождение, не следовать ссылке при установке. Новая source-copy транзакция записывает только один regular файл с owner root:root и mode 644.
- [x] Описать установку через `sudo install -o root -g root -m 644 --` с source path из checkout и destination `/etc/sddm.conf.d/zz-tab-stack-greeter.conf`. Установка не вызывает systemctl restart и не использует user installer.
- [x] После установки сравнить destination/source через `cmp`, проверить mode и вновь вычислить effective DisplayServer. При конфликте оставить систему без restart и выполнить точечный rollback после проверки причины.
- [x] Подготовить два точных rollback маршрута: новый destination удаляется только если его checksum совпадает с installed candidate и backup отмечает исходное отсутствие; прежний destination восстанавливается только из свежей host копии с подтверждёнными исходными modes/ownership. Не выполнять массовый restore.
- [x] Объяснить, что общий snapshot — дополнительная копия, а не готовый пакетный/boot rollback; source_uid_visible_to_sandbox не применяется как host ownership.
- [x] Записать условия application: проверенный TTY login/admin, сохранённая работа, знание активных сессий и согласованное окно. Не предлагать kill/restart как часть команды установки.
- [x] Проверить ссылки, приватность, INI и `git diff --check`; коммитить только greeter guide и ссылку recovery: `Document independent greeter installation and rollback`.

### Task 3: Установка на host и живая приёмка

**Files:**
- Install on host: `/etc/sddm.conf.d/zz-tab-stack-greeter.conf`.
- Local private backup: root-owned directory, указанный в руководстве; содержимое не публикуется.
- Modify: `docs/migration/acceptance.md` и `docs/superpowers/specs/2026-10-10-independent-tab-stack-roadmap.md` — только подтверждённый результат.

**Interfaces:**
- Consumes: verified INI и процедура задачи 2; независимое review подготовленных source/doc changes; подтверждённые recovery prerequisites.
- Produces: installed config status отдельно от runtime acceptance; при отсутствии доступа — подготовленный source и точная пользовательская инструкция, без заявления об установке.

- [x] Провести независимое review задач 1–2 до записи в `/etc`, исправить материальные замечания.
- [x] Получить недостающие read-only host state результаты, включая активные сессии и SDDM; не печатать частные данные других пользователей.
- [x] Проверить подтверждение TTY login/admin и актуальность backup. Если отсутствует хотя бы одно условие, остановить только host mutation и оставить результат «подготовлено, не установлено».
- [ ] Выполнить выбранную host backup/install/verify процедуру задачи 2 в разрешённом окружении; sandbox denial не считать успешной установкой и не обходить.
- [ ] Отдельно согласовать время применения. При согласованной перезагрузке или рестарте сохранить работу и учитывать другие сессии; не запускать действие автоматически сразу после install.
- [ ] Проверить greeter, ручной выбор ShojiWM, `XDG_SESSION_TYPE=wayland`, принадлежность display, отсутствие Hyprland greeter, logout/relogin и cold boot. Другие намеренно запущенные Hyprland sessions не выдавать за отказ greeter изменения.
- [ ] Проверить применимость и доступность rollback без искусственного разрушения working config; после application сохранять previous config до завершения проверки.
- [x] Обновить acceptance/roadmap по фактам: подготовка, установка и runtime приёмка имеют отдельные статусы. Часть 1А не считать завершённой до живой приёмки.
- [x] Коммитить только документированные результаты: `Record independent greeter verification status`. Не публиковать system backup или runtime журналы.

## Перед исполнением

Backend X11 выбран пользователем. Вход в TTY из другой учётной записи подтверждён;
desktop user не имеет sudo и не получит его в рамках этого этапа. Пользователь
подтвердил успешный `sudo -v` в административной записи. План подготовлен для просмотра.
Предлагается тот же метод исполнения: native, один исполнитель и независимое
review подготовленных изменений до system install. Нужные подтверждения для
host application остаются отдельными от согласования плана.

## Результат подготовки 2026-10-10

Задачи 1–2 выполнены. Независимое review: 0 Critical, 2 Important, 0 Minor.
Оба Important исправлены с воспроизведением отказа проверки до изменения:

- SDDM 0.21 читает все QDir::Files, включая non-conf файлы, с LocaleAware
  sorting; исходная схема *.conf/Python sorted заменена временным Qt verifier.
  Host preview требует locale действующего daemon, недоступный из sandbox.
- Существующий destination требует проверки происхождения/содержимого и
  reviewed checksum; отсутствие digest или изменение файла блокирует замену.

Проверено: точный INI/mode; четыре priority fixtures; три checksum guard fixtures;
синтаксис shell-блоков; относительные ссылки; publication scan — 0 findings.
Подготовленный snapshot проверен повторно: 104 файла и 9 symlinks целы,
один исходный файл отсутствовал. Host UID/GID из sandbox не применяются.

Чтение system D-Bus запрещено: Operation not permitted. Destination на host
отсутствует. Текущая конфигурация задаёт wayland; proposed x11 подтверждён
по читаемым файлам при locale окружения проверки, не locale действующего SDDM.
Пользователь подтвердил успешный `sudo -v` в административной записи. Свежая root-owned
host-копия, установка, окно применения, вход/relogin/cold boot и реальный
TTY rollback остаются невыполненными. Системных записей и рестартов не было.
Часть 1А не принята; 1Б не начата.

Review не подтверждает host доступ, активные сессии, GPU или live recovery.
Эти ограничения отражены в acceptance. Временный verifier не добавляется в
production source и не требует установки новых пакетов: при отсутствии
compiler/Qt6Core процедура останавливается. Существующая feature branch
сохраняется локально; публикация и merge не выполняются.

Host-проверки перед установкой: пользователь предоставил `systemctl is-active
sddm.service` → `active` и `loginctl list-sessions`. Видны одна пользовательская
сессия на seat0/tty2 и user manager той же учётной записи. Manager не считается
второй desktop session. Имена, UID, session IDs и PIDs в публичные документы
не включены. Эти данные не доказывают backend greeter или compositor ownership.
Окно применения, host preview, свежая системная копия, установка и runtime
приёмка по-прежнему ожидаются.

Пользователь отложил применение, поскольку занят другой работой. Установка
и перезапуск SDDM не выполняются до возвращения к этой части; разрешена
параллельная подготовка других этапов без изменений работающей сессии.

Пользователь вернулся к проверке и выполнил подготовленный host preflight из
административной учётной записи: SDDM=active, Xorg=available,
Destination=absent, General.DisplayServer=x11 с origin нового local override,
Host preview=PASS. Locale прочитан у работающего daemon. Этот результат
относится к proposed configuration: системный файл ещё не установлен.
Подготовлены локальные операторские install/rollback recipes, извлечённые
из проверенного руководства; установка требует сохранённой работы,
перезапуск/выход в recipes отсутствует. Свежая root-owned копия и установка
ещё ожидаются. Пути частных recipes и backups не публикуются.
