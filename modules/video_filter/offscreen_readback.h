// SPDX-License-Identifier: LGPL-2.1-or-later
#ifndef VLC_OFFSCREEN_READBACK_H
#define VLC_OFFSCREEN_READBACK_H

typedef void (APIENTRY *offscreen_read_buffer_fn)(GLenum);

static inline bool offscreen_CanRead(const opengl_vtable_t *vt,
                                      bool default_framebuffer)
{
    if (!vt->MapBufferRange || !vt->UnmapBuffer || !vt->ReadPixels ||
        !vt->BindFramebuffer || !vt->GenFramebuffers ||
        !vt->DeleteFramebuffers || !vt->FramebufferTexture2D)
        return false;
    if (default_framebuffer)
    {
        /* Separate read/draw targets and the required packing state are core
         * in OpenGL 3 and OpenGL ES 3. Reject older contexts safely. */
        GLint major = 0;
        vt->GetIntegerv(GL_MAJOR_VERSION, &major);
        if (vt->GetError() != GL_NO_ERROR || major < 3)
            return false;
    }
    return true;
}

/* A renderer may leave its own read framebuffer and pixel packing state bound.
 * Capture framebuffer zero without changing that state or its draw target. */
static inline void *
offscreen_ReadDefault(const opengl_vtable_t *vt,
                      offscreen_read_buffer_fn read_buffer, GLenum default_buffer,
                      GLuint pbo, bool mapped, unsigned width, unsigned height)
{
    GLint framebuffer, buffer, alignment, row_length, skip_rows, skip_pixels;
    vt->GetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &framebuffer);
    vt->GetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &buffer);
    vt->GetIntegerv(GL_PACK_ALIGNMENT, &alignment);
    vt->GetIntegerv(GL_PACK_ROW_LENGTH, &row_length);
    vt->GetIntegerv(GL_PACK_SKIP_ROWS, &skip_rows);
    vt->GetIntegerv(GL_PACK_SKIP_PIXELS, &skip_pixels);

    vt->BindFramebuffer(GL_READ_FRAMEBUFFER, 0);
    GLint previous_read_buffer;
    vt->GetIntegerv(GL_READ_BUFFER, &previous_read_buffer);
    read_buffer(default_buffer);
    vt->BindBuffer(GL_PIXEL_PACK_BUFFER, pbo);
    if (mapped)
        vt->UnmapBuffer(GL_PIXEL_PACK_BUFFER);
    vt->PixelStorei(GL_PACK_ALIGNMENT, 1);
    vt->PixelStorei(GL_PACK_ROW_LENGTH, 0);
    vt->PixelStorei(GL_PACK_SKIP_ROWS, 0);
    vt->PixelStorei(GL_PACK_SKIP_PIXELS, 0);
    vt->ReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    void *pixels = vt->MapBufferRange(GL_PIXEL_PACK_BUFFER, 0,
                                     (size_t)width * height * 4, GL_MAP_READ_BIT);

    vt->PixelStorei(GL_PACK_ALIGNMENT, alignment);
    vt->PixelStorei(GL_PACK_ROW_LENGTH, row_length);
    vt->PixelStorei(GL_PACK_SKIP_ROWS, skip_rows);
    vt->PixelStorei(GL_PACK_SKIP_PIXELS, skip_pixels);
    vt->BindBuffer(GL_PIXEL_PACK_BUFFER, buffer);
    read_buffer(previous_read_buffer);
    vt->BindFramebuffer(GL_READ_FRAMEBUFFER, framebuffer);
    return pixels;
}

#endif
