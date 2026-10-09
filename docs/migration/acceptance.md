# Матрица проверок миграции tab-stack

Дата: 2026-10-10. Это исходное состояние аудита чтением.
Все живые сценарии ниже ещё не проверены в рамках миграции.

Подготовка 1А: создан и проверен точный source INI для X11 greeter и
[руководство установки/отката](../../dotfiles/docs/greeter.md). Проверки приоритета
на четырёх временных fixtures с Qt ordering tool прошли; три проверки
checksum gate для существующего destination также прошли. Proposed value
по читаемым файлам — x11; host preview с locale действующего SDDM
ещё не подтверждён из sandbox.
Текущая конфигурация по-прежнему задаёт wayland; system override отсутствует.
Установка на host и runtime приёмка не выполнены. SDDM не перезапускался.
Доступ к состояниям SDDM/сессий через D-Bus запрещён sandbox; для продолжения
Пользователь подтвердил успешный `sudo -v` в административной записи;
пользователь также предоставил SDDM=active и одну пользовательскую сессию
плюс её user manager. Нужны host preview приоритета, свежая системная копия
и окно применения.

Связи: [реестр](dependency-register.md), [восстановление](recovery.md),
[дорожная карта](../superpowers/specs/2026-10-10-independent-tab-stack-roadmap.md).

| Сценарий | Применимость | Текущие доказательства | Ожидаемый результат | Способ проверки | Этап | Локальный отчёт |
| --- | --- | --- | --- | --- | --- | --- |
| cold boot | Да | boot.loader: пакеты/hooks есть; /boot недоступен | Загрузка в рабочий greeter без Hyprland | После проверки rescue и backups перезагрузить вручную | 1, 7 | не создан |
| greeter | Да | login.greeter: SDDM использует start-hyprland; несколько theme overrides | Рабочий экран входа с независимым backend | Проверить действующие settings, затем вход после замены | 1 | не создан |
| вход | Да | login.session: Shoji entry есть; autologin ссылается на Omarchy | Выбранная сессия tab-stack и правильное окружение | Ручной вход после проверки TTY; отдельно автологин, если нужен | 1 | не создан |
| выход/повторный вход | Да | session.lifecycle: direct compositor session; разные shutdown paths | Завершается нужная сессия, повторный запуск без старых процессов | Сохранить работу и проверить logout/login, ownership процессов/targets | 1 | не создан |
| panel recovery | Да | session.panel: WM restart=on-failure; runtime не проверен | Одна восстановленная панель, locker не затронут | Контролируемый отказ панели после проверки recovery | 1–2 | не создан |
| lock | Да | lock.request и lock.pam: отдельный locker, сейчас Omarchy PAM fallback | Secure lock, неверный пароль не открывает сессию | После TTY/recovery проверить пароль, repeated request и outputs | 2 | не создан |
| suspend/resume | Да | sleep.preparation: unit/link и 15s delay; active неизвестен | Перед сном secure, после пробуждения закрытый экран | После lock acceptance проверить manual sleep и failure path | 3 | не создан |
| lid | Да, ACPI lid виден | hardware.applicability: LID и батарея есть | Корректные sleep/clamshell действия с/без внешнего дисплея | Ручной сценарий на оборудовании после lock/sleep acceptance | 3 | не создан |
| monitor hotplug | Да; фактическое подключение уточнить | Profile содержит HDMI/eDP; live output list не получен | Restore layout, secure coverage всех outputs | Подключить/отключить монитор, в том числе при lock/resume | 2–3, 5 | не создан |
| сеть/секреты | Сеть — да; Wi-Fi adapter уточнить | network.secrets: prompt/connectWithPsk; runtime/persistence неизвестны | Новая сеть и reconnect без потери/раскрытия секретов | Новая учётная запись; добровольно выбранная тестовая сеть | 4 | не создан |
| звук/микрофон | Да; устройства уточнить | audio.stack: sockets/alias и QML consumers | Output/input, mute/volume и смена устройства работают | Короткий локальный тест с выбранными устройствами | 4 | не создан |
| Bluetooth | Наличие адаптера уточнить | bluetooth.stack: UI и agent unit есть; active неизвестен | Управляемое pairing/reconnect без конфликтующих агентов | Проверить host adapter/agent state, затем тестовое устройство | 4 | не создан |
| polkit/keyring | Да | auth.polkit-keyring: explicit agent, socket; unlock path неизвестен | Один polkit agent, доступное secret storage после входа | Безопасный запрос прав и тест keyring без вывода содержимого | 4 | не создан |
| file picker | Да | portals.routing: GTK default | Диалог выбора файла работает в Wayland приложении | Открыть локальный несекретный файл через portal client | 4 | не создан |
| screenshot | Да | capture.screenshot: native scripts и tools; source drift | Region/output/all и clipboard при scaling | Сделать снимок несекретного тестового окна | 5 | не создан |
| recording/ScreenCast | Да | capture.screencast: portal/OBS/GSR есть; runtime неизвестен | Запись и browser sharing, stop/indicator без Hyprland | Тест несекретной сцены в OBS и используемых браузерах | 5 | не создан |
| package update | Да | updates.hooks: Omarchy guard; boot integrations из omarchy repo | Полный согласованный update без утраты загрузки/desktop | Проверить sources/hooks/rollback, потом обычный полный update | 6–7 | не создан |

## Ограничения и условия

- `systemctl show` не смог обратиться к user/system bus: `Operation not permitted`.
  Поэтому active state не указан как подтверждённый.
- Наличие enabled symlink, declaration protocol или бинарника не является
  успешной проверкой пользовательского сценария.
- Изменение конфигурации, переключение TTY, вход, сон и запуск захвата не выполнялись.
- «Применимость уточнить» означает недостаток доказательств, а не отсутствие устройства.
- Проверки, которые открывают сессию/меняют оборудование/запрашивают права,
  выполняются в соответствующих этапах после готовности recovery.
- Проверки в новой учётной записи и чистом Arch обязательны для portable результата.
  Успешная работа текущего пользователя не заменяет их.

## Итог этапа 0

Документационная матрица покрывает 17 сценариев. Это не приёмка desktop функций.
Перечень минимальных команд чтения для недоступных результатов приведён в реестре.
Первый этап миграции ограничивается greeter и session lifecycle; парольная политика
и sleep path остаются отдельными следующими этапами.
