/*****************************************************************************
 * projectm.cpp: visualization module based on libprojectM
 *****************************************************************************
 * Copyright © 2009-2011 VLC authors and VideoLAN
 *
 * Authors: Rémi Duraffort <ivoire@videolan.org>
 *          Laurent Aimar
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
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_configuration.h>
#include <vlc_plugin.h>
#include <vlc_aout.h>
#include <vlc_window.h>
#include <vlc_opengl.h>
#include <vlc_filter.h>
#include <vlc_rand.h>
#include <vlc_queue.h>
#include <sys/stat.h>
#include <vlc_fs.h>
#include "opengl_vout.h"

#ifdef HAVE_PROJECTM4
# include <projectM-4/projectM.h>
# include <algorithm>
# include <atomic>
# include <memory>
# include <string>
# include <vector>
#else
# include <libprojectM/projectM.hpp>
#endif

#ifndef HAVE_PROJECTM4
# ifndef _WIN32
#  include <locale.h>
# endif
# ifdef HAVE_XLOCALE_H
#  include <xlocale.h>
# endif
#endif

#ifdef HAVE_PROJECTM4
# ifdef _WIN32
#  include <windows.h>
#  include <GL/glew.h>
# endif
#endif

/*****************************************************************************
 * Module descriptor
 *****************************************************************************/
static int  Open         ( vlc_object_t * );
static void Close        ( filter_t * );

#define CONFIG_TEXT N_("projectM configuration file")
#define CONFIG_LONGTEXT N_("File that will be used to configure the projectM " \
                           "module.")

#define PRESET_PATH_TXT N_("projectM preset path")
#define PRESET_PATH_LONGTXT N_("Path to the projectM preset directory")
#define PRESET_DURATION_TEXT N_("Preset duration")
#define PRESET_DURATION_LONGTEXT N_("Time before the next visualization preset, in seconds.")

#define TITLE_FONT_TXT N_("Title font")
#define TITLE_FONT_LONGTXT N_("Font used for the titles")

#define MENU_FONT_TXT N_("Font menu")
#define MENU_FONT_LONGTXT N_("Font used for the menus")

#define WIDTH_TEXT N_("Video width")
#define WIDTH_LONGTEXT N_("The width of the video window, in pixels.")

#define HEIGHT_TEXT N_("Video height")
#define HEIGHT_LONGTEXT N_("The height of the video window, in pixels.")

#define MESHX_TEXT N_("Mesh width")
#define MESHX_LONGTEXT N_("The width of the mesh, in pixels.")

#define MESHY_TEXT N_("Mesh height")
#define MESHY_LONGTEXT N_("The height of the mesh, in pixels.")

#define TEXTURE_TEXT N_("Texture size")
#define TEXTURE_LONGTEXT N_("The size of the texture, in pixels.")

#ifdef _WIN32
# define FONT_PATH      "C:\\WINDOWS\\Fonts\\arial.ttf"
# define FONT_PATH_MENU "C:\\WINDOWS\\Fonts\\arial.ttf"
# define PRESET_PATH    NULL
#else
# define FONT_PATH      "/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf"
# define FONT_PATH_MENU "/usr/share/fonts/truetype/ttf-dejavu/DejaVuSansMono.ttf"
# define PRESET_PATH    "/usr/share/projectM/presets"
#endif

#ifdef DEFAULT_FONT_FILE
#undef FONT_PATH
#define FONT_PATH DEFAULT_FONT_FILE
#endif

#ifdef DEFAULT_MONOSPACE_FONT_FILE
#undef FONT_PATH_MENU
#define FONT_PATH_MENU DEFAULT_MONOSPACE_FONT_FILE
#endif

vlc_module_begin ()
    set_shortname( N_("projectM"))
    set_description( N_("libprojectM effect") )
    set_capability( "visualization", 0 )
    set_subcategory( SUBCAT_AUDIO_VISUAL )
#if !defined(HAVE_PROJECTM2) && !defined(HAVE_PROJECTM4)
    add_loadfile("projectm-config", "/usr/share/projectM/config.inp",
                 CONFIG_TEXT, CONFIG_LONGTEXT)
#else
# ifdef HAVE_PROJECTM4
    add_obsolete_string("projectm-config")
    add_directory("projectm-preset-path", NULL,
                  PRESET_PATH_TXT, PRESET_PATH_LONGTXT)
# else
    add_directory("projectm-preset-path", PRESET_PATH,
                  PRESET_PATH_TXT, PRESET_PATH_LONGTXT)
    add_loadfile("projectm-title-font", FONT_PATH,
                 TITLE_FONT_TXT, TITLE_FONT_LONGTXT)
    add_loadfile("projectm-menu-font", FONT_PATH_MENU,
                 MENU_FONT_TXT, MENU_FONT_LONGTXT)
# endif
    add_integer_with_range("projectm-preset-duration", 30, 1, 600,
                           PRESET_DURATION_TEXT, PRESET_DURATION_LONGTEXT)
#endif
    add_integer( "projectm-width", 800, WIDTH_TEXT, WIDTH_LONGTEXT )
    add_integer( "projectm-height", 500, HEIGHT_TEXT, HEIGHT_LONGTEXT )
    add_integer( "projectm-meshx", 32, MESHX_TEXT, MESHX_LONGTEXT )
    add_integer( "projectm-meshy", 24, MESHY_TEXT, MESHY_LONGTEXT )
#ifndef HAVE_PROJECTM4
    add_integer( "projectm-texture-size", 1024, TEXTURE_TEXT, TEXTURE_LONGTEXT )
#else
    add_obsolete_integer("projectm-texture-size")
#endif
    add_shortcut( "projectm" )
    set_callback( Open )
vlc_module_end ()


/*****************************************************************************
 * Local prototypes
 *****************************************************************************/
namespace {

#ifdef HAVE_PROJECTM4
class PresetPlaylist
{
    filter_t *filter;
    projectm_handle instance;
    std::vector<std::string> files;
    size_t cursor = 0;
    std::atomic<bool> requested{true}, hard_cut{true}, failed{false};

    static void SwitchRequested(bool hard, void *opaque)
    {
        auto *self = static_cast<PresetPlaylist *>(opaque);
        self->hard_cut.store(hard, std::memory_order_relaxed);
        self->requested.store(true, std::memory_order_release);
    }

    static void SwitchFailed(const char *, const char *message, void *opaque)
    {
        auto *self = static_cast<PresetPlaylist *>(opaque);
        self->failed.store(true, std::memory_order_relaxed);
        msg_Warn(self->filter, "Could not load a projectM preset: %s", message);
    }

    static bool Read(const std::string &path, std::string &contents)
    {
        std::unique_ptr<FILE, decltype(&fclose)> file(vlc_fopen(path.c_str(), "rb"), fclose);
        if (!file || fseek(file.get(), 0, SEEK_END) != 0)
            return false;
        const long length = ftell(file.get());
        /* Match the library's 1 MiB preset parser limit before reading data. */
        if (length <= 0 || length > 1024 * 1024 ||
            fseek(file.get(), 0, SEEK_SET) != 0)
            return false;
        contents.resize(length);
        return fread(&contents[0], 1, length, file.get()) == (size_t)length &&
               contents.find('\0') == std::string::npos;
    }

public:
    PresetPlaylist(filter_t *filter, projectm_handle instance)
        : filter(filter), instance(instance)
    {
        std::unique_ptr<char, decltype(&free)> path(
            var_InheritString(filter, "projectm-preset-path"), free);
        if (!path)
            path.reset(config_GetSysPath(VLC_PKG_DATA_DIR, "visualization"));
        if (path)
        {
            std::unique_ptr<vlc_DIR, decltype(&vlc_closedir)> directory(
                vlc_opendir(path.get()), vlc_closedir);
            if (directory)
                while (files.size() < 4096)
                {
                    const char *entry = vlc_readdir(directory.get());
                    if (entry == NULL)
                        break;
                    const size_t length = strlen(entry);
                    if (length > 5 && !strcasecmp(entry + length - 5, ".milk"))
                        files.emplace_back(std::string(path.get()) + '/' + entry);
                }
            const char *textures[] = {path.get()};
            projectm_set_texture_search_paths(instance, textures, 1);
        }
        if (files.empty())
            msg_Warn(filter, "No projectM presets were found");
        for (size_t i = files.size(); i > 1; --i)
            std::swap(files[i - 1], files[(unsigned)vlc_mrand48() % i]);
        projectm_set_preset_switch_requested_event_callback(instance, SwitchRequested, this);
        projectm_set_preset_switch_failed_event_callback(instance, SwitchFailed, this);
    }

    void Detach()
    {
        projectm_set_preset_switch_requested_event_callback(instance, NULL, NULL);
        projectm_set_preset_switch_failed_event_callback(instance, NULL, NULL);
    }

    void Update()
    {
        if (!requested.exchange(false, std::memory_order_acquire))
            return;
        const bool smooth = !hard_cut.load(std::memory_order_relaxed);
        /* Load outside the render callback. Bad entries are removed, and one
         * audio frame makes only a bounded number of attempts. */
        for (unsigned attempt = 0; !files.empty() && attempt < 8; ++attempt)
        {
            std::string contents;
            failed.store(false, std::memory_order_relaxed);
            if (Read(files[cursor], contents))
            {
                /* VLC's file API supports UTF-8 Windows paths. Passing data
                 * also avoids projectM's narrow-path file stream. */
                projectm_load_preset_data(instance, contents.c_str(), smooth);
                if (!failed.load(std::memory_order_relaxed))
                {
                    msg_Dbg(filter, "Loaded projectM preset: %s", files[cursor].c_str());
                    cursor = (cursor + 1) % files.size();
                    if (files.size() == 1)
                        projectm_set_preset_locked(instance, true);
                    return;
                }
            }
            else
                msg_Warn(filter, "Could not read projectM preset: %s", files[cursor].c_str());
            files.erase(files.begin() + cursor);
            if (!files.empty())
                cursor %= files.size();
        }
        if (!files.empty())
            requested.store(true, std::memory_order_release);
    }
};
#endif

struct filter_sys_t
{
    /* */
    vlc_thread_t thread;

    /* Opengl */
    struct visualization_gl *canvas;

    /* audio info */
    int i_channels;

    vlc_queue_t queue;
    bool dead;
#if defined(HAVE_PROJECTM2) && !defined(HAVE_PROJECTM4)
    char *title_font, *menu_font;
#endif
};

} // namespace

static block_t *DoWork( filter_t *, block_t * );
static void *Thread( void * );

#if defined(HAVE_PROJECTM2) && !defined(HAVE_PROJECTM4)
static bool FontReadable(const char *path)
{
    struct stat st;
    if (path == NULL || vlc_stat(path, &st) != 0 || !S_ISREG(st.st_mode))
        return false;
    FILE *file = vlc_fopen(path, "rb");
    if (file == NULL)
        return false;
    fclose(file);
    return true;
}

static char *FindFont(filter_t *filter, const char *option, bool monospace)
{
    char *path = var_InheritString(filter, option);
    if (FontReadable(path))
        return path;
    free(path);
    const char *const candidates[] = {
        monospace ? FONT_PATH_MENU : FONT_PATH,
        monospace ? "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
                  : "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        monospace ? "/usr/share/fonts/dejavu/DejaVuSansMono.ttf"
                  : "/usr/share/fonts/dejavu/DejaVuSans.ttf",
        monospace ? "/usr/share/fonts/TTF/DejaVuSansMono.ttf"
                  : "/usr/share/fonts/TTF/DejaVuSans.ttf",
    };
    for (const char *candidate : candidates)
        if (FontReadable(candidate))
        {
            msg_Warn(filter, "Using a default font for projectM");
            return strdup(candidate);
        }
    return NULL;
}
#endif

static const struct FilterOperationInitializer {
    struct vlc_filter_operations ops {};
    FilterOperationInitializer()
    {
        ops.filter_audio = DoWork;
        ops.close = Close;
    }
} filter_ops;

/**
 * Open the module
 * @param p_this: the filter object
 * @return VLC_SUCCESS or vlc error codes
 */
static int Open( vlc_object_t * p_this )
{
    filter_t     *p_filter = (filter_t *)p_this;
    filter_sys_t *p_sys;

    p_filter->p_sys = p_sys = (filter_sys_t*)calloc(1, sizeof(*p_sys));
    if( !p_sys )
        return VLC_ENOMEM;

    p_sys->dead = false;
    p_sys->i_channels = aout_FormatNbChannels(&p_filter->fmt_in.audio);
    if (p_sys->i_channels == 0)
        goto error;
    vlc_queue_Init(&p_sys->queue, offsetof(block_t, p_next));
#if defined(HAVE_PROJECTM2) && !defined(HAVE_PROJECTM4)
    p_sys->title_font = FindFont(p_filter, "projectm-title-font", false);
    p_sys->menu_font = FindFont(p_filter, "projectm-menu-font", true);
    if (p_sys->title_font == NULL || p_sys->menu_font == NULL)
    {
        msg_Err(p_filter, "Could not find a font for projectM");
        goto error;
    }
#endif
    p_sys->canvas = visualization_gl_New(p_filter, "projectm-width", "projectm-height");
    if (p_sys->canvas == NULL)
        goto error;

    /* Create the thread */
    if( vlc_clone( &p_sys->thread, Thread, p_filter ) )
    {
        goto error;
    }

    p_filter->fmt_in.audio.i_format = VLC_CODEC_FL32;
    p_filter->fmt_out.audio = p_filter->fmt_in.audio;
    p_filter->ops = &filter_ops.ops;
    return VLC_SUCCESS;

error:
    if (p_sys->canvas)
        visualization_gl_Delete(p_sys->canvas);
#if defined(HAVE_PROJECTM2) && !defined(HAVE_PROJECTM4)
    free(p_sys->title_font);
    free(p_sys->menu_font);
#endif
    free (p_sys );
    return VLC_EGENERIC;
}


/**
 * Close the module
 * @param p_this: the filter object
 */
static void Close( filter_t *p_filter )
{
    filter_sys_t *p_sys = reinterpret_cast<filter_sys_t *>( p_filter->p_sys );

    vlc_queue_Kill(&p_sys->queue, &p_sys->dead);
    visualization_gl_Stop(p_sys->canvas);
    vlc_join(p_sys->thread, NULL);
    visualization_gl_Delete(p_sys->canvas);
    vlc_queue_Lock(&p_sys->queue);
    block_t *pending = static_cast<block_t *>(vlc_queue_DequeueAllUnlocked(&p_sys->queue));
    vlc_queue_Unlock(&p_sys->queue);
    block_ChainRelease(pending);
#if defined(HAVE_PROJECTM2) && !defined(HAVE_PROJECTM4)
    free(p_sys->title_font);
    free(p_sys->menu_font);
#endif
    free( p_sys );
}


/**
 * Do the actual work with the new sample
 * @param p_aout: audio output object
 * @param p_filter: filter object
 * @param p_in_buf: input buffer
 * @param p_out_buf: output buffer
 */
static block_t *DoWork( filter_t *p_filter, block_t *p_in_buf )
{
    filter_sys_t *p_sys = reinterpret_cast<filter_sys_t *>( p_filter->p_sys );

    block_t *copy = block_Duplicate(p_in_buf);
    if (copy == NULL)
        return p_in_buf;
    vlc_queue_Lock(&p_sys->queue);
    block_t *pending = static_cast<block_t *>(vlc_queue_DequeueAllUnlocked(&p_sys->queue));
    if (!p_sys->dead)
    {
        vlc_queue_EnqueueUnlocked(&p_sys->queue, copy);
        vlc_queue_Signal(&p_sys->queue);
        copy = NULL;
    }
    vlc_queue_Unlock(&p_sys->queue);
    block_ChainRelease(pending);
    if (copy)
        block_Release(copy);

    return p_in_buf;
}

/**
 * ProjectM update thread which do the rendering
 * @param p_this: the p_thread object
 */
static void *Thread( void *p_data )
{
    vlc_thread_set_name("vlc-projectm");

    filter_t  *p_filter = (filter_t*)p_data;
    filter_sys_t *p_sys = reinterpret_cast<filter_sys_t *>( p_filter->p_sys );
    vlc_gl_t *gl = p_sys->canvas->gl;

#ifdef HAVE_PROJECTM4
    projectm_handle p_projectm;
#else
    projectM *p_projectm;
#endif

#ifndef HAVE_PROJECTM4
#ifndef HAVE_PROJECTM2
    char *psz_config;
#else
    char *psz_preset_path;
    char *psz_title_font;
    char *psz_menu_font;
    projectM::Settings settings;
#endif
#endif

    if( vlc_gl_MakeCurrent( gl ) != VLC_SUCCESS )
    {
        msg_Err( p_filter, "Can't attach gl context" );
        return NULL;
    }

#ifdef HAVE_PROJECTM4
#ifdef _WIN32
    if (glewInit() != GLEW_OK)
    {
        vlc_gl_ReleaseCurrent( gl );
        return NULL;
    }
#endif
#endif

#ifndef HAVE_PROJECTM4
    /* Work-around the projectM locale bug */
    locale_t loc = newlocale (LC_NUMERIC_MASK, "C", NULL);
    locale_t oldloc = uselocale (loc);
#endif

    /* Create the projectM object */
#ifdef HAVE_PROJECTM4
    p_projectm = projectm_create();
    if (p_projectm == NULL)
    {
        vlc_gl_ReleaseCurrent(gl);
        msg_Err(p_filter, "Could not start projectM");
        return NULL;
    }
    projectm_set_window_size(p_projectm, p_sys->canvas->format.i_width,
                             p_sys->canvas->format.i_height);
    projectm_set_mesh_size(p_projectm,
        std::min<int64_t>(300, std::max<int64_t>(8, var_InheritInteger(p_filter, "projectm-meshx"))),
        std::min<int64_t>(300, std::max<int64_t>(8, var_InheritInteger(p_filter, "projectm-meshy"))));
    projectm_set_preset_duration(p_projectm, var_InheritInteger(p_filter, "projectm-preset-duration"));
    projectm_set_soft_cut_duration(p_projectm, 5);
    PresetPlaylist presets(p_filter, p_projectm);
#else
#ifndef HAVE_PROJECTM2
    psz_config = var_InheritString( p_filter, "projectm-config" );
    p_projectm = new projectM( psz_config ? psz_config : "" );
    p_projectm->projectM_resetGL(p_sys->canvas->format.i_width, p_sys->canvas->format.i_height);
    free( psz_config );
#else
    psz_preset_path = var_InheritString( p_filter, "projectm-preset-path" );

#ifdef _WIN32
    if ( psz_preset_path == NULL )
        psz_preset_path = config_GetSysPath(VLC_PKG_DATA_DIR, "visualization");
#endif
    psz_title_font                = p_sys->title_font;
    psz_menu_font                 = p_sys->menu_font;

    settings.meshX                = var_InheritInteger( p_filter, "projectm-meshx" );
    settings.meshY                = var_InheritInteger( p_filter, "projectm-meshy" );
    settings.fps                  = 35;
    settings.textureSize          = var_InheritInteger( p_filter, "projectm-texture-size" );
    settings.windowWidth          = p_sys->canvas->format.i_width;
    settings.windowHeight         = p_sys->canvas->format.i_height;
    settings.presetURL            = psz_preset_path ? psz_preset_path : "";
    settings.titleFontURL         = psz_title_font;
    settings.menuFontURL          = psz_menu_font;
    settings.smoothPresetDuration = 5;
    settings.presetDuration       = var_InheritInteger(p_filter, "projectm-preset-duration");
    settings.beatSensitivity      = 10;
    settings.aspectCorrection     = 1;
    settings.easterEgg            = 1;
    settings.shuffleEnabled       = 1;
    settings.softCutRatingsEnabled= false;

    p_projectm = new projectM( settings );

    free( psz_preset_path );
#endif /* HAVE_PROJECTM2 */
#endif /* HAVE_PROJECTM4 */

#ifdef HAVE_PROJECTM4
    const unsigned capacity = projectm_pcm_get_max_samples();
#else
    const unsigned capacity = p_projectm->pcm()->maxsamples;
#endif
    float *samples = static_cast<float *>(calloc(capacity, sizeof(float)));
    unsigned engine_width = p_sys->canvas->format.i_width;
    unsigned engine_height = p_sys->canvas->format.i_height;
    vlc_tick_t next_frame = 0;
    /* Choose a preset randomly or projectM will always show the first one */
#ifndef HAVE_PROJECTM4
    if ( p_projectm->getPlaylistSize() > 0 )
        p_projectm->selectPreset( (unsigned)vlc_mrand48() % p_projectm->getPlaylistSize() );
#endif

    block_t *block;
    while (samples && (block = static_cast<block_t *>(vlc_queue_DequeueKillable(&p_sys->queue, &p_sys->dead))))
    {
        /* Keep the previous 50 fps limit even with short audio blocks. */
        if (vlc_tick_now() < next_frame)
        {
            block_Release(block);
            continue;
        }
        if (block->i_pts == VLC_TICK_INVALID || block->i_nb_samples == 0 ||
            !visualization_gl_UpdateSize(p_sys->canvas))
        {
            block_Release(block);
            if (p_sys->canvas->context_failed)
                break;
            continue;
        }
        unsigned width = p_sys->canvas->format.i_width;
        unsigned height = p_sys->canvas->format.i_height;
        if (width != engine_width || height != engine_height)
        {
#ifdef HAVE_PROJECTM4
            projectm_set_window_size(p_projectm, width, height);
#else
            p_projectm->projectM_resetGL(width, height);
#endif
            engine_width = width;
            engine_height = height;
        }
        picture_t *picture = visualization_gl_Acquire(p_sys->canvas);
        if (picture == NULL)
        {
            block_Release(block);
            continue;
        }
        const unsigned count = __MIN(capacity, block->i_nb_samples);
        const float *source = reinterpret_cast<const float *>(block->p_buffer)
            + (block->i_nb_samples - count) * p_sys->i_channels;
        for (unsigned i = 0; i < count; ++i)
        {
            float value = 0;
            for (int channel = 0; channel < p_sys->i_channels; ++channel)
                value += source[i * p_sys->i_channels + channel];
            samples[i] = value / p_sys->i_channels;
        }
#ifdef HAVE_PROJECTM4
        presets.Update();
        projectm_pcm_add_float(p_projectm, samples, count, (projectm_channels)1);
        projectm_opengl_render_frame(p_projectm);
#else
        p_projectm->pcm()->addPCMfloat(samples, count);
        p_projectm->renderFrame();
#endif
        visualization_gl_Present(p_sys->canvas, picture, block->i_pts + block->i_length / 2);
        next_frame = vlc_tick_now() + VLC_TICK_FROM_MS(20);
        block_Release(block);
    }
    free(samples);
#ifdef HAVE_PROJECTM4
    presets.Detach();
#endif
    if (p_sys->canvas->context_failed && vlc_gl_MakeCurrent(gl) == VLC_SUCCESS)
        p_sys->canvas->context_failed = false;
    if (!p_sys->canvas->context_failed)
    {

#ifdef HAVE_PROJECTM4
    projectm_destroy( p_projectm );

#else
    delete p_projectm;

#endif
        vlc_gl_ReleaseCurrent(gl);
    }

#ifndef HAVE_PROJECTM4
    if (loc != (locale_t)0)
    {
        uselocale (oldloc);
        freelocale (loc);
    }
#endif

    return NULL;
}
