// SPDX-License-Identifier: GPL-2.0-or-later
#if !defined(_WIN32_WINNT) || _WIN32_WINNT < 0x0603
# undef _WIN32_WINNT
# define _WIN32_WINNT 0x0603
#endif
#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <QTest>
#include "maininterface/compositor_dcomp_backdrop.hpp"

using Microsoft::WRL::ComPtr;

class TestDCompBackdrop : public QObject
{
    Q_OBJECT
private slots:
    void lifecycle()
    {
        QVERIFY(SUCCEEDED(CoInitializeEx(nullptr, COINIT_MULTITHREADED)));
        struct ComGuard { ~ComGuard() { CoUninitialize(); } } comGuard;
        ComPtr<ID3D11Device> gpu;
        ComPtr<ID3D11DeviceContext> context;
        QCOMPARE(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr,
                                  D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0,
                                  D3D11_SDK_VERSION, &gpu, nullptr, &context), S_OK);
        ComPtr<IDXGIDevice> dxgi;
        QCOMPARE(gpu.As(&dxgi), S_OK);
        ComPtr<IDXGIAdapter> adapter;
        QCOMPARE(dxgi->GetAdapter(&adapter), S_OK);
        ComPtr<IDXGIFactory2> factory;
        QCOMPARE(adapter->GetParent(IID_PPV_ARGS(&factory)), S_OK);
        DXGI_SWAP_CHAIN_DESC1 desc{};
        desc.Width = 256; desc.Height = 128;
        desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
        desc.SampleDesc.Count = 1;
        desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
        desc.BufferCount = 2;
        desc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
        desc.AlphaMode = DXGI_ALPHA_MODE_PREMULTIPLIED;
        ComPtr<IDXGISwapChain1> first, second;
        QCOMPARE(factory->CreateSwapChainForComposition(gpu.Get(), &desc, nullptr, &first), S_OK);
        desc.Width = 512;
        QCOMPARE(factory->CreateSwapChainForComposition(gpu.Get(), &desc, nullptr, &second), S_OK);
        ComPtr<IDCompositionDevice> device;
        QCOMPARE(DCompositionCreateDevice(dxgi.Get(), IID_PPV_ARGS(&device)), S_OK);
        const HWND hwnd = CreateWindowExW(0, L"STATIC", L"Backdrop test",
                                          WS_POPUP, 0, 0, 540, 140, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
        QVERIFY(hwnd);
        struct WindowGuard { HWND hwnd; ~WindowGuard() { DestroyWindow(hwnd); } } guard{hwnd};
        ShowWindow(hwnd, SW_SHOWNOACTIVATE);
        ComPtr<IDCompositionTarget> target;
        QCOMPARE(device->CreateTargetForHwnd(hwnd, TRUE, &target), S_OK);
        ComPtr<IDCompositionVisual> root, original, ui;
        QCOMPARE(device->CreateVisual(&root), S_OK);
        QCOMPARE(device->CreateVisual(&original), S_OK);
        QCOMPARE(device->CreateVisual(&ui), S_OK);
        QCOMPARE(root->AddVisual(original.Get(), FALSE, nullptr), S_OK);
        QCOMPARE(root->AddVisual(ui.Get(), TRUE, original.Get()), S_OK);
        QCOMPARE(target->SetRoot(root.Get()), S_OK);

        auto backdrop = std::make_shared<vlc::DCompVideoBackdrop>(device.Get(), root.Get(), ui.Get());
        VideoBackdropState state{1, {{1, QRectF(40, 20, 120, 80), 25, 10}}};
        QVERIFY(SUCCEEDED(backdrop->setRegions(state)));
        QVERIFY(SUCCEEDED(backdrop->setEnabled(true)));
        ComPtr<IDCompositionVisual> proxy;
        proxy.Attach(vlc::makeVideoBackdropProxy(original.Get(), backdrop));
        ComPtr<IUnknown> identity;
        QCOMPARE(proxy.As(&identity), S_OK);
        QCOMPARE(identity.Get(), static_cast<IUnknown *>(proxy.Get()));
        ComPtr<IDCompositionVisual2> unsupported;
        QCOMPARE(proxy.As(&unsupported), E_NOINTERFACE);
        QCOMPARE(proxy->SetContent(first.Get()), S_OK);
        QCOMPARE(backdrop->setRegions(state), S_FALSE);
        QCOMPARE(backdrop->setPosition(QPointF(10, 15)), S_OK);
        state.revision = 2;
        state.regions[0].rect = QRectF(60, 20, 110, 90);
        QCOMPARE(backdrop->setRegions(state), S_OK);
        const VideoBackdropState stale{1, {}};
        QCOMPARE(backdrop->setRegions(stale), S_FALSE);
        QCOMPARE(proxy->SetContent(second.Get()), S_OK);
        QVERIFY(FAILED(proxy->SetContent(identity.Get())));
        QCOMPARE(proxy->SetContent(nullptr), S_OK);
        QCOMPARE(proxy->SetContent(first.Get()), S_OK);
        state.revision = 3;
        state.regions.append({2, QRectF(180, 10, 70, 110), 12, 6});
        QCOMPARE(backdrop->setRegions(state), S_OK);
        state.revision = 4;
        state.regions.removeFirst();
        QCOMPARE(backdrop->setRegions(state), S_OK);
        QVERIFY(SUCCEEDED(backdrop->setEnabled(false)));
        QVERIFY(SUCCEEDED(backdrop->setEnabled(true)));
        QCOMPARE(proxy->SetContent(second.Get()), S_OK);
        QCOMPARE(device->Commit(), S_OK);
        QCOMPARE(device->WaitForCommitCompletion(), S_OK);
        BOOL valid = FALSE;
        QCOMPARE(device->CheckDeviceState(&valid), S_OK);
        QVERIFY(valid);
        // A renderer may release its raw visual handle after the UI is closed.
        backdrop->close();
        QCOMPARE(proxy->SetContent(first.Get()), S_OK);
        state.revision = 5;
        state.regions.clear();
        QCOMPARE(backdrop->setRegions(state), S_FALSE);
        QCOMPARE(target->SetRoot(nullptr), S_OK);
        QCOMPARE(device->Commit(), S_OK);
    }
};

QTEST_GUILESS_MAIN(TestDCompBackdrop)
#include "test_dcomp_backdrop.moc"
