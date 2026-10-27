#pragma once
#include <QGuiApplication>
#include <QPointer>
#include <QTimer>
#include <QWindow>
#include <QtGui/qguiapplication_platform.h>
#include <wayland-client.h>

// Observe the focused switcher only; never grab or synthesize keyboard input.
class InputState final : public QObject {
    Q_OBJECT
public:
    explicit InputState(QObject *parent = nullptr) : QObject(parent) {
        connect(qGuiApp, &QGuiApplication::focusWindowChanged, this,
                [this](QWindow *) { synchronize(); });
    }
    ~InputState() override { cancelSync(); }
    Q_INVOKABLE void watch(QWindow *window) {
        m_window = window;
        synchronize();
    }
    Q_INVOKABLE void unwatch(QWindow *window) {
        if (m_window != window) return;
        m_window = nullptr;
        cancelSync();
    }
signals:
    void altReleased();
private:
    QPointer<QWindow> m_window;
    wl_callback *m_callback = nullptr;
    unsigned int m_generation = 0;
    void cancelSync() {
        ++m_generation;
        if (m_callback) {
            wl_callback_destroy(m_callback);
            m_callback = nullptr;
        }
    }
    void check() {
        if (m_window && QGuiApplication::focusWindow() == m_window
                && !(QGuiApplication::queryKeyboardModifiers() & Qt::AltModifier))
            emit altReleased();
    }
    static void synced(void *data, wl_callback *callback, uint32_t) {
        auto *self = static_cast<InputState *>(data);
        self->m_callback = nullptr;
        wl_callback_destroy(callback);
        self->check();
    }
    void synchronize() {
        cancelSync();
        if (!m_window || QGuiApplication::focusWindow() != m_window) return;
        auto *wayland = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>();
        if (wayland) {
            // Keyboard enter precedes its modifiers event. The async barrier
            // ensures both have arrived before treating absent Alt as release.
            m_callback = wl_display_sync(wayland->display());
            if (!m_callback) return;
            static const wl_callback_listener listener = { synced };
            wl_callback_add_listener(m_callback, &listener, this);
            wl_display_flush(wayland->display());
        } else {
            const auto generation = m_generation;
            QTimer::singleShot(0, this, [this, generation] {
                if (generation == m_generation) check();
            });
        }
    }
};
