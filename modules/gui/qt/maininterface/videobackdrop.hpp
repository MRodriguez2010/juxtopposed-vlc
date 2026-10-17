// SPDX-License-Identifier: GPL-2.0-or-later
#ifndef VLC_QT_VIDEO_BACKDROP_HPP
#define VLC_QT_VIDEO_BACKDROP_HPP

#include <QQuickItem>
#include <QPointer>
#include <QMap>
#include <QMutex>
#include <memory>
#include "util/video_backdrop_region.hpp"

class VideoBackdropReporter;

class VideoBackdropProvider : public QObject
{
    Q_OBJECT
public:
    explicit VideoBackdropProvider(QObject *parent = nullptr) : QObject(parent) {}
    VideoBackdropState backdropRegions();
    void setBackdropRegion(const VideoBackdropRegion &region);

signals:
    void backdropRegionsChanged(const VideoBackdropState &state);

private:
    QMutex m_backdropLock;
    QMap<quintptr, VideoBackdropRegion> m_backdropRegions;
    quint64 m_backdropRevision = 0;
};

// Reports a floating surface to the native video compositor without painting it.
class VideoBackdrop : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(VideoBackdropProvider* videoSurfaceProvider READ provider WRITE setProvider NOTIFY providerChanged FINAL)
    Q_PROPERTY(qreal blurRadius MEMBER m_blurRadius NOTIFY blurRadiusChanged FINAL)
    Q_PROPERTY(qreal cornerRadius MEMBER m_cornerRadius NOTIFY cornerRadiusChanged FINAL)
public:
    explicit VideoBackdrop(QQuickItem *parent = nullptr);
    ~VideoBackdrop() override;
    VideoBackdropProvider *provider() const { return m_provider; }
    void setProvider(VideoBackdropProvider *provider);

signals:
    void providerChanged();
    void blurRadiusChanged();
    void cornerRadiusChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *, UpdatePaintNodeData *) override;
    void itemChange(ItemChange, const ItemChangeData &) override;

private:
    void synchronizeSoftware();
    QPointer<VideoBackdropProvider> m_provider;
    std::shared_ptr<VideoBackdropReporter> m_reporter;
    QMetaObject::Connection m_frameConnection;
    qreal m_blurRadius = 25;
    qreal m_cornerRadius = 10;
};


#endif
