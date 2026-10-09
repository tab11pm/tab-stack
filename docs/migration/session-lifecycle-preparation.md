# Подготовка 1Б без переключения экрана входа

Дата: 2026-10-10. Это дополнительный аудит чтением, не согласованная
спецификация нового lifecycle и не отчёт о работающей независимой сессии.
Пользователь отложил применение X11 greeter, поскольку занят другой работой,
и разрешил продолжить подготовку других частей миграции.

Связи: [дорожная карта](../superpowers/specs/2026-10-10-independent-tab-stack-roadmap.md),
[реестр](dependency-register.md), [приёмка](acceptance.md).

## Что можно делать параллельно

| Часть | Подготовка сейчас | Приёмка позднее |
| --- | --- | --- |
| 1Б: session lifecycle | Карта владельцев, startup/shutdown, окружение, unit dependencies и source gaps | Вход, выход, повторный вход, отказ панели, проверка manager state |
| 2: locker | Разбор существующего locker, PAM fallback и требований к независимому PAM service | Установка PAM и проверка блокировки после готовности recovery |
| 4: службы | Поиск Omarchy wrappers, описание полезных функций и условий запуска | Сеть, pairing, звук, keyring и агенты в самостоятельной сессии |
| 6: переносимость | Сверка publication source, installer scope и состава зависимостей | Установка и обновление на чистом Arch после готовности обязательных функций |

Автосон и удаление Omarchy/Hyprland не продвигаются до приёмки соответствующих
зависимостей. Подготовка части не означает выполнение её runtime требований.

## Подтверждённая карта владельцев

| Компонент | Сейчас по прочитанным файлам | Что требуется выяснить или подготовить |
| --- | --- | --- |
| Вход | Packaged `shojiwm.desktop` запускает `/usr/bin/shoji_wm --tty` напрямую | Отдельная portable session entry и владелец старта/остановки; desktop entry ещё не заменяется |
| Окружение | `src/index.tsx` регистрирует `session-portals` как once-per-session; script импортирует display/desktop/type/Qt environment в D-Bus и systemd user | Обработка отсутствующих и устаревших значений, включая состояние после logout и несколько сессий одного пользователя |
| Portals | Script последовательно перезапускает GTK/WLR, затем основной portal | Проверить необходимость каждого restart, доступность backend и порядок готовности; script сейчас не исполняется |
| Панель | ShojiWM `process.service("dock")`, restart=on-failure; start-shell запускает Quickshell --no-duplicate | Сохранить одного supervisor и локальные opt-in настройки; проверить cleanup при выходе и отдельный locker |
| Polkit | Явный once-per-session запуск KDE authentication agent | Доказать отсутствие второй autostart-копии и корректное завершение |
| Launcher | Script запускает Elephant user service, затем локальный Walker | Сделать unit частью переносимой установки после утверждения дизайна; согласовать session scope и готовность environment |
| Выход через helper | `scripts/logout` проверяет владельца Wayland socket и executable, затем обращается к native abstract shutdown socket | Сопоставить с кнопкой shell; выбрать canonical путь после проверки возможностей текущего бинарника |
| Выход через shell | `HomeSystemCard.qml` использует loginctl terminate-session по XDG_SESSION_ID | Проверить наличие актуального session ID, завершение нужной сессии и последствия для user services |

Порядок регистраций процессов в TSX сам по себе не доказывает, что импорт
окружения завершён до запуска панели или агента. Прочитанный ProcessController
регистрирует записи; `once` и `service` возвращают void. Это вопрос к runtime
и механизму готовности, а не подтверждённая ошибка запуска.

`graphical-session.target` и `graphical-session-pre.target` в установленном
systemd имеют RefuseManualStart=yes и StopWhenUnneeded=yes. Предложение
«вручную start graphical-session.target» не является готовым решением.
До выбора новой схемы нужно проверить реальные targets и зависимости на host.

## Полезные службы и обёртки Omarchy

Прочитаны существующие user wants links и packaged units. Ссылки не доказывают
active state. Не отключать их списком только из-за названия.

| Unit | Реальный запуск/условие | Граница будущего решения |
| --- | --- | --- |
| omarchy-fcitx5 | `/usr/bin/fcitx5 --disable notificationitem`; ConditionEnvironment=WAYLAND_DISPLAY, PartOf=graphical-session.target | Полезный input method не требует Omarchy CLI; переносить функцию с проверкой окружения и единственного экземпляра |
| omarchy-crash-watch | Omarchy CLI, session target и local toggle | Дополнительная функция; независимый crash notifier проектировать отдельно при необходимости |
| omarchy-migrate-notify | Omarchy CLI и каталог migrations | Не нужен как обязательная функция самостоятельного tab-stack; removal относится к дальнейшей уборке |
| omarchy-recover-internal-monitor | Omarchy CLI и toggle внутреннего монитора | Сопоставить с native monitor handling; сохранение/откат monitor profiles обязательно |
| omarchy-sleep-lock | Omarchy sleep monitor, OMARCHY_PATH, WAYLAND_DISPLAY и waitenv unit | Заменять только в этапе 3 после независимого locker; преждевременно отключать нельзя |
| bt-agent | `/usr/bin/bt-agent -c NoInputNoOutput`; Bluetooth availability | Комментарий unit связывает безопасность auto-accept с pairable state панели Omarchy; проверить управление pairable в tab-stack перед переносом |

Bluetooth здесь отмечен как зависимость поведения, не как доказанный текущий
дефект. Состояние адаптера, агента и pairing не проверялось.

## Разрыв между установленным профилем и publication source

Установленный `~/.config/systemd/user/elephant.service` существует. В текущем
publication tree нет этого unit: `dotfiles/config/elephant/` содержит provider
configs, а installer выбирает config directory, не user unit. Следовательно,
копирование этих configs не воспроизводит наличие Elephant service. Это
конкретная задача подготовки переносимого launcher, а не повод сейчас
устанавливать сервис поверх работающего профиля.

Локальные службы AI-инструментов вне desktop lifecycle остаются вне миграции.
Не копировать их абсолютные пути, account settings или environment в публикацию.
Содержимое `integrations.env` не читается и не переносится.

## Недостающие доказательства перед спецификацией 1Б

- Active/SubState session targets, relevant user services и waitenv units.
- Whitelisted manager environment против окружения текущей графической сессии.
- Ownership и количество panel/polkit/input-method/portal экземпляров.
- Shutdown contract текущего ShojiWM и cleanup контролируемых процессов.
- Поведение user manager при logout, включая linger и другую сессию того же UID.

Эти сведения проверяются позднее из терминала desktop user. `systemctl --user`
из административной учётной записи проверял бы её manager, а не manager нужного
desktop user. Полный manager environment, credentials и runtime logs
не публикуются. Сбой доступа из sandbox не означает, что сервис остановлен.

## Границы результата

Системная установка greeter, применение, logout/relogin, lock/suspend,
отключение units и package removal не выполнялись. Проверено наличие и
содержимое перечисленных файлов, а не runtime поведение. Следующий результат
1Б — спецификация по дополненной карте и host evidence; архитектурный выбор
ещё не утверждён. Работающий профиль сохраняется на время подготовки.
