// SPDX-License-Identifier: GPL-2.0-or-later
#include <QGuiApplication>
#include <QLineF>
#include <QMutex>
#include <QMutexLocker>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QTest>
#include <QtPlugin>
#include <memory>

#include "../plugins.hpp"
#include "widgets/native/viewblockingrectangle.hpp"

class PositionProbe : public ViewBlockingRectangle
{
    Q_OBJECT
public:
    explicit PositionProbe(QQuickItem *parent = nullptr) : ViewBlockingRectangle(parent)
    {
        setUpdateRenderPosition(true);
        connect(this, &ViewBlockingRectangle::scenePositionHasChanged, this, [this] {
            QMutexLocker lock(&m_mutex);
            m_positions.append(renderPosition());
        }, Qt::DirectConnection);
    }

    QList<QPointF> positions()
    {
        QMutexLocker lock(&m_mutex);
        return m_positions;
    }

private:
    QMutex m_mutex;
    QList<QPointF> m_positions;
};

class TestViewBlockingRectangle : public QObject
{
    Q_OBJECT
private slots:
    void capturesKeepWindowCoordinates_data()
    {
        QTest::addColumn<bool>("nested");
        QTest::addColumn<bool>("transformed");
        QTest::newRow("capture") << false << false;
        QTest::newRow("nested-capture") << true << false;
        QTest::newRow("transformed-capture") << false << true;
        QTest::newRow("transformed-nested-capture") << true << true;
    }

    void capturesKeepWindowCoordinates()
    {
        QFETCH(bool, nested);
        QFETCH(bool, transformed);
        QQmlEngine engine;
        QQmlComponent component(&engine);
        component.setData(R"(
import QtQuick
import QtQuick.Window
import PositionTest 1.0
Window {
    id: scene
    visible: true; width: 800; height: 500
    property bool capturing: false
    property bool nested: false
    property bool transformed: false
    property real sourceX: 100
    Item {
        id: source; x: scene.sourceX; y: 80; width: 300; height: 200
        scale: scene.transformed ? 1.5 : 1
        rotation: scene.transformed ? 30 : 0
        Item {
            id: inner; x: 10; y: 15; width: 200; height: 150
            PositionProbe {
                objectName: "probe"; x: 30; y: 15
                width: 100; height: 100; color: "orange"
            }
        }
        ShaderEffectSource {
            x: 200; y: 10; width: 80; height: 60
            sourceItem: scene.capturing && scene.nested ? inner : null
        }
    }
    ShaderEffectSource {
        x: 450; y: 50; width: 300; height: 200
        sourceItem: scene.capturing ? source : null
    }
}
)", QUrl("qrc:/position-test.qml"));
        std::unique_ptr<QObject> root(component.create());
        QVERIFY2(root, qPrintable(component.errorString()));
        auto *window = qobject_cast<QQuickWindow *>(root.get());
        auto *probe = root->findChild<PositionProbe *>("probe");
        QVERIFY(window && probe);
        QVERIFY(QTest::qWaitForWindowExposed(window));
        root->setProperty("nested", nested);
        root->setProperty("transformed", transformed);

        for (bool capture : {false, true, false})
        {
            const auto captureStart = probe->positions().size();
            const auto capturePosition = probe->mapToScene(QPointF());
            root->setProperty("capturing", capture);
            QTest::qWait(50);
            const auto capturePositions = probe->positions();
            for (auto i = captureStart; i < capturePositions.size(); ++i)
                QVERIFY(QLineF(capturePositions[i], capturePosition).length() < 0.01);
            for (int x : {130, 100})
            {
                // Settle the preceding frame before recording this change.
                QTest::qWait(50);
                const auto start = probe->positions().size();
                root->setProperty("sourceX", x);
                const auto expected = probe->mapToScene(QPointF());
                QTRY_VERIFY(probe->positions().size() > start);
                for (int frame = 0; frame < 3; ++frame)
                {
                    window->update();
                    QTest::qWait(30);
                }
                const auto positions = probe->positions();
                for (auto i = start; i < positions.size(); ++i)
                    QVERIFY2(QLineF(positions[i], expected).length() < 0.01,
                             qPrintable(QString("Observed (%1, %2), expected (%3, %4)")
                                 .arg(positions[i].x()).arg(positions[i].y())
                                 .arg(expected.x()).arg(expected.y())));
            }
        }
        window->hide();
    }

    void animationKeepsWindowCoordinates()
    {
        QQmlEngine engine;
        QQmlComponent component(&engine);
        component.setData(R"(
import QtQuick
import QtQuick.Window
import PositionTest 1.0
Window {
    id: scene; visible: true; width: 800; height: 500
    property bool animate: false
    Item {
        x: 100; y: 80; width: 300; height: 200
        Item {
            id: source; x: 20; y: 30; width: 200; height: 150
            XAnimator { target: source; from: 20; to: 120; duration: 300; running: scene.animate }
            PositionProbe { objectName: "probe"; x: 40; y: 10; width: 100; height: 100; color: "orange" }
        }
        ShaderEffectSource { x: 220; width: 80; height: 60; sourceItem: source }
    }
}
)", QUrl("qrc:/position-animation-test.qml"));
        std::unique_ptr<QObject> root(component.create());
        QVERIFY2(root, qPrintable(component.errorString()));
        auto *window = qobject_cast<QQuickWindow *>(root.get());
        auto *probe = root->findChild<PositionProbe *>("probe");
        QVERIFY(window && probe);
        QVERIFY(QTest::qWaitForWindowExposed(window));
        QTRY_VERIFY(!probe->positions().isEmpty());
        root->setProperty("animate", true);
        QTRY_VERIFY(!probe->positions().isEmpty() &&
                    QLineF(probe->positions().last(), QPointF(260, 120)).length() < 0.01);
        const auto positions = probe->positions();
        QVERIFY(positions.size() > 2);
        for (const auto &position : positions)
        {
            QVERIFY(position.x() >= 160 && position.x() <= 260);
            QCOMPARE(position.y(), 120.0);
        }
        window->hide();
    }
};

int main(int argc, char **argv)
{
    // Exercise real layer render passes without requiring a GPU or display server.
#if !defined(Q_OS_WIN) && !defined(Q_OS_MACOS)
    if (!qEnvironmentVariableIsSet("QT_QPA_PLATFORM"))
        qputenv("QT_QPA_PLATFORM", "offscreen");
#endif
    QQuickWindow::setSceneGraphBackend("rhi");
    QQuickWindow::setGraphicsApi(qEnvironmentVariable("VLC_TEST_GRAPHICS_API") == "opengl"
                                  ? QSGRendererInterface::OpenGL : QSGRendererInterface::Null);
    QGuiApplication app(argc, argv);
    qmlRegisterType<PositionProbe>("PositionTest", 1, 0, "PositionProbe");
    TestViewBlockingRectangle test;
    return QTest::qExec(&test, argc, argv);
}

#include "test_viewblockingrectangle.moc"
