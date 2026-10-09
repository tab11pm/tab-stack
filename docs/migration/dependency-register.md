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
