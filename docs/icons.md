# Иконки и брендинг

Исходник — `branding/app_icon_source.png` (логотип PRAXIS на чёрном фоне). Все иконки генерируются из него одной командой:

```bash
python tool/generate_app_icons.py
```

Нужны `numpy` и `Pillow`:

```bash
pip install -r tool/requirements.txt
``` Обновить только один набор можно, указав цель:

```bash
python tool/generate_app_icons.py web      # favicon и иконки PWA
python tool/generate_app_icons.py android  # Android
python tool/generate_app_icons.py ios      # iOS
python tool/generate_app_icons.py store    # Play Store
python tool/generate_app_icons.py preview  # картинка-предпросмотр масок
```

Скрипт превращает чёрный фон исходника в прозрачность, восстанавливая цвет пикселей (они уже смешаны с чёрным, поэтому цвет делится на альфу — иначе края потемнеют), обрезает логотип по содержимому и центрирует его в квадрате.

## Что получается

| Что | Куда | Фон | Размер логотипа |
|---|---|---|---|
| Обычная иконка (Android < 8 и запасной вариант) | `android/app/src/main/res/mipmap-*/ic_launcher.png` | чёрный | 92 % канвы |
| Адаптивный слой (Android 8+) | `.../mipmap-*/ic_launcher_foreground.png` | прозрачный | 64 % канвы |
| Тематическая иконка (Android 13+) | `.../mipmap-*/ic_launcher_monochrome.png` | прозрачный | 64 % канвы |
| Описание адаптивной иконки | `.../mipmap-anydpi-v26/ic_launcher.xml`, `ic_launcher_round.xml` | — | — |
| Цвет фона | `.../res/values/ic_launcher_background.xml` | — | — |
| Набор iOS | `ios/Runner/Assets.xcassets/AppIcon.appiconset/` | чёрный | 92 % |
| Play Store | `branding/generated/play_store_512.png` | чёрный | 86 % |
| Favicon | `web/favicon.png` (48×48) | чёрный | 92 % |
| Иконки PWA | `web/icons/Icon-192.png`, `Icon-512.png` | чёрный | 92 % |
| Maskable-иконки PWA | `web/icons/Icon-maskable-192.png`, `Icon-maskable-512.png` | чёрный, во всю канву | 64 % |
| Предпросмотр масок | `branding/generated/preview_masks.png` | — | — |

Почему у адаптивного слоя логотип меньше: Android гарантирует видимость только центральных 72dp из 108dp, то есть 66.7 % канвы. Логотип занимает 64 %, поэтому золотая орбита не обрезается даже самой агрессивной круглой маской лаунчера. Предпросмотр с реальными размерами масок лежит в `branding/generated/preview_masks.png` — его рисует тот же скрипт.

## Ограничение исходника

Он 432×413, поэтому:

- иконки Android (до 432px) получаются уменьшением — резкие;
- `play_store_512.png` и iOS `1024×1024` — увеличение в 1.2 и 2.4 раза, то есть заметно мягче. Для публикации в магазинах нужен исходник от 1024×1024 (лучше вектор): положите его в `branding/app_icon_source.png` и запустите скрипт заново.

После смены иконки лаунчер Android может показывать старую из кеша: помогает переустановка приложения (`flutter install` или удалить и поставить заново).

## Цвета

Фон иконок — чёрный (`BLACK` в скрипте), он совпадает с фоном исходного логотипа. Тёмная тема приложения использует `#0F1015`, но иконка остаётся на чистом чёрном: так логотип выглядит контрастнее и совпадает с уже опубликованными иконками Android и iOS.

Если меняете палитру, помните: `web/manifest.json` задаёт `background_color` и `theme_color` для PWA, а `lib/theme/app_theme.dart` — цвета самого приложения.
