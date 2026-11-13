#!/usr/bin/env python3
"""Генерация иконок приложения PRAXIS из одного исходника.

Запуск:
    python tool/generate_app_icons.py

Что делает
----------
1. Превращает чёрный фон исходника в прозрачность и восстанавливает цвет
   (исходные пиксели уже смешаны с чёрным, поэтому цвет делится на альфу —
   иначе края логотипа потемнеют).
2. Обрезает по содержимому и центрирует в квадрате.
3. Android:
   * обычные иконки mipmap-*/ic_launcher.png (чёрный фон, логотип крупно);
   * адаптивные слои mipmap-*/ic_launcher_foreground.png (прозрачный фон,
     логотип меньше — с запасом под маску лаунчера);
   * mipmap-anydpi-v26/ic_launcher.xml и ic_launcher_round.xml;
   * monochrome-слой для тематических иконок Android 13+;
   * values/ic_launcher_background.xml (чёрный фон).
4. iOS: AppIcon.appiconset по списку из Contents.json (непрозрачные, без альфы).
5. Play Store: 512x512 в branding/generated/.
6. Web: favicon.png и иконки PWA в web/icons/ (обычные и maskable).

Почему не flutter_launcher_icons
--------------------------------
Нужны два разных масштаба логотипа (адаптивный слой обязан оставлять запас
под маску, обычная иконка не маскируется и может быть крупнее), а исходник
не квадратный и лежит на чёрном фоне. Плюс так видно, что именно попадает
в APK, и ничего не зависит от версии стороннего пакета.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "branding" / "app_icon_source.png"
RES = ROOT / "android" / "app" / "src" / "main" / "res"
IOS = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
GENERATED = ROOT / "branding" / "generated"
WEB = ROOT / "web"

# Доля квадрата, которую занимает логотип.
#
# Адаптивный слой: Android гарантирует видимость только центральных 72dp
# из 108dp, то есть 66.7 % канвы. Логотип занимает 64 %, чтобы даже самые
# края золотой орбиты оставались внутри этой зоны.
ADAPTIVE_SCALE = 0.64
LEGACY_SCALE = 0.92    # обычная иконка не маскируется
IOS_SCALE = 0.92       # iOS скругляет углы сам
STORE_SCALE = 0.86     # в магазине иконку показывают целиком

# Реальные размеры масок лаунчеров, в долях от канвы адаптивной иконки.
MASK_GUARANTEED = 0.667  # гарантированная зона Android: 72dp из 108dp
MASK_TYPICAL = 0.80      # типичная круглая маска лаунчера
MASK_SQUIRCLE = 0.92     # маска-скруглённый квадрат

BLACK = (0, 0, 0, 255)
TRANSPARENT = (0, 0, 0, 0)

# плотность -> размер обычной иконки (48dp)
LEGACY_SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

# плотность -> размер слоя адаптивной иконки (108dp)
ADAPTIVE_SIZES = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}


def load_logo() -> Image.Image:
    """Логотип с прозрачным фоном, обрезанный по содержимому."""
    im = Image.open(SRC).convert("RGBA")
    arr = np.asarray(im).astype(np.float32)

    rgb = arr[..., :3]
    alpha = rgb.max(axis=2)

    # Восстановление цвета: пиксель на чёрном фоне хранит уже умноженный цвет.
    safe = np.maximum(alpha, 1.0)[..., None]
    restored = np.clip(rgb / (safe / 255.0), 0, 255)

    out = np.dstack([restored, alpha]).astype(np.uint8)
    logo = Image.fromarray(out, "RGBA")

    bbox = logo.getchannel("A").point(lambda v: 255 if v > 12 else 0).getbbox()
    if bbox is None:
        raise SystemExit("в исходнике не нашлось содержимого")
    return logo.crop(bbox)


def square(logo: Image.Image, size: int, scale: float, background) -> Image.Image:
    """Логотип по центру квадрата заданного размера."""
    w, h = logo.size
    side = max(w, h)

    centered = Image.new("RGBA", (side, side), TRANSPARENT)
    centered.paste(logo, ((side - w) // 2, (side - h) // 2), logo)

    target = max(1, int(round(size * scale)))
    scaled = centered.resize((target, target), Image.LANCZOS)

    canvas = Image.new("RGBA", (size, size), background)
    offset = (size - target) // 2
    canvas.alpha_composite(scaled, (offset, offset))
    return canvas


def monochrome(logo: Image.Image, size: int, scale: float) -> Image.Image:
    """Силуэт логотипа: тематические иконки Android 13+ красят его сами."""
    white = Image.new("RGBA", logo.size, (255, 255, 255, 0))
    white.putalpha(logo.getchannel("A"))
    return square(white, size, scale, TRANSPARENT)


ANDROID_ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<!-- Адаптивная иконка (Android 8+). Фон — чёрный, как в исходном логотипе;
     логотип лежит отдельным слоем с запасом под маску лаунчера. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
"""

BACKGROUND_XML = """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Чёрный фон иконки: такой же, как в исходном логотипе. -->
    <color name="ic_launcher_background">#000000</color>
</resources>
"""


def write_android(logo: Image.Image) -> list[str]:
    written = []

    for density, size in LEGACY_SIZES.items():
        folder = RES / f"mipmap-{density}"
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / "ic_launcher.png"
        # Обычные иконки делаем без альфы: старые лаунчеры с ней плохо дружат.
        square(logo, size, LEGACY_SCALE, BLACK).convert("RGB").save(path, optimize=True)
        written.append(str(path.relative_to(ROOT)))

    for density, size in ADAPTIVE_SIZES.items():
        folder = RES / f"mipmap-{density}"
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / "ic_launcher_foreground.png"
        square(logo, size, ADAPTIVE_SCALE, TRANSPARENT).save(path, optimize=True)
        written.append(str(path.relative_to(ROOT)))

        path = folder / "ic_launcher_monochrome.png"
        monochrome(logo, size, ADAPTIVE_SCALE).save(path, optimize=True)
        written.append(str(path.relative_to(ROOT)))

    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        path = anydpi / name
        path.write_text(ANDROID_ADAPTIVE_XML, encoding="utf-8")
        written.append(str(path.relative_to(ROOT)))

    path = RES / "values" / "ic_launcher_background.xml"
    path.write_text(BACKGROUND_XML, encoding="utf-8")
    written.append(str(path.relative_to(ROOT)))

    return written


def write_ios(logo: Image.Image) -> list[str]:
    written = []
    contents = json.loads((IOS / "Contents.json").read_text(encoding="utf-8"))

    for entry in contents.get("images", []):
        filename = entry.get("filename")
        if not filename:
            continue

        side = float(entry["size"].split("x")[0])
        scale = int(entry["scale"].rstrip("x"))
        pixels = int(round(side * scale))

        # iOS не принимает альфу в иконке приложения.
        path = IOS / filename
        square(logo, pixels, IOS_SCALE, BLACK).convert("RGB").save(path, optimize=True)
        written.append(str(path.relative_to(ROOT)))

    return written


def write_store(logo: Image.Image) -> list[str]:
    GENERATED.mkdir(parents=True, exist_ok=True)
    path = GENERATED / "play_store_512.png"
    square(logo, 512, STORE_SCALE, BLACK).convert("RGB").save(path, optimize=True)
    return [str(path.relative_to(ROOT))]


def write_web(logo: Image.Image) -> list[str]:
    """Favicon и иконки PWA.

    Maskable-версии — с чёрным фоном во всю канву и логотипом в безопасной
    зоне: браузер сам обрежет иконку маской. Обычные иконки не маскируются,
    поэтому логотип на них крупнее.
    """
    icons = WEB / "icons"
    icons.mkdir(parents=True, exist_ok=True)
    written = []

    for size in (192, 512):
        path = icons / f"Icon-{size}.png"
        square(logo, size, LEGACY_SCALE, BLACK).save(path, optimize=True)
        written.append(str(path.relative_to(ROOT)))

        path = icons / f"Icon-maskable-{size}.png"
        square(logo, size, ADAPTIVE_SCALE, BLACK).save(path, optimize=True)
        written.append(str(path.relative_to(ROOT)))

    path = WEB / "favicon.png"
    square(logo, 48, LEGACY_SCALE, BLACK).save(path, optimize=True)
    written.append(str(path.relative_to(ROOT)))

    return written


def write_preview(logo: Image.Image) -> list[str]:
    """Картинка для проверки глазами: как иконка выглядит в масках лаунчеров.

    Маски нарисованы в реальных размерах, а не во всю канву: круглая маска
    лаунчера обрезает иконку до 66.7 % (гарантированная зона Android), и
    предпросмотр во всю ширину показывал бы неправду.
    """
    panel = 216
    gap = 12

    def masked(tile: Image.Image, ratio: float, shape: str) -> Image.Image:
        from PIL import ImageDraw

        size = panel
        layer = Image.new("L", (size, size), 0)
        draw = ImageDraw.Draw(layer)

        visible = int(size * ratio)
        offset = (size - visible) // 2
        box = (offset, offset, offset + visible - 1, offset + visible - 1)

        if shape == "circle":
            draw.ellipse(box, fill=255)
        else:
            draw.rounded_rectangle(box, radius=int(visible * 0.24), fill=255)

        out = tile.copy()
        out.putalpha(layer)
        return out

    adaptive_tile = Image.alpha_composite(
        Image.new("RGBA", (panel, panel), BLACK),
        square(logo, panel, ADAPTIVE_SCALE, TRANSPARENT),
    )

    tiles = [
        # Худший случай: маска ужимает до гарантированной зоны 72dp из 108dp.
        masked(adaptive_tile, MASK_GUARANTEED, "circle"),
        masked(adaptive_tile, MASK_TYPICAL, "circle"),
        masked(adaptive_tile, MASK_SQUIRCLE, "squircle"),
        # Обычная иконка: не маскируется вовсе.
        square(logo, panel, LEGACY_SCALE, BLACK),
    ]

    width = panel * len(tiles) + gap * (len(tiles) + 1)
    preview = Image.new("RGBA", (width, panel + gap * 2), (32, 34, 40, 255))
    for index, tile in enumerate(tiles):
        preview.alpha_composite(tile, (gap + index * (panel + gap), gap))

    GENERATED.mkdir(parents=True, exist_ok=True)
    path = GENERATED / "preview_masks.png"
    preview.convert("RGB").save(path, optimize=True)
    return [str(path.relative_to(ROOT))]


def report_margins(logo: Image.Image) -> None:
    """Печатает, сколько места логотип оставляет по краям. Данные вместо глаз."""
    for label, size, scale in (
        ("обычная иконка xxxhdpi", LEGACY_SIZES["xxxhdpi"], LEGACY_SCALE),
        ("адаптивный слой xxxhdpi", ADAPTIVE_SIZES["xxxhdpi"], ADAPTIVE_SCALE),
    ):
        tile = square(logo, size, scale, BLACK)
        bbox = tile.convert("L").point(lambda v: 255 if v > 12 else 0).getbbox()
        if bbox is None:
            continue
        left, top, right, bottom = bbox
        print(
            f"  {label}: {size}px, содержимое {right - left}x{bottom - top}, "
            f"запас по краям {left}px / {size - right}px "
            f"({left / size * 100:.1f} %)"
        )


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"нет исходника: {SRC}")

    # Без аргументов обновляется всё. `python tool/generate_app_icons.py web`
    # пересобирает только favicon и иконки PWA.
    targets = {arg.lower() for arg in sys.argv[1:]} or {"all"}

    logo = load_logo()
    print(f"логотип: {logo.size[0]}x{logo.size[1]} после обрезки по содержимому")
    report_margins(logo)

    written = []
    if "all" in targets or "android" in targets:
        written += write_android(logo)
    if "all" in targets or "ios" in targets:
        written += write_ios(logo)
    if "all" in targets or "store" in targets:
        written += write_store(logo)
    if "all" in targets or "web" in targets:
        written += write_web(logo)
    if "all" in targets or "preview" in targets:
        written += write_preview(logo)

    if not written:
        raise SystemExit("неизвестная цель: укажите android, ios, store, web, preview или all")

    print(f"записано файлов: {len(written)}")


if __name__ == "__main__":
    main()
