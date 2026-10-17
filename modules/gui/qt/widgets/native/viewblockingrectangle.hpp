/*****************************************************************************
 * Copyright (C) 2022 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * ( at your option ) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifndef VIEWBLOCKINGRECTANGLE_HPP
#define VIEWBLOCKINGRECTANGLE_HPP

#include <QQuickItem>
#include <QColor>
#include <QMatrix4x4>
#include <QSGRenderNode>
#include <QSGTransformNode>
#include <functional>
#include <cassert>

// WARNING: Do not use QSGTransformNode here with preprocess, Qt does not
//          necessarily call preprocess when the combined matrix changes!
class MatrixChangeObserverNode : public QSGRenderNode
{
public:
    explicit MatrixChangeObserverNode(const std::function<void(const QMatrix4x4&)>& callback,
                                      bool everyFrame = false)
        : m_callback(callback), m_everyFrame(everyFrame) { }

    // Observe render-thread animations after synchronization. A layer renderer
    // starts at a nested root, so its pass matrix is not in window coordinates.
    void prepare() override
    {
        QSGRenderNode::prepare(); // The documentation says that the default implementation is empty, but still call it just in case.

        QMatrix4x4 m;
        for (const QSGNode *node = parent(); node; node = node->parent())
            if (node->type() == QSGNode::TransformNodeType)
                m = static_cast<const QSGTransformNode *>(node)->matrix() * m;
        if (m_everyFrame || m_lastCombinedMatrix != m)
        {
            m_callback(m);
            m_lastCombinedMatrix = m;
        }
    }

    void render(const RenderState *) override
    {
        // We do not render anything in this node.
    }

    RenderingFlags flags() const override
    {
        // Enable all optimizations, as we are not actually rendering anything in this node:
        return static_cast<RenderingFlags>(BoundedRectRendering | DepthAwareRendering | OpaqueRendering | NoExternalRendering);
    }
private:
    std::function<void(const QMatrix4x4& newMatrix)> m_callback;
    QMatrix4x4 m_lastCombinedMatrix;
    bool m_everyFrame;
};

class ViewBlockingRectangle : public QQuickItem
{
    Q_OBJECT

    Q_PROPERTY(QColor color MEMBER m_color NOTIFY colorChanged FINAL)
    Q_PROPERTY(bool renderingEnabled MEMBER m_renderingEnabled WRITE setRenderingEnabled NOTIFY renderingEnabledChanged FINAL)

public:
    explicit ViewBlockingRectangle(QQuickItem *parent = nullptr);

protected:
    QSGNode *updatePaintNode(QSGNode *, UpdatePaintNodeData *) override;

    // For now these are protected, but can be made public if necessary:
    // These methods should only be called from the rendering thread.
    QSizeF renderSize() const;
    QPointF renderPosition() const;
    void setRenderingEnabled(bool enabled);
    void setUpdateRenderPosition(bool update);
    bool updateRenderPosition() const;

    void componentComplete() override;

private:
    QColor m_color;
    bool m_windowChanged = false;

    bool m_renderingEnabled = true;

    // Updating the render position (`m_renderPosition`) requires an additional
    // scene graph node, albeit lightweight, thus it is an opt-in feature:
    bool m_updateRenderPosition = false;

    // Although these members belong to the class instance's thread, they
    // are updated in the rendering thread:
    QSizeF m_renderSize;
    QPointF m_renderPosition {-1., -1.};

signals:
    // NOTE: `scenePositionHasChanged()` signal is emitted from the render thread,
    //       and NOT during synchronization (meaning, GUI thread is not blocked):
    void scenePositionHasChanged();
    void colorChanged();
    void renderingEnabledChanged();
};

#endif
