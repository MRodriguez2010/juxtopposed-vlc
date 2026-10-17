/*****************************************************************************
 * Copyright (C) 2019 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/
#include "videosurface.hpp"

#include <QSGRectangleNode>
#include <QThreadPool>
#include <QLoggingCategory>
#include <utility>
#include <vlc_window.h>

#include <QQuickRenderControl>
#ifdef QT_DECLARATIVE_PRIVATE
#  include <QtGui/qpa/qplatformwindow.h>
#endif

#include "maininterface/mainctx.hpp"
#include "util/video_backdrop_reporter.hpp"

Q_LOGGING_CATEGORY(lcVideoBackdropRegions, "vlc.gui.video.backdrop.regions", QtWarningMsg)

VideoSurfaceProvider::VideoSurfaceProvider(bool threadedSurfaceUpdates, QObject* parent)
    : QObject(parent)
    , m_threadedSurfaceUpdates(threadedSurfaceUpdates)
{
}

VideoBackdropState VideoSurfaceProvider::backdropRegions()
{
    QMutexLocker lock(&m_backdropLock);
    return {m_backdropRevision, m_backdropRegions.values()};
}

void VideoSurfaceProvider::setBackdropRegion(const VideoBackdropRegion &region)
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

void VideoBackdrop::setProvider(VideoSurfaceProvider *provider)
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

bool VideoSurfaceProvider::isEnabled()
{
    return m_voutWindow != nullptr;
}

bool VideoSurfaceProvider::hasVideoEmbed() const
{
    return m_videoEmbed;
}

void VideoSurfaceProvider::enable(vlc_window_t* voutWindow)
{
    assert(voutWindow);
    m_voutWindow = voutWindow;
    m_pressedButtons = 0;
    emit videoEnabledChanged(true);
}

void VideoSurfaceProvider::disable()
{
    setVideoEmbed(false);
    m_voutWindow = nullptr;
    m_pressedButtons = 0;
    emit videoEnabledChanged(false);
}

void VideoSurfaceProvider::setVideoEmbed(bool embed)
{
    m_videoEmbed = embed;
    emit hasVideoEmbedChanged(embed);
}

void VideoSurfaceProvider::onWindowClosed()
{
    if (m_voutWindow)
        vlc_window_ReportClose(m_voutWindow);
}

void VideoSurfaceProvider::onMousePressed(int vlcButton)
{
    if (m_voutWindow && unsigned(vlcButton) < 3)
    {
        m_pressedButtons |= 1u << vlcButton;
        vlc_window_ReportMousePressed(m_voutWindow, vlcButton);
    }
}

void VideoSurfaceProvider::onMouseReleased(int vlcButton)
{
    if (m_voutWindow && unsigned(vlcButton) < 3)
    {
        m_pressedButtons &= ~(1u << vlcButton);
        vlc_window_ReportMouseReleased(m_voutWindow, vlcButton);
    }
}

void VideoSurfaceProvider::releaseMouseButtons()
{
    // A popup takes the mouse grab before the surface receives the release.
    const unsigned pressed = std::exchange(m_pressedButtons, 0);
    if (m_voutWindow)
        for (int button = 0; button < 3; ++button)
            if (pressed & (1u << button))
                vlc_window_ReportMouseReleased(m_voutWindow, button);
}

void VideoSurfaceProvider::onMouseDoubleClick(int vlcButton)
{
    if (m_voutWindow)
        vlc_window_ReportMouseDoubleClick(m_voutWindow, vlcButton);
}

void VideoSurfaceProvider::onMouseMoved(float x, float y)
{
    if (m_voutWindow)
        vlc_window_ReportMouseMoved(m_voutWindow, x, y);
}

void VideoSurfaceProvider::onMouseWheeled(int vlcButton)
{
    if (m_voutWindow)
        vlc_window_ReportKeyPress(m_voutWindow, vlcButton);
}

void VideoSurfaceProvider::onKeyPressed(int key, Qt::KeyboardModifiers modifiers)
{
    QKeyEvent event(QEvent::KeyPress, key, modifiers);
    int vlckey = qtEventToVLCKey(&event);
    if (m_voutWindow)
        vlc_window_ReportKeyPress(m_voutWindow, vlckey);
}

void VideoSurfaceProvider::onSurfacePropertiesChanged(const std::optional<QSizeF>& size,
                                                      const std::optional<QPointF>& position,
                                                      const std::optional<qreal>& scale)
{
    emit surfacePropertiesChanged(size, position, scale);
    if (m_voutWindow && size)
        vlc_window_ReportSize(m_voutWindow, std::ceil(size->width()), std::ceil(size->height()));
}


VideoSurface::VideoSurface(QQuickItem* parent)
    : ViewBlockingRectangle(parent)
{
    setAcceptHoverEvents(true);
    setAcceptedMouseButtons(Qt::AllButtons);
    setFlag(ItemAcceptsInputMethod, true);

    {
        // This is for initialization, they are adjusted in `::updatePaintNode()`:
        setUpdateRenderPosition(true);
        setFlag(ItemHasContents, false); // `setUpdateRenderPosition(true)` sets `ItemHasContents`
    }
}

int VideoSurface::qtMouseButton2VLC( Qt::MouseButton qtButton )
{
    switch( qtButton )
    {
        case Qt::LeftButton:
            return 0;
        case Qt::RightButton:
            return 2;
        case Qt::MiddleButton:
            return 1;
        default:
            return -1;
    }
}

void VideoSurface::mousePressEvent(QMouseEvent* event)
{
    int vlc_button = qtMouseButton2VLC( event->button() );
    if( vlc_button >= 0 )
    {
        emit mousePressed(vlc_button);
        event->accept();
    }
    else
        event->ignore();
}

void VideoSurface::mouseReleaseEvent(QMouseEvent* event)
{
    int vlc_button = qtMouseButton2VLC( event->button() );
    if( vlc_button >= 0 )
    {
        emit mouseReleased(vlc_button);
        event->accept();
    }
    else
        event->ignore();
}

void VideoSurface::mouseMoveEvent(QMouseEvent* event)
{
    QPointF current_pos = event->position();
    QQuickWindow* window = this->window();
    if (!window)
        return;
    qreal dpr = window->effectiveDevicePixelRatio();
    emit mouseMoved(current_pos.x() * dpr, current_pos.y() * dpr);
    event->accept();
}

void VideoSurface::hoverMoveEvent(QHoverEvent* event)
{
    QPointF current_pos = event->position();
    if (current_pos != m_oldHoverPos)
    {
        QQuickWindow* window = this->window();
        if (!window)
            return;
        qreal dpr = window->effectiveDevicePixelRatio();
        emit mouseMoved(current_pos.x() * dpr, current_pos.y()  * dpr);
        m_oldHoverPos = current_pos;
    }
    event->accept();
}

void VideoSurface::mouseDoubleClickEvent(QMouseEvent* event)
{
    int vlc_button = qtMouseButton2VLC( event->button() );
    if( vlc_button >= 0 )
    {
        emit mouseDblClicked(vlc_button);
        event->accept();
    }
    else
        event->ignore();
}

void VideoSurface::keyPressEvent(QKeyEvent* event)
{
    emit keyPressed(event->key(), event->modifiers());
    event->ignore();
}

#if QT_CONFIG(wheelevent)
void VideoSurface::wheelEvent(QWheelEvent *event)
{
    m_wheelEventConverter.wheelEvent(event);
    event->accept();
}
#endif

Qt::CursorShape VideoSurface::getCursorShape() const
{
    return cursor().shape();
}

void VideoSurface::setCursorShape(Qt::CursorShape shape)
{
    setCursor(shape);
}

void VideoSurface::synchronize()
{
    // This may be called from the rendering thread, not necessarily
    // during synchronization (GUI thread is not blocked). Try to
    // be very careful.

    QSizeF size;
    QPointF position;

    static const bool isObjectThread = QThread::currentThread() == thread();
    if (isObjectThread)
    {
        assert(QThread::currentThread() == thread());
        // Item's thread (GUI thread):
        size = this->size();
        position = this->mapToScene(QPointF(0,0));
    }
    else
    {
        assert(QThread::currentThread() != thread());
        // Render thread:
        size = renderSize();
        position = renderPosition();
    }

    std::optional<QSizeF> newSize;
    std::optional<QPointF> newPosition;
    std::optional<qreal> newScale;

    if (m_allDirty || m_dprDirty || m_oldRenderSize != size)
    {
        if (!size.isEmpty())
        {
            newSize = size * m_dpr;
            m_oldRenderSize = size;
        }
    }

    if (m_allDirty || m_dprDirty || m_oldRenderPosition != position)
    {
        if (position.x() >= 0.0 && position.y() >= 0.0)
        {
            newPosition = position * m_dpr; // render position is relative to scene/viewport
            m_oldRenderPosition = position;
        }
    }

    if (m_allDirty || m_dprDirty)
    {
        newScale = m_dpr;
        m_dprDirty = false;
    }

    if (newPosition || newSize || newScale)
        emit surfacePropertiesChanged(newSize, newPosition, newScale);

    m_allDirty = false;
}

void VideoSurface::itemChange(ItemChange change, const ItemChangeData &value)
{
    switch (change)
    {
        case ItemSceneChange:
        {
            // It is intentional that window connection is made in `::updatePaintNode()`, and not here, because we don't
            // want to explicitly connect whenever `ItemHasContents`, `isVisible()`, `window()` are all satisfied, which
            // is implicitly the case with `::updatePaintNode()` (it is only called when all these are satisfied). This
            // is strictly for maintenance reasons.

            disconnect(m_synchConnection);

            // if window changed but is valid, we can signal dpr change just to be sure, It is not clear if Qt signals
            // ItemDevicePixelRatioHasChanged when item's window/scene changes to a new window that has different DPR:
            if (value.window)
                [[fallthrough]];
            else
                break;
        }
        case ItemDevicePixelRatioHasChanged:
        {
            m_dprChanged = true;
            // Request update, so that `updatePaintNode()` gets called which updates the DPR for `::synchronize()`:
            if (flags().testFlag(ItemHasContents)) // "Only items which specify QQuickItem::ItemHasContents are allowed to call QQuickItem::update()."
                update();
            break;
        }
        case ItemVisibleHasChanged:
        {
            if (!value.boolValue)
            {
                // Connection is made in `::updatePaintNode()` (which is called when both the item is visible and `ItemHasContents` is set).
                disconnect(m_synchConnection);
            }
            else if (flags().testFlag(ItemHasContents))
            {
                // An invisible initial paint can consume the pending update
                // before the synchronization connection can be made.
                update();
            }
            break;
        }
        default: break;
    }

    QQuickItem::itemChange(change, value);
}

void VideoSurface::setVideoSurfaceProvider(VideoSurfaceProvider *newVideoSurfaceProvider)
{
    if (m_provider == newVideoSurfaceProvider)
        return;

    if (m_provider)
    {
        disconnect(this, nullptr, m_provider, nullptr);
        disconnect(&m_wheelEventConverter, nullptr, m_provider, nullptr);
        disconnect(m_provider, nullptr, this, nullptr);

        assert(m_provider->videoSurface() == this);
        m_provider->setVideoSurface({});
    }

    m_provider = newVideoSurfaceProvider;

    if (m_provider)
    {
        if (const auto current = m_provider->videoSurface())
            current->setVideoSurfaceProvider(nullptr); // it is probably not a good idea to break the QML binding here

        connect(this, &VideoSurface::mouseMoved, m_provider, &VideoSurfaceProvider::onMouseMoved);
        connect(this, &VideoSurface::mousePressed, m_provider, &VideoSurfaceProvider::onMousePressed);
        connect(this, &VideoSurface::mouseDblClicked, m_provider, &VideoSurfaceProvider::onMouseDoubleClick);
        connect(this, &VideoSurface::mouseReleased, m_provider, &VideoSurfaceProvider::onMouseReleased);
        connect(this, &VideoSurface::keyPressed, m_provider, &VideoSurfaceProvider::onKeyPressed);
        connect(this, &VideoSurface::surfacePropertiesChanged, m_provider, &VideoSurfaceProvider::onSurfacePropertiesChanged, Qt::DirectConnection);

        // With auto connection, this should be queued if the signal was emitted from vout thread,
        // so that the slot is executed in item's thread:
        connect(m_provider, &VideoSurfaceProvider::videoEnabledChanged, this, [this](bool enabled) {
            if (enabled)
            {
                m_videoEnabledChanged = true;
                if (flags().testFlag(ItemHasContents)) // "Only items which specify QQuickItem::ItemHasContents are allowed to call QQuickItem::update()."
                    update();
            }
        });

        connect(&m_wheelEventConverter, &WheelToVLCConverter::vlcWheelKey, m_provider, &VideoSurfaceProvider::onMouseWheeled);

        assert(!m_provider->videoSurface());
        m_provider->setVideoSurface(this);

        setFlag(ItemHasContents, true);
        update(); // this should not be necessary right after setting `ItemHasContents`, but just in case
    }
    else
    {
        setFlag(ItemHasContents, false);
        // Connection is made in `::updatePaintNode()` (which is called when both the item is visible and `ItemHasContents` is set).
        disconnect(m_synchConnection);
    }

    emit videoSurfaceProviderChanged();
}

QSGNode *VideoSurface::updatePaintNode(QSGNode *node, UpdatePaintNodeData *data)
{
    // This is called from the render thread, but during synchronization.
    // So the GUI thread is blocked here. This makes it safer to access the window
    // to get the effective DPR, rather than doing it outside the synchronization
    // stage.

    const auto w = window();
    assert (w);

    if (Q_UNLIKELY(!m_provider))
        return node;

    // WARNING: For some reason `::updatePaintNode()` is called initially when the item is invisible.
    if (!m_synchConnection && isVisible())
    {
        // Disconnection is made in `::itemChange()`'s `ItemSceneChange` handler.

        // This is constant:
        if (m_provider->supportsThreadedSurfaceUpdates())
        {
            // Synchronize just before swapping the frame for better synchronization:
            m_synchConnection = connect(w, &QQuickWindow::afterRendering, this, &VideoSurface::synchronize, Qt::DirectConnection);
        }
        else
        {
            m_synchConnection = connect(w, &QQuickWindow::afterAnimating, this, &VideoSurface::synchronize);
        }
    }

    if (m_dprChanged)
    {
        m_dpr = w->effectiveDevicePixelRatio();
        m_dprDirty = true;
        m_dprChanged = false;
    }

    if (m_videoEnabledChanged)
    {
        m_allDirty = true;
        m_videoEnabledChanged = false;
    }

    if (QThread::currentThread() == thread())
    {
        // As per `::synchronize()` we do not need `ViewBlockingRectangle` to provide the render position in this case:
        setUpdateRenderPosition(false);
        // Override `ViewBlockingRectangle`'s `ItemHasContents`, if it is unset (when both `renderEnabled` and
        // `updateRenderPosition()` are false):
        setFlag(ItemHasContents, true);
    }
    else
    {
        setUpdateRenderPosition(true);
    }

    return ViewBlockingRectangle::updatePaintNode(node, data);
}
