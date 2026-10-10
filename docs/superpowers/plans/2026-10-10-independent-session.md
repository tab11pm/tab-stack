# Independent tab-stack session — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Preserve the selected native method: one implementer, one independent final review before host installation.

**Goal:** Добавить выбираемую сессию tab-stack с управляемыми startup/readiness/cleanup, собственными user services и восстановимым возвратом к ShojiWM.

**Architecture:** Python wrapper запускает ShojiWM и ожидает завершение. Readiness helper получает настоящий display из compositor environment, подтверждает ownership, импортирует выбранные переменные и запускает отдельный target. ShojiWM продолжает управлять панелью и polkit; старый запуск работает через прежнюю ветку.

**Tech Stack:** Python 3 standard library/unittest, systemd user, loginctl, D-Bus activation, ShojiWM TSX, Quickshell QML, desktop-file-validate.

**Spec:** [Согласованная спецификация](../specs/2026-10-10-independent-session-design.md).

## Global Constraints

- Не запускать graphical-session.target или graphical-session-pre.target вручную; не менять packaged units.
- Одна графическая сессия на UID: при другой сессии, включая legacy, отказ без её завершения. Другие пользователи не затрагиваются.
- Не менять autologin, PAM/lock/sleep, boot chain, package sources и состав установленных пакетов.
- Сохранять COMPOSITOR.process.service dock, restart=on-failure и QS_DISABLE_CRASH_HANDLER=1; второй supervisor панели запрещён.
- Не читать integrations.env или private accounts; manager environment обрабатывать только по whitelist, не выводить/сохранять полный набор. Runtime ownership metadata хранится приватно, не коммитится.
- Session component opt-in; пользовательский installer не вызывает sudo, daemon-reload, start/stop или logout.
- Существующие ShojiWM entry и legacy startup ветка остаются пригодными для возврата. При первом переходе отдельно остановить прежний Elephant после выхода из старой сессии.
- Не копировать checkout целиком поверх установленного профиля; live integration — минимальная проверяемая правка двух файлов с backup.
- Работать в отдельном git worktree от согласованного HEAD. Оригинальный checkout с unrelated dirty changes сохраняется; не переносить их в коммиты этой части.
- Любой недоступный host результат имеет статус pending. Source/staging pass не заменяет runtime acceptance.

## Review Focus

1. Другой graphical login того же UID или переиспользованный PID: новый wrapper не должен присвоить чужую сессию или остановить её services.
2. Portal activation до готовности нового display: нельзя считать start target достаточным; services должны получить новое окружение, а cleanup касаться только собственного lease.
3. Нет readiness, compositor падает или helper сообщает ошибку: partial startup и stale display не остаются скрыто работающими.
4. Reload TSX, legacy entry или установленные monitor changes: target не останавливается при reload; старый вход и unrelated configuration сохраняются.
5. Существующий unit/drop-in, symlink, изменённый после установки файл или нестандартный Exec path: установка/откат не теряют чужое содержимое и не запускают shell substitution.

## Файлы и интерфейсы

Runtime source:

- `dotfiles/config/shojiwm/scripts/session_state.py`: ownership, runtime state, выбранное окружение и проверки logind/proc.
- `dotfiles/config/shojiwm/scripts/session_lifecycle.py`: команды start/ready/check, process supervision и service lease.
- `dotfiles/bin/tab-stack-session`: thin user launcher Python module по XDG_CONFIG_HOME.
- `dotfiles/config/systemd/user/tab-stack-session.target`, `elephant.service` и четыре `*.service.d/tab-stack-session.conf` для portal units.
- `dotfiles/system/session/tab-stack.desktop.in`: публичный template с placeholder Exec; частный rendered entry устанавливается отдельно на host.

Integration/install:

- Modify `dotfiles/config/shojiwm/src/index.tsx`: выбор ready helper только при wrapper marker; legacy session-portals остаётся.
- Modify `dotfiles/config/shoji-shell/HomeSystemCard.qml`: logout через существующий native helper без требования XDG_SESSION_ID.
- Modify `dotfiles/scripts/install.py`: explicit component session с ограниченным списком путей.
- Create `dotfiles/scripts/migrate-session.py`: preview/apply/rollback точечных user changes и rendered desktop entry; без system writes.
- Create `dotfiles/docs/session.md`: операторская последовательность и приёмка.

Tests: `dotfiles/tests/test_session_state.py`, `test_session_lifecycle.py`,
`test_session_install.py`, `test_session_integration.py`.
Команда suite: `python3 -m unittest discover -s dotfiles/tests -p 'test_session_*.py' -v`.
Внешние команды тестируются через fixture adapter, без доступа к рабочему bus;
fake adapters живут в tests. Реальные subprocess/socket/file semantics проверяются
на временных worker processes и fixtures; не добавлять fake-mode runtime flags.

### Task 1: Ownership и выбранное окружение

**Files:** Create `session_state.py`, `test_session_state.py` по путям выше.

**Interfaces:**
- `OwnerIdentity(pid: int, uid: int, start_ticks: int, boot_id: str, token: str, session_id: str)` — dataclass.
- `SessionRecord(owner: OwnerIdentity, compositor: OwnerIdentity | None, phase: str, services: tuple[str, ...])` — dataclass; `load_session(runtime: Path) -> SessionRecord`.
- `load_owner(runtime: Path) -> OwnerIdentity`; `owner_is_current(owner: OwnerIdentity, proc_root: Path) -> bool`.
- `selected_environment(env: Mapping[str, str]) -> dict[str, str]`.
- `conflicting_sessions(records: list[dict[str, str]], uid: int, current_session_id: str) -> list[str]`.
- `verify_wayland_peer(display: str, runtime: Path, uid: int, compositor: OwnerIdentity) -> None`.
- Runtime paths: `$XDG_RUNTIME_DIR/tab-stack-session/{owner.json,lock,ready.json}`; directory 700, files 600, reject symlink/foreign owner.

- [ ] Написать RED tests: uid/start_ticks/boot_id mismatch → false; malformed/symlink owner → refusal; второй same-UID wayland/x11 login → conflict, manager/TTY/other UID → no conflict.
- [ ] Добавить тест selected environment: только WAYLAND_DISPLAY, DISPLAY, XDG_CURRENT_DESKTOP, XDG_SESSION_TYPE, QT_QPA_PLATFORM; обязательны непустой WAYLAND_DISPLAY, desktop=ShojiWM, type=wayland; отсутствующие optional keys возвращаются как пустые для очистки старых values. Credential-like extra key исключён.
- [ ] Добавить SO_PEERCRED test с временным Unix socket и proc fixtures: peer uid/PID/start identity обязаны совпадать с дочерним compositor; неправильный executable/owner отвергается.
- [ ] Выполнить `python3 -m unittest discover -s dotfiles/tests -p test_session_state.py -v`. Expected: RED по отсутствующему модулю/функциям, после минимальной реализации — PASS.
- [ ] Для `/proc/PID/stat` отделять comm по последней `)`; starttime — поле 22. Boot ID из `/proc/sys/kernel/random/boot_id`. Не доверять одному PID или marker token.
- [ ] Logind adapter перечисляет IDs, затем читает только User/Type/Class/State/Leader для каждой сессии; текущая incoming session должна принадлежать UID и быть проверена отдельно. Не сохранять имена пользователей или полный вывод.
- [ ] Commit только module/tests: `Add session ownership and environment validation`.

### Task 2: Собственный target и portable services

**Files:** Create user units/drop-ins, `test_session_lifecycle.py` unit-contract cases.

**Interfaces:** `SESSION_UNITS` = elephant.service, xdg-desktop-portal.service,
xdg-desktop-portal-gtk.service, xdg-desktop-portal-wlr.service,
xdg-desktop-portal-shojiwm.service. `SESSION_TARGET` = tab-stack-session.target.

- [ ] RED unit-contract tests: target Wants содержит ровно SESSION_UNITS; нет Requires/BindsTo/Wants старых session targets или Omarchy units; Elephant ExecStart=/usr/bin/elephant, Restart=on-failure, RestartSec=2, PartOf=tab-stack-session.target.
- [ ] Создать target с Description, Wants=SESSION_UNITS и StopWhenUnneeded=no. Не включать его в default.target и не добавлять WantedBy=graphical-session.target.
- [ ] Создать четыре portal drop-ins: `[Unit]` с дополнительным `PartOf=tab-stack-session.target`; packaged relationships не reset. Для всех управляемых services задать пользовательский TimeoutStopSec=10s, сохранив остальные свойства.
- [ ] Проверить graph assertion: stop собственного target распространяется на все пять services; audio, keyring, default.target и другие пользовательские units в lease не входят.
- [ ] Run unit-contract tests. Expected: RED до файлов, PASS после; выполнить offline `systemd-analyze --user verify` с SYSTEMD_UNIT_PATH, содержащим source user directory и `/usr/lib/systemd/user`. Expected: нет новых unit errors; warnings/errors не скрываются.
- [ ] Commit: `Define independent session target and service ownership`.

### Task 3: Wrapper, readiness и bounded cleanup

**Files:** Create `session_lifecycle.py`, `dotfiles/bin/tab-stack-session`; extend lifecycle tests.

**Interfaces:**
- CLI: `start`, `ready`, `check`; exit 0 только при подтверждённом успехе, 1 при отказе; check не меняет state.
- `start_session(backend: SessionBackend, env: Mapping[str, str]) -> int`; `ready_session(backend: SessionBackend, env: Mapping[str, str]) -> None`; `cleanup_session(backend: SessionBackend, owner: OwnerIdentity) -> None`.
- `SessionBackend` protocol: `sessions() -> list[dict[str, str]]`, `identity(pid: int) -> OwnerIdentity`, `unit_states(names: tuple[str, ...]) -> dict[str, str]`, `selected_manager_environment() -> dict[str, str]`, `command(argv: list[str], env: Mapping[str, str] | None, timeout: float) -> subprocess.CompletedProcess[str]`, `spawn(argv: list[str], env: Mapping[str, str]) -> subprocess.Popen`. Production implementation использует logind/systemd/proc; fixture implementation находится в tests.
- Wrapper exports TAB_STACK_SESSION_TOKEN только своему compositor, marker содержит точную child identity. Parent identity и compositor identity хранятся раздельно в SessionRecord. Parent удерживает flock до окончания cleanup; JSON updates atomic.
- Owner phase: starting → ready → stopping; ошибка cleanup → failed-cleanup marker, который блокирует следующий start до проверенного recovery.

- [ ] RED tests: duplicate flock, conflicting login, stale/reused owner, symlink state, wrong ready caller, отсутствующий display; во всех случаях чужие процессы/units не меняются.
- [ ] Implement preflight: проверить доступный logind/user bus и unit provenance, SESSION_UNITS inactive, собственного target active нет; неизвестный active legacy backend → отказ с объяснением migration prerequisite.
- [ ] Запустить только `/usr/bin/shoji_wm --tty`, сохранить child identity и ожидать marker от ready helper до 90 секунд. Child exit, TERM/INT или timeout обрабатываются как разные причины; исходный нормальный exit code сохраняется.
- [ ] Ready helper проверяет caller against child ancestry и Wayland peer, использует Task 1 environment contract. Обновить D-Bus activation и systemd user выбранными values; никаких Shell=True или полного environment dump.
- [ ] После импорта start собственного target; ранее inactive baseline разрешает reconcile только SESSION_UNITS, активированные во время собственного startup. Restart выбранных services после нового environment, проверить ActiveState и ошибки jobs, затем atomically сообщить ready parent. Одна команда ограничена 10 секундами; полный readiness budget 90 секунд.
- [ ] RED/ GREEN tests: один service failed при active target → startup failure; D-Bus activation до ready получает исправленное environment; timeout и смерть child → cleanup; второй ready для того же живого owner → идемпотентность.
- [ ] Cleanup останавливает собственный target и проверяет SESSION_UNITS. Завершение собственного child по timeout: TERM, ожидание 5 секунд, KILL только этого unreaped child при совпадении identity. Не использовать pkill, terminate-user или systemd-user exit.
- [ ] Удалять только совпадающие owned display values из systemd environment. D-Bus activation выставляет выбранные display/type/desktop/Qt keys пустыми для invalidation; не восстанавливать dead display. Изменившееся foreign environment не очищается.
- [ ] Fixture tests нормального/аварийного cleanup, command timeout, foreign state change и failed-cleanup recovery. Expected: собственные leases освобождены либо явный failed state, чужое содержимое сохранено; cleanup budget 30 секунд; timeouts каждого следующего command ограничены оставшимся общим budget.
- [ ] Run session suite. Expected: PASS; commit `Implement session readiness and shutdown lifecycle`.

### Task 4: Integration без изменения legacy входа

**Files:** Modify index.tsx и HomeSystemCard.qml; create `test_session_integration.py`.

**Interfaces:** TSX session-portals registration выбирает `python3 scripts/session_lifecycle.py ready`
только при TAB_STACK_SESSION_TOKEN; иначе старый `bash scripts/session-portals`.
QML logout запускает `python3 ../shojiwm/scripts/logout` через Qt-resolved file path.

- [ ] RED tests двух startup веток: marker отсутствует → прежняя команда; marker задан → ready helper; helper сам валидирует marker. Reload не содержит stop собственного target.
- [ ] Сделать только этот условный выбор команды в существующей once-per-session registration. Dock, polkit, monitors и прочие registrations не переносить.
- [ ] QML requestAction/logout больше не требует XDG_SESSION_ID; confirm запускает существующий native helper. Reboot/poweroff действия сохраняются. stderr helper отображать как отказ, не подменять его массовым kill/loginctl fallback.
- [ ] Test native-helper argv resolution, отсутствие logout при простом requestAction, nonzero exit → error; click/confirmation не запускают два Process одновременно.
- [ ] Run session suite и `qmllint -I dotfiles/config/shoji-shell dotfiles/config/shoji-shell/HomeSystemCard.qml`. Expected: PASS/no new errors against baseline; существующие diagnostics перечислить.
- [ ] TypeScript gate: `tsc --noEmit -p dotfiles/config/shojiwm/tsconfig.json` при наличии локального compiler/runtime imports. Сейчас tsc в PATH не обнаружен: перед gate найти уже установленный compiler, не скачивать через npx. Если недоступен, явно остановить typecheck claim и зафиксировать missing prerequisite до host application.
- [ ] Commit только scoped changes/tests: `Integrate native session readiness and logout`.

### Task 5: Explicit installer, точечная миграция и rollback

**Files:** Modify install.py; create migrate-session.py, desktop template, test_session_install.py.

**Interfaces:**
- `install.py --component session`: копирует только runtime modules, launcher, target, Elephant unit и четыре portal drop-ins; shojiwm/shoji-shell компоненты автоматически session не включают.
- `migrate-session.py [--apply | --rollback MANIFEST] [--target-home PATH]`: preview default; два известных TSX/QML hunks, checksum manifest и private rendered tab-stack.desktop. Никаких `/etc`/`/usr/local` writes.
- `render_desktop_entry(executable: Path) -> str`: Name=tab-stack, Type=Application, DesktopNames=ShojiWM, Exec=quoted absolute launcher path + ` start`; template `@TAB_STACK_SESSION_EXEC@` не устанавливается как executable entry.

- [ ] RED isolated-home tests: default/component preview пишет 0 файлов; legacy component selection не включает user units; session paths точны; unrelated files и opt-in settings сохраняются.
- [ ] Implement session component как ограниченный file mapping, включая parent directory creation, executable launcher mode и backup каждого existing file; symlinks/unexpected config → отказ без silent replacement.
- [ ] Migration tests: установленный index с дополнительным monitors code и QML с пользовательским оформлением → меняются только утверждённые hunks; неизвестная/двойная форма hunk → no writes. Preflight всех files до первой записи, при I/O failure transaction rollback собственных изменений.
- [ ] Migration backup: original presence/mode/owner/checksum, previous copy, installed checksum; private dir 700, manifest 600. Rollback отвергает later edits и restore symlink ambiguity, не восстанавливает весь профиль.
- [ ] Desktop path tests: пробелы, Unicode, quotes/backslash/$/percent; `=` и linebreak в executable path отвергаются. Правила quoting по [Desktop Entry Exec](https://specifications.freedesktop.org/desktop-entry/latest/exec-variables.html); shell expansion не используется.
- [ ] Run session suite, desktop-file-validate на rendered fixture entries, isolated installer checks подходящие для session component. Expected: PASS и 0 host service calls. Full existing check-install.py запускать только с наличием его declared shader/runtime prerequisites, не писать over live home.
- [ ] Commit: `Add opt-in session installation and guarded migration`.

### Task 6: Operator guide и независимое review до host writes

**Files:** Create dotfiles/docs/session.md; update install/architecture/recovery docs только scoped текстом.

- [ ] Документировать preview → staging → review → current-file backup → user install/migration → rendered entry validation → administrative single-entry install → application → acceptance → guarded rollback.
- [ ] После выхода из старой графической сессии войти desktop user в TTY, проверить отсутствие второго graphical login того же UID, отдельно остановить прежний Elephant и оговорённые portal units. До этого live services не трогать; при неизвестном unit/drop-in происхождении остановить только миграцию.
- [ ] User daemon-reload и install не start target. Administrative entry destination: `/usr/local/share/wayland-sessions/tab-stack.desktop`, root:root 644, обычный файл с fresh backup/manifest; symlink/unreviewed existing destination → отказ. Autologin и packaged ShojiWM entry сохраняются.
- [ ] Точный installed baseline, renderer Exec path и helper availability проверяются до создания новой system entry. Privileged action читает только checked rendered entry из private home; home modes не расширяются.
- [ ] При application выбрать tab-stack; failure возвращает пользователя к legacy entry/TTY с доступным backup. Системный restart/выход согласуются отдельно, agent не запускает их автоматически.
- [ ] Run session suite, scoped privacy checker на index blobs, shell syntax/links и offline units/desktop validation. Expected: PASS; ограничения compiler/host доступа перечислены, не скрыты.
- [ ] Commit `Document independent session deployment and recovery`; один fresh reviewer читает весь range, spec/plan и Review Focus. Исправить Critical/Important одним verified pass до installation; runtime proof reviewer не заменяет.

### Task 7: Host применение и отдельная приёмка

**Files:** Installed scoped user files и новая system entry; acceptance/roadmap по подтверждённым фактам.

- [ ] Получить fresh host metadata, selected unit states/provenance, display ownership и список graphical sessions. Не считать старые результаты свежими; secret outputs не публиковать.
- [ ] При разрешённом user apply сохранить component backup и заменить только approved files. Проверить private preserved settings и unchanged monitors code; не делать wholesale install.
- [ ] Administrative install выполнить оператором при недоступном sandbox `/usr/local`. Проверить bytes/mode/owner и rendered Exec. Pending action не отмечать installed.
- [ ] В согласованное окно выполнить переход через проверенный native logout helper и TTY first-migration prerequisite из Task 6, затем выбрать tab-stack. Не отключать legacy Omarchy sleep units ради успешного теста.
- [ ] Host приёмка: target active, все SESSION_UNITS active с текущим environment; один panel/polkit/Elephant; file picker/launcher работают; graphical-session targets не подняты новой схемой; Omarchy units не подтянуты.
- [ ] Logout: собственный target/services inactive, dead display invalidated, cleanup marker корректен; TTY/default/audio/keyring manager сохранены. Повторный вход не дублирует процессы; TSX reload не выполняет cleanup.
- [ ] Проверить отказ panel и её recovery отдельно от locker после готовности соответствующего безопасного сценария. Cold boot и clean-user installation имеют отдельные recorded results; не объявлять успешными по relogin.
- [ ] Проверить доступность и guards точечного rollback; planned recovery rehearsal выполнять отдельно при согласованном окне. Сохранить backups до приёмки; часть 1А с оставшимися проверками не закрывать автоматически.
- [ ] Commit только status docs: `Record independent session acceptance results`. Если live prerequisites отсутствуют, завершить source/staging подготовку со статусом pending deployment, не закрывать этап 1Б.

## Handoff

Спецификация 1Б согласована пользователем. План подготовлен для просмотра;
runtime implementation, user-manager mutations и system entry installation
ещё не выполнялись. Метод сохраняется: native с одним независимым review.
После согласования этого плана начать execution в отдельном worktree.
