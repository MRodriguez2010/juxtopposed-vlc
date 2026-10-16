// SPDX-License-Identifier: LGPL-2.1-or-later
/*****************************************************************************
 * opengl_win_offscreen: Windows offscreen OpenGL module
 *****************************************************************************
 * Copyright © 2025 Videolabs, VLC authors and VideoLAN
 *
 * Authors: Alexandre Janniaux <ajanni@videolabs.io>
 *          Romain Vimont <rom1v@videolabs.io>
 *          Steve Lhomme <robux4@videolabs.io>
 *****************************************************************************/
#ifdef HAVE_CONFIG_H
# include <config.h>
#endif
#include <limits.h>

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_modules.h>
#include <vlc_picture.h>
#include <vlc_filter.h>
#include <vlc_opengl.h>
#include <vlc_vout_display.h>
#include <vlc_atomic.h>
#include "../video_output/opengl/vout_helper.h"
#include "../video_output/opengl/filters.h"
#include "../video_output/opengl/gl_api.h"
#include "../video_output/opengl/gl_common.h"
#include "../video_output/opengl/interop.h"
#include <GL/glew.h>
#include <GL/wglew.h>

#include "offscreen_readback.h"

#define BUFFER_COUNT 4

struct wgl_vt {
    PFNWGLGETEXTENSIONSSTRINGARBPROC     GetExtensionsStringARB;
    PFNWGLCHOOSEPIXELFORMATARBPROC       ChoosePixelFormatARB;
    PFNWGLCREATEPBUFFERARBPROC           CreatePbufferARB;
    PFNWGLDESTROYPBUFFERARBPROC          DestroyPbufferARB;
    PFNWGLGETPBUFFERDCARBPROC            GetPbufferDCARB;
    PFNWGLRELEASEPBUFFERDCARBPROC        ReleasePbufferDCARB;
};
struct pbo_picture_context
{
    struct picture_context_t context;
    void *buffer_mapping;
    int rc;
    vlc_mutex_t *lock;
    vlc_cond_t *cond;
};

struct vlc_gl_pbuffer
{
    vlc_mutex_t             lock;
    vlc_cond_t              cond;

    video_format_t          fmt_out;

    HMODULE                 hOpengl;
    HPBUFFERARB             hbuffer;
    HDC                     pixelBufferDC;
    HGLRC                   hGLRC;

    struct wgl_vt           wgl_vt;
    struct vlc_gl_api       api;

    size_t                  current_flip;
    GLuint                  pixelbuffers[BUFFER_COUNT];
    GLuint                  framebuffers[BUFFER_COUNT];
    GLuint                  textures[BUFFER_COUNT];
    struct pbo_picture_context     picture_contexts[BUFFER_COUNT];

    bool current;
    bool default_framebuffer;
    offscreen_read_buffer_fn read_buffer;
    GLint default_read_buffer;
};

static int MakeCurrentBare (vlc_gl_t *gl)
{
    struct vlc_gl_pbuffer *sys = gl->sys;

    BOOL success = wglMakeCurrent(sys->pixelBufferDC, sys->hGLRC);
    if (unlikely(!success))
        return VLC_EGENERIC;

    return VLC_SUCCESS;
}

static int MakeBoundCurrent (vlc_gl_t *gl)
{
    struct vlc_gl_pbuffer *sys = gl->sys;

    assert(!sys->current);
    int err = MakeCurrentBare(gl);
    if (err != VLC_SUCCESS)
        return err;

    sys->current = true;

    const opengl_vtable_t *vt = &sys->api.vt;
    vt->BindBuffer(GL_PIXEL_PACK_BUFFER, sys->default_framebuffer ? 0 : sys->pixelbuffers[sys->current_flip]);
    vt->BindFramebuffer(GL_FRAMEBUFFER, sys->default_framebuffer ? 0 : sys->framebuffers[sys->current_flip]);

    return VLC_SUCCESS;
}

static void ReleaseCurrent (vlc_gl_t *gl)
{
    struct vlc_gl_pbuffer *sys = gl->sys;

    assert(sys->current);
    wglMakeCurrent(NULL, NULL);

    sys->current = false;
}

static void *GetSymbol(vlc_gl_t *gl, const char *procname)
{
    struct vlc_gl_pbuffer *sys = gl->sys;
    /* See https://www.khronos.org/opengl/wiki/Load_OpenGL_Functions */
    PROC f= wglGetProcAddress(procname);
    if(f == 0 || (f == (void*)0x1) || (f == (void*)0x2) ||
      (f == (void*)0x3) || (f == (void*)-1) )
    {
        f = GetProcAddress(sys->hOpengl, procname);
    }
    return f;
}

static picture_context_t *picture_context_copy(picture_context_t *input)
{
    struct pbo_picture_context *context =
        (struct pbo_picture_context *)input;

    vlc_mutex_lock(context->lock);
    context->rc++;
    vlc_mutex_unlock(context->lock);
    return input;
}

static void picture_context_destroy(picture_context_t *input)
{
    struct pbo_picture_context *context = (struct pbo_picture_context *) input;

    vlc_mutex_lock(context->lock);
    context->rc--;
    vlc_cond_signal(context->cond);
    vlc_mutex_unlock(context->lock);
}

static inline void BindDrawFramebuffer(struct vlc_gl_pbuffer *sys)
{
    const opengl_vtable_t *vt = &sys->api.vt;
    vt->BindFramebuffer(GL_DRAW_FRAMEBUFFER,
                        sys->framebuffers[sys->current_flip]);
}

static void UpdateBuffer(vlc_gl_t *gl)
{
    struct vlc_gl_pbuffer *sys = gl->sys;

    vlc_mutex_lock(&sys->lock);
    size_t index;

    do {
        for (index = 0; index < BUFFER_COUNT; ++index)
        {
            assert(sys->picture_contexts[index].rc >= 0);
            if (sys->picture_contexts[index].rc == 0)
                goto out_loop;
        }
        vlc_cond_wait(&sys->cond, &sys->lock);
    } while (index == BUFFER_COUNT);
out_loop:
    vlc_mutex_unlock(&sys->lock);

    sys->current_flip = index;
    if (!sys->default_framebuffer)
        BindDrawFramebuffer(sys);
}

static picture_t *Swap(vlc_gl_t *gl)
{
    struct vlc_gl_pbuffer *sys = gl->sys;
    const opengl_vtable_t *vt = &sys->api.vt;

    if (!sys->current && MakeCurrentBare(gl) != VLC_SUCCESS)
        return NULL;

    /* Read current framebuffer */
    struct pbo_picture_context *context =
        &sys->picture_contexts[sys->current_flip];

    const unsigned width = sys->fmt_out.i_visible_width;
    const unsigned height = sys->fmt_out.i_visible_height;
    void *pixels;
    if (sys->default_framebuffer)
        pixels = offscreen_ReadDefault(vt, sys->read_buffer,
                                        sys->default_read_buffer,
                                        sys->pixelbuffers[sys->current_flip],
                                        context->buffer_mapping != NULL, width, height);
    else
    {
        vt->BindBuffer(GL_PIXEL_PACK_BUFFER, sys->pixelbuffers[sys->current_flip]);
        vt->BindFramebuffer(GL_FRAMEBUFFER, sys->framebuffers[sys->current_flip]);
        if (context->buffer_mapping != NULL)
            vt->UnmapBuffer(GL_PIXEL_PACK_BUFFER);
        vt->ReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
        pixels = vt->MapBufferRange(GL_PIXEL_PACK_BUFFER, 0,
                                    (size_t)width * height * 4, GL_MAP_READ_BIT);
    }
    context->buffer_mapping = pixels;
    if (pixels == NULL)
    {
        if (!sys->current)
            wglMakeCurrent(NULL, NULL);
        return NULL;
    }
    vlc_mutex_lock(&sys->lock);
    context->rc++;
    vlc_mutex_unlock(&sys->lock);

    /* Swap framebuffer */
    UpdateBuffer(gl);

    if (!sys->current)
        wglMakeCurrent(NULL, NULL);

    /* Output as picture */
    picture_resource_t pict_resource = {
        .pf_destroy = NULL,
    };

    pict_resource.p[0].p_pixels = pixels;
    pict_resource.p[0].i_lines = height;
    pict_resource.p[0].i_pitch = width * 4;


    picture_t *output = picture_NewFromResource(&sys->fmt_out, &pict_resource);
    if (output == NULL)
        goto error;

    output->context = (picture_context_t *)context;

    return output;

error:
    picture_context_destroy(&context->context);
    return NULL;
}

static void Close( vlc_gl_t *gl )
{
    struct vlc_gl_pbuffer *sys = gl->sys;
    const opengl_vtable_t *vt = &sys->api.vt;

    if (MakeCurrentBare(gl) == VLC_SUCCESS)
    {
        vt->DeleteBuffers(BUFFER_COUNT, sys->pixelbuffers);
        vt->DeleteFramebuffers(BUFFER_COUNT, sys->framebuffers);
        vt->DeleteTextures(BUFFER_COUNT, sys->textures);
        wglMakeCurrent(NULL, NULL);
    }

    wglDeleteContext(sys->hGLRC);
    sys->wgl_vt.ReleasePbufferDCARB(sys->hbuffer, sys->pixelBufferDC);
    sys->wgl_vt.DestroyPbufferARB(sys->hbuffer);
}

static int LoadWGLExt(vlc_gl_t *gl, struct wgl_vt *wgl_vt)
{
#define LOAD_EXT(name, type) do { \
    wgl_vt->name = (type)(void*) wglGetProcAddress("wgl" #name); \
    if (!wgl_vt->name) { \
        msg_Warn(gl, "'wgl " #name "' could not be loaded"); \
        return VLC_EGENERIC; \
    } \
} while(0)

    LOAD_EXT(GetExtensionsStringARB, PFNWGLGETEXTENSIONSSTRINGARBPROC);
    LOAD_EXT(ChoosePixelFormatARB,   PFNWGLCHOOSEPIXELFORMATARBPROC);
    LOAD_EXT(CreatePbufferARB,       PFNWGLCREATEPBUFFERARBPROC);
    LOAD_EXT(DestroyPbufferARB,      PFNWGLDESTROYPBUFFERARBPROC);
    LOAD_EXT(GetPbufferDCARB,        PFNWGLGETPBUFFERDCARBPROC);
    LOAD_EXT(ReleasePbufferDCARB,    PFNWGLRELEASEPBUFFERDCARBPROC);
    return VLC_SUCCESS;
}

static int OpenCommon(vlc_gl_t *gl, unsigned width, unsigned height,
                      const struct vlc_gl_cfg *gl_cfg, bool default_framebuffer)
{
    if (width == 0 || height == 0 || width > INT_MAX / 4 || height > INT_MAX
        || (uint64_t)width * height > PTRDIFF_MAX / 4)
        return VLC_EGENERIC;

    if (gl_cfg->need_alpha)
    {
        msg_Err(gl, "Cannot support alpha yet");
        return VLC_ENOTSUP;
    }

    struct vlc_gl_pbuffer *sys = vlc_obj_malloc(&gl->obj, sizeof *sys);
    if (sys == NULL)
        return VLC_ENOMEM;
    memset(sys, 0, sizeof(*sys));
    sys->hbuffer = NULL;
    sys->pixelBufferDC = NULL;

    HWND tmpWindow = NULL;
    HDC tmpScreenDC = NULL;
    HGLRC tmpGLRC = NULL;

    sys->current = false;
    sys->default_framebuffer = default_framebuffer;

    video_format_Init(&sys->fmt_out, VLC_CODEC_RGBA);
    sys->fmt_out.i_visible_width
        = sys->fmt_out.i_width
        = width;
    sys->fmt_out.i_visible_height
        = sys->fmt_out.i_height
        = height;

    gl->offscreen_chroma_out = VLC_CODEC_RGBA;
    gl->offscreen_vctx_out = NULL;

    vlc_mutex_init(&sys->lock);
    vlc_cond_init(&sys->cond);

    gl->sys = sys;

    sys->hOpengl = GetModuleHandleA("opengl32.dll");
    if (unlikely(sys->hOpengl == NULL))
    {
        msg_Err(gl, "Could not get the opengl32 DLL");
        goto error1;
    }

    static const struct vlc_gl_operations gl_ops =
    {
        .make_current = MakeBoundCurrent,
        .release_current = ReleaseCurrent,
        .swap_offscreen = Swap,
        .get_proc_address = GetSymbol,
        .close = Close,
    };
    gl->ops = &gl_ops;
    gl->orientation = ORIENT_VFLIPPED;

    /* WGL needs a window DC with its own pixel format. The desktop DC cannot
     * reliably be used to create the temporary extension-loading context. */
    tmpWindow = CreateWindowExW(0, L"STATIC", NULL, WS_POPUP, 0, 0, 1, 1,
                                NULL, NULL, GetModuleHandleW(NULL), NULL);
    if (tmpWindow == NULL)
        goto error1;
    tmpScreenDC = GetDC(tmpWindow);
    if(unlikely(tmpScreenDC == NULL))
    {
        msg_Err(gl, "Failed to get a temporary DeviceContext");
        goto error1;
    }

    PIXELFORMATDESCRIPTOR pfd = {
        .nSize = sizeof(PIXELFORMATDESCRIPTOR),
        .nVersion = 1,
        .dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER,
        .iPixelType = PFD_TYPE_RGBA,
        .cColorBits = 24,
        .cDepthBits = 16,
        .iLayerType = PFD_MAIN_PLANE,
    };
    int pixel_format = ChoosePixelFormat(tmpScreenDC, &pfd);
    if (pixel_format == 0 || !SetPixelFormat(tmpScreenDC, pixel_format, &pfd))
        goto error1;
    tmpGLRC = wglCreateContext(tmpScreenDC);
    if (tmpGLRC == NULL)
    {
        msg_Err(gl, "Failed to get a wgl context");
        goto error1;
    }
    BOOL current = wglMakeCurrent(tmpScreenDC, tmpGLRC);
    if (unlikely(!current))
    {
        msg_Err(gl, "Failed to set current context");
        goto error1;
    }

    int err = LoadWGLExt(gl, &sys->wgl_vt);
    if (err != VLC_SUCCESS)
    {
        msg_Err(gl, "Failed to get wgl extensions");
        wglMakeCurrent(NULL, NULL);
        goto error1;
    }

    const char *extensions = sys->wgl_vt.GetExtensionsStringARB(tmpScreenDC);
    if (!vlc_gl_StrHasToken(extensions, "WGL_ARB_pbuffer") ||
        !vlc_gl_StrHasToken(extensions, "WGL_ARB_pixel_format"))
    {
        msg_Err(gl, "wgl pixel buffer extensions missing");
        wglMakeCurrent(NULL, NULL);
        goto error1;
    }

    int formatAttributes[] = {
        WGL_DRAW_TO_PBUFFER_ARB, GL_TRUE,
        WGL_SUPPORT_OPENGL_ARB,  GL_TRUE,
        WGL_PIXEL_TYPE_ARB, WGL_TYPE_RGBA_ARB,
        WGL_DEPTH_BITS_ARB, 24,
        WGL_STENCIL_BITS_ARB, default_framebuffer ? 8 : 0,
        WGL_RED_BITS_ARB,   8,
        WGL_GREEN_BITS_ARB, 8,
        WGL_BLUE_BITS_ARB,  8,
        WGL_ALPHA_BITS_ARB, 8,
        0,0
    };
    float fAttributes[] = {0,0};
    int pixelFormats[50] = {0};
    UINT formats_count = 0;
    BOOL gotFormat = sys->wgl_vt.ChoosePixelFormatARB(tmpScreenDC, formatAttributes, fAttributes, ARRAY_SIZE(pixelFormats), pixelFormats, &formats_count);
    if (!gotFormat || formats_count == 0)
    {
        msg_Err(gl, "could not find appropriate pixel buffer PixelFormat");
        wglMakeCurrent(NULL, NULL);
        goto error2;
    }

    sys->hbuffer = sys->wgl_vt.CreatePbufferARB(tmpScreenDC, pixelFormats[0], width, height, NULL);
    if (sys->hbuffer == NULL)
    {
        msg_Err(gl, "failed to create the pixel buffer");
        wglMakeCurrent(NULL, NULL);
        goto error2;
    }
    sys->pixelBufferDC = sys->wgl_vt.GetPbufferDCARB(sys->hbuffer);
    if (sys->pixelBufferDC == NULL)
    {
        msg_Err(gl, "failed to create the pixel buffer DeviceContext");
        wglMakeCurrent(NULL, NULL);
        goto error2;
    }

    sys->hGLRC = wglCreateContext(sys->pixelBufferDC);
    if (sys->hGLRC == NULL)
    {
        msg_Err(gl, "wgl pixel buffer extensions missing");
        wglMakeCurrent(NULL, NULL);
        goto error2;
    }
    wglMakeCurrent(NULL, NULL);
    if (!wglMakeCurrent(sys->pixelBufferDC, sys->hGLRC))
        goto error2;

    int ret = vlc_gl_api_Init(&sys->api, gl);
    if (ret != VLC_SUCCESS)
    {
        msg_Err(gl, "Failed to initialize gl_api");
        wglMakeCurrent(NULL, NULL);
        goto error2;
    }

    const opengl_vtable_t *vt = &sys->api.vt;
    if (!offscreen_CanRead(vt, default_framebuffer))
        goto error2;
    if (default_framebuffer)
    {
        sys->read_buffer = vlc_gl_GetProcAddress(gl, "glReadBuffer");
        if (sys->read_buffer == NULL)
            goto error2;
        vt->GetIntegerv(GL_READ_BUFFER, &sys->default_read_buffer);
    }
    vt->GenBuffers(BUFFER_COUNT, sys->pixelbuffers);
    if (!default_framebuffer)
    {
        vt->GenFramebuffers(BUFFER_COUNT, sys->framebuffers);
        vt->GenTextures(BUFFER_COUNT, sys->textures);
    }

    for (size_t i=0; i<BUFFER_COUNT; ++i)
    {
        vt->BindBuffer(GL_PIXEL_PACK_BUFFER, sys->pixelbuffers[i]);
        vt->BufferData(GL_PIXEL_PACK_BUFFER, (size_t)width*height*4, NULL,
                       GL_STREAM_READ);
        if (!default_framebuffer)
        {
            vt->BindFramebuffer(GL_FRAMEBUFFER, sys->framebuffers[i]);
            vt->BindTexture(GL_TEXTURE_2D, sys->textures[i]);
            vt->TexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0,
                           GL_RGBA, GL_UNSIGNED_BYTE, NULL);
            vt->FramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                     GL_TEXTURE_2D, sys->textures[i], 0);
        }

        struct pbo_picture_context *context = &sys->picture_contexts[i];
        context->buffer_mapping = NULL;
        context->lock = &sys->lock;
        context->cond = &sys->cond;
        context->context.destroy = picture_context_destroy;
        context->context.copy = picture_context_copy;
        context->context.vctx = NULL;
        context->rc = 0;
    }

    sys->current_flip = BUFFER_COUNT - 1;
    if (default_framebuffer)
        vt->BindBuffer(GL_PIXEL_PACK_BUFFER, 0);
    else
        BindDrawFramebuffer(sys);
    if (vt->GetError() != GL_NO_ERROR)
        goto error2;
    wglMakeCurrent(NULL, NULL);

    wglDeleteContext(tmpGLRC);
    ReleaseDC(tmpWindow, tmpScreenDC);
    DestroyWindow(tmpWindow);

    return VLC_SUCCESS;

error2:
    wglMakeCurrent(NULL, NULL);
    if (sys->hGLRC != NULL)
        wglDeleteContext(sys->hGLRC);
    if (sys->pixelBufferDC != NULL)
        sys->wgl_vt.ReleasePbufferDCARB(sys->hbuffer, sys->pixelBufferDC);
    if (sys->hbuffer != NULL)
        sys->wgl_vt.DestroyPbufferARB(sys->hbuffer);
error1:
    if (tmpGLRC)
        wglDeleteContext(tmpGLRC);
    if (tmpScreenDC)
        ReleaseDC(tmpWindow, tmpScreenDC);
    if (tmpWindow)
        DestroyWindow(tmpWindow);
    vlc_obj_free(&gl->obj, sys);

    return VLC_EGENERIC;
}

static int Open(vlc_gl_t *gl, unsigned width, unsigned height,
                const struct vlc_gl_cfg *gl_cfg)
{
    return OpenCommon(gl, width, height, gl_cfg, false);
}

static int OpenDefault(vlc_gl_t *gl, unsigned width, unsigned height,
                       const struct vlc_gl_cfg *gl_cfg)
{
    return OpenCommon(gl, width, height, gl_cfg, true);
}

vlc_module_begin()
    add_shortcut( "opengl_win_offscreen" )
    set_shortname( N_("opengl_offscreen") )
    set_description( N_("offscreen opengl provider for Windows") )
    set_callback_opengl_offscreen( Open, 1 )
    add_submodule()
    set_callback_opengl_offscreen_default( OpenDefault, 1 )
vlc_module_end()
