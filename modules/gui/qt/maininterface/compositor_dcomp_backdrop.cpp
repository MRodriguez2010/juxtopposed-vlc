// SPDX-License-Identifier: GPL-2.0-or-later
#if !defined(_WIN32_WINNT) || _WIN32_WINNT < 0x0603
# undef _WIN32_WINNT
# define _WIN32_WINNT 0x0603
#endif
#include "compositor_dcomp_backdrop.hpp"

#include <QMutex>
#include <QMutexLocker>
#include <QDebug>
#include <QLoggingCategory>
#include <atomic>
#include <algorithm>
#include <cmath>
#include <map>

using Microsoft::WRL::ComPtr;
#define RETURN_IF_FAILED(call) do { const HRESULT result = (call); if (FAILED(result)) return result; } while (0)

namespace vlc {

Q_LOGGING_CATEGORY(lcVideoBackdrop, "vlc.gui.video.backdrop", QtWarningMsg)

struct DCompVideoBackdrop::Private
{
    struct Visual
    {
        ComPtr<IDCompositionVisual> panel, blur, source;
        ComPtr<IDCompositionRectangleClip> clip;
        ComPtr<IDCompositionGaussianBlurEffect> effect;
        VideoBackdropRegion lastRegion;
        QPointF lastPosition;
        IUnknown *lastContent = nullptr;
    };
    QMutex lock;
    ComPtr<IDCompositionDevice> interfaceDevice;
    ComPtr<IDCompositionVisual> root, ui;
    HMODULE library = nullptr;
    ComPtr<IDCompositionDevice> effectDevice;
    ComPtr<IDCompositionDevice3> effects;
    ComPtr<IUnknown> content;
    VideoBackdropState state;
    QPointF position;
    std::map<quintptr, Visual> visuals;
    bool enabled = false;
    bool closed = false;
    bool failed = false;

    ~Private()
    {
        effects.Reset();
        effectDevice.Reset();
        if (library)
            FreeLibrary(library);
    }

    HRESULT ensureDevice()
    {
        if (effects)
            return S_OK;
        library = LoadLibraryExW(L"dcomp.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
        if (!library)
            return HRESULT_FROM_WIN32(GetLastError());
        using CreateDevice = HRESULT (WINAPI *)(IUnknown *, REFIID, void **);
        const auto create = reinterpret_cast<CreateDevice>(GetProcAddress(library, "DCompositionCreateDevice3"));
        if (!create)
            return E_NOINTERFACE;
        RETURN_IF_FAILED(create(nullptr, IID_PPV_ARGS(&effectDevice)));
        return effectDevice.As(&effects);
    }

    HRESULT createVisual(Visual &visual)
    {
        RETURN_IF_FAILED(effectDevice->CreateVisual(&visual.panel));
        RETURN_IF_FAILED(effectDevice->CreateVisual(&visual.blur));
        RETURN_IF_FAILED(effectDevice->CreateVisual(&visual.source));
        RETURN_IF_FAILED(effectDevice->CreateRectangleClip(&visual.clip));
        RETURN_IF_FAILED(effects->CreateGaussianBlurEffect(&visual.effect));
        RETURN_IF_FAILED(visual.effect->SetBorderMode(D2D1_BORDER_MODE_HARD));
        RETURN_IF_FAILED(visual.blur->SetEffect(visual.effect.Get()));
        RETURN_IF_FAILED(visual.blur->AddVisual(visual.source.Get(), FALSE, nullptr));
        RETURN_IF_FAILED(visual.panel->AddVisual(visual.blur.Get(), FALSE, nullptr));
        return visual.panel->SetClip(visual.clip.Get());
    }

    HRESULT updateVisual(Visual &visual, const VideoBackdropRegion &region, bool fresh)
    {
        if (fresh || !(region == visual.lastRegion) || position != visual.lastPosition)
        {
            const auto rect = region.rect;
            const float radius = std::min({region.cornerRadius, rect.width() / 2, rect.height() / 2});
            RETURN_IF_FAILED(visual.panel->SetOffsetX(rect.x()));
            RETURN_IF_FAILED(visual.panel->SetOffsetY(rect.y()));
            RETURN_IF_FAILED(visual.clip->SetLeft(0.0f));
            RETURN_IF_FAILED(visual.clip->SetTop(0.0f));
            RETURN_IF_FAILED(visual.clip->SetRight(rect.width()));
            RETURN_IF_FAILED(visual.clip->SetBottom(rect.height()));
            RETURN_IF_FAILED(visual.clip->SetTopLeftRadiusX(radius));
            RETURN_IF_FAILED(visual.clip->SetTopLeftRadiusY(radius));
            RETURN_IF_FAILED(visual.clip->SetTopRightRadiusX(radius));
            RETURN_IF_FAILED(visual.clip->SetTopRightRadiusY(radius));
            RETURN_IF_FAILED(visual.clip->SetBottomLeftRadiusX(radius));
            RETURN_IF_FAILED(visual.clip->SetBottomLeftRadiusY(radius));
            RETURN_IF_FAILED(visual.clip->SetBottomRightRadiusX(radius));
            RETURN_IF_FAILED(visual.clip->SetBottomRightRadiusY(radius));
            RETURN_IF_FAILED(visual.effect->SetStandardDeviation(region.blurRadius));
            RETURN_IF_FAILED(visual.source->SetOffsetX(position.x() - rect.x()));
            RETURN_IF_FAILED(visual.source->SetOffsetY(position.y() - rect.y()));
            // Crop before applying the effect. Retain three standard deviations
            // around the panel so its edge samples do not see the cropped border.
            const qreal padding = std::ceil(3 * region.blurRadius);
            const QRectF crop = rect.translated(-position).adjusted(-padding, -padding, padding, padding);
            const D2D_RECT_F sourceClip{float(crop.left()), float(crop.top()),
                                       float(crop.right()), float(crop.bottom())};
            RETURN_IF_FAILED(visual.source->SetClip(sourceClip));
            visual.lastRegion = region;
            visual.lastPosition = position;
            qCDebug(lcVideoBackdrop) << "Region" << region.id << rect
                                    << "sigma" << region.blurRadius << "padding" << padding;
        }
        if (fresh || visual.lastContent != content.Get())
        {
            RETURN_IF_FAILED(visual.source->SetContent(content.Get()));
            visual.lastContent = content.Get();
        }
        return S_OK;
    }

    void clear()
    {
        if (!visuals.empty())
            qCDebug(lcVideoBackdrop) << "Clear regions" << visuals.size();
        for (auto &[id, visual] : visuals)
        {
            root->RemoveVisual(visual.panel.Get());
            visual.source->SetContent(nullptr);
        }
        visuals.clear();
    }

    HRESULT sync()
    {
        if (closed || failed)
            return S_FALSE;
        if (!enabled || !content || state.regions.isEmpty())
        {
            if (visuals.empty())
                return S_FALSE;
            clear();
        }
        else
        {
            RETURN_IF_FAILED(ensureDevice());
            for (auto it = visuals.begin(); it != visuals.end();)
            {
                const bool keep = std::any_of(state.regions.begin(), state.regions.end(),
                    [id = it->first](const auto &region) { return region.id == id; });
                if (keep)
                    ++it;
                else
                {
                    RETURN_IF_FAILED(root->RemoveVisual(it->second.panel.Get()));
                    RETURN_IF_FAILED(it->second.source->SetContent(nullptr));
                    it = visuals.erase(it);
                }
            }
            for (const auto &region : state.regions)
            {
                if (region.rect.isEmpty() || region.blurRadius <= 0)
                    continue;
                auto it = visuals.find(region.id);
                const bool fresh = it == visuals.end();
                if (fresh)
                {
                    Visual visual;
                    RETURN_IF_FAILED(createVisual(visual));
                    RETURN_IF_FAILED(updateVisual(visual, region, true));
                    RETURN_IF_FAILED(root->AddVisual(visual.panel.Get(), FALSE, ui.Get()));
                    it = visuals.emplace(region.id, std::move(visual)).first;
                }
                else
                    RETURN_IF_FAILED(updateVisual(it->second, region, false));
            }
        }
        // Each device owns a separate transaction, even in the same visual tree.
        if (effectDevice)
            RETURN_IF_FAILED(effectDevice->Commit());
        return interfaceDevice->Commit();
    }

    HRESULT apply()
    {
        const auto result = sync();
        if (FAILED(result))
        {
            clear();
            if (effectDevice)
                effectDevice->Commit();
            interfaceDevice->Commit();
            failed = true;
            qWarning("Video backdrop blur failed: 0x%08lx", static_cast<unsigned long>(result));
        }
        return result;
    }
};

DCompVideoBackdrop::DCompVideoBackdrop(IDCompositionDevice *device, IDCompositionVisual *root, IDCompositionVisual *ui)
    : d(std::make_unique<Private>())
{
    d->interfaceDevice = device;
    d->root = root;
    d->ui = ui;
}

DCompVideoBackdrop::~DCompVideoBackdrop() { close(); }

HRESULT DCompVideoBackdrop::setRegions(const VideoBackdropState &state)
{
    QMutexLocker lock(&d->lock);
    // GUI teardown and render updates may emit snapshots from different threads.
    if (state.revision < d->state.revision ||
        (state.revision == d->state.revision && state.regions == d->state.regions))
        return S_FALSE;
    d->state = state;
    qCDebug(lcVideoBackdrop) << "Backdrop regions" << state.revision << state.regions.size();
    return d->apply();
}

HRESULT DCompVideoBackdrop::setContent(IUnknown *content)
{
    QMutexLocker lock(&d->lock);
    if (d->closed || (!d->enabled && content) || content == d->content.Get())
        return S_FALSE;
    d->content = content;
    qCDebug(lcVideoBackdrop) << "Backdrop content" << bool(content);
    return d->apply();
}

HRESULT DCompVideoBackdrop::setPosition(const QPointF &position)
{
    QMutexLocker lock(&d->lock);
    if (d->position == position)
        return S_FALSE;
    d->position = position;
    return d->apply();
}

HRESULT DCompVideoBackdrop::setEnabled(bool enabled)
{
    QMutexLocker lock(&d->lock);
    d->enabled = enabled;
    qCDebug(lcVideoBackdrop) << "Backdrop enabled" << enabled;
    if (!enabled)
        d->content.Reset();
    return d->apply();
}

void DCompVideoBackdrop::close()
{
    QMutexLocker lock(&d->lock);
    if (d->closed)
        return;
    d->clear();
    d->content.Reset();
    if (d->effectDevice)
        d->effectDevice->Commit();
    d->interfaceDevice->Commit();
    d->closed = true;
}

class VideoBackdropProxy final : public IDCompositionVisual
{
public:
    VideoBackdropProxy(IDCompositionVisual *visual, std::shared_ptr<DCompVideoBackdrop> backdrop)
        : m_visual(visual), m_backdrop(std::move(backdrop)) {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **out) override
    {
        if (!out) return E_POINTER;
        *out = nullptr;
        // Older MinGW dcomp.h headers omit the __uuidof specialization for V1.
        static constexpr GUID visualIid{0x4d93059d, 0x097b, 0x4651,
                                       {0x9a, 0x60, 0xf0, 0xf2, 0x51, 0x16, 0xe2, 0xf3}};
        if (iid != __uuidof(IUnknown) && iid != visualIid)
            return E_NOINTERFACE;
        *out = static_cast<IDCompositionVisual *>(this);
        AddRef();
        return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++m_refs; }
    ULONG STDMETHODCALLTYPE Release() override
    {
        const auto refs = --m_refs;
        if (!refs) delete this;
        return refs;
    }
    HRESULT STDMETHODCALLTYPE SetContent(IUnknown *content) override
    {
        const auto result = m_visual->SetContent(content);
        if (SUCCEEDED(result)) m_backdrop->setContent(content);
        return result;
    }
    HRESULT STDMETHODCALLTYPE SetOffsetX(float value) override { return m_visual->SetOffsetX(value); }
    HRESULT STDMETHODCALLTYPE SetOffsetX(IDCompositionAnimation *value) override { return m_visual->SetOffsetX(value); }
    HRESULT STDMETHODCALLTYPE SetOffsetY(float value) override { return m_visual->SetOffsetY(value); }
    HRESULT STDMETHODCALLTYPE SetOffsetY(IDCompositionAnimation *value) override { return m_visual->SetOffsetY(value); }
    HRESULT STDMETHODCALLTYPE SetTransform(const D2D_MATRIX_3X2_F &value) override { return m_visual->SetTransform(value); }
    HRESULT STDMETHODCALLTYPE SetTransform(IDCompositionTransform *value) override { return m_visual->SetTransform(value); }
    HRESULT STDMETHODCALLTYPE SetTransformParent(IDCompositionVisual *value) override { return m_visual->SetTransformParent(value); }
    HRESULT STDMETHODCALLTYPE SetEffect(IDCompositionEffect *value) override { return m_visual->SetEffect(value); }
    HRESULT STDMETHODCALLTYPE SetBitmapInterpolationMode(DCOMPOSITION_BITMAP_INTERPOLATION_MODE value) override { return m_visual->SetBitmapInterpolationMode(value); }
    HRESULT STDMETHODCALLTYPE SetBorderMode(DCOMPOSITION_BORDER_MODE value) override { return m_visual->SetBorderMode(value); }
    HRESULT STDMETHODCALLTYPE SetClip(const D2D_RECT_F &value) override { return m_visual->SetClip(value); }
    HRESULT STDMETHODCALLTYPE SetClip(IDCompositionClip *value) override { return m_visual->SetClip(value); }
    HRESULT STDMETHODCALLTYPE AddVisual(IDCompositionVisual *value, BOOL above, IDCompositionVisual *reference) override { return m_visual->AddVisual(value, above, reference); }
    HRESULT STDMETHODCALLTYPE RemoveVisual(IDCompositionVisual *value) override { return m_visual->RemoveVisual(value); }
    HRESULT STDMETHODCALLTYPE RemoveAllVisuals() override { return m_visual->RemoveAllVisuals(); }
    HRESULT STDMETHODCALLTYPE SetCompositeMode(DCOMPOSITION_COMPOSITE_MODE value) override { return m_visual->SetCompositeMode(value); }
private:
    std::atomic<ULONG> m_refs{1};
    ComPtr<IDCompositionVisual> m_visual;
    std::shared_ptr<DCompVideoBackdrop> m_backdrop;
};

IDCompositionVisual *makeVideoBackdropProxy(IDCompositionVisual *visual, std::shared_ptr<DCompVideoBackdrop> backdrop)
{
    return new VideoBackdropProxy(visual, std::move(backdrop));
}

}
#undef RETURN_IF_FAILED
