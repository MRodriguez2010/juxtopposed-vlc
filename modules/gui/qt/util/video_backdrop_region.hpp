// SPDX-License-Identifier: GPL-2.0-or-later
#ifndef VLC_QT_VIDEO_BACKDROP_REGION_HPP
#define VLC_QT_VIDEO_BACKDROP_REGION_HPP

#include <QList>
#include <QMetaType>
#include <QRectF>

// Window coordinates in physical pixels, independent of the video viewport.
struct VideoBackdropRegion
{
    quintptr id = 0;
    QRectF rect;
    qreal blurRadius = 0;
    qreal cornerRadius = 0;

    bool operator==(const VideoBackdropRegion &other) const
    {
        return id == other.id && rect == other.rect &&
               blurRadius == other.blurRadius && cornerRadius == other.cornerRadius;
    }
};
Q_DECLARE_METATYPE(VideoBackdropRegion)

struct VideoBackdropState
{
    quint64 revision = 0;
    QList<VideoBackdropRegion> regions;
};
Q_DECLARE_METATYPE(VideoBackdropState)

#endif
