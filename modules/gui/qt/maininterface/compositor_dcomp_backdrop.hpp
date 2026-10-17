// SPDX-License-Identifier: GPL-2.0-or-later
#ifndef VLC_QT_DCOMP_BACKDROP_HPP
#define VLC_QT_DCOMP_BACKDROP_HPP

#include "util/video_backdrop_region.hpp"
#include <wrl.h>
#include <dcomp.h>
#include <memory>

namespace vlc {

// A second device supplies effects while Qt retains its own device and target.
class DCompVideoBackdrop
{
public:
    DCompVideoBackdrop(IDCompositionDevice *, IDCompositionVisual *root, IDCompositionVisual *ui);
    ~DCompVideoBackdrop();
    HRESULT setRegions(const VideoBackdropState &);
    HRESULT setContent(IUnknown *);
    HRESULT setPosition(const QPointF &);
    HRESULT setEnabled(bool);
    void close();

private:
    struct Private;
    std::unique_ptr<Private> d;
};

// Only the real visual enters the composition tree. The vout's SetContent call
// also updates the mirrors, including when the swapchain is replaced.
IDCompositionVisual *makeVideoBackdropProxy(IDCompositionVisual *, std::shared_ptr<DCompVideoBackdrop>);

}
#endif
