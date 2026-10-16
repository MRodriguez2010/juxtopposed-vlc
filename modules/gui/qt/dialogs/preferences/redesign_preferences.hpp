// SPDX-License-Identifier: GPL-2.0-or-later
#ifndef VLC_REDESIGN_PREFERENCES_HPP
#define VLC_REDESIGN_PREFERENCES_HPP

#include <QObject>
#include <QVariantMap>
#include <QVariantList>
#include <QSet>
#include <QTimer>
#include <QUrl>
#include <QElapsedTimer>
#include <memory>
#include "maininterface/mainctx.hpp"

class StereoTestPlayer;
/** A preferences transaction. Edits stay local until save() succeeds. */
class RedesignPreferences : public QObject
{
    Q_OBJECT
    Q_PROPERTY(MainCtx* ctx READ ctx WRITE setCtx NOTIFY ctxChanged FINAL)
    Q_PROPERTY(bool autoSave READ autoSave WRITE setAutoSave NOTIFY autoSaveChanged FINAL)
    Q_PROPERTY(bool dirty READ dirty NOTIFY changed FINAL)
    Q_PROPERTY(int revision READ revision NOTIFY changed FINAL)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY changed FINAL)
    Q_PROPERTY(bool editPlayerPreset MEMBER m_editPlayerPreset)
    Q_PROPERTY(QVariantList playerPresets READ playerPresets NOTIFY changed FINAL)
    Q_PROPERTY(QString selectedPlayerPreset READ selectedPlayerPreset NOTIFY changed FINAL)
    Q_PROPERTY(bool pendingPlayerPreset READ pendingPlayerPreset NOTIFY changed FINAL)
    Q_PROPERTY(bool stereoTestRunning READ stereoTestRunning NOTIFY stereoTestChanged FINAL)
    Q_PROPERTY(QString stereoTestMessage READ stereoTestMessage NOTIFY stereoTestChanged FINAL)
public:
    explicit RedesignPreferences(QObject* parent = nullptr);
    ~RedesignPreferences() override;
    MainCtx* ctx() const { return m_ctx; }
    void setCtx(MainCtx* ctx);
    bool autoSave() const { return m_autoSave; }
    void setAutoSave(bool enabled);
    bool dirty() const { return !m_edits.isEmpty() || !m_invalid.isEmpty(); }
    int revision() const { return m_revision; }
    QString errorMessage() const { return m_error; }
    Q_INVOKABLE void refresh();
    bool stereoTestRunning() const { return m_stereoTest != nullptr; }
    QString stereoTestMessage() const { return m_stereoTestMessage; }
    Q_INVOKABLE bool startStereoTest();
    Q_INVOKABLE void stopStereoTest();
    Q_INVOKABLE QStringList subtitleSearchLanguages() const;
    QVariantList playerPresets() const;
    QString selectedPlayerPreset() const;
    bool pendingPlayerPreset() const { return m_edits.contains(QStringLiteral("qt-player-presets")); }
    Q_INVOKABLE bool createPlayerPreset(const QString& name);
    Q_INVOKABLE bool selectPlayerPreset(const QString& id);
    Q_INVOKABLE bool renamePlayerPreset(const QString& id, const QString& name);
    Q_INVOKABLE bool duplicatePlayerPreset(const QString& id, const QString& name);
    Q_INVOKABLE bool deletePlayerPreset(const QString& id);
    Q_INVOKABLE void cancelPlayerPreset();
    Q_INVOKABLE QUrl configurationFolder() const;
    Q_INVOKABLE QVariantList equalizerBands() const;
    Q_INVOKABLE bool setEqualizerBand(int index, double gain);
    Q_INVOKABLE QVariantList shortcutCatalog() const;
    Q_INVOKABLE QString shortcutForKey(int key, int modifiers) const;
    Q_INVOKABLE QVariantList shortcutConflicts(const QString& name, const QString& shortcut) const;
    Q_INVOKABLE bool assignShortcut(const QString& name, const QString& shortcut, bool replaceConflicts = false);
    Q_INVOKABLE QString choosePath(const QString& name);
    Q_INVOKABLE QString chooseColor(const QString& initial);
    Q_INVOKABLE QVariantMap describe(const QString& name) const;
    Q_INVOKABLE QVariant value(const QString& name) const;
    Q_INVOKABLE QVariant videoValue(const QString& name) const;
    Q_INVOKABLE bool isStaged(const QString& name) const;
    Q_INVOKABLE bool stage(const QString& name, const QVariant& value);
    Q_INVOKABLE void cancelLanguageEdit(const QString& name);
    Q_INVOKABLE void reset(const QString& name);
    Q_INVOKABLE void discard();
    Q_INVOKABLE bool save();
    Q_INVOKABLE bool resetAll();
    Q_INVOKABLE QVariantList catalog(const QString& category, const QString& search = QString()) const;
signals:
    void ctxChanged();
    void autoSaveChanged();
    void changed();
    void stereoTestChanged();
private:
    struct Entry { QString name, category, title; };
    QString audioOutputModule() const;
    QVariantList audioDeviceChoices() const;
    static QVariant read(const QByteArray& name);
    static void write(const QByteArray& name, const QVariant& value);
    QVariantMap playerPresetState() const;
    QVariantMap playerPresetOptions() const;
    bool storePlayerPresetState(const QVariantMap& state);
    bool playerPresetError(const QString& message);
    bool stagePlayerPresetOptions(const QVariantMap& options);
    void updateStereoTest();
    void finishStereoTest(const QString& message = {});
    MainCtx* m_ctx = nullptr;
    QVariantMap m_edits;
    QSet<QString> m_invalid;
    QList<Entry> m_catalog;
    QString m_error;
    int m_revision = 0;
    bool m_autoSave = false;
    bool m_editPlayerPreset = false;
    bool m_presetTransaction = false;
    QVariantMap m_editsBeforePreset;
    QTimer m_saveTimer;
    QTimer m_stereoTestTimer;
    QElapsedTimer m_stereoTestElapsed;
    std::unique_ptr<StereoTestPlayer> m_stereoTest;
    QString m_stereoTestMessage;
};
#endif
