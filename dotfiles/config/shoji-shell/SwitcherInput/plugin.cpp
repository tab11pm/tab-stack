#include <QQmlExtensionPlugin>
#include <qqml.h>
#include "inputstate.h"
class SwitcherInputPlugin final : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override {
        qmlRegisterSingletonType<InputState>(uri, 1, 0, "InputState",
            [](QQmlEngine *, QJSEngine *) -> QObject * { return new InputState; });
    }
};
#include "plugin.moc"
