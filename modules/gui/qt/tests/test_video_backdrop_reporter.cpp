// SPDX-License-Identifier: GPL-2.0-or-later
#include <QTest>
#include <QSemaphore>
#include <memory>
#include <thread>
#include "util/video_backdrop_reporter.hpp"
#include "widgets/native/viewblockingrectangle.hpp"

class TestVideoBackdropReporter : public QObject
{
    Q_OBJECT
private slots:
    void transformsAndChanges()
    {
        QList<VideoBackdropRegion> reports;
        auto reporter = std::make_shared<VideoBackdropReporter>(42);
        reporter->setSink([&](const auto &region) { reports.append(region); });
        reporter->update({100, 50}, 2, 25, 10, true);
        QSGTransformNode outer;
        QMatrix4x4 transform;
        transform.translate(100, 80);
        outer.setMatrix(transform);
        auto inner = new QSGTransformNode;
        transform.setToIdentity();
        transform.translate(40, 30);
        transform.scale(1.5);
        inner->setMatrix(transform);
        outer.appendChildNode(inner);
        auto node = new MatrixChangeObserverNode([reporter](const auto &matrix) {
            reporter->publish(matrix);
        }, true);
        inner->appendChildNode(node);
        node->prepare();
        QCOMPARE(reports.size(), 1);
        QCOMPARE(reports.last().id, quintptr(42));
        QCOMPARE(reports.last().rect, QRectF(280, 220, 300, 150));
        QCOMPARE(reports.last().blurRadius, 75.);
        QCOMPARE(reports.last().cornerRadius, 30.);
        node->prepare();
        QCOMPARE(reports.size(), 1);
        // The matrix stays the same when the panel size or radius changes.
        reporter->update({120, 60}, 2, 20, 8, true);
        node->prepare();
        QCOMPARE(reports.size(), 2);
        QCOMPARE(reports.last().rect, QRectF(280, 220, 360, 180));
        QCOMPARE(reports.last().blurRadius, 60.);
        QCOMPARE(reports.last().cornerRadius, 24.);
        reporter->update({120, 60}, 2, 20, 8, false);
        QCOMPARE(reports.size(), 3);
        QVERIFY(reports.last().rect.isEmpty());
        node->prepare();
        QCOMPARE(reports.size(), 3);
    }

    void nodeOutlivesOwner()
    {
        QList<VideoBackdropRegion> reports;
        auto reporter = std::make_shared<VideoBackdropReporter>(43);
        std::weak_ptr<VideoBackdropReporter> weak = reporter;
        reporter->setSink([&](const auto &region) { reports.append(region); });
        reporter->update({100, 50}, 1, 25, 10, true);
        auto node = std::make_unique<MatrixChangeObserverNode>([reporter](const auto &matrix) {
            reporter->publish(matrix);
        }, true);
        node->prepare();
        QCOMPARE(reports.size(), 1);
        reporter->deactivate();
        reporter.reset();
        QVERIFY(!weak.expired());
        QCOMPARE(reports.size(), 2);
        QVERIFY(reports.last().rect.isEmpty());
        node->prepare();
        QCOMPARE(reports.size(), 2);
        node.reset();
        QVERIFY(weak.expired());
    }

    void removalFollowsInFlightPublication()
    {
        QList<VideoBackdropRegion> reports;
        QSemaphore entered, release, removing;
        VideoBackdropReporter reporter(44);
        reporter.setSink([&](const auto &region) {
            if (!region.rect.isEmpty())
            {
                entered.release();
                release.acquire();
            }
            reports.append(region);
        });
        reporter.update({100, 50}, 1, 25, 10, true);
        std::thread render([&] { reporter.publish({}); });
        const bool started = entered.tryAcquire(1, 5000);
        if (!started)
        {
            release.release();
            render.join();
            QFAIL("The render callback did not start");
        }
        std::thread gui([&] { removing.release(); reporter.deactivate(); });
        removing.acquire();
        release.release();
        render.join();
        gui.join();
        QCOMPARE(reports.size(), 2);
        QVERIFY(!reports.first().rect.isEmpty());
        QVERIFY(reports.last().rect.isEmpty());
        reporter.publish({});
        QCOMPARE(reports.size(), 2);
    }
};

QTEST_GUILESS_MAIN(TestVideoBackdropReporter)
#include "test_video_backdrop_reporter.moc"
