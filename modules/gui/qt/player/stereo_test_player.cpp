// SPDX-License-Identifier: GPL-2.0-or-later
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "stereo_test_player.hpp"
#include "stereo_test_signal.hpp"
#include <vlc_input_item.h>
#include <algorithm>
#include <memory>

namespace {
bool setBool(vlc_object_t *object, const char *name, bool value)
{
    return var_Create(object, name, VLC_VAR_BOOL) == VLC_SUCCESS &&
        var_SetBool(object, name, value) == VLC_SUCCESS;
}
bool setString(vlc_object_t *object, const char *name, const char *value)
{
    return var_Create(object, name, VLC_VAR_STRING) == VLC_SUCCESS &&
        var_SetString(object, name, value) == VLC_SUCCESS;
}
bool setInteger(vlc_object_t *object, const char *name, int value)
{
    return var_Create(object, name, VLC_VAR_INTEGER) == VLC_SUCCESS &&
        var_SetInteger(object, name, value) == VLC_SUCCESS;
}
bool setFloat(vlc_object_t *object, const char *name, float value)
{
    return var_Create(object, name, VLC_VAR_FLOAT) == VLC_SUCCESS &&
        var_SetFloat(object, name, value) == VLC_SUCCESS;
}
}

StereoTestPlayer::StereoTestPlayer()
{
    vlc_mutex_init(&m_clockLock);
}

StereoTestPlayer::~StereoTestPlayer()
{
    if (m_clockListener) vlc_player_RemoveTimer(m_player, m_clockListener);
    if (m_player) vlc_player_Delete(m_player);
    if (m_owner) vlc_object_delete(m_owner);
}

void StereoTestPlayer::clockUpdate(const vlc_player_timer_point *point, void *opaque)
{
    auto *self = static_cast<StereoTestPlayer *>(opaque);
    vlc_mutex_lock(&self->m_clockLock);
    self->m_clockPoint = *point;
    self->m_clockValid = true;
    vlc_mutex_unlock(&self->m_clockLock);
}

bool StereoTestPlayer::start(vlc_object_t *parent, audio_output_t *source, int stereoMode)
{
    if (m_owner) return false;
    const float volume = aout_VolumeGet(source);
    std::unique_ptr<char, decltype(&free)> device(aout_DeviceGet(source), free);
    m_owner = static_cast<vlc_object_t *>(vlc_object_create(parent, sizeof(vlc_object_t)));
    if (!m_owner) return false;
    if (!setBool(m_owner, "video", false) || !setBool(m_owner, "spu", false) ||
        !setBool(m_owner, "audio-spatial", false) ||
        !setBool(m_owner, "metadata-network-access", false) ||
        !setString(m_owner, "audio-visual", "none") ||
        !setString(m_owner, "audio-filter", "") ||
        !setString(m_owner, "audio-replay-gain-mode", "none") ||
        !setString(m_owner, "sout", "") ||
        !setFloat(m_owner, "rate", 1.f) ||
        !setInteger(m_owner, "audio-desync", 0) ||
        !setInteger(m_owner, "input-repeat", 0) ||
        !setInteger(m_owner, "stereo-mode", stereoMode)) return false;
#ifdef _WIN32
    /* Create the output on the live endpoint and level. The saved startup
     * settings can differ, and Windows sessions can share volume controls. */
    if (!setFloat(m_owner, "mmdevice-volume", volume < 0 ? 0.5f : std::min(volume, 1.f)) ||
        (device && !setString(m_owner, "mmdevice-audio-device", device.get()))) return false;
#endif

    m_player = vlc_player_New(m_owner, VLC_PLAYER_LOCK_NORMAL);
    if (!m_player) return false;
    static const vlc_player_timer_cbs callbacks = [] {
        vlc_player_timer_cbs cbs{};
        cbs.on_update = clockUpdate;
        return cbs;
    }();
    m_clockListener = vlc_player_AddTimer(m_player, VLC_TICK_FROM_MS(40), &callbacks, this);
    if (!m_clockListener) return false;
    audio_output_t *output = vlc_player_aout_Hold(m_player);
    if (!output) return false;
    const int deviceResult = device && *device ? aout_DeviceSet(output, device.get()) : VLC_SUCCESS;
    aout_Release(output);
    if (deviceResult != VLC_SUCCESS) return false;
    vlc_player_aout_SetVolume(m_player, volume < 0 ? 0.5f : std::min(volume, 1.f));

    const QByteArray uri = QByteArray("data:audio/wav;base64,") + StereoTestSignal::wave().toBase64();
    input_item_t *media = input_item_New(uri.constData(), "Stereo test");
    if (!media) return false;
    vlc_player_Lock(m_player);
    int result = vlc_player_SetCurrentMedia(m_player, media);
    if (result == VLC_SUCCESS) result = vlc_player_Start(m_player);
    vlc_player_Unlock(m_player);
    input_item_Release(media);
    return result == VLC_SUCCESS;
}

StereoTestPlayer::State StereoTestPlayer::state()
{
    vlc_player_Lock(m_player);
    const auto state = vlc_player_GetState(m_player);
    const auto error = vlc_player_GetError(m_player);
    auto time = vlc_player_GetTime(m_player);
    auto position = vlc_player_GetPosition(m_player);
    vlc_player_Unlock(m_player);
    if (error != VLC_PLAYER_ERROR_NONE) return State::Failed;
    if (state == VLC_PLAYER_STATE_PLAYING) m_played = true;
    if (state == VLC_PLAYER_STATE_STOPPED && m_played) return State::Complete;
    /* The input can leave the player while its audio is still draining. Keep
     * the last output-clock point for the channel labels during that tail. */
    vlc_mutex_lock(&m_clockLock);
    vlc_tick_t interpolated;
    if (m_clockValid && vlc_player_timer_point_Interpolate(&m_clockPoint,
        vlc_tick_now(), &interpolated, &position) == VLC_SUCCESS)
        time = interpolated - VLC_TICK_0;
    vlc_mutex_unlock(&m_clockLock);
    if (!m_played || time == VLC_TICK_INVALID) return State::Starting;
    const auto ms = MS_FROM_VLC_TICK(time);
    if (position >= 1. || ms >= StereoTestSignal::durationMS) return State::Complete;
    if (ms < StereoTestSignal::toneMS) return State::Left;
    if (ms >= StereoTestSignal::rightStartMS &&
        ms < StereoTestSignal::rightStartMS + StereoTestSignal::toneMS) return State::Right;
    return State::Gap;
}
