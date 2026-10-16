// SPDX-License-Identifier: GPL-2.0-or-later
#include <QTest>
#include "player/stereo_test_signal.hpp"

class TestStereoTestSignal : public QObject
{
    Q_OBJECT
private slots:
    void stereoWaveHasSeparateFadedChannels()
    {
        const auto wave = StereoTestSignal::wave();
        QCOMPARE(wave.first(4), QByteArray("RIFF"));
        QCOMPARE(wave.mid(8, 8), QByteArray("WAVEfmt "));
        QCOMPARE(qFromLittleEndian<quint16>(wave.constData() + 20), quint16(1));
        QCOMPARE(qFromLittleEndian<quint16>(wave.constData() + 22), quint16(2));
        QCOMPARE(qFromLittleEndian<quint32>(wave.constData() + 24), quint32(16000));
        QCOMPARE(qFromLittleEndian<quint16>(wave.constData() + 34), quint16(16));
        QCOMPARE(qFromLittleEndian<quint32>(wave.constData() + 40), quint32(wave.size() - 44));
        QCOMPARE(wave.size() - 44, 16000 * 1600 / 1000 * 4);
        for (int i = 44; i < wave.size(); i += 2)
            QVERIFY(std::abs(int(qFromLittleEndian<qint16>(wave.constData() + i))) <= 4096);
        auto sample = [&wave](int ms, int channel) {
            return qFromLittleEndian<qint16>(wave.constData() + 44 + ms * 16 * 4 + channel * 2);
        };
        auto energy = [&wave](int fromMS, int toMS, int channel) {
            double sum = 0;
            for (int i = fromMS * 16; i < toMS * 16; ++i) {
                const auto value = qFromLittleEndian<qint16>(wave.constData() + 44 + i * 4 + channel * 2);
                sum += double(value) * value;
            }
            return sum / ((toMS - fromMS) * 16);
        };
        QCOMPARE(energy(0, 600, 1), 0.);
        QCOMPARE(energy(800, 1400, 0), 0.);
        QVERIFY(energy(100, 200, 0) > 1000000);
        QVERIFY(energy(900, 1000, 1) > 1000000);
        QCOMPARE(energy(600, 800, 0) + energy(600, 800, 1), 0.);
        QCOMPARE(energy(1400, 1600, 0) + energy(1400, 1600, 1), 0.);
        QVERIFY(energy(0, 5, 0) < energy(100, 105, 0) / 4);
        QCOMPARE(sample(0, 0), qint16(0));
        QCOMPARE(sample(800, 1), qint16(0));
    }
};
QTEST_GUILESS_MAIN(TestStereoTestSignal)
#include "test_stereo_test_signal.moc"
