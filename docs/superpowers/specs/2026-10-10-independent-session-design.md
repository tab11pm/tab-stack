# Этап 1Б: самостоятельная сессия tab-stack

Статус: спецификация согласована пользователем; реализация не начата.
Подготовлен [план исполнения](../plans/2026-10-10-independent-session.md).
Основание: [дорожная карта](2026-10-10-independent-tab-stack-roadmap.md),
[аудит lifecycle](../../migration/session-lifecycle-preparation.md).

## Цель

Сделать отдельную выбираемую сессию tab-stack на ShojiWM: известный владелец
запуска и завершения, актуальное окружение сервисов, один экземпляр панели,
воспроизводимый Elephant unit и проверяемая уборка после выхода.
Текущий внешний вид сохраняется. SDDM X11 greeter уже установлен и подтверждён
журналом; установка этой сессии не зависит от смены темы или автологина.

Автологин другой учётной записи, PAM, lock/sleep policy, package removal,
boot chain и дополнительные приложения остаются вне этой части.

## Подтверждённое состояние

Пользователь предоставил данные из терминала desktop user:

| Объект | Состояние |
| --- | --- |
| graphical-session.target | inactive / dead |
| graphical-session-pre.target | inactive / dead |
| elephant.service | active / running |
| omarchy-sleep-lock.service | inactive / dead |
| Manager XDG_CURRENT_DESKTOP | ShojiWM |
| Manager XDG_SESSION_TYPE | wayland |
| Manager display variables | DISPLAY и WAYLAND_DISPLAY заданы |
| Manager OMARCHY_PATH | В выбранном выводе отсутствует |

Таким образом, наличие пользовательских wants links не означает, что Omarchy
services сейчас запущены. Прочитанный native logout helper прошёл пользовательский
`--check`; фактическое завершение и cleanup ещё не доказаны отдельным отчётом.

Elephant работает несмотря на неактивный graphical-session.target. Его текущий
unit не содержит PartOf и отсутствует в publication source. Основной portal и
GTK/WLR/ShojiWM backend units имеют PartOf=graphical-session.target, но этот
target неактивен. Active state порталов и их ownership ещё предстоит проверить.

## Рассмотренные подходы

1. **Собственный wrapper и target tab-stack — предлагается.** Управляет только
   оговорёнными user services, сохраняет supervisor панели внутри ShojiWM и
   обходит необходимость запускать существующие Omarchy wants. Требует своих
   правил readiness, cleanup и проверки одной графической сессии на UID.
2. **Подключить UWSM.** Готовая инфраструктура environment и session targets,
   но текущие graphical-session wants подтянут прежние units. Требуется более
   широкий разбор и перенос legacy autostart/lock/sleep до безопасного применения.
3. **Оставить direct ShojiWM и исправить только скрипты.** Наименьший diff,
   но не решает воспроизводимое завершение самостоятельных user services;
   недостаточно для цели этого этапа.

Вариант 1 не запускает graphical-session.target вручную и не меняет packaged
systemd units. В качестве прототипа не использовать массовое отключение старых
units, запуск второй панели или немедленную миграцию всех процессов в systemd.

## Предлагаемые владельцы

| Объект | Владелец |
| --- | --- |
| Login entry | Отдельная tab-stack.desktop; существующая ShojiWM entry сохраняется для отката |
| ShojiWM | User wrapper запускает и ожидает compositor, сохраняет exit status |
| Readiness | Helper, вызываемый из настоящего окружения ShojiWM после появления его Wayland display |
| User services | tab-stack-session.target с явным перечнем зависимостей |
| Панель | Существующий COMPOSITOR.process.service("dock"), restart=on-failure |
| Polkit agent | Существующий once-per-session запуск ShojiWM |
| Elephant | Единственный elephant.service; переносимый source unit с PartOf=tab-stack-session.target |
| Portals | Существующие services с user drop-ins для принадлежности tab-stack-session.target |
| Выход | Проверенный native logout helper; кнопка shell вызывает тот же helper |
| Cleanup | Wrapper после завершения compositor; reload TSX не означает logout |

## Последовательность запуска

1. Пользователь явно выбирает новую tab-stack session. Wrapper проверяет
   prerequisites и отсутствие другой графической сессии того же UID, включая
   legacy session; при конфликте прекращает новый запуск без kill/stop чужой сессии.
2. Wrapper захватывает session ownership lock и создаёт приватный runtime marker
   с идентичностью своего процесса. Stale marker не является разрешением
   завершать чужие процессы. Точные проверки PID reuse задаются в плане.
3. Wrapper запускает ShojiWM. Его собственные display values не угадываются
   заранее: readiness helper получает их из compositor environment и проверяет
   принадлежность Wayland socket текущему compositor/user.
4. Helper импортирует только выбранные desktop/display/Qt переменные в systemd
   user и D-Bus activation. Недостающие необязательные значения не наследуются
   молча от предыдущего запуска. Никакой полный dump environment не сохраняется.
5. После импорта helper запускает собственный target и необходимые services.
   Elephant стартует один раз. При первом переходе прежний elephant.service
   останавливается отдельно в окне применения после завершения старой
   графической сессии; затем новый source unit загружается в user manager.
   Если перед readiness остаётся неожиданный активный backend или другой
   владелец, новый запуск прекращается до takeover без kill по имени.
6. Helper возвращает подтверждённый результат wrapper. Ошибка readiness, импорт
   или service startup не выдаются за успешный запуск: частично созданные
   собственные ресурсы освобождаются, причина фиксируется без private settings.

Target запускает elephant.service, основной xdg-desktop-portal.service и
GTK/WLR/ShojiWM backend services. Для всех четырёх portal units нужны user
drop-ins с дополнительным PartOf=tab-stack-session.target. Прежние packaged
отношения сохраняются. Helper проверяет результат запуска требуемых services:
сам по себе успешный start target не доказывает готовность его Wants.
Точные unit definitions, checks и failure paths задаются в implementation plan
до runtime code.
Поддержка нескольких графических сессий одного UID в этой части не заявляется;
новый запуск должен отказать безопасно, а не перезаписать их общее окружение.
Другие пользователи имеют отдельные user managers и не затрагиваются.

## Последовательность выхода

- Кнопка shell и терминальная команда используют один native helper, который
  проверяет Wayland peer и запрашивает завершение только текущего ShojiWM.
- Wrapper ожидает compositor и выполняет cleanup также при неуспешном exit.
  Reload конфигурации не останавливает target или launcher.
- Останавливаются только принадлежащие этой сессии services. Panel/polkit
  cleanup проверяется по фактическому supervisor contract ShojiWM; не вводить
  pkill по имени или kill всех процессов пользователя.
- Собственные display values удаляются из systemd user environment только
  при подтверждённом ownership. Для D-Bus activation отдельно определяется
  supported invalidation: unset в systemd не означает unset в session bus.
  Старые значения с мёртвым display не восстанавливаются как пригодные.
- Не останавливать user manager, default.target, audio/keyring sockets или
  другую пользовательскую сессию. Освобождаются собственные runtime marker/lock.

## Source, установка и откат

Новые wrapper/helper, unit/target и portal drop-ins входят в publication source;
installer получает явный session component и preview соответствующих путей.
Не устанавливать их скрытно через существующий component shojiwm.
Новая system desktop entry устанавливается отдельной административной
операцией после user prerequisites, а не через неявный sudo user installer.

Перед записью сохранить именно затрагиваемые файлы, presence/absence, mode,
ownership и checksums. Не копировать весь профиль и не переносить integrations.
Не изменять широким копированием текущие unrelated dirty source changes.
Новые user units и drop-ins сначала проверяются в staging; live daemon-reload
и выбор новой session выполняются в согласованный момент.

Legacy ShojiWM entry и её профиль остаются пригодными для возврата. Новая
startup/cleanup ветка включается только по проверенному marker собственного
wrapper; обычный запуск ShojiWM сохраняет прежний session-portals путь.
Исходные изменяемые scripts/TSX/QML отдельно сохраняются для отката.
Откат удаляет только добавленные файлы с совпадающим установленным checksum
и восстанавливает прежние затронутые файлы из свежего component backup.
После остановки новой session восстановление не запускает старые Omarchy
targets, не меняет автологин и не удаляет пакеты.

## Проверки и критерии приёмки

- Fixture checks: отсутствующий display, неправильный peer/owner, повторный
  запуск, stale marker/PID reuse, отказ импорта/target/service, смерть compositor.
- Проверка native shutdown, нормального logout и TSX reload как разных случаев.
- User installer preview/staging сохраняет unrelated config и private data;
  rollback покрывает и исходное отсутствие, и прежний regular file.
- Host: одна панель, один polkit agent и Elephant; manager display относится
  к текущему ShojiWM. File picker и launcher работают после ручного входа.
- После logout target и его services остановлены; dead display не используется
  при повторном входе; UI/agents не дублируются.
- Legacy login entry, выбранный способ TTY recovery и другой пользователь
  сохраняются. Cold boot и clean-user installation проверяются отдельно.

Этап 1А ещё имеет непроверенные сценарии relogin/cold boot/rollback; подготовка
1Б не объявляет их выполненными. Применение 1Б требует отдельной готовности
recovery и проверки точного изменения в source, staging и live session.
