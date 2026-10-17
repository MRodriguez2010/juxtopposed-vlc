// SPDX-License-Identifier: GPL-2.0-or-later
#ifndef VLC_QT_VIDEO_BACKDROP_REPORTER_HPP
#define VLC_QT_VIDEO_BACKDROP_REPORTER_HPP

#include "video_backdrop_region.hpp"
#include <QMatrix4x4>
#include <QMutex>
#include <QMutexLocker>
#include <algorithm>
#include <functional>
#include <utility>

// Shared by the GUI item and its render node. Render callbacks must not retain
// or read the item: a panel can close while a frame is still being rendered.
class VideoBackdropReporter
{
public:
    using Sink = std::function<void(const VideoBackdropRegion &)>;
    explicit VideoBackdropReporter(quintptr id) : m_id(id) {}

    void setSink(Sink sink)
    {
        QMutexLocker lock(&m_lock);
        clear();
        m_active = false;
        m_sink = std::move(sink);
    }

    void update(const QSizeF &size, qreal dpr, qreal blur, qreal corner, bool active)
    {
        QMutexLocker lock(&m_lock);
        m_size = size;
        m_dpr = dpr;
        m_blur = blur;
        m_corner = corner;
        m_active = active && !size.isEmpty() && blur > 0;
        if (!m_active)
            clear();
    }

    void deactivate()
    {
        QMutexLocker lock(&m_lock);
        m_active = false;
        clear();
    }

    void publish(const QMatrix4x4 &matrix)
    {
        QMutexLocker lock(&m_lock);
        if (!m_active || !m_sink)
            return;
        const auto bounds = matrix.mapRect(QRectF(QPointF(), m_size));
        const qreal scale = std::max(matrix.mapVector(QVector3D(1, 0, 0)).length(),
                                     matrix.mapVector(QVector3D(0, 1, 0)).length());
        const VideoBackdropRegion region{m_id, QRectF(bounds.topLeft() * m_dpr, bounds.size() * m_dpr),
                                         m_blur * scale * m_dpr, m_corner * scale * m_dpr};
        if (m_published && region == m_last)
            return;
        m_sink(region);
        m_last = region;
        m_published = true;
    }

private:
    // Serialize removal with an in-flight publication, so it is always last.
    void clear()
    {
        if (m_published && m_sink)
            m_sink({m_id, {}, 0, 0});
        m_published = false;
    }

    QMutex m_lock;
    const quintptr m_id;
    Sink m_sink;
    QSizeF m_size;
    qreal m_dpr = 1, m_blur = 25, m_corner = 10;
    bool m_active = false, m_published = false;
    VideoBackdropRegion m_last;
};

#endif
