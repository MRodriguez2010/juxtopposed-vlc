// SPDX-License-Identifier: GPL-2.0-or-later
#ifndef VLC_QT_STEREO_TEST_SIGNAL_HPP
#define VLC_QT_STEREO_TEST_SIGNAL_HPP

#include <QByteArray>
#include <QtEndian>
#include <algorithm>
#include <cmath>
#include <cstring>

namespace StereoTestSignal {
constexpr int sampleRate = 16000;
constexpr int durationMS = 1600;
constexpr int toneMS = 600;
constexpr int rightStartMS = 800;

inline QByteArray wave()
{
    const int frames = sampleRate * durationMS / 1000;
    const int bytes = frames * 4;
    QByteArray result(44 + bytes, '\0');
    auto *out = result.data();
    memcpy(out, "RIFF", 4);
    qToLittleEndian<quint32>(36 + bytes, out + 4);
    memcpy(out + 8, "WAVEfmt ", 8);
    qToLittleEndian<quint32>(16, out + 16);
    qToLittleEndian<quint16>(1, out + 20);
    qToLittleEndian<quint16>(2, out + 22);
    qToLittleEndian<quint32>(sampleRate, out + 24);
    qToLittleEndian<quint32>(sampleRate * 4, out + 28);
    qToLittleEndian<quint16>(4, out + 32);
    qToLittleEndian<quint16>(16, out + 34);
    memcpy(out + 36, "data", 4);
    qToLittleEndian<quint32>(bytes, out + 40);
    const int toneFrames = sampleRate * toneMS / 1000;
    const int rightStart = sampleRate * rightStartMS / 1000;
    const int fadeFrames = sampleRate / 100;
    for (int channel = 0; channel < 2; ++channel) {
        const int start = channel == 0 ? 0 : rightStart;
        for (int i = 0; i < toneFrames; ++i) {
            const double fade = std::min(1., double(std::min(i, toneFrames - 1 - i)) / fadeFrames);
            const auto value = qint16(std::lround(4096 * fade * std::sin(2 * 3.141592653589793 * 500 * i / sampleRate)));
            qToLittleEndian<qint16>(value, out + 44 + (start + i) * 4 + channel * 2);
        }
    }
    return result;
}
}
#endif
