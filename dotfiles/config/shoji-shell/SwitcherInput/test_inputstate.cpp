#include <QtTest>
#include "inputstate.h"
class InputStateTests : public QObject {
    Q_OBJECT
private slots:
    void absentAltAfterFocusCommits() {
        QWindow window; window.resize(100,100); window.show(); window.requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(&window));
        InputState input; QSignalSpy spy(&input, &InputState::altReleased);
        input.watch(&window);
        QTRY_COMPARE(spy.count(), 1);
    }
    void heldAltDoesNotCommit() {
        QWindow window; window.resize(100,100); window.show(); window.requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(&window));
        QTest::keyPress(&window, Qt::Key_Alt, Qt::AltModifier);
        InputState input; QSignalSpy spy(&input, &InputState::altReleased);
        input.watch(&window); QCoreApplication::processEvents();
        QCOMPARE(spy.count(), 0);
        input.unwatch(&window);
        QTest::keyRelease(&window, Qt::Key_Alt);
    }
    void cancelBeforeSyncDoesNotCommit() {
        QWindow window; window.resize(100,100); window.show(); window.requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(&window));
        InputState input; QSignalSpy spy(&input, &InputState::altReleased);
        input.watch(&window); input.unwatch(&window);
        QCoreApplication::processEvents(); QCOMPARE(spy.count(), 0);
    }
    void unfocusedWindowDoesNotCommit() {
        QWindow window;
        InputState input; QSignalSpy spy(&input, &InputState::altReleased);
        input.watch(&window); QCoreApplication::processEvents(); QCOMPARE(spy.count(), 0);
    }
};
QTEST_MAIN(InputStateTests)
#include "test_inputstate.moc"
