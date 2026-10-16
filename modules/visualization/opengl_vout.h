// SPDX-License-Identifier: LGPL-2.1-or-later
#ifndef VLC_VISUALIZATION_OPENGL_VOUT_H
#define VLC_VISUALIZATION_OPENGL_VOUT_H

#include <assert.h>
#include <stdlib.h>
#include <vlc_aout.h>
#include <vlc_filter.h>
#include <vlc_opengl.h>
#include <vlc_picture_pool.h>
#include <vlc_vout.h>
#include <vlc_window.h>
#include "size.h"

struct visualization_gl
{
    filter_t *filter;
    vlc_gl_t *gl;
    vout_thread_t *vout;
    video_format_t format;
    picture_pool_t *pool;
    vlc_mutex_t lock;
    bool stopped, display_ready, context_failed, native_surface;
    const char *width_option, *height_option;
    unsigned failed_width, failed_height;
    vlc_tick_t retry;
};

static inline bool visualization_gl_GetSize(struct visualization_gl *vis,
                                            unsigned *width, unsigned *height)
{
    if (visualization_GetSize(VLC_OBJECT(vis->filter), width, height))
        return *width <= INT_MAX / 4 && (uint64_t)*width * *height <= PTRDIFF_MAX / 4;
    int64_t w = var_InheritInteger(vis->filter, vis->width_option);
    int64_t h = var_InheritInteger(vis->filter, vis->height_option);
    if (w <= 0 || h <= 0 || w > INT_MAX / 4 || h > INT_MAX)
        return false;
    *width = w;
    *height = h;
    return (uint64_t)*width * *height <= PTRDIFF_MAX / 4;
}

static inline void visualization_gl_Delete(struct visualization_gl *vis)
{
    if (vis->pool)
        picture_pool_Release(vis->pool);
    if (vis->gl)
    {
        if (vis->native_surface)
            vlc_gl_surface_Destroy(vis->gl);
        else
            vlc_gl_Delete(vis->gl);
    }
    video_format_Clean(&vis->format);
    free(vis);
}

static inline struct visualization_gl *
visualization_gl_New(filter_t *filter, const char *width_option,
                      const char *height_option)
{
    struct visualization_gl *vis = (struct visualization_gl *)calloc(1, sizeof(*vis));
    if (vis == NULL)
        return NULL;
    vis->filter = filter;
    vis->width_option = width_option;
    vis->height_option = height_option;
    vlc_mutex_init(&vis->lock);
    video_format_Init(&vis->format, VLC_CODEC_RGBA);
    unsigned width, height;
    if (!visualization_gl_GetSize(vis, &width, &height))
        goto error;
    vis->gl = vlc_gl_CreateOffscreen(VLC_OBJECT(filter), NULL, width, height,
                                    VLC_OPENGL | VLC_GL_OFFSCREEN_DEFAULT_FRAMEBUFFER,
                                    NULL, NULL);
#ifdef __APPLE__
    /* Keep native surface rendering where no default-framebuffer offscreen
     * provider is available. CGL does not yet supply that capability. */
    if (vis->gl == NULL)
    {
        vlc_window_cfg_t cfg;
        memset(&cfg, 0, sizeof(cfg));
        cfg.is_decorated = true;
        cfg.width = width;
        cfg.height = height;
        vis->gl = vlc_gl_surface_Create(VLC_OBJECT(filter), &cfg, NULL, NULL);
        if (vis->gl == NULL)
            goto error;
        vis->native_surface = true;
    }
#endif
    if (vis->native_surface)
    {
        /* The picture is only a nonblocking render token on a native surface. */
        video_format_t token;
        video_format_Init(&token, VLC_CODEC_RGBA);
        token.i_width = token.i_visible_width = 1;
        token.i_height = token.i_visible_height = 1;
        token.i_sar_num = token.i_sar_den = 1;
        vis->pool = picture_pool_NewFromFormat(&token, 1);
        video_format_Clean(&token);
        if (vis->pool == NULL)
            goto error;
        vis->format.i_width = vis->format.i_visible_width = width;
        vis->format.i_height = vis->format.i_visible_height = height;
        vis->display_ready = true;
        return vis;
    }
    if (vis->gl == NULL || vis->gl->offscreen_chroma_out != VLC_CODEC_RGBA)
        goto error;
    vis->format.i_width = vis->format.i_visible_width = width;
    vis->format.i_height = vis->format.i_visible_height = height;
    vis->format.i_sar_num = vis->format.i_sar_den = 1;
    vis->format.orientation = vis->gl->orientation;
    vis->format.color_range = COLOR_RANGE_FULL;
    vis->pool = picture_pool_NewFromFormat(&vis->format, 3);
    if (vis->pool == NULL)
        goto error;
    vis->vout = aout_filter_GetVout(filter, &vis->format);
    if (vis->vout == NULL)
        goto error;
    vis->display_ready = true;
    return vis;
error:
    visualization_gl_Delete(vis);
    return NULL;
}

/* Stop never waits for a paused vout to release pictures. Provider PBOs are
 * copied and released immediately; only independent CPU pictures reach vout. */
static inline void visualization_gl_Stop(struct visualization_gl *vis)
{
    vlc_mutex_lock(&vis->lock);
    vis->stopped = true;
    vlc_mutex_unlock(&vis->lock);
}

static inline int visualization_gl_UpdateVout(struct visualization_gl *vis,
                                               const video_format_t *format)
{
    /* The display can make its own context current on this render thread. */
    vlc_gl_ReleaseCurrent(vis->gl);
    int ret = aout_filter_UpdateVoutFormat(vis->filter, format);
    if (vlc_gl_MakeCurrent(vis->gl) != VLC_SUCCESS)
    {
        vis->context_failed = true;
        msg_Err(vis->filter, "Could not restore the visualization context");
        return VLC_EGENERIC;
    }
    return ret;
}

/* Called by the render thread with the GL context current. */
static inline bool visualization_gl_UpdateSize(struct visualization_gl *vis)
{
    vlc_mutex_lock(&vis->lock);
    bool stopped = vis->stopped;
    vlc_mutex_unlock(&vis->lock);
    if (stopped)
        return false;
    unsigned width, height;
    if (vis->native_surface)
    {
        if (vlc_gl_surface_CheckSize(vis->gl, &width, &height))
        {
            vis->format.i_width = vis->format.i_visible_width = width;
            vis->format.i_height = vis->format.i_visible_height = height;
        }
        return vis->format.i_width > 0 && vis->format.i_height > 0;
    }
    if (!visualization_gl_GetSize(vis, &width, &height))
        return vis->display_ready;
    if (width == vis->format.i_width && height == vis->format.i_height)
    {
        if (!vis->display_ready && vlc_tick_now() >= vis->retry)
        {
            vis->display_ready = vlc_gl_ResizeOffscreen(vis->gl, width, height) == VLC_SUCCESS &&
                visualization_gl_UpdateVout(vis, &vis->format) == VLC_SUCCESS;
            vis->retry = vlc_tick_now() + VLC_TICK_FROM_SEC(1);
        }
        return vis->display_ready;
    }
    if (width == vis->failed_width && height == vis->failed_height &&
        vlc_tick_now() < vis->retry)
        return vis->display_ready;

    video_format_t format = vis->format;
    format.i_width = format.i_visible_width = width;
    format.i_height = format.i_visible_height = height;
    picture_pool_t *previous;
    picture_pool_t *pool = picture_pool_NewFromFormat(&format, 3);
    if (pool == NULL)
        goto retry;
    if (vlc_gl_ResizeOffscreen(vis->gl, width, height) != VLC_SUCCESS)
    {
        picture_pool_Release(pool);
        goto retry;
    }
    if (visualization_gl_UpdateVout(vis, &format) != VLC_SUCCESS)
    {
        /* Restore the old canvas and display before rendering old-size frames. */
        bool restored = vlc_gl_ResizeOffscreen(vis->gl, vis->format.i_width,
                                              vis->format.i_height) == VLC_SUCCESS;
        vis->display_ready = restored &&
            visualization_gl_UpdateVout(vis, &vis->format) == VLC_SUCCESS;
        picture_pool_Release(pool);
        goto retry;
    }
    vlc_mutex_lock(&vis->lock);
    if (vis->stopped)
    {
        vlc_mutex_unlock(&vis->lock);
        picture_pool_Release(pool);
        return false;
    }
    previous = vis->pool;
    vis->pool = pool;
    vis->format = format;
    vis->display_ready = true;
    vlc_mutex_unlock(&vis->lock);
    picture_pool_Release(previous);
    msg_Dbg(vis->filter, "OpenGL visualization canvas resized to %ux%u", width, height);
    return true;
retry:
    vis->failed_width = width;
    vis->failed_height = height;
    vis->retry = vlc_tick_now() + VLC_TICK_FROM_SEC(1);
    return vis->display_ready;
}

static inline picture_t *visualization_gl_Acquire(struct visualization_gl *vis)
{
    vlc_mutex_lock(&vis->lock);
    picture_t *picture = vis->stopped || !vis->display_ready ? NULL : picture_pool_Get(vis->pool);
    vlc_mutex_unlock(&vis->lock);
    return picture;
}

static inline void visualization_gl_Present(struct visualization_gl *vis,
                                            picture_t *picture, vlc_tick_t pts)
{
    if (pts == VLC_TICK_INVALID)
    {
        picture_Release(picture);
        return;
    }
    if (vis->native_surface)
    {
        picture_Release(picture);
        vlc_gl_Swap(vis->gl);
        return;
    }
    picture_t *source = vlc_gl_SwapOffscreen(vis->gl);
    if (source == NULL)
    {
        picture_Release(picture);
        return;
    }
    /* picture_CopyPixels also clones the provider context. Copy only plane
     * bytes so the CPU picture never retains a mapped provider buffer. */
    assert(source->i_planes == 1 && picture->i_planes == 1);
    assert(source->format.i_visible_width == picture->format.i_visible_width);
    assert(source->format.i_visible_height == picture->format.i_visible_height);
    plane_CopyPixels(&picture->p[0], &source->p[0]);
    picture_Release(source);
    picture->date = pts;
    picture->b_progressive = true;
    vout_PutPicture(vis->vout, picture);
}

#endif
