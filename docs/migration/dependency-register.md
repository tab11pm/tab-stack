# Реестр зависимостей миграции tab-stack

Дата аудита: 2026-10-10. Область: текущая установка и выбранные исходники.
Это аудит чтением, а не доказательство прохождения live-сценариев.

## Легенда

Статусы: подтверждено конфигурацией; подтверждено исполнением; заблокировано средой; не проверено; не применимо. Классы: общая Arch; Omarchy CLI/IPC; Hyprland CLI/протокол; локальная tab-stack.

Package metadata подтверждена запросами к локальной базе; работа служб и фактический источник ранее установленного пакета из неё автоматически не следуют.

## Пакеты, обновление и загрузка

### packages.omarchy

- **Функция:** Состав Omarchy
- **Компонент/владелец:** omarchy 4.0.4-1; omarchy-settings 4.0.4-1, оба explicit
- **Запуск/область:** pacman / системные пакеты
- **Зависимость:** Omarchy CLI/IPC
- **Доказательство:** pacman -Qi: omarchy требует Hyprland, UWSM, SDDM, Quickshell, PipeWire, WirePlumber, GNOME Keyring, Limine, snapper и две Limine-интеграции. omarchy-settings требует plymouth.
- **Решение:** убрать после проверки
- **Этап:** 7
- **Предусловия:** Приёмка этапов 1–6, проверка свежей транзакции и сохранение нужных пакетов
- **Проверка:** После удаления проверить boot/login/lock/sleep/portals/update; не обходить reverse dependencies
- **Откат:** Проверенные package archives и восстановление /etc; их наличие пока не подтверждено
- **Статус:** подтверждено конфигурацией.
- **Ограничение:** живые сценарии и недоступные системные пути не проверены; подробности приведены в доказательстве.

### packages.hyprland

- **Функция:** Зависимости Hyprland
- **Компонент/владелец:** hyprland 0.56.2-2, explicit
- **Запуск/область:** SDDM greeter и отдельные session entries
- **Зависимость:** Hyprland CLI/протокол
- **Доказательство:** pacman -Qi: Required By = omarchy и hyprland-preview-share-picker; наличие SDDM greeter command подтверждено предварительно.
- **Решение:** убрать после проверки
- **Этап:** 7
- **Предусловия:** Заменить greeter compositor и учесть share-picker
- **Проверка:** Вход и capture работают без бинарника Hyprland
- **Откат:** Вернуть пакет и SDDM конфигурацию; backup обязателен перед изменением
- **Статус:** подтверждено конфигурацией.
- **Ограничение:** живые сценарии и недоступные системные пути не проверены; подробности приведены в доказательстве.

### packages.desktop-runtime

- **Функция:** Самостоятельные runtime компоненты
- **Компонент/владелец:** quickshell 0.3.1-1; sddm 0.21.0-7; uwsm 0.26.7-1; pipewire 1:1.6.8-1; wireplumber 0.5.17-1; power-profiles-daemon 0.30-1
- **Запуск/область:** Пакеты Arch; конкретные владельцы запуска уточняются
- **Зависимость:** общая Arch
- **Доказательство:** pacman -Qi: перечисленные пакеты explicit; xdg-desktop-portal 1.22.1-2 установлен как dependency, GTK 1.15.3-1, WLR 0.8.2-1 и Hyprland portal 1.4.1-2 explicit. Отдельный пакет xdg-desktop-portal-shojiwm не найден запросом.
- **Решение:** сохранить
- **Этап:** 6
- **Предусловия:** Проверить действующие компоненты и минимальный runtime набор
- **Проверка:** Чистая установка и повторное обновление; пакетная metadata не доказывает runtime
- **Откат:** Сохранить нужные explicit пакеты; portal проверяется также в kisa-shojiwm
- **Статус:** подтверждено конфигурацией.
- **Ограничение:** живые сценарии и недоступные системные пути не проверены; подробности приведены в доказательстве.

### packages.sources

- **Функция:** Происхождение compositor и launcher
- **Компонент/владелец:** kisa-shojiwm 0.1.0.dcb73aa-1; elephant-bin 2.22.1-1; ~/.local/bin/walker-shoji
- **Запуск/область:** ShojiWM session / локальный launcher
- **Зависимость:** локальная tab-stack
- **Доказательство:** pacman -Qo: /usr/bin/shoji_wm принадлежит kisa-shojiwm, elephant принадлежит elephant-bin; walker-shoji существует, пакетного владельца нет. sources.json закрепляет dcb73aa3165e1fb66fca8226f076f3183e38806c и Walker 56c9e2b69e7d2b00f0f9481ae8c89f53810c1de5. Версия пакета согласуется с префиксом pin, но полная provenance бинарника не доказана.
- **Решение:** исследовать до решения
- **Этап:** 6
- **Предусловия:** Зафиксировать рецепт/архив compositor и фактическую сборку Walker
- **Проверка:** Воспроизводимая сборка из pin; отсутствие владельца не означает отсутствие бинарника
- **Откат:** Сохранить работающие binaries и runtime до их замены
- **Статус:** подтверждено конфигурацией.
- **Ограничение:** живые сценарии и недоступные системные пути не проверены; подробности приведены в доказательстве.

### updates.repositories

- **Функция:** Источники пакетов
- **Компонент/владелец:** /etc/pacman.conf: core, extra, multilib, omarchy
- **Запуск/область:** pacman / системная конфигурация
- **Зависимость:** общая Arch; Omarchy CLI/IPC
- **Доказательство:** Локальная pacman -Si: Limine, Quickshell, SDDM из extra; limine-mkinitcpio-hook и limine-snapper-sync из omarchy. Локальная sync DB не обновлялась.
- **Решение:** заменить
- **Этап:** 7
- **Предусловия:** Проверить все нужные пакеты из omarchy и альтернативы перед отключением repo
- **Проверка:** Пакеты разрешаются в оставшихся источниках, полный update проверяется позже
- **Откат:** Вернуть конфигурацию репозиториев и доверенные package archives
- **Статус:** подтверждено конфигурацией.
- **Ограничение:** живые сценарии и недоступные системные пути не проверены; подробности приведены в доказательстве.

### updates.hooks

- **Функция:** Ограничения обновления и миграции
- **Компонент/владелец:** 00-omarchy-update-guard.hook; 10/90-omarchy-hyprland-reload-*.hook; /etc/pacman.d/hooks
- **Запуск/область:** pacman transactions; службы update notification
- **Зависимость:** Omarchy CLI/IPC; Hyprland CLI/протокол
- **Доказательство:** Код omarchy-update-pacman-guard ограничивает прямой system upgrade вне разрешённого entrypoint. Reload hooks вызывают omarchy-hyprland-reload-guard. Пользовательский 99-omarchy-limine.hook копирует EFI бинарник; 90-mkinitcpio-install.hook вызывает Limine helper. Ничего не исполнялось.
- **Решение:** заменить
- **Этап:** 6
- **Предусловия:** Согласовать собственный update path; определить владельцев и backups hooks
- **Проверка:** Проверить выбранный полный update после миграции, без потери initramfs/EFI hooks
- **Откат:** Вернуть hook files; не выполнять upgrade ради проверки аудита
- **Статус:** подтверждено конфигурацией.
- **Ограничение:** живые сценарии и недоступные системные пути не проверены; подробности приведены в доказательстве.

### boot.loader

- **Функция:** Загрузчик и initramfs
- **Компонент/владелец:** limine 12.8.0-1 explicit; limine-mkinitcpio-hook 1.38.0-1.1 dependency; plymouth
- **Запуск/область:** Системная загрузка / package hooks
- **Зависимость:** общая Arch; Omarchy CLI/IPC
- **Доказательство:** Установленные пакеты и hooks подтверждены. /boot имеет режим 700 и недоступен данной среде. omarchy_hooks.conf задаёт encrypt, plymouth, fsck, btrfs-overlayfs и условную KMS обработку; omarchy_resume.conf добавляет resume. Это код, а не доказательство фактически загруженного initramfs.
- **Решение:** сохранить
- **Этап:** 7
- **Предусловия:** Проверить реальную загрузочную цепочку, mounts, encryption и rescue до демонтажа
- **Проверка:** Холодная загрузка и доступ к восстановлению; не менять ядро/loader ради брендинга
- **Откат:** Загрузочный носитель и сохранённые boot configs/EFI/initramfs; доступность не проверена
- **Статус:** подтверждено конфигурацией.
- **Ограничение:** живые сценарии и недоступные системные пути не проверены; подробности приведены в доказательстве.

### boot.snapshots

- **Функция:** Снимки и интеграция с загрузчиком
- **Компонент/владелец:** snapper 0.13.1-3; limine-snapper-sync 1.31.0-1.1, оба dependencies
- **Запуск/область:** Systemd timers / Limine hooks
- **Зависимость:** общая Arch
- **Доказательство:** Пакеты установлены; /etc/snapper/configs существует. Содержимое root policy, реальные snapshots и restore не проверены. Наличие пакета не является гарантией восстановления.
- **Решение:** сохранить
- **Этап:** 7
- **Предусловия:** Определить реальные configs, таймеры и путь восстановления
- **Проверка:** Проверить создание/restore отдельно до удаления зависимостей
- **Откат:** Сохранить configs и проверенные snapshots; не предполагать их наличие
- **Статус:** подтверждено конфигурацией.
- **Ограничение:** живые сценарии и недоступные системные пути не проверены; подробности приведены в доказательстве.

## Официальные источники альтернатив

Проверено 2026-10-10: [Quickshell в Arch extra](https://archlinux.org/packages/extra/x86_64/quickshell/) и [SDDM](https://archlinux.org/packages/extra/x86_64/sddm/files/) доступны независимо от Omarchy. Онлайн-каталог Quickshell показывает 0.3.2-1, установленная версия и локальная sync DB — 0.3.1-1; совместимость обновления ещё не проверена.

[ArchWiki: Limine](https://wiki.archlinux.org/title/Limine) описывает limine-mkinitcpio-hook и limine-snapper-sync как AUR-компоненты. Это возможные источники, не подтверждение равенства рецептов установленным Omarchy-сборкам и не разрешение их заменить.

## Вход и жизненный цикл

### login.greeter

- **Функция:** Экран входа
- **Компонент/владелец:** SDDM; /etc/sddm.conf.d/10-wayland.conf; theme overrides
- **Запуск/область:** display-manager.service → sddm.service
- **Зависимость:** общая Arch; Hyprland CLI/протокол
- **Доказательство:** DisplayServer=wayland, CompositorCommand=start-hyprland -- --config /usr/share/sddm/hyprland.lua. 10-theme.conf и 99-omarchy-login.conf задают omarchy, zz-user-switch-theme.conf задаёт elarun. Несколько overrides; на экране фактическая тема не проверена.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** заменить
- **Этап:** 1
- **Предусловия:** Проверенный TTY/rescue и backup всех SDDM конфигураций
- **Проверка:** Холодная загрузка и greeter без Hyprland; тема выбирается по действующим overrides
- **Откат:** Восстановить SDDM файлы и оставленный бинарник Hyprland

### login.session

- **Функция:** Выбор desktop сессии
- **Компонент/владелец:** /usr/share/wayland-sessions/shojiwm.desktop, владелец kisa-shojiwm
- **Запуск/область:** SDDM user session; Exec=/usr/bin/shoji_wm --tty
- **Зависимость:** локальная tab-stack; Omarchy CLI/IPC
- **Доказательство:** ShojiWM session entry существует. autologin.conf указывает Session=omarchy.desktop; этот entry не найден в просмотренном /usr/share/wayland-sessions. Нельзя заключать, что текущий вход использует autologin: фактическая сессия и другие SessionDir ещё не подтверждены.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** заменить
- **Этап:** 1
- **Предусловия:** Разобрать выбор session/автологин без изменения других пользователей
- **Проверка:** Вход и повторный вход в нужную сессию после reboot
- **Откат:** Восстановить session entry и SDDM backup, запустить ShojiWM из проверенного TTY

### session.environment

- **Функция:** Окружение служб и desktop
- **Компонент/владелец:** shojiwm/scripts/session-portals
- **Запуск/область:** COMPOSITOR.process.once once-per-session
- **Зависимость:** локальная tab-stack; общая Arch
- **Доказательство:** Окружение агента: XDG_CURRENT_DESKTOP=ShojiWM, XDG_SESSION_TYPE=wayland. Скрипт импортирует WAYLAND_DISPLAY, DISPLAY, XDG_CURRENT_DESKTOP, XDG_SESSION_TYPE, QT_QPA_PLATFORM и перезапускает portal services. OMARCHY_PATH не очищается скриптом. Manager environment не прочитан из-за доступа к bus.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** исследовать до решения
- **Этап:** 1
- **Предусловия:** Получить выбранные свойства user manager и проверить session targets
- **Проверка:** Portal/launcher стартуют с актуальным display; после logout нет stale environment
- **Откат:** Восстановить session-portals и исходные unit/config files

### session.lifecycle

- **Функция:** Запуск и завершение
- **Компонент/владелец:** ShojiWM direct session; scripts/logout; HomeSystemCard.qml
- **Запуск/область:** WM и кнопка пользовательской оболочки
- **Зависимость:** локальная tab-stack; общая Arch
- **Доказательство:** Session entry запускает compositor напрямую без UWSM. scripts/logout обращается к native abstract socket, а установленный HomeSystemCard использует loginctl terminate-session по XDG_SESSION_ID. Разные пути; ни один logout не исполнялся.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** исследовать до решения
- **Этап:** 1
- **Предусловия:** Определить canonical shutdown и жизненный цикл graphical-session.target
- **Проверка:** Повторный вход не оставляет старых процессов; завершение не затрагивает другую сессию
- **Откат:** Вернуть старые session scripts и маршруты кнопки

### session.panel

- **Функция:** Панель и её восстановление
- **Компонент/владелец:** COMPOSITOR.process.service dock; shojiwm/scripts/start-shell
- **Запуск/область:** ShojiWM supervisor
- **Зависимость:** локальная tab-stack
- **Доказательство:** restart=on-failure, QS_DISABLE_CRASH_HANDLER=1; start-shell вызывает quickshell --no-duplicate --path ~/.config/shoji-shell. Код source local integrations.env не читался и не исполнялся. Штатный omarchy restart shell обращается к другой shell и Hyprland.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** сохранить
- **Этап:** 1
- **Предусловия:** Сохранить локальные integrations и исключить второй supervisor
- **Проверка:** Сбой панели восстанавливается; locker переживает reload
- **Откат:** Восстановить index.tsx/start-shell из component backup

### session.launcher

- **Функция:** Launcher и search backend
- **Компонент/владелец:** ~/.local/bin/walker-shoji; ~/.config/systemd/user/elephant.service
- **Запуск/область:** launcher script → systemctl --user start elephant.service
- **Зависимость:** локальная tab-stack; общая Arch
- **Доказательство:** Elephant unit ExecStart=/usr/bin/elephant, Restart=on-failure; Installed launcher starts unit then execs walker-shoji. Unit существует, enabled/active manager state недоступен.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** сохранить
- **Этап:** 1
- **Предусловия:** Согласовать user unit и PATH независимо от Omarchy
- **Проверка:** Launcher открывает приложения и повторно стартует backend при необходимости
- **Откат:** Вернуть launcher/unit files и локальный Walker binary

### session.agents

- **Функция:** Autostart и пользовательские targets
- **Компонент/владелец:** polkit KDE explicit WM startup; Omarchy user unit symlinks; GNOME Keyring socket
- **Запуск/область:** WM и systemd user
- **Зависимость:** общая Arch; Omarchy CLI/IPC
- **Доказательство:** В graphical-session.target.wants есть ссылки на omarchy-sleep-lock, migrate-notify, fcitx5, crash-watch; pre.target.wants включает recover-internal-monitor. PipeWire sockets и gnome-keyring socket в /etc/systemd/user; pipewire-session-manager alias указывает wireplumber. KDE polkit autostart ограничен KDE, WM запускает его явно. Enabled links не доказывают active targets.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** заменить
- **Этап:** 1
- **Предусловия:** Разделить полезные службы и Omarchy wrappers; учесть aliases/drop-ins
- **Проверка:** Ровно один agent каждого назначения и корректные start/stop сессии
- **Откат:** Восстановить unit links/configs, не удалять keyring data

### portals.routing

- **Функция:** File picker и screen capture backend
- **Компонент/владелец:** GTK/WLR и ShojiWM portal из kisa-shojiwm
- **Запуск/область:** D-Bus activation; graphical-session.target
- **Зависимость:** общая Arch; локальная tab-stack
- **Доказательство:** shojiwm-portals.conf: default=gtk, ScreenCast=shojiwm, Screenshot=wlr. shojiwm.portal объявляет только ScreenCast, UseIn=ShojiWM. /usr/bin/xdg-desktop-portal-shojiwm и unit принадлежат kisa-shojiwm. Отсутствие отдельного пакета не означает отсутствие portal.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** сохранить
- **Этап:** 4
- **Предусловия:** Проверить D-Bus активацию и runtime discovery в новой учётной записи
- **Проверка:** File picker, screenshot и ScreenCast проверяются приложениями
- **Откат:** Вернуть portal routing и сохранить compositor package


## Ограничения доступа и минимальные проверки

User и system bus: `Operation not permitted`; ActiveState/UnitFileState не получены. Видимость процессов sandbox не является перечнем host-процессов. Чтение /boot ограничено permissions; live lock/sleep/logout не выполнялись.

Команды для обычного пользовательского терминала, только чтение:

```bash
systemctl --user show elephant.service xdg-desktop-portal.service xdg-desktop-portal-shojiwm.service omarchy-sleep-lock.service -p FragmentPath -p DropInPaths -p UnitFileState -p ActiveState -p SubState
systemctl show sddm.service -p FragmentPath -p DropInPaths -p UnitFileState -p ActiveState -p SubState
systemctl --user show graphical-session.target graphical-session-pre.target -p ActiveState -p SubState
systemctl --user show-environment | rg '^(WAYLAND_DISPLAY|DISPLAY|XDG_CURRENT_DESKTOP|XDG_SESSION_TYPE|OMARCHY_PATH)='
ps -eo comm | rg '^(shoji_wm|quickshell|Hyprland|elephant|nm-applet|gnome-keyring-d|polkit-kde-auth)'
```

Из результатов перед публикацией удаляются персональные пути. Выбранное окружение и имена процессов не заменяют проверку ownership конкретной сессии. Для /boot и реальных snapshots требуется отдельная минимальная проверка в доступном пользователю окружении; не снимать ограничения массовым privileged dump.

Порядок конфигураций SDDM сверялся с [sddm.conf(5)](https://man.archlinux.org/man/sddm.conf.5.en): системные defaults, local directory, затем /etc/sddm.conf. Не проверено, какие значения использует уже запущенный процесс. Дата проверки источника: 2026-10-10.

## Функции и локальные различия

### lock.request

- **Функция:** Ручная блокировка
- **Компонент/владелец:** lock/launch.py; LockScreen.qml; lock/SessionLock.qml
- **Запуск/область:** Super+L и кнопка профиля → отдельный Quickshell locker
- **Зависимость:** локальная tab-stack
- **Доказательство:** Launcher ждёт secure, отдельный process и --no-duplicate; SessionLock проверяет secure/requested до PAM. Panel reload не является владельцем locker. --check запускает QML и пишет runtime, поэтому не запускался в аудите.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** сохранить
- **Этап:** 2
- **Предусловия:** Проверить recovery и PAM до live lock
- **Проверка:** Неверный/верный пароль, повторный запрос, hotplug, panel restart
- **Откат:** Вернуть locker files; аварийный orphaned lock требует выхода через TTY, panel restart не обещает recovery

### lock.pam

- **Функция:** Независимая политика пароля
- **Компонент/владелец:** /etc/pam.d/omarchy-lock-password; bundled lock/pam/shoji-lock
- **Запуск/область:** Launcher выбирает первый существующий policy file
- **Зависимость:** Omarchy CLI/IPC; локальная tab-stack
- **Доказательство:** /etc/pam.d/shoji-lock отсутствует; omarchy-lock-password присутствует; swaylock и hyprlock policy отсутствуют. По текущему порядку launcher выбирает Omarchy policy. Реально запущенный locker/PAM выбор не подтверждён. Bundled shoji-lock включает system-auth и system-local-login.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** заменить
- **Этап:** 2
- **Предусловия:** Сохранить rate limiting/account policy и проверить password flow
- **Проверка:** Блокировка работает при отсутствии policy Omarchy
- **Откат:** Восстановить прежнюю PAM конфигурацию до удаления Omarchy; не перезапускать active locker

### sleep.preparation

- **Функция:** Блокировка до suspend
- **Компонент/владелец:** omarchy-sleep-lock.service; logind 20-inhibit-delay.conf
- **Запуск/область:** graphical-session.target → delay inhibitor
- **Зависимость:** Omarchy CLI/IPC; Hyprland CLI/протокол
- **Доказательство:** Unit enabled link существует; helper запрашивает lock/status через Omarchy shell и clamshell через Hyprland helper. InhibitDelayMaxSec=15 в drop-in. Active state неизвестен. Истечение delay inhibitor не отменяет suspend автоматически.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** заменить
- **Этап:** 3
- **Предусловия:** Независимый secure lock и verified recovery
- **Проверка:** Manual suspend/lid возвращают закрытый экран; failure path явный
- **Откат:** Вернуть sleep units и logind drop-in; новую обработку убрать до следующего сна

### idle.control

- **Функция:** Автоблокировка и inhibition
- **Компонент/владелец:** Shoji locker README; omarchy toggle idle state marker
- **Запуск/область:** Требуется самостоятельный idle consumer
- **Зависимость:** Omarchy CLI/IPC; локальная tab-stack
- **Доказательство:** README явно не включает automatic idle/sleep lock. По просмотренному index.tsx нет отдельного idle supervisor; idle={inactive} относится к rendering, не к user inactivity. Поддержка native idle protocols не проверена.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** исследовать до решения
- **Этап:** 3
- **Предусловия:** Проверить idle-notify/idle-inhibit/API композитора
- **Проверка:** Видео/презентации блокируют idle; после закрытия inhibition снимается
- **Откат:** Отключить новые timers/consumer, вернуть ручную блокировку

### outputs.power

- **Функция:** Питание экранов, крышка и ночной режим
- **Компонент/владелец:** src/monitors.ts; hyprsunset.service; omarchy toggle nightlight
- **Запуск/область:** Мониторный IPC и будущая power service
- **Зависимость:** локальная tab-stack; Hyprland CLI/протокол
- **Доказательство:** monitors.ts содержит apply/preview/rollback, но это не доказательство DPMS. Nightlight CLI использует hyprctl hyprsunset. Output-power/gamma protocol support не проверена; по клиентскому коду нельзя считать её отсутствующей.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** исследовать до решения
- **Этап:** 3
- **Предусловия:** Протокольная capability проверка; nightlight планируется также в этапе 5
- **Проверка:** Off/on, resume/hotplug и temperature restore без hyprctl
- **Откат:** Вернуть profile monitors; остановить новый power/gamma consumer

### hardware.applicability

- **Функция:** Матрица оборудования
- **Компонент/владелец:** sysfs power supply; ACPI lid; локальный профиль outputs
- **Запуск/область:** Hardware / compositor
- **Зависимость:** общая Arch; локальная tab-stack
- **Доказательство:** В доступном sysfs есть Battery и Mains, в ACPI lid есть LID; профиль содержит HDMI и eDP. Поэтому батарея/крышка применимы, многомониторная проверка нужна. Профиль не доказывает текущее физическое подключение. Серийные номера не собирались.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** сохранить
- **Этап:** 3
- **Предусловия:** Получить фактический список выходов из host session
- **Проверка:** Проверить крышку с/без внешнего output, battery warnings, hotplug
- **Откат:** Восстановить профиль outputs, сохранить работающую настройку крышки

### network.secrets

- **Функция:** Wi-Fi и хранение секретов
- **Компонент/владелец:** Quickshell Networking; ControlCentre.qml
- **Запуск/область:** Панель → network.connect / connectWithPsk
- **Зависимость:** общая Arch; локальная tab-stack
- **Доказательство:** Код показывает PSK prompt для неизвестной защищённой сети и очищает поле. NetworkManager enabled symlink существует. nm-applet не найден в PATH; наличие другого secret agent/runtime persistence не проверено. Данные соединений и пароли не читались.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** исследовать до решения
- **Этап:** 4
- **Предусловия:** Проверить secure network connect и credential persistence на новой учётной записи
- **Проверка:** Новое подключение, повторный вход, отказ/отмена без раскрытия пароля
- **Откат:** Вернуть network UI; существующие NM connection secrets не изменять

### audio.stack

- **Функция:** Звук и микрофон
- **Компонент/владелец:** PipeWire/WirePlumber, Services.qml, pavucontrol
- **Запуск/область:** Socket activation; panel via PipeWire
- **Зависимость:** общая Arch; локальная tab-stack
- **Доказательство:** PipeWire sockets enabled links, wireplumber alias; Services.qml использует default sink, outputs, volume; горячие клавиши wpctl. Нет зависимости от hyprctl в этих маршрутах. Реальный звук/микрофон не проверялся.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** сохранить
- **Этап:** 4
- **Предусловия:** Проверить sockets/session agents и default devices
- **Проверка:** Выходы/микрофон, mute/volume, смена устройства
- **Откат:** Вернуть выбранные sound configs/units; не удалять shared runtime

### bluetooth.stack

- **Функция:** Bluetooth и pairing
- **Компонент/владелец:** Quickshell Bluetooth; bluedevil-wizard; bt-agent.service
- **Запуск/область:** Panel + graphical-session.target
- **Зависимость:** общая Arch; Omarchy CLI/IPC
- **Доказательство:** bt-agent unit использует NoInputNoOutput; его комментарий рассчитывает на pairable gating панели Omarchy. Таб-оболочка использует Bluetooth UI/мастер; реальное pairing и ownership agent не проверены. Это требует проверки, а не вывода о текущей уязвимости.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** исследовать до решения
- **Этап:** 4
- **Предусловия:** Проверить текущие pairable/agent states и избежать дублей
- **Проверка:** Pair/forget/reconnect с явным участием пользователя
- **Откат:** Вернуть unit/UI, сохранить paired devices database

### auth.polkit-keyring

- **Функция:** Повышение прав и secret storage
- **Компонент/владелец:** polkit-kde-agent; gnome-keyring-daemon socket/service; SDDM PAM
- **Запуск/область:** WM startup / user socket activation
- **Зависимость:** общая Arch
- **Доказательство:** WM явно запускает KDE polkit. GNOME Keyring socket enabled; service components pkcs11,secrets. Просмотренные PAM sddm и sddm-autologin не содержат прямой pam_gnome_keyring строки; transitive includes и runtime unlock не доказаны.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** исследовать до решения
- **Этап:** 4
- **Предусловия:** Разобрать activation/unlock path без чтения keyring содержимого
- **Проверка:** Polkit dialog и keyring после обычного входа/автологина
- **Откат:** Вернуть PAM/unit configs; не удалять credential stores

### power.profiles

- **Функция:** Профили питания
- **Компонент/владелец:** power-profiles-daemon 0.30-1; installed Power.qml
- **Запуск/область:** Панель → powerprofilesctl
- **Зависимость:** общая Arch; локальная tab-stack
- **Доказательство:** powerprofilesctl доступен; installed Power.qml читает и меняет профили. В опубликованном checkout dotfiles/config/shoji-shell/Power.qml отсутствует. Работа на чистой установке не подтверждена.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** исследовать до решения
- **Этап:** 4
- **Предусловия:** Отдельно перенести reviewed power feature в source; проверить prerequisites
- **Проверка:** Profiles list/set и battery status без Omarchy
- **Откат:** Сохранить installed Power.qml и service; не заменять source автоматически

### input.xwayland

- **Функция:** Методы ввода и X11 приложения
- **Компонент/владелец:** xorg-xwayland dependency; fcitx5; omarchy-fcitx5.service
- **Запуск/область:** Compositor native backend / user target
- **Зависимость:** общая Arch; Omarchy CLI/IPC
- **Доказательство:** fcitx5 доступен; Omarchy unit содержит session ordering и WAYLAND_DISPLAY condition. xwayland-satellite не найден в PATH, но xorg-xwayland есть в dependency compositor. Это не доказательство отсутствия XWayland. Keyboard.qml uses native Shoji IPC.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** исследовать до решения
- **Этап:** 4
- **Предусловия:** Разобрать фактический native XWayland/backend и сохранить compose/input поведение
- **Проверка:** Русский/English, compose, X11 GUI, повторный вход
- **Откат:** Вернуть input env/unit files и binaries

### appearance.theme

- **Функция:** Темы, шрифты и wallpaper
- **Компонент/владелец:** Theme.qml; Ghostty config; Omarchy state/theme hooks
- **Запуск/область:** Quickshell/Ghostty; Omarchy theme CLI
- **Зависимость:** локальная tab-stack; Omarchy CLI/IPC
- **Доказательство:** Theme.qml фиксирует Catppuccin/Noto Sans; Ghostty отдельная Catppuccin theme и GTK CSS. Просмотренные theme hooks не содержат tab-stack адаптера. Nightlight требует capability investigation.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** заменить
- **Этап:** 5
- **Предусловия:** Сохранить пользовательские profiles и согласовать собственные settings
- **Проверка:** Theme/font changes применяются последовательно без Omarchy IPC
- **Откат:** Вернуть фиксированную палитру и terminal config; wallpapers локально сохраняются

### capture.screenshot

- **Функция:** Скриншоты
- **Компонент/владелец:** scripts/screenshot-region и screenshot-all; Flameshot/grim/slurp/wl-copy
- **Запуск/область:** Hotkeys WM → scripts
- **Зависимость:** локальная tab-stack; общая Arch
- **Доказательство:** Регион определяет monitor через Shoji IPC и Qt screen order, затем Flameshot; fallback grim/slurp. Fullscreen grim и wl-copy. Installed screenshot-region отличается от source, не синхронизирован. Omarchy capture scripts содержат hyprctl.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** сохранить
- **Этап:** 5
- **Предусловия:** Проверить локальные различия и native capture protocols
- **Проверка:** Region/output/all, clipboard, scaling; live capture отложен
- **Откат:** Вернуть installed scripts из backup, сохранить tools

### capture.screencast

- **Функция:** Запись и screen sharing
- **Компонент/владелец:** ShojiWM portal; OBS; GPU Screen Recorder
- **Запуск/область:** Applications → portal / recorder
- **Зависимость:** локальная tab-stack; общая Arch; Hyprland CLI/протокол
- **Доказательство:** obs и gpu-screen-recorder присутствуют. Это уже возможные независимые инструменты, не отсутствующая функция по определению. Portal declares ScreenCast; Omarchy recording helpers содержат hyprctl/indicator IPC. Capability/selection/browser/recording не проверены.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** исследовать до решения
- **Этап:** 5
- **Предусловия:** Проверить existing recorder прежде чем писать новый; подтвердить portal support
- **Проверка:** OBS/браузер, stop/indicator; отдельное окно не обещается без проверки
- **Откат:** Вернуть portal routing и recorder config

### source.drift

- **Функция:** Различия installed/source
- **Компонент/владелец:** Выбранные 16 файлов и исходный git status
- **Запуск/область:** Отдельная публикация и installation
- **Зависимость:** локальная tab-stack
- **Доказательство:** 14 из 16 whitelist files одинаковы, screenshot-region отличается, Power.qml отсутствует в source. index.tsx и monitors.ts совпадают с рабочим checkout, но checkout содержит tracked/untracked несохранённые изменения; это не равно HEAD. Secret/runtime файлы не сравнивались.
- **Статус:** подтверждено конфигурацией
- **Ограничение:** Runtime state не подтверждён; D-Bus и процессы host недоступны из среды аудита.
- **Решение:** исследовать до решения
- **Этап:** 6
- **Предусловия:** Сохранить локальные changes отдельно; feature-by-feature review
- **Проверка:** Чистая установка не теряет проверенные функции; public privacy pass
- **Откат:** Component backups и исходный checkout без массового копирования


## Выводы для этапа 1

Первое изменение должно закрыть greeter/session lifecycle: независимый greeter compositor, корректный выбор ShojiWM, импорт окружения и управление session targets. SDDM можно сохранить. Конкретный greeter backend выбирается после проверки TTY/recovery; автоматический переход на другой display manager не нужен.

До изменений входа требуется вручную подтвердить доступ к TTY и вернуть отсутствующие manager-state результаты. В этапах 2–3 сначала отделить PAM и lock/sleep path. Bootstrap и обновления нельзя свести к удалению пакета Omarchy: сохраняются boot hooks и источники необходимых интеграций.

Безопасная будущая capability проверка: из обычного терминала получить только имена globals Wayland через доступный inspection tool (например wayland-info), сравнить idle-notify, idle-inhibit, output-power, gamma-control и ext-session-lock с API/кодом pinned ShojiWM. Данная проверка не выполнена; не запускать blocker/check GUI автоматически.
