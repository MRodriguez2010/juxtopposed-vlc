// SPDX-License-Identifier: GPL-2.0-or-later
#include "redesign_preferences.hpp"
#include "player/stereo_test_player.hpp"
#include <vlc_configuration.h>
#include <vlc_modules.h>
#include <vlc_plugin.h>
#include <vlc_aout.h>
#include <vlc_player.h>
#include <vlc_iso_lang.h>
#include <vlc_subpicture.h>
#include <vlc_vout.h>
#include "../../../../audio_filter/equalizer_presets.h"
#include <cmath>
#include <climits>
#include <algorithm>
#include <QFileDialog>
#include <QColorDialog>
#include <QGuiApplication>
#include <QScreen>
#include <QKeyEvent>
#include <QRegularExpression>
#include <QCollator>
#include <QDir>
#include <QFileInfo>
#include <QSettings>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUuid>
#include "util/vlchotkeyconverter.hpp"

namespace {
const QString presetOption = QStringLiteral("qt-player-presets");

struct ResamplingQuality {
    const char* module;
    const char* option;
    int low, balanced, high;
};

const ResamplingQuality resamplingQualities[] = {
    {"soxr", "soxr-resampler-quality", 0, 2, 4},
    {"samplerate", "src-converter-type", 4, 2, 0},
    {"speex_resampler", "speex-resampler-quality", 0, 4, 10},
};

const ResamplingQuality* resamplingQuality(const QString& module)
{
    const bool automatic = module.isEmpty() || module == QLatin1String("any");
    for (const auto& quality : resamplingQualities) {
        if ((automatic || module == QLatin1String(quality.module)
             || (module == QLatin1String("speex") && !strcmp(quality.module, "speex_resampler")))
            && config_FindConfig(quality.option)) return &quality;
    }
    return nullptr;
}

QString audioPassthroughOption(const QString& module)
{
    const auto option = module == QLatin1String("mmdevice") ? QStringLiteral("mmdevice-passthrough")
        : module == QLatin1String("alsa") ? QStringLiteral("alsa-passthrough")
        : module == QLatin1String("oss") ? QStringLiteral("oss-spdif")
        : module == QLatin1String("waveout") ? QStringLiteral("spdif") : QString();
    const auto* cfg = option.isEmpty() ? nullptr : config_FindConfig(option.toUtf8().constData());
    return cfg && cfg->psz_text ? option : QString();
}

QString audioFilterHelp(const QString& name)
{
    if (name == QLatin1String("equalizer")) return qtr("Change the level of each frequency band.");
    if (name == QLatin1String("normvol")) return qtr("Reduce the volume when the average audio level is above the target level.");
    if (name == QLatin1String("compressor")) return qtr("Reduce the difference between loud and quiet sounds.");
    if (name == QLatin1String("stereo_widen")) return qtr("Increase the separation between the left and right audio channels.");
    if (name == QLatin1String("chorus_flanger")) return qtr("Mix the audio with delayed copies to change its sound.");
    if (name == QLatin1String("karaoke")) return qtr("Reduce sounds in the center of stereo audio.");
    if (name == QLatin1String("spatializer")) return qtr("Add the sound of a room to stereo audio.");
    if (name == QLatin1String("audioscrobbler")) return qtr("Send information about played tracks to Last.fm.");
    return {};
}

const QStringList& videoFilterOptions()
{
    static const QStringList names{
        QStringLiteral("sharpen-sigma"), QStringLiteral("gradfun-radius"), QStringLiteral("grain-variance"),
        QStringLiteral("extract-component"), QStringLiteral("colorthres-color"),
        QStringLiteral("colorthres-saturationthres"), QStringLiteral("colorthres-similaritythres"),
        QStringLiteral("posterize-level"), QStringLiteral("gradient-mode"), QStringLiteral("gradient-color"),
        QStringLiteral("gradient-cartoon"), QStringLiteral("sepia-intensity"),
        QStringLiteral("brightness-threshold"), QStringLiteral("puzzle-rows"), QStringLiteral("puzzle-cols"),
        QStringLiteral("puzzle-mode"), QStringLiteral("puzzle-rotation"), QStringLiteral("puzzle-border"),
        QStringLiteral("puzzle-preview"), QStringLiteral("puzzle-preview-size"), QStringLiteral("puzzle-shape-size"),
        QStringLiteral("puzzle-auto-shuffle"), QStringLiteral("puzzle-auto-solve"),
        QStringLiteral("erase-mask"), QStringLiteral("erase-x"), QStringLiteral("erase-y"),
        QStringLiteral("blur-factor"), QStringLiteral("gaussianblur-sigma"),
        QStringLiteral("antiflicker-window-size"), QStringLiteral("antiflicker-softening-size"),
        QStringLiteral("hqdn3d-luma-spat"), QStringLiteral("hqdn3d-chroma-spat"),
        QStringLiteral("hqdn3d-luma-temp"), QStringLiteral("hqdn3d-chroma-temp"), QStringLiteral("anaglyph-scheme")
    };
    return names;
}

const QStringList& audioFilterFloatOptions()
{
    static const QStringList names{
        QStringLiteral("spatializer-roomsize"), QStringLiteral("spatializer-width"),
        QStringLiteral("spatializer-wet"), QStringLiteral("spatializer-dry"), QStringLiteral("spatializer-damp"),
        QStringLiteral("pitch-shift")
    };
    return names;
}

const QStringList& overlayOptions()
{
    static const QStringList names{
        QStringLiteral("marq-marquee"), QStringLiteral("marq-file"),
        QStringLiteral("marq-x"), QStringLiteral("marq-y"), QStringLiteral("marq-position"),
        QStringLiteral("marq-color"), QStringLiteral("marq-size"), QStringLiteral("marq-opacity"),
        QStringLiteral("marq-timeout"), QStringLiteral("marq-refresh"),
        QStringLiteral("logo-file"), QStringLiteral("logo-x"), QStringLiteral("logo-y"),
        QStringLiteral("logo-position"), QStringLiteral("logo-opacity"),
        QStringLiteral("logo-delay"), QStringLiteral("logo-repeat")
    };
    return names;
}

const QStringList& presetOptions()
{
    // Only media presentation belongs in a show preset. Overlay images and
    // text files are presentation assets. Do not capture device selections,
    // credentials, general file paths or other machine preferences.
    static const QStringList names = [] {
        QStringList names{
            QStringLiteral("qt-subtitle-timeline"),
            QStringLiteral("audio-track"), QStringLiteral("audio-track-id"), QStringLiteral("audio-language"),
            QStringLiteral("sub-track"), QStringLiteral("sub-track-id"), QStringLiteral("sub-language"),
            QStringLiteral("audio-desync"), QStringLiteral("sub-delay"), QStringLiteral("sub-delay-ms"), QStringLiteral("sub-fps"),
            QStringLiteral("stereo-mode"), QStringLiteral("mix-mode"), QStringLiteral("audio-spatial"), QStringLiteral("audio-spatial-mode"),
            QStringLiteral("audio-filter"), QStringLiteral("equalizer-preset"), QStringLiteral("equalizer-bands"),
            QStringLiteral("equalizer-preamp"), QStringLiteral("equalizer-2pass"), QStringLiteral("norm-max-level"),
            QStringLiteral("compressor-rms-peak"), QStringLiteral("compressor-attack"), QStringLiteral("compressor-release"),
            QStringLiteral("compressor-threshold"), QStringLiteral("compressor-ratio"), QStringLiteral("compressor-knee"), QStringLiteral("compressor-makeup-gain"),
            QStringLiteral("video-filter"), QStringLiteral("hue"), QStringLiteral("brightness"), QStringLiteral("contrast"),
            QStringLiteral("saturation"), QStringLiteral("gamma"), QStringLiteral("transform-type"), QStringLiteral("rotate-angle"), QStringLiteral("qt-video-transform-state"),
            QStringLiteral("fit"), QStringLiteral("autoscale"), QStringLiteral("zoom"), QStringLiteral("aspect-ratio"), QStringLiteral("crop"), QStringLiteral("deinterlace"), QStringLiteral("deinterlace-mode"),
            QStringLiteral("subsdec-formatted"), QStringLiteral("sub-margin"), QStringLiteral("sub-text-scale"),
            QStringLiteral("sub-text-use-embedded-style"), QStringLiteral("sub-text-size-mode"), QStringLiteral("sub-text-size-pixels"),
            QStringLiteral("subsdelay-factor"), QStringLiteral("subsdelay-mode"), QStringLiteral("sub-filter"),
            QStringLiteral("freetype-font"), QStringLiteral("freetype-fontsize"), QStringLiteral("freetype-rel-fontsize"),
            QStringLiteral("freetype-color"), QStringLiteral("freetype-opacity"), QStringLiteral("freetype-bold"),
            QStringLiteral("freetype-outline-thickness"), QStringLiteral("freetype-outline-color"), QStringLiteral("freetype-outline-opacity"),
            QStringLiteral("freetype-shadow-angle"), QStringLiteral("freetype-shadow-distance"), QStringLiteral("freetype-shadow-color"),
            QStringLiteral("freetype-shadow-opacity"), QStringLiteral("freetype-background-color"), QStringLiteral("freetype-background-opacity")
        };
        names += videoFilterOptions();
        names += overlayOptions();
        names += audioFilterFloatOptions();
        names.append(QStringLiteral("sub-source"));
        names += {QStringLiteral("preferred-resolution"), QStringLiteral("d3d11-hdr-mode")};
        return names;
    }();
    return names;
}

bool subtitleStyleOption(const QString& name)
{
    return name.startsWith(QLatin1String("freetype-")) || name.startsWith(QLatin1String("sub-text-"));
}

const QStringList& videoOutputOptions()
{
    // Output variables own the current presentation. Hotkeys and the native
    // choice models can change these without changing saved preferences.
    // Apply fit before autoscale: disabling automatic scaling must win over
    // a retained fit mode. Set the chain last so new filters inherit values.
    static const QStringList names = [] {
        QStringList names{
            QStringLiteral("fit"), QStringLiteral("autoscale"), QStringLiteral("zoom"), QStringLiteral("aspect-ratio"), QStringLiteral("crop"),
            QStringLiteral("deinterlace-mode"), QStringLiteral("deinterlace"),
            QStringLiteral("hue"), QStringLiteral("brightness"), QStringLiteral("contrast"),
            QStringLiteral("saturation"), QStringLiteral("gamma"),
            QStringLiteral("transform-type"), QStringLiteral("rotate-angle")
        };
        names += videoFilterOptions();
        names += overlayOptions();
        names.append(QStringLiteral("video-filter"));
        names.append(QStringLiteral("sub-source"));
        return names;
    }();
    return names;
}

QVariant outputValue(vout_thread_t* output, const QString& name)
{
    const auto bytes = name.toUtf8();
    switch (var_Type(output, bytes.constData()) & VLC_VAR_CLASS) {
    case VLC_VAR_BOOL: return var_GetBool(output, bytes.constData());
    case VLC_VAR_INTEGER: return QVariant::fromValue<qlonglong>(var_GetInteger(output, bytes.constData()));
    case VLC_VAR_FLOAT: return var_GetFloat(output, bytes.constData());
    case VLC_VAR_STRING: {
        char* text = var_GetString(output, bytes.constData());
        const auto result = qfu(text ? text : "");
        free(text);
        return result;
    }
    default: return {};
    }
}

bool validPresetName(const QString& name, const QVariantList& presets, const QString& except = {})
{
    if (name.isEmpty() || name.size() > 80 || name.compare(qtr("Default Preset"), Qt::CaseInsensitive) == 0
        || name.contains(QRegularExpression(QStringLiteral("[\\x00-\\x1f]")))) return false;
    return std::none_of(presets.cbegin(), presets.cend(), [&](const QVariant& row) {
        const auto preset = row.toMap();
        return preset.value(QStringLiteral("id")).toString() != except
            && preset.value(QStringLiteral("name")).toString().compare(name, Qt::CaseInsensitive) == 0;
    });
}

QString trackOption(const QString& name)
{
    if (name == QLatin1String("redesign-audio-track")) return QStringLiteral("audio-track");
    if (name == QLatin1String("redesign-sub-track")) return QStringLiteral("sub-track");
    return {};
}

QString languageOption(const QString& name)
{
    if (name == QLatin1String("redesign-audio-language")) return QStringLiteral("audio-language");
    if (name == QLatin1String("redesign-sub-language")) return QStringLiteral("sub-language");
    return {};
}

QString languageNames(const QString& codes)
{
    if (codes.isEmpty()) return qtr("Automatic");
    QStringList names;
    for (const auto& code : codes.split(QLatin1Char(','))) {
        const auto bytes = code.trimmed().toUtf8();
        const auto* language = vlc_find_iso639(bytes.constData(), true);
        // Keep unrecognized codes and native fallback tokens editable.
        names.append(code == QLatin1String("system") ? qtr("System language")
            : language ? qtr(language->psz_eng_name) : code.trimmed());
    }
    return names.join(QStringLiteral(", "));
}

const iso639_lang_t* languageFromText(const QString& text)
{
    const auto bytes=text.toUtf8();
    if (const auto* language=vlc_find_iso639(bytes.constData(),true)) return language;
    size_t count;const auto* languages=vlc_iso639_languages(&count);
    for (size_t i=0;i<count;++i)
        if (text.compare(qtr(languages[i].psz_eng_name),Qt::CaseInsensitive)==0) return &languages[i];
    return nullptr;
}

QString languageCodes(const QString& input)
{
    QStringList result;
    for (const auto& token : input.split(QLatin1Char(','), Qt::SkipEmptyParts)) {
        const auto bytes = token.trimmed().toUtf8();
        const auto* language = vlc_find_iso639(bytes.constData(), true);
        result.append(language ? qfu(*language->psz_iso639_1 ? language->psz_iso639_1 : language->psz_iso639_2T) : token.trimmed());
    }
    return result.join(QLatin1Char(','));
}

QVariantList languageChoices(const QString& current)
{
    static const QVariantList languages = [] {
        QVariantList result;size_t count;
        const auto* records = vlc_iso639_languages(&count);
        for (size_t i = 0; i < count; ++i) {
            const auto& record = records[i];
            const auto code = qfu(*record.psz_iso639_1 ? record.psz_iso639_1 : record.psz_iso639_2T);
            result.append(QVariantMap{{"label", qtr(record.psz_eng_name)}, {"value", code}});
        }
        QCollator collator;collator.setCaseSensitivity(Qt::CaseInsensitive);
        std::sort(result.begin(),result.end(),[&](const auto& a,const auto& b) {
            return collator.compare(a.toMap().value("label").toString(),b.toMap().value("label").toString()) < 0;
        });
        return result;
    }();
    QVariantList result{QVariantMap{{"label",qtr("System language")},{"value",QStringLiteral("system")}},
        QVariantMap{{"label",qtr("Automatic")},{"value",QString()}}};
    result.append(languages);
    if (!current.isEmpty() && current != QLatin1String("system")
        && std::none_of(languages.cbegin(),languages.cend(),[&](const auto& row){return row.toMap().value("value").toString()==current;}))
        result.append(QVariantMap{{"label",languageNames(current)},{"value",current}});
    result.append(QVariantMap{{"label",qtr("Custom…")},{"value",QStringLiteral("__custom__")}});
    return result;
}

bool supportsWebRemote()
{
    // Lua's HTTP interface is a submodule: its shortcut need not be the
    // primary module name used by module_exists().
    static const bool available = [] {
        module_t** modules = nullptr;
        const ssize_t count = vlc_module_match("interface", "luahttp", true, &modules, nullptr);
        free(modules);
        return count > 0;
    }();
    return available;
}

QString categoryFor(const QString& name, int subcat)
{
    if (name.startsWith(QLatin1String("key-")) || name.startsWith(QLatin1String("global-key-"))
        || name.startsWith(QLatin1String("hotkeys-")) || name.startsWith(QLatin1String("mouse-"))
        || name.endsWith(QLatin1String("-jump-size"))) return QStringLiteral("controls");
    if (name.startsWith(QLatin1String("sub-")) || name.startsWith(QLatin1String("subsdec-"))
        || name.startsWith(QLatin1String("freetype-")) || name == QLatin1String("spu")) return QStringLiteral("subtitles");
    if (name.startsWith(QLatin1String("record")) || subcat / 100 == 5) return QStringLiteral("recording");
    if (name.contains(QLatin1String("caching")) || name.startsWith(QLatin1String("avcodec-"))
        || subcat == SUBCAT_INPUT_VCODEC || subcat == SUBCAT_INPUT_ACODEC) return QStringLiteral("performance");
    if (subcat == SUBCAT_ADVANCED_NETWORK || subcat == SUBCAT_INPUT_ACCESS
        || name.startsWith(QLatin1String("http-"))) return QStringLiteral("network");
    if (name.startsWith(QLatin1String("metadata-")) || name.contains(QLatin1String("scrobbler"))) return QStringLiteral("privacy");
    if (name.startsWith(QLatin1String("qt-"))) return QStringLiteral("interface");
    switch (subcat / 100) {
    case 2: return QStringLiteral("audio");
    case 3: return subcat == SUBCAT_VIDEO_SUBPIC ? QStringLiteral("subtitles") : QStringLiteral("video");
    case 4: return QStringLiteral("playback");
    case 7: return QStringLiteral("library");
    default: return QStringLiteral("general");
    }
}
}

RedesignPreferences::RedesignPreferences(QObject* parent) : QObject(parent)
{
    m_saveTimer.setSingleShot(true);
    m_saveTimer.setInterval(300);
    connect(&m_saveTimer, &QTimer::timeout, this, [this]() { if (m_autoSave && dirty()) save(); });
    m_stereoTestTimer.setInterval(50);
    connect(&m_stereoTestTimer, &QTimer::timeout, this, &RedesignPreferences::updateStereoTest);
    size_t count = 0;
    module_t** modules = module_list_get(&count);
    for (size_t i = 0; i < count; ++i) {
        unsigned size = 0;
        module_config_t* configs = module_config_get(modules[i], &size);
        int subcat = SUBCAT_UNKNOWN;
        for (unsigned j = 0; j < size; ++j) {
            const module_config_t& cfg = configs[j];
            if (cfg.i_type == CONFIG_SUBCATEGORY) { subcat = cfg.value.i; continue; }
            if (!CONFIG_ITEM(cfg.i_type) || !cfg.psz_name || !cfg.psz_text
                || subcat == SUBCAT_HIDDEN || subcat == SUBCAT_UNKNOWN) continue;
            const QString name = qfu(cfg.psz_name);
            m_catalog.append({name, categoryFor(name, subcat), qtr(cfg.psz_text)});
        }
        module_config_free(configs);
    }
    module_list_free(modules);
    std::sort(m_catalog.begin(), m_catalog.end(), [](const Entry& a, const Entry& b) {
        return QString::localeAwareCompare(a.title, b.title) < 0;
    });
}

RedesignPreferences::~RedesignPreferences()
{
    m_stereoTestTimer.stop();
    m_stereoTest.reset();
}

bool RedesignPreferences::startStereoTest()
{
    stopStereoTest();
    if (!m_ctx || !value(QStringLiteral("audio")).toBool()) {
        finishStereoTest(qtr("Enable audio to run this test."));
        return false;
    }
    auto *output = vlc_player_aout_Hold(m_ctx->getIntf()->p_player);
    if (!output) {
        finishStereoTest(qtr("VLC cannot start the audio test."));
        return false;
    }
    const bool muted = aout_MuteGet(output) > 0;
    const bool silent = aout_VolumeGet(output) == 0;
    if (muted || silent) {
        aout_Release(output);
        finishStereoTest(muted ? qtr("Unmute audio to run this test.")
                              : qtr("Increase the volume to run this test."));
        return false;
    }
    const int mode = isStaged(QStringLiteral("stereo-mode"))
        ? value(QStringLiteral("stereo-mode")).toInt() : var_GetInteger(output, "stereo-mode");
    auto test = std::make_unique<StereoTestPlayer>();
    const bool started = test->start(VLC_OBJECT(m_ctx->getIntf()), output, mode);
    aout_Release(output);
    if (!started) {
        test.reset();
        finishStereoTest(qtr("VLC cannot start the audio test."));
        return false;
    }
    m_stereoTest = std::move(test);
    m_stereoTestMessage = qtr("Starting test");
    m_stereoTestElapsed.start();
    m_stereoTestTimer.start();
    emit stereoTestChanged();
    return true;
}

void RedesignPreferences::finishStereoTest(const QString& message)
{
    m_stereoTestTimer.stop();
    m_stereoTest.reset();
    m_stereoTestMessage = message;
    emit stereoTestChanged();
}

void RedesignPreferences::stopStereoTest()
{
    if (m_stereoTest || !m_stereoTestMessage.isEmpty()) finishStereoTest();
}

void RedesignPreferences::updateStereoTest()
{
    if (!m_stereoTest) return;
    const auto state = m_stereoTest->state();
    if (state == StereoTestPlayer::State::Failed || m_stereoTestElapsed.elapsed() > 8000) {
        finishStereoTest(qtr("VLC cannot start the audio test."));
        return;
    }
    if (state == StereoTestPlayer::State::Complete) { finishStereoTest(); return; }
    const auto message = state == StereoTestPlayer::State::Left ? qtr("Left channel")
        : state == StereoTestPlayer::State::Right ? qtr("Right channel")
        : state == StereoTestPlayer::State::Starting ? qtr("Starting test") : QString();
    if (message != m_stereoTestMessage) {
        m_stereoTestMessage = message;
        emit stereoTestChanged();
    }
}

void RedesignPreferences::setAutoSave(bool enabled)
{
    if (m_autoSave == enabled) return;
    m_autoSave = enabled;
    if (!enabled) m_saveTimer.stop();
    else if (dirty()) m_saveTimer.start();
    emit autoSaveChanged();
}

void RedesignPreferences::setCtx(MainCtx* ctx)
{
    if (m_ctx == ctx) return;
    stopStereoTest();
    if (m_ctx) disconnect(m_ctx, &MainCtx::redesignPlayerPreferencesChanged, this, &RedesignPreferences::refresh);
    if (m_ctx) disconnect(m_ctx, &MainCtx::backdropBlurEnabledChanged, this, &RedesignPreferences::refresh);
    m_ctx = ctx;
    if (m_ctx) connect(m_ctx, &MainCtx::redesignPlayerPreferencesChanged, this, &RedesignPreferences::refresh);
    if (m_ctx) connect(m_ctx, &MainCtx::backdropBlurEnabledChanged, this, &RedesignPreferences::refresh);
    emit ctxChanged();
    refresh();
}

QVariant RedesignPreferences::read(const QByteArray& name)
{
    const auto* cfg = config_FindConfig(name.constData());
    if (!cfg) return {};
    switch (CONFIG_CLASS(cfg->i_type)) {
    case CONFIG_ITEM_BOOL: return bool(config_GetInt(name.constData()));
    case CONFIG_ITEM_INTEGER: return QVariant::fromValue<qlonglong>(config_GetInt(name.constData()));
    case CONFIG_ITEM_FLOAT: return config_GetFloat(name.constData());
    case CONFIG_ITEM_STRING: {
        char* text = config_GetPsz(name.constData());
        const QString result = qfu(text ? text : "");
        free(text);
        return result;
    }
    default: return {};
    }
}

void RedesignPreferences::write(const QByteArray& name, const QVariant& value)
{
    const auto* cfg = config_FindConfig(name.constData());
    if (!cfg) return;
    switch (CONFIG_CLASS(cfg->i_type)) {
    case CONFIG_ITEM_BOOL:
    case CONFIG_ITEM_INTEGER: config_PutInt(name.constData(), value.toLongLong()); break;
    case CONFIG_ITEM_FLOAT: config_PutFloat(name.constData(), value.toFloat()); break;
    case CONFIG_ITEM_STRING: config_PutPsz(name.constData(), value.toString().toUtf8().constData()); break;
    }
}

QString RedesignPreferences::audioOutputModule() const
{
    if (!m_ctx) return {};
    audio_output_t* output = vlc_player_aout_Hold(m_ctx->getIntf()->p_player);
    if (!output) return {};
    char* name = vlc_object_get_name(VLC_OBJECT(output));
    const QString result = qfu(name ? name : "");
    free(name); aout_Release(output);
    return result;
}

QVariantList RedesignPreferences::audioDeviceChoices() const
{
    QVariantList choices{QVariantMap{{QStringLiteral("label"), qtr("System default")}, {QStringLiteral("value"), QString()}}};
    if (!m_ctx) return choices;
    audio_output_t* output = vlc_player_aout_Hold(m_ctx->getIntf()->p_player);
    if (!output) return choices;
    char **ids = nullptr, **names = nullptr;
    const int count = aout_DevicesList(output, &ids, &names);
    for (int i = 0; i < count; ++i) {
        if (ids[i] && *ids[i]) choices.append(QVariantMap{{QStringLiteral("label"), qfu(names[i])}, {QStringLiteral("value"), qfu(ids[i])}});
        free(ids[i]); free(names[i]);
    }
    free(ids); free(names); aout_Release(output);
    return choices;
}

void RedesignPreferences::refresh()
{
    ++m_revision; emit changed();
}

QStringList RedesignPreferences::subtitleSearchLanguages() const
{
    QStringList result;
    for (const auto& token : value(QStringLiteral("sub-language")).toString().split(QLatin1Char(','))) {
        const auto code = token.trimmed().toLower().toUtf8();
        if (code.isEmpty()) continue;
        if (code == "any" || code == "none") break;
        const auto* language = code == "system" ? vlc_get_system_language()
            : vlc_find_iso639(code.constData(), true);
        if (!language) continue;
        const auto searchCode = qfu(*language->psz_iso639_1 ? language->psz_iso639_1 : language->psz_iso639_2T);
        if (!result.contains(searchCode)) result.append(searchCode);
    }
    return result;
}

QVariantMap RedesignPreferences::playerPresetOptions() const
{
    QVariantMap options;
    for (const auto& name : presetOptions()) {
        if (name.startsWith(QLatin1String("audio-spatial")) && !module_exists("spatialaudio")) continue;
        const auto current = value(name);
        if (current.isValid()) options.insert(name, current);
    }
    if (m_ctx) {
        auto* player = m_ctx->getIntf()->p_player;
        vlc_player_Lock(player);
        const bool hasVideo = vlc_player_IsStarted(player) && vlc_player_GetSelectedTrack(player, VIDEO_ES);
        if (vlc_player_IsStarted(player)) {
            // Shortcuts can change timing without writing the defaults. Capture
            // the values the viewer is using, while preserving staged edits.
            if (!isStaged(QStringLiteral("audio-desync")))
                options.insert(QStringLiteral("audio-desync"), QVariant::fromValue<qlonglong>(MS_FROM_VLC_TICK(vlc_player_GetAudioDelay(player))));
            if (!isStaged(QStringLiteral("redesign-subtitle-delay"))) {
                options.insert(QStringLiteral("sub-delay"), 0);
                options.insert(QStringLiteral("sub-delay-ms"), QVariant::fromValue<qlonglong>(MS_FROM_VLC_TICK(vlc_player_GetSubtitleDelay(player))));
            }
            if (!isStaged(QStringLiteral("sub-fps")))
                options.insert(QStringLiteral("sub-fps"), vlc_player_GetAssociatedSubsFPS(player));
            if (!isStaged(QStringLiteral("sub-text-scale")))
                options.insert(QStringLiteral("sub-text-scale"), vlc_player_GetSubtitleTextScale(player));
            if (!isStaged(QStringLiteral("sub-text-size-mode")))
                options.insert(QStringLiteral("sub-text-size-mode"), int(vlc_player_GetSubtitleTextSizeMode(player)));
            if (!isStaged(QStringLiteral("sub-text-size-pixels")))
                options.insert(QStringLiteral("sub-text-size-pixels"), vlc_player_GetSubtitleTextPixelSize(player));
        }
        vlc_player_Unlock(player);
        // Hold() can return the placeholder output when no video is selected.
        // Its cached defaults must not replace the current saved preferences.
        auto* output = hasVideo ? vlc_player_vout_Hold(player) : nullptr;
        if (output) {
            for (const auto& name : videoOutputOptions()) {
                const auto current = outputValue(output, name);
                if (!isStaged(name) && current.isValid()) options.insert(name, current);
            }
            vout_Release(output);
        }
    }
    return options;
}

QVariantMap RedesignPreferences::playerPresetState() const
{
    const auto text = value(presetOption).toString().toUtf8();
    if (text.isEmpty()) return {{QStringLiteral("version"), 1}, {QStringLiteral("selected"), QString()},
        {QStringLiteral("default"), playerPresetOptions()}, {QStringLiteral("presets"), QVariantList()}};
    if (text.size() > 1024 * 1024) return {};
    const auto document = QJsonDocument::fromJson(text);
    if (!document.isObject()) return {};
    auto state = document.object().toVariantMap();
    if (state.value(QStringLiteral("version")).toInt() != 1
        || state.value(QStringLiteral("default")).metaType().id() != QMetaType::QVariantMap
        || state.value(QStringLiteral("presets")).metaType().id() != QMetaType::QVariantList) return {};
    const auto validOptions = [](const QVariant& value) {
        if (value.metaType().id() != QMetaType::QVariantMap) return false;
        const auto options = value.toMap();
        for (auto it = options.cbegin(); it != options.cend(); ++it) {
            if (!presetOptions().contains(it.key()) || it.value().isNull()
                || it.value().metaType().id() == QMetaType::QVariantMap || it.value().metaType().id() == QMetaType::QVariantList) return false;
        }
        return true;
    };
    if (!validOptions(state.value(QStringLiteral("default")))) return {};
    auto presets = state.value(QStringLiteral("presets")).toList();
    if (presets.size() > 128) return {};
    QSet<QString> ids;
    for (const auto& row : presets) {
        const auto preset = row.toMap();
        const auto id = preset.value(QStringLiteral("id")).toString();
        const auto name = preset.value(QStringLiteral("name")).toString();
        if (id.isEmpty() || ids.contains(id) || !validPresetName(name, presets, id)
            || !validOptions(preset.value(QStringLiteral("options")))) return {};
        ids.insert(id);
    }
    const auto selected = state.value(QStringLiteral("selected")).toString();
    if (!selected.isEmpty() && !ids.contains(selected)) return {};
    // Older presets stored fit=None for pixel zoom but omitted autoscale.
    // Normalize each snapshot before merging a named preset with defaults.
    const auto withScaling = [](QVariantMap options) {
        if (!options.contains(QStringLiteral("autoscale")) && options.contains(QStringLiteral("fit")))
            options.insert(QStringLiteral("autoscale"), options.value(QStringLiteral("fit")).toInt() != VLC_VIDEO_FIT_NONE);
        return options;
    };
    state.insert(QStringLiteral("default"), withScaling(state.value(QStringLiteral("default")).toMap()));
    for (auto& row : presets) {
        auto preset = row.toMap();
        preset.insert(QStringLiteral("options"), withScaling(preset.value(QStringLiteral("options")).toMap()));
        row = preset;
    }
    state.insert(QStringLiteral("presets"), presets);
    return state;
}

QVariantList RedesignPreferences::playerPresets() const
{
    QVariantList result;
    for (const auto& row : playerPresetState().value(QStringLiteral("presets")).toList()) {
        const auto preset = row.toMap();
        result.append(QVariantMap{{QStringLiteral("id"), preset.value(QStringLiteral("id"))},
            {QStringLiteral("name"), preset.value(QStringLiteral("name"))}});
    }
    return result;
}

QString RedesignPreferences::selectedPlayerPreset() const
{
    return playerPresetState().value(QStringLiteral("selected")).toString();
}

bool RedesignPreferences::playerPresetError(const QString& message)
{
    m_error = message; ++m_revision; emit changed(); return false;
}

bool RedesignPreferences::storePlayerPresetState(const QVariantMap& state)
{
    if (!m_presetTransaction) {
        m_editsBeforePreset = m_edits;
        m_presetTransaction = true;
    }
    m_edits.insert(presetOption, QString::fromUtf8(QJsonDocument::fromVariant(state).toJson(QJsonDocument::Compact)));
    ++m_revision; emit changed();
    return save();
}

void RedesignPreferences::cancelPlayerPreset()
{
    if (!m_presetTransaction) return;
    m_saveTimer.stop();
    m_edits = std::move(m_editsBeforePreset);
    m_presetTransaction = false;
    if (m_invalid.isEmpty()) m_error.clear();
    ++m_revision; emit changed();
    if (m_autoSave && dirty()) m_saveTimer.start();
}

bool RedesignPreferences::createPlayerPreset(const QString& proposed)
{
    auto state = playerPresetState();
    if (state.isEmpty()) return playerPresetError(qtr("VLC cannot read the saved presets."));
    auto presets = state.value(QStringLiteral("presets")).toList();
    const auto name = proposed.trimmed();
    if (!validPresetName(name, presets)) return playerPresetError(qtr("Enter a unique preset name with 1 to 80 characters."));
    if (presets.size() >= 128) return playerPresetError(qtr("Delete a preset before you add another preset."));
    const auto id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    presets.append(QVariantMap{{QStringLiteral("id"), id}, {QStringLiteral("name"), name}, {QStringLiteral("options"), playerPresetOptions()}});
    state.insert(QStringLiteral("presets"), presets);
    state.insert(QStringLiteral("selected"), id);
    return storePlayerPresetState(state);
}

bool RedesignPreferences::selectPlayerPreset(const QString& id)
{
    // Finish any edits to the active preset before switching to another one.
    if (dirty() && !save()) return false;
    auto state = playerPresetState();
    if (state.isEmpty()) return playerPresetError(qtr("VLC cannot read the saved presets."));
    QVariantMap options = state.value(QStringLiteral("default")).toMap();
    if (!id.isEmpty()) {
        const auto presets = state.value(QStringLiteral("presets")).toList();
        const auto it = std::find_if(presets.cbegin(), presets.cend(), [&](const QVariant& row) { return row.toMap().value(QStringLiteral("id")).toString() == id; });
        if (it == presets.cend()) return playerPresetError(qtr("This preset is no longer available."));
        const auto saved = it->toMap().value(QStringLiteral("options")).toMap();
        for (auto it = saved.cbegin(); it != saved.cend(); ++it) options.insert(it.key(), it.value());
        // A default hint cannot describe an older preset's native transform.
        if (!saved.contains(QStringLiteral("qt-video-transform-state")))
            options.insert(QStringLiteral("qt-video-transform-state"), QString());
    }
    if (!stagePlayerPresetOptions(options)) return false;
    state.insert(QStringLiteral("selected"), id);
    return storePlayerPresetState(state);
}

bool RedesignPreferences::stagePlayerPresetOptions(const QVariantMap& options)
{
    // Validate before changing the transaction. A preset from another build can
    // contain options for modules that are not installed here; retain those in
    // the manifest and apply the options that this build supports.
    const auto edits = m_edits;
    const auto invalid = m_invalid;
    // Older presets have native transforms but no logical Rotate/Flip hint.
    // Do not let the previous preset's ambiguous pair label their output.
    if (!options.contains(QStringLiteral("qt-video-transform-state")))
        stage(QStringLiteral("qt-video-transform-state"), QString());
    for (auto it = options.cbegin(); it != options.cend(); ++it) {
        if (it.key().startsWith(QLatin1String("audio-spatial")) && !module_exists("spatialaudio")) continue;
        if (!config_FindConfig(it.key().toUtf8().constData())) continue;
        if (!stage(it.key(), it.value())) {
            m_edits = edits; m_invalid = invalid; m_saveTimer.stop();
            return playerPresetError(qtr("VLC cannot apply this preset. Check its saved settings."));
        }
    }
    // Some editors stage dependent settings (for example, an equalizer curve).
    // Restore the validated snapshot exactly after those editor side effects.
    for (auto it = options.cbegin(); it != options.cend(); ++it) {
        if (it.key().startsWith(QLatin1String("audio-spatial")) && !module_exists("spatialaudio")) continue;
        if (!config_FindConfig(it.key().toUtf8().constData())) continue;
        // Reapply even an unchanged default: a shortcut may have changed the
        // live output since this configuration was saved.
        m_edits.insert(it.key(), it.value());
    }
    if (!m_presetTransaction) {
        m_editsBeforePreset = edits;
        m_presetTransaction = true;
    }
    return true;
}

bool RedesignPreferences::renamePlayerPreset(const QString& id, const QString& proposed)
{
    auto state = playerPresetState();
    if (state.isEmpty()) return playerPresetError(qtr("VLC cannot read the saved presets."));
    auto presets = state.value(QStringLiteral("presets")).toList();
    const auto name = proposed.trimmed();
    if (!validPresetName(name, presets, id)) return playerPresetError(qtr("Enter a unique preset name with 1 to 80 characters."));
    for (auto& row : presets) {
        auto preset = row.toMap();
        if (preset.value(QStringLiteral("id")).toString() != id) continue;
        preset.insert(QStringLiteral("name"), name); row = preset;
        state.insert(QStringLiteral("presets"), presets);
        return storePlayerPresetState(state);
    }
    return playerPresetError(qtr("This preset is no longer available."));
}

bool RedesignPreferences::duplicatePlayerPreset(const QString& id, const QString& proposed)
{
    auto state = playerPresetState();
    if (state.isEmpty()) return playerPresetError(qtr("VLC cannot read the saved presets."));
    auto presets = state.value(QStringLiteral("presets")).toList();
    const auto name = proposed.trimmed();
    if (!validPresetName(name, presets)) return playerPresetError(qtr("Enter a unique preset name with 1 to 80 characters."));
    if (presets.size() >= 128) return playerPresetError(qtr("Delete a preset before you add another preset."));
    for (const auto& row : std::as_const(presets)) {
        auto preset = row.toMap();
        if (preset.value(QStringLiteral("id")).toString() != id) continue;
        preset.insert(QStringLiteral("id"), QUuid::createUuid().toString(QUuid::WithoutBraces));
        preset.insert(QStringLiteral("name"), name);
        presets.append(preset);
        state.insert(QStringLiteral("presets"), presets);
        return storePlayerPresetState(state);
    }
    return playerPresetError(qtr("This preset is no longer available."));
}

bool RedesignPreferences::deletePlayerPreset(const QString& id)
{
    auto state = playerPresetState();
    if (state.isEmpty()) return playerPresetError(qtr("VLC cannot read the saved presets."));
    auto presets = state.value(QStringLiteral("presets")).toList();
    const auto it = std::find_if(presets.begin(), presets.end(), [&](const QVariant& row) { return row.toMap().value(QStringLiteral("id")).toString() == id; });
    if (it == presets.end()) return playerPresetError(qtr("This preset is no longer available."));
    presets.erase(it);
    // Deleting the active preset restores the user's default presentation in
    // the same transaction. Deleting another preset does not affect playback.
    if (state.value(QStringLiteral("selected")).toString() == id) {
        if (!stagePlayerPresetOptions(state.value(QStringLiteral("default")).toMap())) return false;
        state.insert(QStringLiteral("selected"), QString());
    }
    state.insert(QStringLiteral("presets"), presets);
    return storePlayerPresetState(state);
}

QVariant RedesignPreferences::value(const QString& name) const
{
    if (name == QLatin1String("redesign-audio-passthrough")) {
        const auto option = audioPassthroughOption(audioOutputModule());
        if (option.isEmpty()) return {};
        const auto native = value(option);
        return option == QLatin1String("mmdevice-passthrough") ? QVariant(native.toInt() != 0) : native;
    }
    if (name == QLatin1String("redesign-resampling-quality")) {
        const auto* quality = resamplingQuality(value(QStringLiteral("audio-resampler")).toString());
        if (!quality) return QStringLiteral("custom");
        const int current = value(qfu(quality->option)).toInt();
        return current == quality->low ? QStringLiteral("low")
            : current == quality->balanced ? QStringLiteral("balanced")
            : current == quality->high ? QStringLiteral("high") : QStringLiteral("custom");
    }
    if (name == QLatin1String("redesign-subtitle-relative-size"))
        return value(QStringLiteral("sub-text-scale"));
    if (name == QLatin1String("redesign-subtitle-duration"))
        return value(QStringLiteral("filter:sub-filter:subsdelay")).toBool() ? value(QStringLiteral("subsdelay-factor")) : QVariant(0.0);
    if (name == QLatin1String("redesign-subtitle-delay"))
        return value(QStringLiteral("sub-delay")).toLongLong() * 100 + value(QStringLiteral("sub-delay-ms")).toLongLong();
    if (name == QLatin1String("redesign-equalizer-preset")) {
        if (!value(QStringLiteral("filter:audio-filter:equalizer")).toBool()) return QString();
        const auto preset = value(QStringLiteral("equalizer-preset")).toString();
        return preset.isEmpty() ? QStringLiteral("custom") : preset;
    }
    if (const auto option = trackOption(name); !option.isEmpty())
        return value(option).toLongLong() + 1;
    if (const auto option = languageOption(name); !option.isEmpty())
        return languageCodes(value(option).toString());
    if (name == QLatin1String("redesign-audio-device")) {
        const QString module = audioOutputModule();
        const QString configured = value(QStringLiteral("audio-device-default")).toString();
        const QString driver = value(QStringLiteral("audio-device-default-module")).toString();
        if (!configured.isEmpty() && (driver.isEmpty() || driver == module)) return configured;
        const QString legacyName = module + QStringLiteral("-audio-device");
        const auto* legacy = config_FindConfig(legacyName.toUtf8().constData());
        if (legacy && CONFIG_CLASS(legacy->i_type) == CONFIG_ITEM_STRING) {
            const QString selected = value(legacyName).toString();
            if (selected != qfu(legacy->orig.psz ? legacy->orig.psz : "")) return selected;
        }
        return QString();
    }
    if (name == QLatin1String("redesign-startup-volume")) {
        const int configured = value(QStringLiteral("audio-startup-volume")).toInt();
        if (configured >= 0) return configured;
        const QString module = audioOutputModule();
        const bool gain = module == QLatin1String("alsa") || module == QLatin1String("jack") || module == QLatin1String("kai");
        const QString legacyName = module + (gain ? QStringLiteral("-gain") : QStringLiteral("-volume"));
        if (config_FindConfig(legacyName.toUtf8().constData())) {
            double volume = value(legacyName).toDouble();
            if (gain) volume = std::cbrt(volume);
            if (module == QLatin1String("auhal")) volume /= AOUT_VOLUME_DEFAULT;
            if (std::isfinite(volume)) return std::clamp(int(std::lround(volume * 100)), 0, 300);
        }
        return 100;
    }

    if (name == QLatin1String("redesign-web-remote")) {
        const auto interfaces = value(QStringLiteral("extraintf")).toString().split(QLatin1Char(':'), Qt::SkipEmptyParts);
        return std::any_of(interfaces.cbegin(), interfaces.cend(), [](const auto& entry) {
            const auto module = entry.section(QLatin1Char('{'), 0, 0);
            return module == QLatin1String("http") || module == QLatin1String("luahttp");
        });
    }
    if (name == QLatin1String("redesign-repeat"))
        return value(QStringLiteral("repeat")).toBool() ? 1 : value(QStringLiteral("loop")).toBool() ? 2 : 0;
    if (name == QLatin1String("redesign-after-playback"))
        return value(QStringLiteral("play-and-exit")).toBool() ? 1 : value(QStringLiteral("play-and-pause")).toBool() ? 2 : 0;
    if (name.startsWith(QLatin1String("filter:"))) {
        const auto parts = name.split(QLatin1Char(':'));
        return parts.size() == 3 && value(parts[1]).toString().split(QLatin1Char(':')).contains(parts[2]);
    }

    const auto it = m_edits.constFind(name);
    if (it != m_edits.cend()) return *it;
    if (m_ctx && name == QLatin1String("qt-backdrop-blur"))
        return m_ctx->backdropBlurRequested();
    return read(name.toUtf8());
}

QVariant RedesignPreferences::videoValue(const QString& name) const
{
    if (!m_ctx || m_edits.contains(name) || (!videoOutputOptions().contains(name) && name != QLatin1String("sub-filter")))
        return value(name);
    auto* player = m_ctx->getIntf()->p_player;
    vlc_player_Lock(player);
    const bool hasVideo = vlc_player_IsStarted(player) && vlc_player_GetSelectedTrack(player, VIDEO_ES);
    auto* output = hasVideo ? vlc_player_vout_Hold(player) : nullptr;
    vlc_player_Unlock(player);
    if (!output) return value(name);
    const auto current = outputValue(output, name);
    vout_Release(output);
    return current.isValid() ? current : value(name);
}

bool RedesignPreferences::isStaged(const QString& name) const
{
    if (name == QLatin1String("redesign-audio-passthrough"))
        return m_edits.contains(audioPassthroughOption(audioOutputModule()));
    if (name == QLatin1String("redesign-resampling-quality")) {
        if (m_edits.contains(QStringLiteral("audio-resampler"))) return true;
        for (const auto& quality : resamplingQualities)
            if (m_edits.contains(qfu(quality.option))) return true;
        return false;
    }
    if (name == QLatin1String("redesign-subtitle-relative-size"))
        return m_edits.contains(QStringLiteral("sub-text-scale")) || m_edits.contains(QStringLiteral("sub-text-size-mode"));
    if (name == QLatin1String("redesign-subtitle-delay"))
        return m_edits.contains(QStringLiteral("sub-delay")) || m_edits.contains(QStringLiteral("sub-delay-ms"));
    return m_edits.contains(name);
}

QVariantMap RedesignPreferences::describe(const QString& name) const
{
    if (name == QLatin1String("redesign-audio-passthrough")) {
        const auto option = audioPassthroughOption(audioOutputModule());
        if (option.isEmpty()) return {};
        auto description = describe(option);
        if (description.isEmpty()) return {};
        description.insert(QStringLiteral("name"), name);
        description.insert(QStringLiteral("title"), qtr("Pass compressed audio to the receiver"));
        description.insert(QStringLiteral("value"), value(name));
        description.insert(QStringLiteral("help"), qtr("Send compressed audio to the receiver. The receiver must support the audio format. This setting uses the active audio output."));
        if (option == QLatin1String("mmdevice-passthrough")) {
            description.insert(QStringLiteral("kind"), QStringLiteral("bool"));
            description.insert(QStringLiteral("choices"), QVariantList());
            description.insert(QStringLiteral("defaultValue"), description.value(QStringLiteral("defaultValue")).toInt() != 0);
        }
        return description;
    }
    if (name == QLatin1String("redesign-resampling-quality")) {
        QVariantList choices{
            QVariantMap{{QStringLiteral("label"), qtr("Low")}, {QStringLiteral("value"), QStringLiteral("low")}},
            QVariantMap{{QStringLiteral("label"), qtr("Balanced")}, {QStringLiteral("value"), QStringLiteral("balanced")}},
            QVariantMap{{QStringLiteral("label"), qtr("High")}, {QStringLiteral("value"), QStringLiteral("high")}}
        };
        if (value(name) == QStringLiteral("custom"))
            choices.append(QVariantMap{{QStringLiteral("label"), qtr("Custom")}, {QStringLiteral("value"), QStringLiteral("custom")}});
        return {{QStringLiteral("kind"), QStringLiteral("string")}, {QStringLiteral("choices"), choices},
            {QStringLiteral("value"), value(name)}, {QStringLiteral("defaultValue"), QStringLiteral("balanced")},
            {QStringLiteral("supported"), resamplingQuality(value(QStringLiteral("audio-resampler")).toString()) != nullptr},
            {QStringLiteral("help"), qtr("Set the quality for audio sample rate conversion. Higher quality uses more processing power. Some resamplers do not have a quality control.")}};
    }
    if (name == QLatin1String("redesign-subtitle-relative-size")) {
        auto description = describe(QStringLiteral("sub-text-scale"));
        description.insert(QStringLiteral("value"), value(name));
        description.insert(QStringLiteral("help"), qtr("Set the relative subtitle font size. This setting uses relative values."));
        return description;
    }
    if (name == QLatin1String("redesign-subtitle-duration")) {
        if (!module_exists("subsdelay")) return {};
        auto description = describe(QStringLiteral("subsdelay-factor"));
        description.insert(QStringLiteral("value"), value(name));
        description.insert(QStringLiteral("defaultValue"), 0.0);
        description.insert(QStringLiteral("help"), qtr("Change how long subtitles stay on screen. Set 0 to use the file duration."));
        return description;
    }
    if (name == QLatin1String("redesign-subtitle-delay")) {
        auto description = describe(QStringLiteral("sub-delay-ms"));
        description.insert(QStringLiteral("value"), value(name));
        description.insert(QStringLiteral("defaultValue"), 0);
        description.insert(QStringLiteral("help"), qtr("Positive values show subtitles later. Negative values show subtitles earlier."));
        return description;
    }
    if (name == QLatin1String("redesign-equalizer-preset")) {
        auto result = describe(QStringLiteral("equalizer-preset"));
        if (result.isEmpty()) return {};
        auto choices = result.value(QStringLiteral("choices")).toList();
        if (value(QStringLiteral("equalizer-preset")).toString().isEmpty()
            && !value(QStringLiteral("equalizer-bands")).toString().isEmpty())
            choices.insert(1, QVariantMap{{QStringLiteral("label"), qtr("Custom")}, {QStringLiteral("value"), QStringLiteral("custom")}, {QStringLiteral("curve"), equalizerBands()}});
        result.insert(QStringLiteral("choices"), choices);
        result.insert(QStringLiteral("value"), value(name));
        result.insert(QStringLiteral("defaultValue"), QString());
        return result;
    }
    if (!trackOption(name).isEmpty())
        return {{QStringLiteral("kind"), QStringLiteral("integer")}, {QStringLiteral("editor"), QStringLiteral("track")},
            {QStringLiteral("minimum"), 0}, {QStringLiteral("maximum"), INT_MAX},
            {QStringLiteral("defaultValue"), 0}, {QStringLiteral("value"), value(name)},
            {QStringLiteral("help"), qtr("Choose a track for the next video. Track numbers start at 1. Automatic uses the language setting.")}};
    if (!languageOption(name).isEmpty())
        return {{QStringLiteral("kind"), QStringLiteral("string")}, {QStringLiteral("editor"), QStringLiteral("language")},
            {QStringLiteral("choices"), languageChoices(value(name).toString())},
            {QStringLiteral("defaultValue"), QStringLiteral("system")},
            {QStringLiteral("value"), value(name)},
            {QStringLiteral("help"), qtr("Choose a language. System language uses your system's language. Choose Custom to enter a language order. Separate names or codes with commas. This sets the track to Automatic for the next file.")}};
    if (name == QLatin1String("redesign-reset-all"))
        return {{QStringLiteral("kind"), QStringLiteral("action")}, {QStringLiteral("editor"), QStringLiteral("action")},
            {QStringLiteral("buttonLabel"), qtr("Reset")}, {QStringLiteral("destructive"), true},
            {QStringLiteral("help"), qtr("Replace all VLC settings with the default settings.")}};
    if (name == QLatin1String("redesign-config-folder"))
        return {{QStringLiteral("kind"), QStringLiteral("action")}, {QStringLiteral("editor"), QStringLiteral("action")},
            {QStringLiteral("buttonLabel"), qtr("Open")},
            {QStringLiteral("help"), qtr("Open the folder that contains the VLC settings.")}};
    if (name == QLatin1String("redesign-audio-device")) {
        auto choices = audioDeviceChoices();
        const QString configured = value(name).toString();
        if (!configured.isEmpty() && std::none_of(choices.cbegin(), choices.cend(), [&](const auto& choice) {
            return choice.toMap().value(QStringLiteral("value")).toString() == configured;
        })) choices.append(QVariantMap{{QStringLiteral("label"), qtr("Unavailable device (%1)").arg(configured)}, {QStringLiteral("value"), configured}});
        return {{QStringLiteral("kind"), QStringLiteral("string")}, {QStringLiteral("title"), qtr("Output device")},
            {QStringLiteral("choices"), choices}, {QStringLiteral("defaultValue"), QString()}, {QStringLiteral("value"), configured},
            {QStringLiteral("help"), qtr("Choose the device to use for audio. A disconnected device falls back to the audio driver's default.")}};
    }
    if (name == QLatin1String("redesign-startup-volume"))
        return {{QStringLiteral("kind"), QStringLiteral("integer")}, {QStringLiteral("title"), qtr("Startup volume")},
            {QStringLiteral("minimum"), 0}, {QStringLiteral("maximum"), 300}, {QStringLiteral("defaultValue"), 100},
            {QStringLiteral("value"), value(name)}};

    if (name == QLatin1String("redesign-web-remote"))
        return {{QStringLiteral("kind"), QStringLiteral("bool")}, {QStringLiteral("title"), qtr("Web remote control")},
            {QStringLiteral("defaultValue"), false}, {QStringLiteral("value"), value(name)},
            {QStringLiteral("supported"), supportsWebRemote()},
            {QStringLiteral("help"), supportsWebRemote() ? qtr("Control VLC from a web browser. Restart VLC after changing the web remote, port or password.")
                : qtr("Web remote control is unavailable in this VLC build.")}};

    if (name == QLatin1String("redesign-repeat") || name == QLatin1String("redesign-after-playback")) {
        const bool repeat = name == QLatin1String("redesign-repeat");
        const QStringList labels = repeat ? QStringList{qtr("Off"), qtr("Current item"), qtr("All items")}
            : QStringList{qtr("Stop"), qtr("Quit VLC"), qtr("Pause on the last frame")};
        QVariantList choices;
        for (int i = 0; i < labels.size(); ++i) choices.append(QVariantMap{{QStringLiteral("label"), labels[i]}, {QStringLiteral("value"), i}});
        return {{QStringLiteral("kind"), QStringLiteral("integer")}, {QStringLiteral("title"), repeat ? qtr("Repeat") : qtr("When playback finishes")},
            {QStringLiteral("choices"), choices}, {QStringLiteral("defaultValue"), 0}, {QStringLiteral("value"), value(name)}};
    }
    if (name.startsWith(QLatin1String("filter:"))) {
        const auto parts = name.split(QLatin1Char(':'));
        if (parts.size() != 3 || !module_exists(parts[2].toUtf8().constData())) return {};
        return {{QStringLiteral("kind"), QStringLiteral("bool")}, {QStringLiteral("title"), parts[2]},
            {QStringLiteral("value"), value(name)}, {QStringLiteral("defaultValue"), false},
            {QStringLiteral("help"), parts[1] == QLatin1String("audio-filter") ? audioFilterHelp(parts[2]) : QString()}};
    }

    const QByteArray bytes = name.toUtf8();
    const auto* cfg = config_FindConfig(bytes.constData());
    // Removed compatibility options have no UI text. Use the same rule as
    // the native catalog, so curated sections do not expose dead controls.
    if (!cfg || !CONFIG_ITEM(cfg->i_type) || !cfg->psz_text) return {};
    QVariantMap result{{QStringLiteral("name"), name}, {QStringLiteral("title"), qtr(cfg->psz_text ? cfg->psz_text : cfg->psz_name)},
        {QStringLiteral("help"), qtr(cfg->psz_longtext ? cfg->psz_longtext : "")}, {QStringLiteral("value"), value(name)}};
    if (name == QLatin1String("aout"))
        result.insert(QStringLiteral("help"), qtr("Select an audio output driver. Restart VLC to use a new driver."));
    if (name == QLatin1String("pitch-shift"))
        result.insert(QStringLiteral("help"), qtr("Set the pitch in semitones. Use 0 to turn off this effect. Playback speed does not change."));
    if (name == QLatin1String("audio-spatial") || name == QLatin1String("audio-spatial-mode")) {
        const bool supported = module_exists("spatialaudio");
        result.insert(QStringLiteral("supported"), supported);
        if (!supported) result.insert(QStringLiteral("help"), qtr("VLC cannot use spatial audio in this version."));
    }
    QVariantList choices;
    QString kind;
    switch (CONFIG_CLASS(cfg->i_type)) {
    case CONFIG_ITEM_BOOL:
        kind = QStringLiteral("bool"); result.insert(QStringLiteral("defaultValue"), bool(cfg->orig.i)); break;
    case CONFIG_ITEM_INTEGER: {
        kind = QStringLiteral("integer");
        result.insert(QStringLiteral("defaultValue"), QVariant::fromValue<qlonglong>(cfg->orig.i));
        result.insert(QStringLiteral("minimum"), QVariant::fromValue<qlonglong>(cfg->min.i));
        result.insert(QStringLiteral("maximum"), QVariant::fromValue<qlonglong>(cfg->max.i));
        int64_t* values = nullptr; char** labels = nullptr;
        const ssize_t count = config_GetIntChoices(bytes.constData(), &values, &labels);
        for (ssize_t i = 0; i < count; ++i) {
            choices.append(QVariantMap{{QStringLiteral("label"), qfu(labels[i])}, {QStringLiteral("value"), QVariant::fromValue<qlonglong>(values[i])}});
            free(labels[i]);
        }
        free(values); free(labels);
        break;
    }
    case CONFIG_ITEM_FLOAT:
        kind = QStringLiteral("float"); result.insert(QStringLiteral("defaultValue"), cfg->orig.f);
        result.insert(QStringLiteral("minimum"), cfg->min.f); result.insert(QStringLiteral("maximum"), cfg->max.f); break;
    case CONFIG_ITEM_STRING: {
        kind = cfg->i_type == CONFIG_ITEM_PASSWORD ? QStringLiteral("password") : QStringLiteral("string");
        result.insert(QStringLiteral("defaultValue"), qfu(cfg->orig.psz ? cfg->orig.psz : ""));
        char** values = nullptr; char** labels = nullptr;
        const ssize_t count = config_GetPszChoices(bytes.constData(), &values, &labels);
        for (ssize_t i = 0; i < count; ++i) {
            choices.append(QVariantMap{{QStringLiteral("label"), qfu(labels[i])}, {QStringLiteral("value"), qfu(values[i])}});
            free(values[i]); free(labels[i]);
        }
        free(values); free(labels);
        break;
    }
    }
    QString editor;
    switch (cfg->i_type) {
    case CONFIG_ITEM_LOADFILE: case CONFIG_ITEM_SAVEFILE: editor = QStringLiteral("file"); break;
    case CONFIG_ITEM_DIRECTORY: editor = QStringLiteral("directory"); break;
    case CONFIG_ITEM_RGB: editor = QStringLiteral("color"); break;
    }
    if (name == QLatin1String("qt-fullscreen-screennumber")) {
        choices.append(QVariantMap{{QStringLiteral("label"), qtr("Current screen")}, {QStringLiteral("value"), -1}});
        const auto screens = QGuiApplication::screens();
        for (int i = 0; i < screens.size(); ++i)
            choices.append(QVariantMap{{QStringLiteral("label"), screens[i]->name()}, {QStringLiteral("value"), i}});
    }
    if (name == QLatin1String("equalizer-preset")) {
        choices.clear();
        choices.append(QVariantMap{{QStringLiteral("label"), qtr("None")}, {QStringLiteral("value"), QString()}});
        for (int i = 0; i < NB_PRESETS; ++i) {
            QVariantList curve;
            for (int band = 0; band < eqz_preset_10b[i].i_band; ++band)
                curve.append(eqz_preset_10b[i].f_amp[band]);
            choices.append(QVariantMap{{QStringLiteral("label"), qtr(preset_list_text[i])},
                {QStringLiteral("value"), qfu(preset_list[i])}, {QStringLiteral("curve"), curve}});
        }
    }
    result.insert(QStringLiteral("editor"), editor);
    result.insert(QStringLiteral("kind"), kind);
    result.insert(QStringLiteral("choices"), choices);
    return result;
}

bool RedesignPreferences::stage(const QString& name, const QVariant& proposed)
{
    if (name == QLatin1String("redesign-audio-passthrough")) {
        const auto option = audioPassthroughOption(audioOutputModule());
        if (option.isEmpty()) return false;
        if (option == QLatin1String("mmdevice-passthrough")) {
            if (proposed.metaType().id() != QMetaType::Bool) return false;
            // Preserve an existing AC3/DTS-only policy; enable all supported
            // compressed formats when switching on from Disabled.
            const int current = value(option).toInt();
            const int enabled = current > 0 ? current : 2;
            return stage(option, proposed.toBool() ? enabled : 0);
        }
        return stage(option, proposed);
    }
    if (name == QLatin1String("redesign-resampling-quality")) {
        const auto* quality = resamplingQuality(value(QStringLiteral("audio-resampler")).toString());
        if (!quality) return false;
        const auto level = proposed.toString();
        if (level == QLatin1String("custom")) return value(name) == proposed;
        if (level != QLatin1String("low") && level != QLatin1String("balanced") && level != QLatin1String("high")) return false;
        const int setting = level == QLatin1String("low") ? quality->low
            : level == QLatin1String("high") ? quality->high : quality->balanced;
        if (!stage(qfu(quality->option), setting)) return false;
        // Select the matching converter when Automatic would otherwise fall
        // back to a resampler that has no quality control.
        return stage(QStringLiteral("audio-resampler"), qfu(quality->module));
    }
    if (name == QLatin1String("redesign-subtitle-relative-size")) {
        if (!stage(QStringLiteral("sub-text-scale"), proposed)) return false;
        return stage(QStringLiteral("sub-text-size-mode"), 0);
    }
    if (name == QLatin1String("redesign-subtitle-duration")) {
        if (!module_exists("subsdelay") || !stage(QStringLiteral("subsdelay-factor"), proposed)) return false;
        if (proposed.toDouble() > 0) stage(QStringLiteral("subsdelay-mode"), 1);
        return stage(QStringLiteral("filter:sub-filter:subsdelay"), proposed.toDouble() > 0);
    }
    if (name == QLatin1String("redesign-subtitle-delay")) {
        if (!stage(QStringLiteral("sub-delay-ms"), proposed)) return false;
        return stage(QStringLiteral("sub-delay"), 0);
    }
    if (name == QLatin1String("redesign-equalizer-preset")) {
        const auto preset = proposed.toString();
        if (preset.isEmpty()) return stage(QStringLiteral("filter:audio-filter:equalizer"), false);
        if (preset == QLatin1String("custom")) {
            if (!value(QStringLiteral("equalizer-preset")).toString().isEmpty()) return false;
        } else if (!stage(QStringLiteral("equalizer-preset"), preset)) return false;
        return stage(QStringLiteral("filter:audio-filter:equalizer"), true);
    }
    if (const auto option = trackOption(name); !option.isEmpty()) {
        bool valid = false;
        const auto number = proposed.toLongLong(&valid);
        if (!stage(option, valid && number >= 0 && number <= INT_MAX ? QVariant(number - 1) : QVariant(QStringLiteral("invalid")))) return false;
        // A legacy stream ID would otherwise override the chosen number.
        return stage(option + QStringLiteral("-id"), QString());
    }
    if (const auto option = languageOption(name); !option.isEmpty()) {
        const QString input = proposed.toString().trimmed();
        if (input == value(name).toString()) {
            m_invalid.remove(name);
            if (!stage(option, value(option))) return false;
            const QString track = option == QLatin1String("audio-language") ? QStringLiteral("audio-track") : QStringLiteral("sub-track");
            stage(track, -1);
            return stage(track + QStringLiteral("-id"), QString());
        }
        QStringList codes;
        bool valid = true;
        if (!input.isEmpty() && input.compare(qtr("Automatic"), Qt::CaseInsensitive) != 0) {
            for (const auto& token : input.split(QLatin1Char(','))) {
                const auto code = token.trimmed().toLower().toUtf8();
                const auto* language = code.isEmpty() ? nullptr : languageFromText(token.trimmed());
                if (token.trimmed().compare(qtr("System language"),Qt::CaseInsensitive)==0 || code=="system") codes.append(QStringLiteral("system"));
                else if (language) codes.append(qfu(*language->psz_iso639_1 ? language->psz_iso639_1 : language->psz_iso639_2T));
                else if (code == "any" || code == "none") codes.append(qfu(code.constData()));
                else { valid = false; break; }
            }
        }
        if (!valid) {
            m_invalid.insert(name);
            m_error = qtr("Enter a language name or a two or three letter language code.");
            ++m_revision; emit changed(); return false;
        }
        m_invalid.remove(name);
        if (!stage(option, codes.join(QLatin1Char(',')))) return false;
        const QString track = option == QLatin1String("audio-language") ? QStringLiteral("audio-track") : QStringLiteral("sub-track");
        stage(track, -1);
        return stage(track + QStringLiteral("-id"), QString());
    }
    if (name == QLatin1String("audio-spatial") || name == QLatin1String("audio-spatial-mode")) {
        if (!module_exists("spatialaudio")) return false;
        if (name == QLatin1String("audio-spatial-mode") && proposed.toInt() != AOUT_MIX_MODE_BINAURAL
            && proposed.toInt() != AOUT_MIX_MODE_UNSET) return false;
    }
    if (name == QLatin1String("redesign-startup-volume")) {
        bool valid = false;
        const auto volume = proposed.toLongLong(&valid);
        return stage(QStringLiteral("audio-startup-volume"), valid && volume >= 0 && volume <= 300 ? QVariant(volume) : QVariant(QStringLiteral("invalid")));
    }
    if (name == QLatin1String("redesign-audio-device")) {
        const QString id = proposed.toString();
        const auto choices = audioDeviceChoices();
        if (std::none_of(choices.cbegin(), choices.cend(), [&](const auto& choice) { return choice.toMap().value(QStringLiteral("value")).toString() == id; })) return false;
        const QString module = audioOutputModule();
        stage(QStringLiteral("audio-device-default-module"), id.isEmpty() ? QString() : module);
        const QString legacyName = module + QStringLiteral("-audio-device");
        const auto* legacy = config_FindConfig(legacyName.toUtf8().constData());
        if (legacy && CONFIG_CLASS(legacy->i_type) == CONFIG_ITEM_STRING)
            stage(legacyName, id.isEmpty() ? qfu(legacy->orig.psz ? legacy->orig.psz : "") : id);
        return stage(QStringLiteral("audio-device-default"), id);
    }
    if (name == QLatin1String("volume-save")) {
        if (proposed.toBool() && m_invalid.contains(QStringLiteral("audio-startup-volume")))
            stage(QStringLiteral("audio-startup-volume"), value(QStringLiteral("audio-startup-volume")));
        if (!proposed.toBool() && value(QStringLiteral("audio-startup-volume")).toInt() < 0)
            stage(QStringLiteral("audio-startup-volume"), value(QStringLiteral("redesign-startup-volume")));
        if (proposed.toBool() && m_ctx) {
            const float current = vlc_player_aout_GetVolume(m_ctx->getIntf()->p_player);
            if (std::isfinite(current) && current >= 0) stage(QStringLiteral("audio-last-volume"), std::min(current, 3.f));
        }
    }

    if (name == QLatin1String("redesign-web-remote")) {
        if (proposed.toBool() && !supportsWebRemote()) return false;
        auto interfaces = value(QStringLiteral("extraintf")).toString().split(QLatin1Char(':'), Qt::SkipEmptyParts);
        interfaces.erase(std::remove_if(interfaces.begin(), interfaces.end(), [](const auto& entry) {
            const auto module = entry.section(QLatin1Char('{'), 0, 0);
            return module == QLatin1String("http") || module == QLatin1String("luahttp");
        }), interfaces.end());
        if (proposed.toBool()) interfaces.append(QStringLiteral("http"));
        return stage(QStringLiteral("extraintf"), interfaces.join(QLatin1Char(':')));
    }

    if (name == QLatin1String("redesign-repeat") || name == QLatin1String("redesign-after-playback")) {
        const int choice = proposed.toInt();
        if (choice < 0 || choice > 2) return false;
        const bool repeat = name == QLatin1String("redesign-repeat");
        stage(repeat ? QStringLiteral("repeat") : QStringLiteral("play-and-exit"), choice == 1);
        return stage(repeat ? QStringLiteral("loop") : QStringLiteral("play-and-pause"), choice == 2);
    }
    if (name.startsWith(QLatin1String("filter:"))) {
        const auto parts = name.split(QLatin1Char(':'));
        if (parts.size() != 3 || !module_exists(parts[2].toUtf8().constData())) return false;
        auto filters = (parts[1] == QLatin1String("video-filter") || parts[1] == QLatin1String("sub-source")
            ? videoValue(parts[1]) : value(parts[1])).toString().split(QLatin1Char(':'), Qt::SkipEmptyParts);
        // Older configurations can put sources in sub-filter. Move the
        // active sources together, so enabling one does not hide another.
        if (parts[1] == QLatin1String("sub-source")) {
            const auto legacy = videoValue(QStringLiteral("sub-filter")).toString().split(QLatin1Char(':'), Qt::SkipEmptyParts);
            QStringList retained;
            for (const auto& entry : legacy) {
                const auto* module = module_find(entry.toUtf8().constData());
                if (module && module_provides(module, "sub source")) {
                    if (!filters.contains(entry)) filters.append(entry);
                } else {
                    retained.append(entry);
                }
            }
            if (retained != legacy)
                stage(QStringLiteral("sub-filter"), retained.join(QLatin1Char(':')));
        }
        // Editing an enabled effect must preserve its position. Moving an
        // adjust filter after transform can discard the transform orientation.
        if (!proposed.toBool()) filters.removeAll(parts[2]);
        else if (!filters.contains(parts[2])) {
            // Transform describes the final display orientation. A new pixel
            // effect after it can replace that format and lose the flip.
            const int transform = filters.indexOf(QStringLiteral("transform"));
            if (parts[1] == QLatin1String("video-filter") && transform >= 0)
                filters.insert(transform, parts[2]);
            else
                filters.append(parts[2]);
        }
        return stage(parts[1], filters.join(QLatin1Char(':')));
    }

    if (name == QLatin1String("equalizer-preset") && !proposed.toString().isEmpty()) {
        const QByteArray preset = proposed.toString().toUtf8();
        const auto it = std::find_if(std::begin(eqz_preset_10b), std::end(eqz_preset_10b), [&](const auto& row) { return preset == row.psz_name; });
        if (it == std::end(eqz_preset_10b)) return false;
        QStringList bands;
        for (int i = 0; i < it->i_band; ++i) bands.append(QString::number(std::abs(it->f_amp[i]) < 0.05f ? 0.f : it->f_amp[i], 'f', 1));
        stage(QStringLiteral("equalizer-bands"), bands.join(QLatin1Char(' ')));
        stage(QStringLiteral("equalizer-preamp"), it->f_preamp);
    }

    const auto* cfg = config_FindConfig(name.toUtf8().constData());
    if (!cfg || !CONFIG_ITEM(cfg->i_type)) return false;
    QVariant normalized;
    bool valid = true;
    switch (CONFIG_CLASS(cfg->i_type)) {
    case CONFIG_ITEM_BOOL: normalized = proposed.toBool(); break;
    case CONFIG_ITEM_INTEGER: {
        const qlonglong v = proposed.toLongLong(&valid);
        valid = valid && (cfg->min.i == cfg->max.i || (v >= cfg->min.i && v <= cfg->max.i));
        normalized = QVariant::fromValue(v); break;
    }
    case CONFIG_ITEM_FLOAT: {
        const double v = proposed.toDouble(&valid);
        valid = valid && std::isfinite(v) && (cfg->min.f == cfg->max.f || (v >= cfg->min.f && v <= cfg->max.f));
        if (name == QLatin1String("equalizer-preamp")) valid = valid && v >= -20 && v <= 20;
        normalized = float(v); break;
    }
    case CONFIG_ITEM_STRING: normalized = proposed.toString(); break;
    default: valid = false; break;
    }
    if (!valid) {
        m_invalid.insert(name);
        m_error = qtr("Enter a value within the allowed range.");
        ++m_revision; emit changed(); return false;
    }
    m_invalid.remove(name);
    if (QStringList{QStringLiteral("hue"), QStringLiteral("brightness"), QStringLiteral("contrast"), QStringLiteral("saturation"), QStringLiteral("gamma")}.contains(name))
        stage(QStringLiteral("filter:video-filter:adjust"), true);

    const QString effect = name == QLatin1String("sharpen-sigma") ? QStringLiteral("sharpen")
        : name == QLatin1String("gradfun-radius") ? QStringLiteral("gradfun")
        : name == QLatin1String("grain-variance") ? QStringLiteral("grain")
        : name == QLatin1String("sepia-intensity") ? QStringLiteral("sepia") : QString();
    if (!effect.isEmpty())
        stage(QStringLiteral("filter:video-filter:") + effect, true);

    bool applyToPlayer = m_ctx && name == QLatin1String("qt-backdrop-blur")
        && normalized.toBool() != m_ctx->backdropBlurRequested();
    if (m_ctx && (name == QLatin1String("sub-text-scale") || name == QLatin1String("sub-text-size-mode")
        || name == QLatin1String("sub-text-size-pixels"))) {
        auto *player = m_ctx->getIntf()->p_player;
        vlc_player_Lock(player);
        if (name == QLatin1String("sub-text-scale"))
            applyToPlayer = normalized.toUInt() != vlc_player_GetSubtitleTextScale(player);
        else if (name == QLatin1String("sub-text-size-mode"))
            applyToPlayer = normalized.toInt() != vlc_player_GetSubtitleTextSizeMode(player);
        else
            applyToPlayer = normalized.toUInt() != vlc_player_GetSubtitleTextPixelSize(player);
        vlc_player_Unlock(player);
    }
    if (m_ctx && videoOutputOptions().contains(name)) {
        auto* output = vlc_player_vout_Hold(m_ctx->getIntf()->p_player);
        if (output) {
            const auto current = outputValue(output, name);
            applyToPlayer = current.isValid() && normalized != current;
            vout_Release(output);
        }
    }
    // A shortcut can change the current size without changing saved defaults.
    if (normalized == read(name.toUtf8()) && !applyToPlayer) m_edits.remove(name);
    else m_edits.insert(name, normalized);
    if (m_invalid.isEmpty())
        m_error.clear();
    ++m_revision;
    emit changed();
    if (m_autoSave) m_saveTimer.start();
    if (name == QLatin1String("pitch-shift"))
        return stage(QStringLiteral("filter:audio-filter:scaletempo_pitch"), normalized.toFloat() != 0.f);
    return true;
}

void RedesignPreferences::cancelLanguageEdit(const QString& name)
{
    if (languageOption(name).isEmpty() || !m_invalid.remove(name)) return;
    if (m_invalid.isEmpty()) m_error.clear();
    ++m_revision;emit changed();
    if (m_autoSave && !m_edits.isEmpty()) m_saveTimer.start();
}

void RedesignPreferences::reset(const QString& name)
{
    const auto data = describe(name);
    if (!data.isEmpty()) stage(name, data.value(QStringLiteral("defaultValue")));
}

void RedesignPreferences::discard()
{
    m_saveTimer.stop();
    m_presetTransaction = false; m_editsBeforePreset.clear();
    m_edits.clear(); m_invalid.clear(); m_error.clear(); ++m_revision; emit changed();
}

bool RedesignPreferences::save()
{
    m_saveTimer.stop();
    if (!m_ctx || !m_invalid.isEmpty()) return false;
    const bool presentationChanged = std::any_of(m_edits.keyBegin(), m_edits.keyEnd(), [](const QString& name) {
        return presetOptions().contains(name);
    });
    if (presentationChanged && (!value(presetOption).toString().isEmpty() || m_editPlayerPreset)) {
        auto state = playerPresetState();
        if (state.isEmpty() && m_editPlayerPreset) return playerPresetError(qtr("VLC cannot read the saved presets."));
        if (!state.isEmpty()) {
            const auto selected = state.value(QStringLiteral("selected")).toString();
            if (m_editPlayerPreset && !selected.isEmpty()) {
                auto presets = state.value(QStringLiteral("presets")).toList();
                for (auto& row : presets) {
                    auto preset = row.toMap();
                    if (preset.value(QStringLiteral("id")).toString() != selected) continue;
                    auto options = preset.value(QStringLiteral("options")).toMap();
                    const auto current = playerPresetOptions();
                    for (auto it = current.cbegin(); it != current.cend(); ++it) options.insert(it.key(), it.value());
                    preset.insert(QStringLiteral("options"), options); row = preset;
                }
                state.insert(QStringLiteral("presets"), presets);
            } else {
                auto defaults = state.value(QStringLiteral("default")).toMap();
                for (auto it = m_edits.cbegin(); it != m_edits.cend(); ++it)
                    if (presetOptions().contains(it.key())) defaults.insert(it.key(), it.value());
                state.insert(QStringLiteral("default"), defaults);
            }
            m_edits.insert(presetOption, QString::fromUtf8(QJsonDocument::fromVariant(state).toJson(QJsonDocument::Compact)));
        }
    }
    QVariantMap previous;
    for (auto it = m_edits.cbegin(); it != m_edits.cend(); ++it) {
        previous.insert(it.key(), read(it.key().toUtf8()));
        write(it.key().toUtf8(), it.value());
    }
    if (config_SaveConfigFile(m_ctx->getIntf()) != 0) {
        for (auto it = previous.cbegin(); it != previous.cend(); ++it) write(it.key().toUtf8(), it.value());
        m_error = qtr("The preferences file could not be saved. Your edits are still open.");
        ++m_revision; emit changed(); return false;
    }
    // These controls are inherited by the current input and action dispatcher.
    auto* instance = vlc_object_instance(m_ctx->getIntf());
    if (previous.contains(QStringLiteral("qt-backdrop-blur"))) {
        // An explicit UI choice replaces a startup override for this interface.
        auto* intf = m_ctx->getIntf();
        if (var_Type(intf, "qt-backdrop-blur") == 0)
            var_Create(intf, "qt-backdrop-blur", VLC_VAR_BOOL);
        var_SetBool(intf, "qt-backdrop-blur", bool(config_GetInt("qt-backdrop-blur")));
    }
    for (const auto& name : {QStringLiteral("mouse-pause-policy"), QStringLiteral("hotkeys-x-wheel-mode"),
                            QStringLiteral("hotkeys-y-wheel-mode"), QStringLiteral("hotkeys-wheel-direction")}) {
        if (!previous.contains(name)) continue;
        const QByteArray bytes = name.toUtf8();
        const int type = name == QLatin1String("mouse-pause-policy") ? VLC_VAR_STRING
            : name == QLatin1String("hotkeys-wheel-direction") ? VLC_VAR_BOOL : VLC_VAR_INTEGER;
        if (var_Type(instance, bytes.constData()) == 0) var_Create(instance, bytes.constData(), type);
        if (type == VLC_VAR_STRING) var_SetString(instance, bytes.constData(), value(name).toString().toUtf8().constData());
        else if (type == VLC_VAR_BOOL) var_SetBool(instance, bytes.constData(), value(name).toBool());
        else var_SetInteger(instance, bytes.constData(), value(name).toLongLong());
    }

    // Apply audio effects to the current output after persistence succeeds.
    // Defaults remain available for the next output if nothing is playing.
    auto* player = m_ctx->getIntf()->p_player;
    // Language preferences are cached by the player. Updating the config alone
    // would leave subsequent episodes using the language from player creation.
    vlc_player_Lock(player);
    if (previous.contains(QStringLiteral("audio-desync")))
        vlc_player_SetAudioDelay(player, VLC_TICK_FROM_MS(value(QStringLiteral("audio-desync")).toLongLong()), VLC_PLAYER_WHENCE_ABSOLUTE);
    if (previous.contains(QStringLiteral("sub-delay")) || previous.contains(QStringLiteral("sub-delay-ms")))
        vlc_player_SetSubtitleDelay(player, VLC_TICK_FROM_MS(value(QStringLiteral("redesign-subtitle-delay")).toLongLong()), VLC_PLAYER_WHENCE_ABSOLUTE);
    if (previous.contains(QStringLiteral("sub-fps")))
        vlc_player_SetAssociatedSubsFPS(player, value(QStringLiteral("sub-fps")).toFloat());
    if (previous.contains(QStringLiteral("sub-text-scale")))
        vlc_player_SetSubtitleTextScale(player, value(QStringLiteral("sub-text-scale")).toUInt());
    if (previous.contains(QStringLiteral("sub-text-size-mode")))
        vlc_player_SetSubtitleTextSizeMode(player, static_cast<vlc_player_subtitle_size_mode>(value(QStringLiteral("sub-text-size-mode")).toInt()));
    if (previous.contains(QStringLiteral("sub-text-size-pixels")))
        vlc_player_SetSubtitleTextPixelSize(player, value(QStringLiteral("sub-text-size-pixels")).toUInt());
    for (const auto category : {AUDIO_ES, SPU_ES}) {
        const QString option = category == AUDIO_ES ? QStringLiteral("audio-language") : QStringLiteral("sub-language");
        if (previous.contains(option)) {
            const auto language = value(option).toString().toUtf8();
            vlc_player_SelectCategoryLanguage(player, category, language.constData());
        }
    }
    vlc_player_Unlock(player);
    if (std::any_of(videoOutputOptions().cbegin(), videoOutputOptions().cend(),
                    [&](const auto& name) { return previous.contains(name); })) {
        size_t count = 0;
        auto** outputs = vlc_player_vout_HoldAll(player, &count);
        for (size_t i = 0; i < count; ++i) {
            for (const auto& name : videoOutputOptions()) {
                if (!previous.contains(name)) continue;
                const auto bytes = name.toUtf8();
                const int type = config_GetType(bytes.constData()) & VLC_VAR_CLASS;
                if (var_Type(outputs[i], bytes.constData()) == 0)
                    // Filter proxy callbacks use ISCOMMAND to find and remove
                    // mappings when the chain changes. Keep that contract even
                    // if the settings editor creates the mapping first.
                    var_Create(outputs[i], bytes.constData(), type | VLC_VAR_ISCOMMAND);
                const auto current = value(name);
                switch (type) {
                case VLC_VAR_BOOL: var_SetBool(outputs[i], bytes.constData(), current.toBool()); break;
                case VLC_VAR_INTEGER: var_SetInteger(outputs[i], bytes.constData(), current.toLongLong()); break;
                case VLC_VAR_FLOAT: var_SetFloat(outputs[i], bytes.constData(), current.toFloat()); break;
                case VLC_VAR_STRING: var_SetString(outputs[i], bytes.constData(), current.toString().toUtf8().constData()); break;
                }
            }
            // marq-file is inherited at creation, unlike the command-backed
            // overlay options. Reload its source after a successful save.
            if (previous.contains(QStringLiteral("marq-file"))
                && !previous.contains(QStringLiteral("sub-source"))) {
                const auto sources = outputValue(outputs[i], QStringLiteral("sub-source")).toString().split(QLatin1Char(':'));
                const auto legacy = outputValue(outputs[i], QStringLiteral("sub-filter")).toString().split(QLatin1Char(':'));
                if (sources.contains(QStringLiteral("marq")))
                    var_TriggerCallback(outputs[i], "sub-source");
                else if (legacy.contains(QStringLiteral("marq")))
                    var_TriggerCallback(outputs[i], "sub-filter");
            }
            vout_Release(outputs[i]);
        }
        free(outputs);
    }
    if (previous.contains(QStringLiteral("sub-margin")) || previous.contains(QStringLiteral("subsdelay-factor"))
        || previous.contains(QStringLiteral("subsdelay-mode")) || previous.contains(QStringLiteral("sub-filter"))) {
        size_t count = 0;
        auto** outputs = vlc_player_vout_HoldAll(player, &count);
        for (size_t i = 0; i < count; ++i) {
            // Set duration parameters before loading its filter. Existing
            // filters receive changes through the native command proxies.
            for (const auto& name : {QStringLiteral("subsdelay-factor"), QStringLiteral("subsdelay-mode"),
                                   QStringLiteral("sub-margin"), QStringLiteral("sub-filter")}) {
                if (!previous.contains(name)) continue;
                const auto bytes = name.toUtf8();
                const int type = config_GetType(bytes.constData()) & VLC_VAR_CLASS;
                if (var_Type(outputs[i], bytes.constData()) == 0)
                    var_Create(outputs[i], bytes.constData(), type);
                const auto current = value(name);
                if (type == VLC_VAR_FLOAT) var_SetFloat(outputs[i], bytes.constData(), current.toFloat());
                else if (type == VLC_VAR_STRING) var_SetString(outputs[i], bytes.constData(), current.toString().toUtf8().constData());
                else var_SetInteger(outputs[i], bytes.constData(), current.toLongLong());
            }
            vout_Release(outputs[i]);
        }
        free(outputs);
    }
    if (std::any_of(previous.keyBegin(), previous.keyEnd(), subtitleStyleOption))
        vlc_subpicture_InvalidateTextStyle();
    const bool deviceChanged = previous.contains(QStringLiteral("audio-device-default"))
        || previous.contains(QStringLiteral("audio-device-default-module"))
        || previous.contains(audioOutputModule() + QStringLiteral("-audio-device"));
    if (previous.contains(QStringLiteral("volume-save")) || deviceChanged || previous.contains(QStringLiteral("mix-mode"))
        || previous.contains(QStringLiteral("stereo-mode")) || previous.contains(QStringLiteral("audio-spatial"))
        || previous.contains(QStringLiteral("audio-spatial-mode"))) {
        audio_output_t* output = vlc_player_aout_Hold(player);
        if (output) {
            for (const auto& option : {QStringLiteral("mix-mode"), QStringLiteral("stereo-mode"), QStringLiteral("audio-spatial-mode")})
                if (previous.contains(option)) var_SetInteger(output, option.toUtf8().constData(), value(option).toLongLong());
            if (previous.contains(QStringLiteral("audio-spatial")))
                var_SetBool(output, "audio-spatial", value(QStringLiteral("audio-spatial")).toBool());
            if (previous.contains(QStringLiteral("volume-save"))) {
                if (var_Type(output, "volume-save") == 0) var_Create(output, "volume-save", VLC_VAR_BOOL);
                var_SetBool(output, "volume-save", value(QStringLiteral("volume-save")).toBool());
            }
            if (deviceChanged) {
                const QByteArray id = value(QStringLiteral("redesign-audio-device")).toString().toUtf8();
                aout_DeviceSet(output, id.isEmpty() ? nullptr : id.constData());
            }
            aout_Release(output);
        }
    }
    if (previous.contains(QStringLiteral("audio-filter"))) {
        const auto before = previous.value(QStringLiteral("audio-filter")).toString().split(QLatin1Char(':'), Qt::SkipEmptyParts);
        const auto after = value(QStringLiteral("audio-filter")).toString().split(QLatin1Char(':'), Qt::SkipEmptyParts);
        for (const auto& filter : before)
            if (!after.contains(filter)) vlc_player_aout_EnableFilter(player, filter.toUtf8().constData(), false);
        for (const auto& filter : after)
            if (!before.contains(filter)) vlc_player_aout_EnableFilter(player, filter.toUtf8().constData(), true);
    }
    if (previous.contains(QStringLiteral("audio-visual"))) {
        audio_output_t* output = vlc_player_aout_Hold(player);
        if (output) {
            var_SetString(output, "visual", value(QStringLiteral("audio-visual")).toString().toUtf8().constData());
            aout_Release(output);
        }
    }
    const QStringList equalizerOptions{QStringLiteral("equalizer-preset"), QStringLiteral("equalizer-bands"), QStringLiteral("equalizer-preamp"), QStringLiteral("equalizer-2pass")};
    if (std::any_of(equalizerOptions.cbegin(), equalizerOptions.cend(), [&](const auto& name) { return previous.contains(name); })) {
        audio_output_t* output = vlc_player_aout_Hold(player);
        if (output) {
            for (const auto& name : equalizerOptions) {
                const auto current = value(name);
                const QByteArray bytes = name.toUtf8();
                if (name == QLatin1String("equalizer-preamp")) var_SetFloat(output, bytes.constData(), current.toFloat());
                else if (name == QLatin1String("equalizer-2pass")) var_SetBool(output, bytes.constData(), current.toBool());
                else if (name != QLatin1String("equalizer-preset") || !current.toString().isEmpty()) var_SetString(output, bytes.constData(), current.toString().toUtf8().constData());
            }
            aout_Release(output);
        }
    }
    if (std::any_of(audioFilterFloatOptions().cbegin(), audioFilterFloatOptions().cend(), [&](const auto& name) { return previous.contains(name); })) {
        audio_output_t* output = vlc_player_aout_Hold(player);
        if (output) {
            for (const auto& name : audioFilterFloatOptions()) {
                if (!previous.contains(name)) continue;
                const QByteArray bytes = name.toUtf8();
                if (var_Type(output, bytes.constData()) == 0) var_Create(output, bytes.constData(), VLC_VAR_FLOAT);
                var_SetFloat(output, bytes.constData(), value(name).toFloat());
            }
            aout_Release(output);
        }
    }
    const auto passthrough = audioPassthroughOption(audioOutputModule());
    if (!passthrough.isEmpty() && previous.contains(passthrough)) {
        audio_output_t* output = vlc_player_aout_Hold(player);
        if (output) {
            const auto bytes = passthrough.toUtf8();
            const bool boolean = config_GetType(bytes.constData()) == CONFIG_ITEM_BOOL;
            if (var_Type(output, bytes.constData()) == 0)
                var_Create(output, bytes.constData(), boolean ? VLC_VAR_BOOL : VLC_VAR_INTEGER);
            if (boolean) var_SetBool(output, bytes.constData(), value(passthrough).toBool());
            else var_SetInteger(output, bytes.constData(), value(passthrough).toLongLong());
            // A compressed stream can require a different decoder after the
            // output policy changes, even when the device is unchanged.
            aout_RestartRequest(output, true);
            aout_Release(output);
        }
    }
    if (previous.contains(QStringLiteral("audio-resampler"))
        || std::any_of(std::begin(resamplingQualities), std::end(resamplingQualities), [&](const auto& quality) {
            return previous.contains(qfu(quality.option));
        })) {
        audio_output_t* output = vlc_player_aout_Hold(player);
        if (output) {
            if (var_Type(output, "audio-resampler") == 0) var_Create(output, "audio-resampler", VLC_VAR_STRING);
            var_SetString(output, "audio-resampler", value(QStringLiteral("audio-resampler")).toString().toUtf8().constData());
            for (const auto& quality : resamplingQualities) {
                if (!previous.contains(qfu(quality.option))) continue;
                if (var_Type(output, quality.option) == 0) var_Create(output, quality.option, VLC_VAR_INTEGER);
                var_SetInteger(output, quality.option, value(qfu(quality.option)).toLongLong());
            }
            aout_RestartRequest(output, false);
            aout_Release(output);
        }
    }
    m_ctx->reloadPrefs();
    m_ctx->getIntf()->preferencesResetPending = false;
    discard();
    return true;
}

bool RedesignPreferences::resetAll()
{
    if (!m_ctx) return false;
    m_saveTimer.stop();
    auto* intf = m_ctx->getIntf();
    QSettings uiSettings(intf->mainSettings->fileName(), intf->mainSettings->format());
    uiSettings.setFallbacksEnabled(false);
    QVariantMap previousUi;
    for (const auto& key : uiSettings.allKeys()) previousUi.insert(key, uiSettings.value(key));

    QVariantMap previous;
    size_t count = 0;
    module_t** modules = module_list_get(&count);
    for (size_t i = 0; i < count; ++i) {
        unsigned size = 0;
        module_config_t* configs = module_config_get(modules[i], &size);
        for (unsigned j = 0; j < size; ++j) {
            if (!CONFIG_ITEM(configs[j].i_type) || !configs[j].psz_name) continue;
            const auto current = read(configs[j].psz_name);
            if (current.isValid()) previous.insert(qfu(configs[j].psz_name), current);
        }
        module_config_free(configs);
    }
    module_list_free(modules);
    const auto restore = [&]() {
        for (auto it = previous.cbegin(); it != previous.cend(); ++it) write(it.key().toUtf8(), it.value());
    };
    const auto failed = [&]() {
        m_error = qtr("VLC cannot save the default settings. Your settings did not change.");
        ++m_revision; emit changed(); return false;
    };
#ifdef _WIN32
    QSettings language(QStringLiteral("HKEY_CURRENT_USER\\Software\\VideoLAN\\VLC"), QSettings::NativeFormat);
    const bool hasLanguage = language.contains(QStringLiteral("Lang"));
    const QVariant previousLanguage = language.value(QStringLiteral("Lang"));
    if (hasLanguage && !language.isWritable()) return failed();
#endif
    const auto rollback = [&]() {
        QSettings recovery(uiSettings.fileName(), uiSettings.format());
        recovery.setFallbacksEnabled(false);
        recovery.clear();
        for (auto it = previousUi.cbegin(); it != previousUi.cend(); ++it) recovery.setValue(it.key(), it.value());
        recovery.sync();
        restore();
        const int restored = config_SaveConfigFile(intf);
        if (restored != 0 || recovery.status() != QSettings::NoError) {
            m_error = qtr("VLC cannot restore the settings file. Restart VLC and check your settings.");
            ++m_revision; emit changed(); return false;
        }
        return failed();
    };
    if (!uiSettings.isWritable()) return failed();
    config_ResetAll();
    if (config_SaveConfigFile(intf) != 0) {
        restore();
        return failed();
    }
    uiSettings.clear();
    uiSettings.sync();
    if (uiSettings.status() != QSettings::NoError) return rollback();
#ifdef _WIN32
    if (hasLanguage) {
        language.remove(QStringLiteral("Lang"));
        language.sync();
        if (language.status() != QSettings::NoError) {
            language.setValue(QStringLiteral("Lang"), previousLanguage);
            language.sync();
            return rollback();
        }
    }
#endif
    intf->preferencesResetPending = true;
    if (var_Type(intf, "qt-backdrop-blur") == 0)
        var_Create(intf, "qt-backdrop-blur", VLC_VAR_BOOL);
    var_SetBool(intf, "qt-backdrop-blur", bool(config_GetInt("qt-backdrop-blur")));
    vlc_subpicture_InvalidateTextStyle();
    vlc_player_Lock(intf->p_player);
    vlc_player_SetSubtitleTextScale(intf->p_player, config_GetInt("sub-text-scale"));
    vlc_player_SetSubtitleTextSizeMode(intf->p_player, static_cast<vlc_player_subtitle_size_mode>(config_GetInt("sub-text-size-mode")));
    vlc_player_SetSubtitleTextPixelSize(intf->p_player, config_GetInt("sub-text-size-pixels"));
    vlc_player_Unlock(intf->p_player);
    m_ctx->reloadPrefs();
    m_ctx->reloadFromSettings();
    discard();
    return true;
}

QVariantList RedesignPreferences::catalog(const QString& category, const QString& search) const
{
    QVariantList result;
    for (const auto& entry : m_catalog) {
        if (entry.name == QLatin1String("sub-delay-ms")) continue;
        if (!search.isEmpty()) {
            if (!entry.name.contains(search, Qt::CaseInsensitive) && !entry.title.contains(search, Qt::CaseInsensitive)) continue;
        } else if (entry.category != category) continue;
        const bool track = entry.name == QLatin1String("audio-track") || entry.name == QLatin1String("sub-track");
        const bool language = entry.name == QLatin1String("audio-language") || entry.name == QLatin1String("sub-language");
        const auto name = entry.name == QLatin1String("sub-delay") ? QStringLiteral("redesign-subtitle-delay")
            : track || language ? QStringLiteral("redesign-") + entry.name : entry.name;
        result.append(QVariantMap{{QStringLiteral("name"), name}, {QStringLiteral("title"), entry.title}});
    }
    return result;
}

QString RedesignPreferences::choosePath(const QString& name)
{
    const auto* cfg = config_FindConfig(name.toUtf8().constData());
    if (!cfg) return {};
    const QString initial = value(name).toString();
    switch (cfg->i_type) {
    case CONFIG_ITEM_DIRECTORY: return QFileDialog::getExistingDirectory(nullptr, qtr("Select folder"), initial);
    case CONFIG_ITEM_SAVEFILE: return QFileDialog::getSaveFileName(nullptr, qtr("Select file"), initial);
    case CONFIG_ITEM_LOADFILE: return QFileDialog::getOpenFileName(nullptr, qtr("Select file"), initial);
    default: return {};
    }
}

QUrl RedesignPreferences::configurationFolder() const
{
    if (!m_ctx) return {};
    char* custom = var_InheritString(m_ctx->getIntf(), "config");
    QString folder;
    if (custom && *custom) folder = QFileInfo(qfu(custom)).absolutePath();
    free(custom);
    if (folder.isEmpty()) {
        char* path = config_GetUserDir(VLC_CONFIG_DIR);
        folder = qfu(path ? path : "");
        free(path);
    }
    if (folder.isEmpty() || !QDir().mkpath(folder)) return {};
    return QUrl::fromLocalFile(folder);
}

QString RedesignPreferences::chooseColor(const QString& initial)
{
    const QColor color = QColorDialog::getColor(QColor(initial), nullptr, qtr("Choose color"));
    return color.isValid() ? color.name() : QString();
}

QVariantList RedesignPreferences::equalizerBands() const
{
    const auto custom = value(QStringLiteral("equalizer-bands")).toString().split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
    const QByteArray name = value(QStringLiteral("equalizer-preset")).toString().toUtf8();
    const auto preset = std::find_if(std::begin(eqz_preset_10b), std::end(eqz_preset_10b), [&](const auto& row) { return name == row.psz_name; });
    QVariantList result;
    for (int i = 0; i < 10; ++i) {
        bool valid = false;
        double gain = i < custom.size() ? custom[i].toDouble(&valid) : 0;
        if (!valid || !std::isfinite(gain)) gain = preset != std::end(eqz_preset_10b) ? preset->f_amp[i] : 0;
        result.append(std::abs(gain) < 0.05 ? 0.0 : std::clamp(gain, -20.0, 20.0));
    }
    return result;
}

bool RedesignPreferences::setEqualizerBand(int index, double gain)
{
    if (index < 0 || index >= 10 || !std::isfinite(gain) || gain < -20 || gain > 20) return false;
    const auto values = equalizerBands();
    QStringList bands;
    for (int i = 0; i < values.size(); ++i) bands.append(QString::number(i == index ? gain : values[i].toDouble(), 'f', 1));
    if (!stage(QStringLiteral("equalizer-bands"), bands.join(QLatin1Char(' ')))) return false;
    if (!stage(QStringLiteral("filter:audio-filter:equalizer"), true)) return false;
    return stage(QStringLiteral("equalizer-preset"), QString());
}

QVariantList RedesignPreferences::shortcutCatalog() const
{
    struct Shortcut { QString name, title, group; int groupOrder, order; };
    QList<Shortcut> shortcuts;
    const QStringList basic{QStringLiteral("key-toggle-fullscreen"), QStringLiteral("key-leave-fullscreen"), QStringLiteral("key-position"), QStringLiteral("key-intf-show")};
    const QStringList playback{QStringLiteral("key-play-pause"), QStringLiteral("key-stop"), QStringLiteral("key-next"), QStringLiteral("key-prev"), QStringLiteral("key-program-sid-next"), QStringLiteral("key-program-sid-prev")};
    for (const auto& entry : m_catalog) {
        if (!entry.name.startsWith(QLatin1String("key-"))) continue;
        Shortcut row{entry.name, entry.title, qtr("Other"), 5, 1000};
        if (basic.contains(entry.name)) { row.group = qtr("Basic"); row.groupOrder = 0; row.order = basic.indexOf(entry.name); }
        else if (playback.contains(entry.name)) { row.group = qtr("Playback"); row.groupOrder = 1; row.order = playback.indexOf(entry.name); }
        else if (entry.name.contains(QLatin1String("sub"))) { row.group = qtr("Subtitles"); row.groupOrder = 4; }
        else if (entry.name.contains(QLatin1String("audio")) || entry.name.contains(QLatin1String("vol-"))) { row.group = qtr("Audio"); row.groupOrder = 2; }
        else if (entry.name.contains(QLatin1String("aspect")) || entry.name.contains(QLatin1String("crop")) || entry.name.contains(QLatin1String("zoom")) || entry.name.contains(QLatin1String("snapshot")) || entry.name.contains(QLatin1String("deinterlace"))) { row.group = qtr("Video"); row.groupOrder = 3; }
        else if (entry.name.contains(QLatin1String("jump")) || entry.name.contains(QLatin1String("rate")) || entry.name.contains(QLatin1String("frame"))) { row.group = qtr("Playback"); row.groupOrder = 1; }
        if (entry.name == QLatin1String("key-toggle-fullscreen")) row.title = qtr("Toggle fullscreen");
        else if (entry.name == QLatin1String("key-leave-fullscreen")) row.title = qtr("Exit fullscreen / close dialog");
        else if (entry.name == QLatin1String("key-position")) row.title = qtr("Show playback position and time");
        else if (entry.name == QLatin1String("key-intf-show")) row.title = qtr("Show interface controls in fullscreen");
        else if (entry.name == QLatin1String("key-play-pause")) row.title = qtr("Play / pause");
        else if (entry.name == QLatin1String("key-stop")) row.title = qtr("Stop playback");
        else if (entry.name == QLatin1String("key-next")) row.title = qtr("Next track");
        else if (entry.name == QLatin1String("key-prev")) row.title = qtr("Previous track");
        shortcuts.append(row);
    }
    std::sort(shortcuts.begin(), shortcuts.end(), [](const Shortcut& a, const Shortcut& b) {
        if (a.groupOrder != b.groupOrder) return a.groupOrder < b.groupOrder;
        if (a.order != b.order) return a.order < b.order;
        return QString::localeAwareCompare(a.title, b.title) < 0;
    });
    QVariantList result;
    for (const auto& row : shortcuts) {
        const QString global = QStringLiteral("global-") + row.name;
        result.append(QVariantMap{{QStringLiteral("name"), row.name}, {QStringLiteral("title"), row.title},
            {QStringLiteral("group"), row.group}, {QStringLiteral("globalName"), config_FindConfig(global.toUtf8().constData()) ? global : QString()}});
    }
    return result;
}

QString RedesignPreferences::shortcutForKey(int key, int modifiers) const
{
    QKeyEvent event(QEvent::KeyPress, key, Qt::KeyboardModifiers::fromInt(modifiers));
    return VLCKeyToString(qtEventToVLCKey(&event), false);
}

QVariantList RedesignPreferences::shortcutConflicts(const QString& name, const QString& shortcut) const
{
    QVariantList conflicts;
    if (shortcut.isEmpty()) return conflicts;
    const bool global = name.startsWith(QLatin1String("global-key-"));
    for (const auto& entry : m_catalog) {
        if (entry.name == name || entry.name.startsWith(QLatin1String("global-key-")) != global) continue;
        if (!entry.name.startsWith(global ? QLatin1String("global-key-") : QLatin1String("key-"))) continue;
        if (value(entry.name).toString().split(QLatin1Char('\t')).contains(shortcut, Qt::CaseInsensitive))
            conflicts.append(QVariantMap{{QStringLiteral("name"), entry.name}, {QStringLiteral("title"), entry.title}});
    }
    return conflicts;
}

bool RedesignPreferences::assignShortcut(const QString& name, const QString& shortcut, bool replaceConflicts)
{
    const auto* cfg = config_FindConfig(name.toUtf8().constData());
    if (!cfg || cfg->i_type != CONFIG_ITEM_KEY) return false;
    const auto conflicts = shortcutConflicts(name, shortcut);
    if (!conflicts.isEmpty() && !replaceConflicts) return false;
    for (const auto& conflict : conflicts) {
        const QString other = conflict.toMap().value(QStringLiteral("name")).toString();
        QStringList bindings = value(other).toString().split(QLatin1Char('\t'), Qt::SkipEmptyParts);
        bindings.erase(std::remove_if(bindings.begin(), bindings.end(), [&shortcut](const QString& binding) {
            return binding.compare(shortcut, Qt::CaseInsensitive) == 0;
        }), bindings.end());
        stage(other, bindings.join(QLatin1Char('\t')));
    }
    if (shortcut.isEmpty()) return stage(name, QString());
    QStringList bindings = value(name).toString().split(QLatin1Char('\t'), Qt::SkipEmptyParts);
    // Replace the displayed binding while retaining alternate and media keys.
    if (!bindings.isEmpty() && !bindings.first().startsWith(QLatin1String("Media ")))
        bindings.removeFirst();
    bindings.removeAll(shortcut);
    bindings.prepend(shortcut);
    return stage(name, bindings.join(QLatin1Char('\t')));
}
