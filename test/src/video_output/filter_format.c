// SPDX-License-Identifier: LGPL-2.1-or-later
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#define MODULE_NAME test_filter_format
#undef VLC_DYNAMIC_PLUGIN
#include <vlc/vlc.h>
#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_filter.h>
#include <vlc_player.h>
#include <vlc_vout.h>
#include <vlc_vout_display.h>
#include <vlc_window.h>
#include <stdatomic.h>
#include <limits.h>
#include <stdlib.h>
#include <stdio.h>
#undef NDEBUG
#include <assert.h>
#include "../../../lib/libvlc_internal.h"

static vlc_sem_t event;
static atomic_uint frames, last_chroma, updates, rejected, conversions, opened;
static atomic_bool reject_update;

static int EnableWindow(vlc_window_t *window, const vlc_window_cfg_t *cfg)
{
    (void) window; (void) cfg;
    return VLC_SUCCESS;
}

static int OpenWindow(vlc_window_t *window)
{
    static const struct vlc_window_operations ops = { .enable = EnableWindow };
    window->ops = &ops;
    return VLC_SUCCESS;
}

static void Display(vout_display_t *display, picture_t *picture)
{
    assert(display->fmt->i_chroma == picture->format.i_chroma);
    assert(display->fmt->i_width == picture->format.i_width);
    assert(display->fmt->i_height == picture->format.i_height);
    atomic_store(&last_chroma, picture->format.i_chroma);
    atomic_fetch_add(&frames, 1);
    vlc_sem_post(&event);
}

static int UpdateFormat(vout_display_t *display, const video_format_t *format,
                        vlc_video_context *context)
{
    (void) display; (void) context;
    assert(format->i_chroma == VLC_CODEC_I420 || format->i_chroma == VLC_CODEC_I422);
    if (atomic_load(&reject_update))
    {
        atomic_fetch_add(&rejected, 1);
        vlc_sem_post(&event);
        return VLC_EGENERIC;
    }
    atomic_fetch_add(&updates, 1);
    vlc_sem_post(&event);
    return VLC_SUCCESS;
}

static int OpenDisplay(vout_display_t *display, video_format_t *format,
                       vlc_video_context *context)
{
    (void) context;
    assert(format->i_chroma == VLC_CODEC_I420);
    static const struct vlc_display_operations ops = {
        .display = Display, .update_format = UpdateFormat,
    };
    display->ops = &ops;
    return VLC_SUCCESS;
}

static picture_t *Convert(filter_t *filter, picture_t *input)
{
    picture_t *output = picture_NewFromFormat(&filter->fmt_out.video);
    assert(output);
    picture_CopyProperties(output, input);
    picture_Release(input);
    return output;
}

static int OpenFilter(filter_t *filter)
{
    filter->fmt_out.video.i_chroma = filter->fmt_out.i_codec = VLC_CODEC_I422;
    static const struct vlc_filter_operations ops = { .filter_video = Convert };
    filter->ops = &ops;
    atomic_fetch_add(&opened, 1);
    vlc_sem_post(&event);
    return VLC_SUCCESS;
}

static int OpenConverter(filter_t *filter)
{
    atomic_fetch_add(&conversions, 1);
    vlc_sem_post(&event);
    if (filter->fmt_in.video.i_width != filter->fmt_out.video.i_width
        || filter->fmt_in.video.i_height != filter->fmt_out.video.i_height)
        return VLC_EGENERIC;
    static const struct vlc_filter_operations ops = { .filter_video = Convert };
    filter->ops = &ops;
    return VLC_SUCCESS;
}

vlc_module_begin()
    set_capability("vout window", INT_MAX)
    set_callback(OpenWindow)
    add_shortcut("format-test")
    add_submodule()
        set_callback_display(OpenDisplay, INT_MAX)
        add_shortcut("format-test")
    add_submodule()
        set_callback_video_filter(OpenFilter)
        add_shortcut("format-shift")
    add_submodule()
        set_callback_video_converter(OpenConverter, INT_MAX)
vlc_module_end()

VLC_EXPORT const vlc_plugin_cb vlc_static_modules[] = { VLC_SYMBOL(vlc_entry), NULL };

static void WaitCounter(atomic_uint *counter, unsigned minimum)
{
    const vlc_tick_t deadline = vlc_tick_now() + VLC_TICK_FROM_SEC(5);
    while (atomic_load(counter) < minimum)
        assert(vlc_sem_timedwait(&event, deadline) == 0);
}

static void WaitFrame(vlc_fourcc_t chroma, unsigned previous)
{
    const vlc_tick_t deadline = vlc_tick_now() + VLC_TICK_FROM_SEC(5);
    while (atomic_load(&last_chroma) != chroma || atomic_load(&frames) <= previous)
        assert(vlc_sem_timedwait(&event, deadline) == 0);
}

static void SetFilter(vout_thread_t *vout, const char *name, vlc_fourcc_t chroma)
{
    fprintf(stderr, "request filter '%s', expected chroma %.4s\n", name, (const char *)&chroma);
    const unsigned before = atomic_load(&opened);
    assert(var_SetString(vout, "video-filter", name) == VLC_SUCCESS);
    if (*name) WaitCounter(&opened, before + 1);
    WaitFrame(chroma, atomic_load(&frames));
}

static void Run(bool paused)
{
    fprintf(stderr, "filter format test: paused=%d\n", paused);
    const unsigned previous_updates = atomic_load(&updates);
    const char *args[] = {
        "--ignore-config", "--no-plugins-cache", "--no-media-library", "--no-auto-preparse",
        "--no-spu", "--no-osd", "--aout=dummy", "--clock-master=monotonic",
        "--vout=format-test,none",
        "--video-filter=",
    };
    libvlc_instance_t *instance = libvlc_new(ARRAY_SIZE(args), args);
    assert(instance);
    assert(var_Create(instance->p_libvlc_int, "window", VLC_VAR_STRING) == VLC_SUCCESS);
    assert(var_SetString(instance->p_libvlc_int, "window", "format-test,none") == VLC_SUCCESS);
    vlc_player_t *player = vlc_player_New(VLC_OBJECT(instance->p_libvlc_int), VLC_PLAYER_LOCK_NORMAL);
    assert(player);
    input_item_t *media = input_item_New("mock://video_track_count=1;video_width=64;video_height=48;length=60000000", "format test");
    assert(media);
    vlc_player_Lock(player);
    assert(vlc_player_SetCurrentMedia(player, media) == VLC_SUCCESS);
    assert(vlc_player_Start(player) == VLC_SUCCESS);
    vlc_player_Unlock(player);
    input_item_Release(media);
    WaitFrame(VLC_CODEC_I420, atomic_load(&frames));
    vout_thread_t *vout = vlc_player_vout_Hold(player);
    assert(vout);
    if (paused)
    {
        vlc_player_Lock(player);
        vlc_player_Pause(player);
        vlc_player_Unlock(player);
        const vlc_tick_t deadline = vlc_tick_now() + VLC_TICK_FROM_SEC(5);
        for (;;)
        {
            vlc_player_Lock(player);
            const bool is_paused = vlc_player_IsPaused(player);
            vlc_player_Unlock(player);
            if (is_paused) break;
            assert(vlc_tick_now() < deadline);
            WaitCounter(&frames, atomic_load(&frames) + 1);
        }
    }
    /* User crop must not become the conversion target for filter removal. */
    assert(var_SetString(vout, "crop", "0+2+0+2") == VLC_SUCCESS);
    for (unsigned i = 0; i < 3; ++i)
    {
        SetFilter(vout, "format-shift", VLC_CODEC_I422);
        SetFilter(vout, "", VLC_CODEC_I420);
    }
    SetFilter(vout, "format-shift", VLC_CODEC_I422);
    atomic_store(&reject_update, true);
    const unsigned failures = atomic_load(&rejected);
    const unsigned previous_conversions = atomic_load(&conversions);
    assert(var_SetString(vout, "video-filter", "") == VLC_SUCCESS);
    WaitCounter(&rejected, failures + 1);
    WaitFrame(VLC_CODEC_I422, atomic_load(&frames) + 1);
    assert(atomic_load(&conversions) > previous_conversions);
    atomic_store(&reject_update, false);
    SetFilter(vout, "format-shift", VLC_CODEC_I422);
    SetFilter(vout, "", VLC_CODEC_I420);
    assert(atomic_load(&updates) == previous_updates + 8);
    vlc_player_Lock(player);
    assert(vlc_player_IsPaused(player) == paused);
    vlc_player_Unlock(player);
    vout_Release(vout);
    vlc_player_Delete(player);
    libvlc_release(instance);
}

static void Timeout(void *opaque)
{
    (void) opaque;
    abort();
}

int main(void)
{
    vlc_sem_init(&event, 0);
    vlc_timer_t timer;
    assert(vlc_timer_create(&timer, Timeout, NULL) == 0);
    vlc_timer_schedule(timer, false, VLC_TICK_FROM_SEC(25), 0);
    Run(false);
    Run(true);
    vlc_timer_destroy(timer);
    return 0;
}
