// SPDX-License-Identifier: GPL-2.0-or-later
#ifndef VLC_QT_STEREO_TEST_PLAYER_HPP
#define VLC_QT_STEREO_TEST_PLAYER_HPP

#include <vlc_common.h>
#include <vlc_player.h>
#include <vlc_aout.h>

class StereoTestPlayer
{
public:
    enum class State { Starting, Left, Right, Gap, Complete, Failed };
    StereoTestPlayer();
    ~StereoTestPlayer();
    bool start(vlc_object_t *parent, audio_output_t *source, int stereoMode);
    State state();
private:
    static void clockUpdate(const vlc_player_timer_point *point, void *opaque);
    vlc_object_t *m_owner = nullptr;
    vlc_player_t *m_player = nullptr;
    vlc_player_timer_id *m_clockListener = nullptr;
    vlc_mutex_t m_clockLock;
    vlc_player_timer_point m_clockPoint{};
    bool m_clockValid = false;
    bool m_played = false;
};
#endif
