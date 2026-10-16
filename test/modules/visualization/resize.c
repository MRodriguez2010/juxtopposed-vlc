// SPDX-License-Identifier: LGPL-2.1-or-later
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#define MODULE_NAME test_visual_resize
#ifndef VISUAL_RESIZE_TEST_PLUGIN
#undef VLC_DYNAMIC_PLUGIN
#endif
#include <vlc/vlc.h>
#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_player.h>
#include <vlc_window.h>
#include <vlc_vout_display.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#undef NDEBUG
#include <assert.h>
#include <limits.h>
#include <vlc_opengl.h>
#include <vlc_modules.h>
#include "../../../lib/libvlc_internal.h"

static atomic_uint_fast64_t picture_size;
static atomic_uint picture_count, window_opens, window_closes, failed_formats;
static atomic_uint display_opens, display_closes, display_updates;
static atomic_bool fail_format;
static bool test_scope, test_meter, test_converted, test_gl;
static vlc_sem_t frame_event;

static uint64_t size_key(unsigned width, unsigned height)
{
    return ((uint64_t)width << 32) | height;
}

static int EnableWindow(vlc_window_t *wnd, const vlc_window_cfg_t *cfg)
{
    assert(var_InheritBool(wnd, "video-is-visualization"));
    assert(cfg->width == 800 && cfg->height == 500);
    return VLC_SUCCESS;
}

static void DisableWindow(vlc_window_t *wnd)
{
    (void) wnd;
}

static void DestroyWindow(vlc_window_t *wnd)
{
    (void) wnd;
    atomic_fetch_add(&window_closes, 1);
}

static int OpenWindow(vlc_window_t *wnd)
{
    static const struct vlc_window_operations ops = {
        .enable = EnableWindow, .disable = DisableWindow, .destroy = DestroyWindow,
    };
    wnd->ops = &ops;
    atomic_fetch_add(&window_opens, 1);
    return VLC_SUCCESS;
}

static void Display(vout_display_t *vd, picture_t *picture)
{
    assert(vd->fmt->i_visible_width == picture->format.i_visible_width);
    assert(vd->fmt->i_visible_height == picture->format.i_visible_height);
    assert(vd->fmt->i_chroma == picture->format.i_chroma);
    if (test_gl)
    {
        assert(picture->context == NULL);
        if (atomic_load(&picture_size) != size_key(picture->format.i_visible_width,
                                                  picture->format.i_visible_height))
        {
            bool colored = false;
            for (unsigned y = 0; y < picture->format.i_visible_height && !colored; ++y)
                for (unsigned x = 0; x < picture->format.i_visible_width && !colored; ++x)
                {
                    const uint8_t *p = picture->p[0].p_pixels + y * picture->p[0].i_pitch + x * 4;
                    colored = p[0] > 50 || p[1] > 50 || p[2] > 50;
                }
            assert(colored);
        }
    }
    if (test_converted)
        assert(picture->format.i_chroma == VLC_CODEC_BGRX);
    if (test_meter && atomic_load(&picture_size)
                      != size_key(picture->format.i_visible_width,
                                  picture->format.i_visible_height))
    {
        const unsigned width = picture->format.i_visible_width;
        const unsigned height = picture->format.i_visible_height;
        unsigned top = height, bottom = 0, left = width, right = 0;
        const plane_t *luma = &picture->p[0];
        for (unsigned y = 0; y < height; ++y)
            for (unsigned x = 0; x < width; ++x)
                if (luma->p_pixels[y * luma->i_pitch + x] != 0)
                {
                    top = __MIN(top, y); bottom = __MAX(bottom, y);
                    left = __MIN(left, x); right = __MAX(right, x);
                }
        assert(top < bottom && left < right);
        assert(abs((int)(top + bottom) - (int)height) <= 2);
        assert(abs((int)(left + right) - (int)width) <= 2);
    }
    if (test_scope)
    {
        const unsigned width = picture->format.i_visible_width;
        const unsigned height = picture->format.i_visible_height;
        /* Silent audio must make two centered traces across the whole canvas,
         * including sizes whose allocated rows and strides contain padding. */
        assert(picture->format.i_chroma == VLC_CODEC_I420);
        for (unsigned channel = 0; channel < 2; ++channel)
        {
            const unsigned y = (channel * 2 + 1) * height / 4;
            const plane_t *luma = &picture->p[0];
            const plane_t *chroma = &picture->p[channel + 1];
            const uint8_t value = channel == 0 ? 0xbf : 0x9f;
            assert(luma->p_pixels[y * luma->i_pitch] == value);
            assert(luma->p_pixels[y * luma->i_pitch + width - 1] == value);
            assert(chroma->p_pixels[(y / 2) * chroma->i_pitch + (width - 1) / 2]
                   == (channel == 0 ? 0xff : 0xdd));
        }
    }
    atomic_store(&picture_size, size_key(picture->format.i_visible_width,
                                       picture->format.i_visible_height));
    atomic_fetch_add(&picture_count, 1);
    vlc_sem_post(&frame_event);
}

static void CloseDisplay(vout_display_t *vd)
{
    if (test_gl)
        vlc_gl_Delete(vd->sys);
    atomic_fetch_add(&display_closes, 1);
}

static int UpdateDisplay(vout_display_t *vd, const video_format_t *fmt,
                         vlc_video_context *vctx)
{
    (void)vctx;
    if (test_gl)
    {
        /* Real GL displays temporarily use their own context on the caller's
         * thread. The visualizer must restore its context after this update. */
        assert(vlc_gl_MakeCurrent(vd->sys) == VLC_SUCCESS);
        vlc_gl_ReleaseCurrent(vd->sys);
    }
    if (test_converted && fmt->i_chroma != VLC_CODEC_BGRX)
        return VLC_EGENERIC;
    if (fmt->i_visible_width == 1200 && atomic_load(&fail_format))
    {
        atomic_fetch_add(&failed_formats, 1);
        vlc_sem_post(&frame_event);
        return VLC_EGENERIC;
    }
    atomic_fetch_add(&display_updates, 1);
    return VLC_SUCCESS;
}

static int OpenDisplay(vout_display_t *vd, video_format_t *fmt,
                       vlc_video_context *vctx)
{
    (void) vctx;
    assert(vd->cfg->display.fitting == VLC_VIDEO_FIT_SMALLER);
    assert(vd->cfg->display.align.horizontal == VLC_VIDEO_ALIGN_CENTER);
    assert(vd->cfg->display.align.vertical == VLC_VIDEO_ALIGN_CENTER);
    assert(vd->cfg->display.zoom.num == vd->cfg->display.zoom.den);
    assert(fmt->i_sar_num == fmt->i_sar_den);
    assert(fmt->i_x_offset == 0 && fmt->i_y_offset == 0);
    assert(fmt->i_width == fmt->i_visible_width);
    assert(fmt->i_height == fmt->i_visible_height);
    if (fmt->i_visible_width == 1200 && atomic_load(&fail_format))
    {
        atomic_fetch_add(&failed_formats, 1);
        vlc_sem_post(&frame_event);
        return VLC_EGENERIC;
    }
    if (test_gl)
    {
        vd->sys = vlc_gl_CreateOffscreen(VLC_OBJECT(vd), NULL, 16, 16,
                                         VLC_OPENGL | VLC_GL_OFFSCREEN_DEFAULT_FRAMEBUFFER,
                                         NULL, NULL);
        if (vd->sys == NULL)
            return VLC_EGENERIC;
    }
    atomic_fetch_add(&display_opens, 1);
    if (test_converted)
        fmt->i_chroma = VLC_CODEC_BGRX;
    static const struct vlc_display_operations ops = {
        .display = Display, .close = CloseDisplay, .update_format = UpdateDisplay,
    };
    vd->ops = &ops;
    return VLC_SUCCESS;
}

vlc_module_begin()
    set_capability("vout window", 9999)
    set_callback(OpenWindow)
    add_shortcut("resize-test")
    add_submodule()
        set_callback_display(OpenDisplay, 9999)
        add_shortcut("resize-test")
vlc_module_end()

#ifndef VISUAL_RESIZE_TEST_PLUGIN
VLC_EXPORT const vlc_plugin_cb vlc_static_modules[] = {
    VLC_SYMBOL(vlc_entry), NULL
};
#endif

static void wait_picture(unsigned width, unsigned height, unsigned previous)
{
    const vlc_tick_t deadline = vlc_tick_now() + VLC_TICK_FROM_SEC(5);
    while (atomic_load(&picture_size) != size_key(width, height)
           || atomic_load(&picture_count) <= previous)
    {
        assert(vlc_sem_timedwait(&frame_event, deadline) == 0);
    }
}

static void resize(libvlc_int_t *root, int64_t width, int64_t height,
                   unsigned expected_width, unsigned expected_height)
{
    const unsigned previous = atomic_load(&picture_count);
    fprintf(stderr, "request canvas %" PRId64 "x%" PRId64 "\n", width, height);
    assert(var_SetInteger(root, "effect-width", width) == VLC_SUCCESS);
    assert(var_SetInteger(root, "effect-height", height) == VLC_SUCCESS);
    assert(var_SetInteger(root, "goom-width", width) == VLC_SUCCESS);
    assert(var_SetInteger(root, "goom-height", height) == VLC_SUCCESS);
    assert(var_SetInteger(root, "glspectrum-width", width) == VLC_SUCCESS);
    assert(var_SetInteger(root, "glspectrum-height", height) == VLC_SUCCESS);
    assert(var_SetInteger(root, "projectm-width", width) == VLC_SUCCESS);
    assert(var_SetInteger(root, "projectm-height", height) == VLC_SUCCESS);
    wait_picture(expected_width, expected_height, previous);
    assert(atomic_load(&window_opens) == 1);
    assert(atomic_load(&window_closes) == 0);
}

static bool test_resize(const char *effect, bool converted)
{
    const bool goom = !strcmp(effect, "goom");
    const bool projectm = !strcmp(effect, "projectm");
    const bool gl = test_gl = projectm || !strcmp(effect, "glspectrum");
    test_converted = converted;
    test_scope = !converted && !strcmp(effect, "scope");
    test_meter = !strcmp(effect, "vuMeter");
    atomic_store(&picture_size, 0);
    atomic_store(&picture_count, 0);
    atomic_store(&window_opens, 0);
    atomic_store(&window_closes, 0);
    atomic_store(&failed_formats, 0);
    atomic_store(&display_opens, 0);
    atomic_store(&display_closes, 0);
    atomic_store(&display_updates, 0);
    atomic_store(&fail_format, false);
    vlc_sem_init(&frame_event, 0);
    const char *args[] = {
        "--ignore-config", "--no-plugins-cache", "--no-media-library", "--no-auto-preparse",
        "--no-spu", "--no-osd", "--aout=dummy", "--clock-master=monotonic",
        goom ? "--audio-visual=goom" : projectm ? "--audio-visual=projectm" : gl ? "--audio-visual=glspectrum" : "--audio-visual=visual", "--vout=resize-test,none",
        /* These preferences apply to video, but must not affect visualizers. */
        "--no-autoscale", "--zoom=2", "--align=5", "--fit=2",
        "--aspect-ratio=1:1", "--crop=4:3", "--width=100", "--height=100",
    };
    libvlc_instance_t *instance = libvlc_new(ARRAY_SIZE(args), args);
    assert(instance);
    libvlc_int_t *root = instance->p_libvlc_int;
    if (gl)
    {
        if (!module_exists(effect))
        {
            libvlc_release(instance);
            return false;
        }
        vlc_gl_t *probe = vlc_gl_CreateOffscreen(VLC_OBJECT(root), NULL, 16, 16,
                                                VLC_OPENGL | VLC_GL_OFFSCREEN_DEFAULT_FRAMEBUFFER,
                                                NULL, NULL);
        if (probe == NULL)
        {
            libvlc_release(instance);
            return false;
        }
        vlc_gl_Delete(probe);
    }

    var_Create(root, "window", VLC_VAR_STRING);
    var_SetString(root, "window", "resize-test,none");
    var_Create(root, "effect-width", VLC_VAR_INTEGER);
    var_Create(root, "effect-height", VLC_VAR_INTEGER);
    var_Create(root, "effect-list", VLC_VAR_STRING);
    var_SetInteger(root, "effect-width", 800);
    var_SetInteger(root, "effect-height", 500);
    var_SetString(root, "effect-list", effect);
    var_Create(root, "goom-width", VLC_VAR_INTEGER);
    var_Create(root, "goom-height", VLC_VAR_INTEGER);
    var_SetInteger(root, "goom-width", 800);
    var_SetInteger(root, "goom-height", 500);
    var_Create(root, "glspectrum-width", VLC_VAR_INTEGER);
    var_Create(root, "glspectrum-height", VLC_VAR_INTEGER);
    var_SetInteger(root, "glspectrum-width", 800);
    var_SetInteger(root, "glspectrum-height", 500);
    var_Create(root, "projectm-width", VLC_VAR_INTEGER);
    var_Create(root, "projectm-height", VLC_VAR_INTEGER);
    var_SetInteger(root, "projectm-width", 800);
    var_SetInteger(root, "projectm-height", 500);
    if (projectm)
    {
        const char *presets = getenv("VLC_TEST_PROJECTM_PRESETS");
#ifdef TOP_SRCDIR
        if (presets == NULL)
            presets = TOP_SRCDIR "/test/modules/visualization/projectm-presets";
#endif
        var_Create(root, "projectm-preset-path", VLC_VAR_STRING);
        if (presets != NULL)
            var_SetString(root, "projectm-preset-path", presets);
    }
    var_Create(root, "visualization-size", VLC_VAR_INTEGER);
    var_Create(root, "visualization-window-size", VLC_VAR_INTEGER);
    var_SetInteger(root, "visualization-size", -1);

    vlc_player_t *player = vlc_player_New(VLC_OBJECT(root), VLC_PLAYER_LOCK_NORMAL);
    assert(player);
    input_item_t *media = input_item_New(gl ? "mock://length=20000000;audio_track_count=1;audio_sinewave=true"
                                           : "mock://length=20000000;audio_track_count=1;audio_sinewave=false", effect);
    assert(media);
    vlc_player_Lock(player);
    assert(vlc_player_SetCurrentMedia(player, media) == VLC_SUCCESS);
    assert(vlc_player_Start(player) == VLC_SUCCESS);
    vlc_player_Unlock(player);
    input_item_Release(media);
    wait_picture(800, 500, 0);
    fprintf(stderr, "%s: initial canvas 800x500 rendered\n", effect);

    resize(root, 1920, 480, 1920, 480);
    resize(root, 975, 549, gl ? 975 : 974, gl ? 549 : 548);
    resize(root, 200, 100, goom || gl ? 200 : 532, goom || gl ? 100 : 400);
    resize(root, -1, -1, gl ? 200 : goom ? 64 : 532, gl ? 100 : goom ? 64 : 400);
    resize(root, 1280, 720, 1280, 720);
    resize(root, 800, 500, 800, 500);

    assert(atomic_load(&display_opens) == 1);
    assert(atomic_load(&display_closes) == 0);
    assert(atomic_load(&display_updates) >= 5);

    unsigned previous = atomic_load(&picture_count);
    var_SetInteger(root, "effect-width", INT64_C(4294967297));
    var_SetInteger(root, "goom-width", INT64_C(4294967297));
    var_SetInteger(root, "glspectrum-width", INT64_C(4294967297));
    var_SetInteger(root, "projectm-width", INT64_C(4294967297));
    wait_picture(800, 500, previous + 2);
    assert(atomic_load(&window_opens) == 1);

    atomic_store(&fail_format, true);
    previous = atomic_load(&picture_count);
    var_SetInteger(root, "effect-width", 1200);
    var_SetInteger(root, "effect-height", 600);
    var_SetInteger(root, "goom-width", 1200);
    var_SetInteger(root, "goom-height", 600);
    var_SetInteger(root, "glspectrum-width", 1200);
    var_SetInteger(root, "glspectrum-height", 600);
    var_SetInteger(root, "projectm-width", 1200);
    var_SetInteger(root, "projectm-height", 600);
    const vlc_tick_t deadline = vlc_tick_now() + VLC_TICK_FROM_SEC(5);
    /* Wait for both the live update and fallback display open to reject the
     * format before allowing it again. A retained old-size picture alone does
     * not prove that the fallback has finished. */
    while (atomic_load(&failed_formats) < 2)
    {
        assert(vlc_sem_timedwait(&frame_event, deadline) == 0);
    }
    previous = atomic_load(&picture_count);
    wait_picture(800, 500, previous + 1);
    atomic_store(&fail_format, false);
    resize(root, 960, 540, 960, 540);

    const unsigned widths[] = {800, 1280, 1920};
    const unsigned heights[] = {500, 720, 1080};
    for (unsigned i = 0; i < ARRAY_SIZE(widths); ++i)
    {
        previous = atomic_load(&picture_count);
        var_SetInteger(root, "visualization-size", i + 1);
        wait_picture(widths[i], heights[i], previous);
    }
    previous = atomic_load(&picture_count);
    var_SetInteger(root, "visualization-window-size", size_key(1901, 791));
    var_SetInteger(root, "visualization-size", 0);
    wait_picture(gl ? 1901 : 1900, gl ? 791 : 790, previous);
    previous = atomic_load(&picture_count);
    var_SetInteger(root, "visualization-window-size", size_key(1040, 620));
    wait_picture(1040, 620, previous);
    if (gl)
    {
        previous = atomic_load(&picture_count);
        var_SetInteger(root, "visualization-window-size", size_key(INT_MAX, 620));
        wait_picture(1040, 620, previous + 2);
    }
    previous = atomic_load(&picture_count);
    var_SetInteger(root, "visualization-size", -1);
    wait_picture(960, 540, previous);
    assert(var_GetInteger(root, "effect-width") == 960);
    assert(var_GetInteger(root, "goom-width") == 960);

    vlc_player_Lock(player);
    assert(vlc_player_GetState(player) == VLC_PLAYER_STATE_PLAYING);
    vlc_player_Stop(player);
    vlc_player_Unlock(player);
    vlc_player_Delete(player);
    libvlc_release(instance);
    assert(atomic_load(&window_opens) == 1);
    assert(atomic_load(&window_closes) == 1);
    return true;
}

static void Timeout(void *opaque)
{
    (void) opaque;
    fputs("visualization resize test timed out\n", stderr);
    abort();
}

#ifdef VISUAL_RESIZE_TEST_PLUGIN
VLC_EXPORT int visual_resize_test_run(void);
int visual_resize_test_run(void)
#else
int main(void)
#endif
{
    vlc_timer_t timer;
    assert(vlc_timer_create(&timer, Timeout, NULL) == 0);
    vlc_timer_schedule(timer, false, VLC_TICK_FROM_SEC(45), 0);
#ifdef VISUAL_RESIZE_TEST_GL
# ifdef VISUAL_RESIZE_TEST_PROJECTM
    const char *effect = "projectm";
# else
    const char *effect = "glspectrum";
# endif
    if (!test_resize(effect, false))
    {
        vlc_timer_destroy(timer);
        assert(getenv("VLC_TEST_REQUIRE_GL") == NULL);
        return 77;
    }
    fprintf(stderr, "%s: live resize and recovery passed\n", effect);
    assert(test_resize(effect, true));
    fprintf(stderr, "%s: converted display resize and recovery passed\n", effect);
#else
    const char *effects[] = { "scope", "spectrum", "spectrometer", "vuMeter", "dummy" };
    for (size_t i = 0; i < ARRAY_SIZE(effects); ++i)
    {
        test_resize(effects[i], false);
        fprintf(stderr, "%s: live resize and recovery passed\n", effects[i]);
    }
#ifdef VISUAL_RESIZE_TEST_GOOM
    test_resize("goom", false);
    fprintf(stderr, "goom: live resize and recovery passed\n");
#endif
    test_resize("scope", true);
    fprintf(stderr, "scope: converted display resize and recovery passed\n");
#endif
    vlc_timer_destroy(timer);
    return 0;
}
