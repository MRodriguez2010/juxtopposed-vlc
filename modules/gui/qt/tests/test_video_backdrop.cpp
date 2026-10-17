// SPDX-License-Identifier: GPL-2.0-or-later
#include <QGuiApplication>
#include <QDir>
#include <QFileInfo>
#include <QLineF>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QTest>
#include <QtPlugin>
#include <memory>
#include "../plugins.hpp"
#include "maininterface/videobackdrop.hpp"
#include "util/seek_preview_image_provider.hpp"

static QSGRendererInterface::GraphicsApi expectedApi;

class TestVideoBackdrop : public QObject
{
    Q_OBJECT
private slots:
    void seekPreview_data()
    {
        QTest::addColumn<double>("scale");
        QTest::newRow("normal") << 1.;
        QTest::newRow("scaled") << 1.5;
    }

    void seekPreview()
    {
        QFETCH(double, scale);
        VideoBackdropProvider provider;
        QQmlEngine engine;
        engine.rootContext()->setContextProperty("testBackdropProvider", &provider);
        engine.addImageProvider("seekpreview", new SeekPreviewImageProvider);
        engine.rootContext()->setContextProperty("testPreviewImage", SeekPreviewImageProvider::url(
            QByteArray::fromBase64("iVBORw0KGgoAAAANSUhEUgAAABAAAAAJCAIAAAC0SDtlAAAAFUlEQVR4nGP8z0AaYCJR/agG2mgAAMeRARHH28OHAAAAAElFTkSuQmCC")));
        const QString sourceRoot = qEnvironmentVariable("VLC_TEST_SOURCE_ROOT", QStringLiteral(TOP_SRCDIR));
        const QString designPath = QDir(sourceRoot).filePath("modules/gui/qt/player/qml/redesign");
        QVERIFY2(QFileInfo::exists(designPath + "/RedesignSeekBar.qml"), qPrintable(designPath));
        QQmlComponent component(&engine);
        const QString source = QStringLiteral(R"(
import QtQuick
import QtQuick.Window
import BackdropTest 1.0
import "%1" as Design
Window {
    visible: true; width: 1000; height: 700
    Design.RedesignSeekBar {
        id: seek
        objectName: "seek"
        x: 100; y: 620; width: 700; height: 28
        previewEnabled: true
        previewImagePosition: 0.5
        previewImage: testPreviewImage
        videoBackdropContent: Component {
            VideoBackdrop {
                videoSurfaceProvider: testBackdropProvider
                blurRadius: 25 * seek.scaleFactor
                cornerRadius: 10 * seek.scaleFactor
            }
        }
    }
}
)").arg(QUrl::fromLocalFile(designPath).toString());
        component.setData(source.toUtf8(), QUrl("qrc:/backdrop-test.qml"));
        std::unique_ptr<QObject> root(component.create());
        QVERIFY2(root, qPrintable(component.errorString()));
        auto *window = qobject_cast<QQuickWindow *>(root.get());
        auto *seek = root->findChild<QQuickItem *>("seek");
        auto *popup = root->findChild<QObject *>("seekThumbnailPopup");
        QVERIFY(window && seek && popup);
        seek->setProperty("scaleFactor", scale);
        QSignalSpy frames(window, &QQuickWindow::frameSwapped);
        QVERIFY(QTest::qWaitForWindowExposed(window));
        QTRY_VERIFY(!frames.isEmpty());
        QCOMPARE(window->rendererInterface()->graphicsApi(), expectedApi);
        QVERIFY(provider.backdropRegions().regions.isEmpty());
        QTest::mouseMove(window, QPoint(20, 20));
        QTest::mouseMove(window, seek->mapToScene({seek->width() / 2, seek->height() / 2}).toPoint());
        if (!QTest::qWaitFor([&] { return popup->property("visible").toBool(); }, 3000))
        {
            auto *image = root->findChild<QQuickItem *>("seekThumbnailImage");
            qDebug() << "Preview state" << seek->property("hovered") << seek->property("previewActive")
                     << seek->property("previewReady") << (image ? image->property("status") : QVariant());
        }
        QTRY_VERIFY(popup->property("visible").toBool());
        QTRY_COMPARE(provider.backdropRegions().regions.size(), 1);
        auto *background = qvariant_cast<QQuickItem *>(popup->property("background"));
        QVERIFY(background);
        const auto matchesBackground = [&] {
            const auto state = provider.backdropRegions();
            if (state.regions.size() != 1)
                return false;
            const auto region = state.regions.first();
            const auto rect = background->mapRectToScene(QRectF(QPointF(), background->size()));
            const qreal dpr = window->effectiveDevicePixelRatio();
            return QLineF(region.rect.topLeft(), rect.topLeft() * dpr).length() < 0.01 &&
                   QLineF(region.rect.bottomRight(), rect.bottomRight() * dpr).length() < 0.01 &&
                   qAbs(region.cornerRadius - 14 * scale * dpr) < 0.01 &&
                   qAbs(region.blurRadius - 25 * scale * dpr) < 0.01;
        };
        QTRY_VERIFY(matchesBackground());
        const auto original = provider.backdropRegions().regions.first();
        seek->setX(180);
        seek->setY(590);
        QTest::mouseMove(window, seek->mapToScene({seek->width() - 2, seek->height() / 2}).toPoint());
        QTRY_VERIFY(matchesBackground());
        QTRY_VERIFY(provider.backdropRegions().regions.first().rect != original.rect);
        QCOMPARE(provider.backdropRegions().regions.first().id, original.id);
        window->resize(1200, 800);
        QTRY_VERIFY(matchesBackground());
        QTest::mousePress(window, Qt::LeftButton, Qt::NoModifier,
                          seek->mapToScene({seek->width() / 2, seek->height() / 2}).toPoint());
        QTRY_VERIFY(matchesBackground());
        QTest::mouseRelease(window, Qt::LeftButton, Qt::NoModifier,
                            seek->mapToScene({seek->width() / 2, seek->height() / 2}).toPoint());
        seek->setProperty("previewEnabled", false);
        QTRY_VERIFY(provider.backdropRegions().regions.isEmpty());
        seek->setProperty("previewEnabled", true);
        QTRY_VERIFY(matchesBackground());
        QTest::mouseMove(window, QPoint(20, 20));
        QTRY_VERIFY(provider.backdropRegions().regions.isEmpty());
        QTest::mouseMove(window, seek->mapToScene({seek->width() / 2, seek->height() / 2}).toPoint());
        QTRY_VERIFY(matchesBackground());
        root.reset();
        QVERIFY(provider.backdropRegions().regions.isEmpty());
    }
};

int main(int argc, char **argv)
{
#if !defined(Q_OS_WIN) && !defined(Q_OS_MACOS)
    if (!qEnvironmentVariableIsSet("QT_QPA_PLATFORM"))
        qputenv("QT_QPA_PLATFORM", "offscreen");
#endif
    const auto api = qEnvironmentVariable("VLC_TEST_GRAPHICS_API");
    if (api == "software")
    {
        QQuickWindow::setSceneGraphBackend("software");
        expectedApi = QSGRendererInterface::Software;
    }
    else
    {
        QQuickWindow::setSceneGraphBackend("rhi");
        expectedApi = api == "opengl" ? QSGRendererInterface::OpenGL :
                      api == "d3d11" ? QSGRendererInterface::Direct3D11 : QSGRendererInterface::Null;
        QQuickWindow::setGraphicsApi(expectedApi);
    }
    QGuiApplication app(argc, argv);
    app.setQuitOnLastWindowClosed(false);
    qmlRegisterAnonymousType<VideoBackdropProvider>("BackdropTest", 1);
    qmlRegisterType<VideoBackdrop>("BackdropTest", 1, 0, "VideoBackdrop");
    TestVideoBackdrop test;
    return QTest::qExec(&test, argc, argv);
}

#include "test_video_backdrop.moc"
