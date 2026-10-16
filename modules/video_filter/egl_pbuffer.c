/*****************************************************************************
 * egl_pbuffer.c: OpenGL filter in EGL offscreen framebuffer
 *****************************************************************************
 * Copyright (C) 2020 Videolabs
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
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
#include "../video_output/opengl/egl_display.h"
#include <EGL/egl.h>
#include <EGL/eglext.h>

#include "offscreen_readback.h"

#define BUFFER_COUNT 4

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

    struct vlc_gl_api api;

    size_t                  current_flip;
    GLuint                  pixelbuffers[BUFFER_COUNT];
    GLuint                  framebuffers[BUFFER_COUNT];
    GLuint                  textures[BUFFER_COUNT];
    struct pbo_picture_context     picture_contexts[BUFFER_COUNT];

    struct vlc_egl_display *vlc_display;

    EGLDisplay display;
    EGLSurface surface;
    EGLContext context;

    bool current;
    bool default_framebuffer;
    offscreen_read_buffer_fn read_buffer;
    GLint default_read_buffer;
};

static int MakeCurrent (vlc_gl_t *gl)
{
    struct vlc_gl_pbuffer *sys = gl->sys;

    assert(!sys->current);
    if (eglMakeCurrent (sys->display, sys->surface, sys->surface,
                        sys->context) != EGL_TRUE)
        return VLC_EGENERIC;

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
    eglMakeCurrent (sys->display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                    EGL_NO_CONTEXT);

    sys->current = false;
}

static void *GetSymbol(vlc_gl_t *gl, const char *procname)
{
    (void) gl;
    return (void *)eglGetProcAddress (procname);
}

static EGLContext CreateContext(vlc_gl_t *gl, EGLConfig cfg, EGLint client_version)
{
    struct vlc_gl_pbuffer *sys = gl->sys;

    const EGLint ctx_attr[] = {
        EGL_CONTEXT_CLIENT_VERSION, client_version,
        EGL_NONE
    };

    return eglCreateContext(sys->display, cfg, EGL_NO_CONTEXT, ctx_attr);
}

static int InitEGL(vlc_gl_t *gl, int opengl_api, unsigned width, unsigned height)
{
    struct vlc_gl_pbuffer *sys = gl->sys;

    sys->vlc_display = vlc_egl_display_New(VLC_OBJECT(gl), NULL);
    if (!sys->vlc_display)
        return VLC_EGENERIC;

    sys->display = sys->vlc_display->display;
    assert(sys->display != EGL_NO_DISPLAY);

    msg_Dbg(gl, "EGL version %s by %s, API %s",
            eglQueryString(sys->display, EGL_VERSION),
            eglQueryString(sys->display, EGL_VENDOR),
            opengl_api == VLC_OPENGL ? "OpenGL" : "OpenGL ES2");

    const char *extensions = eglQueryString(sys->display, EGL_EXTENSIONS);
    bool need_surface = sys->default_framebuffer ||
        !vlc_gl_StrHasToken(extensions, "EGL_KHR_surfaceless_context");

    EGLint renderable_type = opengl_api == VLC_OPENGL ? EGL_OPENGL_BIT : EGL_OPENGL_ES2_BIT;
    const EGLint conf_attr_surface[] = {
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_DEPTH_SIZE, sys->default_framebuffer ? 24 : 0,
        EGL_STENCIL_SIZE, sys->default_framebuffer ? 8 : 0,
        EGL_RENDERABLE_TYPE, renderable_type,
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_NONE,
    };

    const EGLint conf_attr_surfaceless[] = {
        EGL_RENDERABLE_TYPE, renderable_type,
        EGL_SURFACE_TYPE, 0,
        EGL_NONE,
    };

    const EGLint *conf_attr = need_surface ? conf_attr_surface
                                           : conf_attr_surfaceless;

    EGLConfig cfgv[1];
    EGLint cfgc;

    msg_Dbg(gl, "canvas size %ux%u", width, height);
    const EGLint surface_attr[] = {
        EGL_WIDTH, width,
        EGL_HEIGHT, height,
        EGL_NONE,
    };

    if (eglChooseConfig(sys->display, conf_attr, cfgv, 1, &cfgc) != EGL_TRUE
     || cfgc == 0)
    {
        msg_Err (gl, "cannot choose EGL configuration");
        goto error;
    }

    if (need_surface)
    {
        /* Create a drawing surface */
        sys->surface = eglCreatePbufferSurface(sys->display, cfgv[0],
                                               surface_attr);
        if (sys->surface == EGL_NO_SURFACE)
        {
            msg_Err (gl, "cannot create EGL window surface");
            goto error;
        }
    }
    else
        sys->surface = EGL_NO_SURFACE;

    EGLint egl_api;
    if (opengl_api == VLC_OPENGL_ES2)
        egl_api = EGL_OPENGL_ES_API;
    else
        egl_api = EGL_OPENGL_API;

    if (eglBindAPI(egl_api) != EGL_TRUE)
    {
        msg_Err (gl, "cannot bind EGL OPENGL API");
        goto error;
    }

    EGLContext ctx = CreateContext(gl, cfgv[0], 3);
    if (ctx != EGL_NO_CONTEXT)
        goto context_created;

    ctx = CreateContext(gl, cfgv[0], 2);
    if (ctx != EGL_NO_CONTEXT)
        goto context_created;

    msg_Err (gl, "cannot create EGL context");
    goto error;

context_created:
    sys->context = ctx;

    return VLC_SUCCESS;
error:
    if (sys->surface != EGL_NO_SURFACE)
        eglDestroySurface(sys->display, sys->surface);
    vlc_egl_display_Delete(sys->vlc_display);
    return VLC_EGENERIC;
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

    if (!sys->current &&
        eglMakeCurrent(sys->display, sys->surface, sys->surface, sys->context) != EGL_TRUE)
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
            eglMakeCurrent(sys->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        return NULL;
    }
    vlc_mutex_lock(&sys->lock);
    context->rc++;
    vlc_mutex_unlock(&sys->lock);

    /* Swap framebuffer */
    UpdateBuffer(gl);

    if (!sys->current)
        eglMakeCurrent(sys->display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                       EGL_NO_CONTEXT);

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

    if (eglMakeCurrent(sys->display, sys->surface, sys->surface, sys->context) == EGL_TRUE)
    {
        vt->DeleteBuffers(BUFFER_COUNT, sys->pixelbuffers);
        vt->DeleteFramebuffers(BUFFER_COUNT, sys->framebuffers);
        vt->DeleteTextures(BUFFER_COUNT, sys->textures);
        eglMakeCurrent(sys->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    }

    eglDestroyContext(sys->display, sys->context);
    if (sys->surface != EGL_NO_SURFACE)
        eglDestroySurface(sys->display, sys->surface);
    vlc_egl_display_Delete(sys->vlc_display);
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

    if (InitEGL(gl, gl->api_type, width, height) != VLC_SUCCESS)
    {
        msg_Err(gl, "Failed to create opengl context\n");
        goto error1;
    }

    static const struct vlc_gl_operations gl_ops =
    {
        .make_current = MakeCurrent,
        .release_current = ReleaseCurrent,
        .swap_offscreen = Swap,
        .get_proc_address = GetSymbol,
        .close = Close,
    };
    gl->ops = &gl_ops;
    gl->orientation = ORIENT_VFLIPPED;

    if (eglMakeCurrent(sys->display, sys->surface, sys->surface,
                       sys->context) != EGL_TRUE)
        goto error2;


    int ret = vlc_gl_api_Init(&sys->api, gl);
    if (ret != VLC_SUCCESS)
    {
        msg_Err(gl, "Failed to initialize gl_api");
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
    eglMakeCurrent(sys->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);

    return VLC_SUCCESS;

error2:
    eglMakeCurrent(sys->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(sys->display, sys->context);
    if (sys->surface != EGL_NO_SURFACE)
        eglDestroySurface(sys->display, sys->surface);
    vlc_egl_display_Delete(sys->vlc_display);
error1:
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
    add_shortcut( "egl_pbuffer" )
    set_shortname( N_("egl_pbuffer") )
    set_description( N_("EGL PBuffer offscreen opengl provider") )
    set_callback_opengl_offscreen( Open, 1 )

    add_submodule()
    set_callback_opengl_es2_offscreen( Open, 1 )
    add_submodule()
    set_callback_opengl_offscreen_default( OpenDefault, 1 )
    add_submodule()
    set_callback_opengl_es2_offscreen_default( OpenDefault, 1 )
vlc_module_end()
