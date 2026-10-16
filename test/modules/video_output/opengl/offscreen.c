// SPDX-License-Identifier: LGPL-2.1-or-later
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#undef NDEBUG
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <vlc/vlc.h>
#include <vlc_common.h>
#include <vlc_opengl.h>
#include <vlc_picture.h>
#include "../../../../lib/libvlc_internal.h"
#include "../../../../modules/video_output/opengl/gl_api.h"

#ifndef VLC_TEST_OPENGL_API
# define VLC_TEST_OPENGL_API VLC_OPENGL
#endif

#ifdef VLC_TEST_EXTERNAL_EGL
# include <EGL/egl.h>
static EGLDisplay external_display;
static EGLContext external_context;
static EGLSurface external_surface;

static bool create_external_context(void)
{
    external_display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (external_display == EGL_NO_DISPLAY ||
        !eglInitialize(external_display, NULL, NULL))
        return false;
    const bool es = VLC_TEST_OPENGL_API == VLC_OPENGL_ES2;
    const EGLint attrs[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, es ? EGL_OPENGL_ES2_BIT : EGL_OPENGL_BIT,
        EGL_NONE,
    };
    EGLConfig config;
    EGLint count;
    assert(eglChooseConfig(external_display, attrs, &config, 1, &count) && count);
    assert(eglBindAPI(es ? EGL_OPENGL_ES_API : EGL_OPENGL_API));
    const EGLint context_attrs[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
    external_context = eglCreateContext(external_display, config, EGL_NO_CONTEXT,
                                         context_attrs);
    assert(external_context != EGL_NO_CONTEXT);
    const EGLint surface_attrs[] = {EGL_WIDTH, 4, EGL_HEIGHT, 4, EGL_NONE};
    external_surface = eglCreatePbufferSurface(external_display, config, surface_attrs);
    assert(external_surface != EGL_NO_SURFACE);
    return true;
}

static void check_external_context(void)
{
    assert(eglMakeCurrent(external_display, external_surface, external_surface,
                         external_context));
    assert(eglMakeCurrent(external_display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                         EGL_NO_CONTEXT));
    assert(eglDestroyContext(external_display, external_context));
    assert(eglDestroySurface(external_display, external_surface));
    assert(eglTerminate(external_display));
    fprintf(stderr, "external EGL context survives provider shutdown\n");
}
#endif

typedef void (APIENTRY *scissor_fn)(GLint, GLint, GLsizei, GLsizei);
const char vlc_module_name[] = "test_offscreen";

static void check_integer(const opengl_vtable_t *vt, GLenum key, GLint expected)
{
    GLint value;
    vt->GetIntegerv(key, &value);
    assert(value == expected);
}

static void check_picture(const picture_t *picture, unsigned width, unsigned height,
                          unsigned frame)
{
    assert(picture != NULL && picture->format.i_chroma == VLC_CODEC_RGBA);
    assert(picture->format.i_visible_width == width);
    assert(picture->format.i_visible_height == height);
    assert(picture->p[0].i_pitch == (int)width * 4);
    for (unsigned y = 0; y < height; ++y)
        for (unsigned x = 0; x < width; ++x)
        {
            const uint8_t *pixel = picture->p[0].p_pixels + y * picture->p[0].i_pitch + x * 4;
            assert(pixel[0] == (x < width / 2 ? 255 : 0));
            assert(pixel[1] == (y < height / 2 ? 0 : 255));
            assert(pixel[2] == ((frame & 1) ? 255 : 0));
            assert(pixel[3] == 255);
        }
}

static bool check_context(vlc_object_t *root, unsigned width, unsigned height,
                           bool default_framebuffer)
{
    unsigned flags = VLC_TEST_OPENGL_API;
    if (default_framebuffer)
        flags |= VLC_GL_OFFSCREEN_DEFAULT_FRAMEBUFFER;
    vlc_gl_t *gl = vlc_gl_CreateOffscreen(root, NULL, width, height, flags, NULL, NULL);
    if (gl == NULL)
    {
        assert(getenv("VLC_TEST_REQUIRE_GL") == NULL);
        return false;
    }
    assert(gl->orientation == ORIENT_VFLIPPED);
    /* Destroying a second context must not terminate the first one's display. */
    vlc_gl_t *peer = vlc_gl_CreateOffscreen(root, NULL, 3, 3,
                                           VLC_TEST_OPENGL_API, NULL, NULL);
    assert(peer != NULL);
    assert(vlc_gl_MakeCurrent(peer) == VLC_SUCCESS);
    vlc_gl_ReleaseCurrent(peer);
    vlc_gl_Delete(peer);
    assert(vlc_gl_MakeCurrent(gl) == VLC_SUCCESS);
    struct vlc_gl_api api;
    assert(vlc_gl_api_Init(&api, gl) == VLC_SUCCESS);
    const opengl_vtable_t *vt = &api.vt;
    scissor_fn scissor = vlc_gl_GetProcAddress(gl, "glScissor");
    assert(scissor != NULL);
    GLint target;
    vt->GetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &target);
    assert(default_framebuffer ? target == 0 : target != 0);
    assert(vt->CheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE);
    GLuint renderer_pbo, renderer_fbo;
    vt->GenBuffers(1, &renderer_pbo);
    vt->GenFramebuffers(1, &renderer_fbo);
    picture_t *held[2] = {NULL, NULL};
    unsigned held_frame[2] = {0, 0};
    for (unsigned frame = 0; frame < 8; ++frame)
    {
        if (default_framebuffer)
            vt->BindFramebuffer(GL_FRAMEBUFFER, 0);
        vt->Viewport(0, 0, width, height);
        vt->Enable(GL_SCISSOR_TEST);
        for (unsigned quadrant = 0; quadrant < 4; ++quadrant)
        {
            bool right = quadrant & 1, top = quadrant & 2;
            unsigned x = right ? width / 2 : 0, y = top ? height / 2 : 0;
            scissor(x, y, right ? width - x : width / 2, top ? height - y : height / 2);
            vt->ClearColor(right ? 0.f : 1.f, top ? 1.f : 0.f, (frame & 1) ? 1.f : 0.f, 1.f);
            vt->Clear(GL_COLOR_BUFFER_BIT);
        }
        vt->Disable(GL_SCISSOR_TEST);
        if (default_framebuffer)
        {
            /* Engines may leave unrelated read targets and nondefault packing. */
            vt->BindFramebuffer(GL_FRAMEBUFFER, renderer_fbo);
            vt->BindBuffer(GL_PIXEL_PACK_BUFFER, renderer_pbo);
            vt->PixelStorei(GL_PACK_ALIGNMENT, 8);
            vt->PixelStorei(GL_PACK_ROW_LENGTH, width + 9);
            vt->PixelStorei(GL_PACK_SKIP_ROWS, 2);
            vt->PixelStorei(GL_PACK_SKIP_PIXELS, 3);
        }
        assert(vt->GetError() == GL_NO_ERROR);
        picture_t *picture = vlc_gl_SwapOffscreen(gl);
        assert(vt->GetError() == GL_NO_ERROR);
        check_picture(picture, width, height, frame);
        if (default_framebuffer)
        {
            check_integer(vt, GL_DRAW_FRAMEBUFFER_BINDING, renderer_fbo);
            check_integer(vt, GL_READ_FRAMEBUFFER_BINDING, renderer_fbo);
            check_integer(vt, GL_PIXEL_PACK_BUFFER_BINDING, renderer_pbo);
            check_integer(vt, GL_PACK_ALIGNMENT, 8);
            check_integer(vt, GL_PACK_ROW_LENGTH, width + 9);
            check_integer(vt, GL_PACK_SKIP_ROWS, 2);
            check_integer(vt, GL_PACK_SKIP_PIXELS, 3);
        }
        unsigned slot = frame % 2;
        if (held[slot])
        {
            check_picture(held[slot], width, height, held_frame[slot]);
            picture_Release(held[slot]);
        }
        held[slot] = picture_Clone(picture);
        assert(held[slot]);
        held_frame[slot] = frame;
        picture_Release(picture);
        vlc_gl_ReleaseCurrent(gl);
        assert(vlc_gl_MakeCurrent(gl) == VLC_SUCCESS);
    }
    for (unsigned slot = 0; slot < 2; ++slot)
        picture_Release(held[slot]);
    vt->DeleteBuffers(1, &renderer_pbo);
    vt->DeleteFramebuffers(1, &renderer_fbo);
    assert(vt->GetError() == GL_NO_ERROR);
    vlc_gl_ReleaseCurrent(gl);
    vlc_gl_Delete(gl);
    fprintf(stderr, "offscreen %s %ux%u: pixels, retained pictures and GL state passed\n",
            default_framebuffer ? "default framebuffer" : "supplied FBO", width, height);
    return true;
}

static void Timeout(void *opaque)
{
    (void)opaque;
    abort();
}

int main(void)
{
    vlc_timer_t timer;
    assert(vlc_timer_create(&timer, Timeout, NULL) == 0);
    vlc_timer_schedule(timer, false, VLC_TICK_FROM_SEC(30), 0);
#ifdef VLC_TEST_EXTERNAL_EGL
    if (!create_external_context())
    {
        assert(getenv("VLC_TEST_REQUIRE_GL") == NULL);
        vlc_timer_destroy(timer);
        return 77;
    }
#endif
    const char *args[] = {"--ignore-config", "--no-plugins-cache", "--no-media-library", "-vv"};
    libvlc_instance_t *instance = libvlc_new(ARRAY_SIZE(args), args);
    assert(instance);
    bool passed = true;
    for (unsigned mode = 0; mode < 2 && passed; ++mode)
        for (unsigned size = 0; size < 2 && passed; ++size)
            passed = check_context(VLC_OBJECT(instance->p_libvlc_int),
                                   size ? 81 : 7, size ? 53 : 5, mode != 0);
    if (passed)
    {
        const unsigned sizes[][2] = {
            {0, 1}, {1, 0}, {UINT_MAX, 1}, {1, UINT_MAX},
        };
        for (unsigned i = 0; i < ARRAY_SIZE(sizes); ++i)
            assert(vlc_gl_CreateOffscreen(VLC_OBJECT(instance->p_libvlc_int), NULL,
                                         sizes[i][0], sizes[i][1],
                                         VLC_TEST_OPENGL_API | VLC_GL_OFFSCREEN_DEFAULT_FRAMEBUFFER,
                                         NULL, NULL) == NULL);
    }
    libvlc_release(instance);
#ifdef VLC_TEST_EXTERNAL_EGL
    check_external_context();
#endif
    vlc_timer_destroy(timer);
    return passed ? 0 : 77;
}
