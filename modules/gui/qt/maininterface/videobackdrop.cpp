// SPDX-License-Identifier: GPL-2.0-or-later
#include "videobackdrop.hpp"
#include "util/video_backdrop_reporter.hpp"
#include "widgets/native/viewblockingrectangle.hpp"
#include <QQuickWindow>
#include <QLoggingCategory>
#include <QMutexLocker>

Q_LOGGING_CATEGORY(lcVideoBackdropRegions, "vlc.gui.video.backdrop.regions", QtWarningMsg)

VideoBackdropState VideoBackdropProvider::backdropRegions()
{
    QMutexLocker lock(&m_backdropLock);
    return {m_backdropRevision, m_backdropRegions.values()};
}

void VideoBackdropProvider::setBackdropRegion(const VideoBackdropRegion &region)
{
    VideoBackdropState state;
    {
        QMutexLocker lock(&m_backdropLock);
        auto it = m_backdropRegions.find(region.id);
        if (region.rect.isEmpty() || region.blurRadius <= 0)
        {
            if (it == m_backdropRegions.end())
                return;
            m_backdropRegions.erase(it);
        }
        else
        {
            if (it != m_backdropRegions.end() && it.value() == region)
                return;
            m_backdropRegions.insert(region.id, region);
        }
        state = {++m_backdropRevision, m_backdropRegions.values()};
    }
    qCDebug(lcVideoBackdropRegions) << "Backdrop snapshot" << state.revision << state.regions.size();
    emit backdropRegionsChanged(state);
}

VideoBackdrop::VideoBackdrop(QQuickItem *parent)
    : QQuickItem(parent), m_reporter(std::make_shared<VideoBackdropReporter>(quintptr(this)))
{
    setFlag(ItemHasContents);
    connect(this, &VideoBackdrop::blurRadiusChanged, this, &QQuickItem::update);
    connect(this, &VideoBackdrop::cornerRadiusChanged, this, &QQuickItem::update);
}

VideoBackdrop::~VideoBackdrop()
{
    disconnect(m_frameConnection);
    m_reporter->deactivate();
}

void VideoBackdrop::setProvider(VideoBackdropProvider *provider)
{
    if (m_provider == provider)
        return;
    m_provider = provider;
    m_reporter->setSink([provider = QPointer(provider)](const VideoBackdropRegion &region) {
        if (provider)
            provider->setBackdropRegion(region);
    });
    update();
    emit providerChanged();
}

QSGNode *VideoBackdrop::updatePaintNode(QSGNode *node, UpdatePaintNodeData *)
{
    m_reporter->update(size(), window()->effectiveDevicePixelRatio(), m_blurRadius, m_cornerRadius, isVisible());
    if (window()->rendererInterface()->graphicsApi() == QSGRendererInterface::Software)
    {
        if (!m_frameConnection)
            m_frameConnection = connect(window(), &QQuickWindow::afterAnimating,
                                        this, &VideoBackdrop::synchronizeSoftware);
        QMetaObject::invokeMethod(this, &VideoBackdrop::synchronizeSoftware, Qt::QueuedConnection);
        delete node;
        return nullptr;
    }
    if (!node)
        node = new MatrixChangeObserverNode([reporter = m_reporter](const QMatrix4x4 &matrix) {
            reporter->publish(matrix);
        }, true);
    return node;
}

void VideoBackdrop::synchronizeSoftware()
{
    // Software rendering does not prepare custom render nodes. This connection
    // runs on the GUI thread and is removed with the item.
    const auto origin = mapToScene(QPointF());
    const auto x = mapToScene(QPointF(1, 0)) - origin;
    const auto y = mapToScene(QPointF(0, 1)) - origin;
    QMatrix4x4 matrix;
    matrix(0, 0) = x.x(); matrix(1, 0) = x.y();
    matrix(0, 1) = y.x(); matrix(1, 1) = y.y();
    matrix(0, 3) = origin.x(); matrix(1, 3) = origin.y();
    m_reporter->publish(matrix);
}

void VideoBackdrop::itemChange(ItemChange change, const ItemChangeData &data)
{
    if (change == ItemVisibleHasChanged || change == ItemSceneChange)
    {
        m_reporter->deactivate();
        disconnect(m_frameConnection);
        m_frameConnection = {};
        if (isVisible())
            update();
    }
    else if (change == ItemDevicePixelRatioHasChanged)
        update();
    QQuickItem::itemChange(change, data);
}

