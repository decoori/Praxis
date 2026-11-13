# Релиз Android

Идентификатор приложения — **`com.praxis.game`**. После первой публикации в Google Play он не меняется никогда, поэтому менять его можно только до релиза. При смене идентификатора обновление «поверх» уже установленной сборки не встанет — приложение придётся переставлять заново.

## Подпись

Релиз подписывается собственным ключом, а не отладочным:

- ключ: `android/praxis-release.jks`, alias `praxis`, действует до 2054 года;
- пароли: `android/key.properties`.

Оба файла перечислены в `.gitignore` и в репозиторий не попадают. Без `android/key.properties` сборка релиза подпишется отладочным ключом (`CN=Android Debug`) — такой APK не примет Google Play.

**Ключ и пароль нужно сохранить в двух местах.** Если они потеряются, выпустить обновление приложения будет невозможно: Google Play принимает только сборки, подписанные тем же ключом, что и первая. Восстановить ключ нельзя.

## Сборка

```bash
# Отдельные APK под каждый тип процессора
flutter build apk --release --split-per-abi

# Универсальный APK на все процессоры (крупнее)
flutter build apk --release

# Bundle для Google Play
flutter build appbundle --release
```

Что отдавать людям напрямую: **`app-arm64-v8a-release.apk`** (~19 МБ) — он подходит всем телефонам примерно с 2017 года. Универсальный `app-release.apk` (~53 МБ) встанет на любой аппарат, но весит как три отдельных вместе.

Ключи Supabase попадают в сборку через `--dart-define`:

```bash
flutter build apk --release --split-per-abi --dart-define-from-file=env.json
```

Без этого соберётся приложение с экраном настройки вместо игры.

## Версионирование

Версия берётся из `pubspec.yaml` (`version: 1.0.0+1`). Число после `+` — это `versionCode`, и для каждой следующей публикации оно должно расти: `1.0.1+2`, `1.0.1+3` и так далее.

В сборках `--split-per-abi` Flutter сам добавляет к коду номер типа процессора: 1000 для armeabi-v7a, 2000 для arm64-v8a, 3000 для x86_64. Поэтому у arm64-сборки код 2001, а у универсальной — 1.

## Проверка готового файла

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\36.0.0\aapt2.exe" dump badging app-arm64-v8a-release.apk |
  Select-String "^package"
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\36.0.0\apksigner.bat" verify --print-certs app-arm64-v8a-release.apk
```

Ожидаемо: `package: name='com.praxis.game'` и подпись `CN=PRAXIS, OU=Game, O=PRAXIS, L=Moscow, C=RU`, а не `CN=Android Debug`.

## Чек-лист перед публикацией

- [ ] `version` в `pubspec.yaml` поднят, `versionCode` больше предыдущего.
- [ ] `flutter analyze` и `flutter test` зелёные.
- [ ] Сборка сделана с `--dart-define-from-file=env.json`.
- [ ] `aapt2 dump badging` показывает `com.praxis.game`.
- [ ] `apksigner verify --print-certs` показывает релизную подпись.
- [ ] Иконки и название обновлены (см. `tool/generate_app_icons.py`).
- [ ] Ключи `key.properties` и `.jks` не попали в репозиторий.
