#!/usr/bin/env python3
"""Публикация статьи в Telegraph.

Запуск:
    python tool/publish_telegraph.py --dry-run   # показать, что уйдёт на сервер
    python tool/publish_telegraph.py             # создать или обновить страницу

Что делает:
  * читает docs/telegraph_article.md;
  * превращает его в формат Telegraph (h3/h4, абзацы, списки, жирный, ссылки);
  * загружает картинки из строк вида `![подпись](screenshots/файл.png)` на
    хостинг Telegraph и подставляет их адреса;
  * при первом запуске создаёт анонимный аккаунт и сохраняет токен в
    docs/.telegraph_state.json, при следующих — обновляет ту же страницу;
  * печатает адрес страницы.

Почему не через Telegram-аккаунт: у API нет входа по аккаунту, он выдаёт
отдельный токен. Токен лежит рядом и позволяет править страницу позже.

Важно про Telegraph в России: домен telegra.ph бывает недоступен без VPN.
Если скрипт не может подключиться — это блокировка, а не ошибка статьи.
"""

from __future__ import annotations

import argparse
import json
import re
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ARTICLE = ROOT / "docs" / "telegraph_article.md"
STATE = ROOT / "docs" / ".telegraph_state.json"

API = "https://api.telegra.ph"
# Картинки грузятся на сам Telegraph: у API отдельного хостинга нет, а этот
# эндпоинт использует редактор telegra.ph. Он недокументированный, но рабочий;
# при недоступности домена (бывает в России без VPN) скрипт скажет об этом.
TELEGRAPH = "https://telegra.ph"
AUTHOR = "PRAXIS"

# Telegraph поддерживает только h3 и h4 — заголовков h1/h2 в нём нет,
# а таблиц нет вообще, поэтому статья написана списками.
INLINE = re.compile(r"(\*\*[^*]+\*\*|\[[^\]]+\]\([^)]+\))")

IMAGE = re.compile(r"^!\[([^\]]*)\]\(([^)]+)\)$")


def inline_nodes(text: str) -> list:
    """Разбирает жирный текст и ссылки внутри абзаца."""
    nodes: list = []
    for part in INLINE.split(text):
        if not part:
            continue
        if part.startswith("**") and part.endswith("**"):
            nodes.append({"tag": "b", "children": [part[2:-2]]})
        elif part.startswith("[") and "](" in part:
            label, url = part[1:-1].split("](", 1)
            nodes.append({"tag": "a", "attrs": {"href": url}, "children": [label]})
        else:
            nodes.append(part)
    return nodes


def markdown_to_nodes(markdown: str) -> tuple[str, list]:
    """Возвращает заголовок страницы и список узлов."""
    title = "Без названия"
    nodes: list = []
    paragraph: list[str] = []
    bullets: list[str] = []

    def flush_paragraph() -> None:
        if paragraph:
            nodes.append({"tag": "p", "children": inline_nodes(" ".join(paragraph))})
            paragraph.clear()

    def flush_bullets() -> None:
        if bullets:
            nodes.append({
                "tag": "ul",
                "children": [{"tag": "li", "children": inline_nodes(item)} for item in bullets],
            })
            bullets.clear()

    for raw in markdown.split("\n"):
        line = raw.rstrip()

        if not line.strip():
            flush_paragraph()
            flush_bullets()
            continue

        if line.startswith("# "):
            flush_paragraph()
            flush_bullets()
            title = line[2:].strip()
            continue

        if line.startswith("## "):
            flush_paragraph()
            flush_bullets()
            nodes.append({"tag": "h3", "children": inline_nodes(line[3:].strip())})
            continue

        if line.startswith("### "):
            flush_paragraph()
            flush_bullets()
            nodes.append({"tag": "h4", "children": inline_nodes(line[4:].strip())})
            continue

        image = IMAGE.match(line.strip())
        if image:
            flush_paragraph()
            flush_bullets()
            caption, source = image.group(1), image.group(2)
            children: list = [{"tag": "img", "attrs": {"src": ""}}]
            if caption:
                children.append({"tag": "figcaption", "children": [caption]})
            # Локальный путь до файла живёт в attrs до публикации: Telegraph
            # не принимает свои же узлы с лишними полями, поэтому в конце
            # дерево чистится.
            nodes.append({"tag": "figure", "attrs": {"data-local": source}, "children": children})
            continue

        if line.startswith("- "):
            flush_paragraph()
            bullets.append(line[2:].strip())
            continue

        # Продолжение абзаца: строки склеиваются в один узел.
        paragraph.append(line.strip())

    flush_paragraph()
    flush_bullets()
    return title, nodes


def call(method: str, payload: dict) -> dict:
    data = urllib.parse.urlencode(payload).encode()
    request = urllib.request.Request(f"{API}/{method}", data=data)
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read().decode())


def upload_image(path: Path) -> str:
    """Загружает картинку на Telegraph и возвращает её публичный адрес."""
    boundary = "----praxis" + uuid.uuid4().hex
    body = b"".join([
        f"--{boundary}\r\n".encode(),
        f'Content-Disposition: form-data; name="file"; filename="{path.name}"\r\n'.encode(),
        b"Content-Type: application/octet-stream\r\n\r\n",
        path.read_bytes(),
        f"\r\n--{boundary}--\r\n".encode(),
    ])

    request = urllib.request.Request(
        f"{TELEGRAPH}/upload",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        result = json.loads(response.read().decode())

    # Ответ вида [{"src": "/file/xxxx.png"}]
    return TELEGRAPH + result[0]["src"]


def prepare_images(nodes: list, skip_missing: bool, cache: dict) -> list[str]:
    """Загружает локальные картинки и подставляет их адреса в узлы.

    Уже загруженные файлы берутся из кеша в состоянии: иначе каждый повторный
    запуск заливал бы те же скриншоты заново и плодил дубликаты на хостинге.
    Кеш учитывает размер и время изменения — если файл пересняли, он загрузится
    снова.
    """
    missing: list[str] = []

    # Сначала проверяем все пути и только потом грузим: иначе при одном
    # отсутствующем файле часть картинок уже уедет на хостинг впустую.
    pending: list[tuple[dict, str, Path]] = []

    for node in nodes:
        if node.get("tag") != "figure":
            continue

        source = node.get("attrs", {}).get("data-local", "")

        # Готовая ссылка: картинка уже где-то лежит, грузить её не нужно.
        # Так можно держать скриншоты на своём хостинге, а не у Telegraph.
        if source.startswith(("http://", "https://")):
            node["children"][0]["attrs"]["src"] = source
            del node["attrs"]["data-local"]
            if not node["attrs"]:
                del node["attrs"]
            print(f"  внешняя ссылка: {source}")
            continue

        # Путь в метке пишется относительно самой статьи (она в docs/),
        # как и принято в Markdown. Абсолютные пути тоже принимаются.
        path = Path(source) if Path(source).is_absolute() else ARTICLE.parent / source

        if not path.exists():
            missing.append(source)
            continue

        pending.append((node, source, path))

    if missing and not skip_missing:
        raise SystemExit(
            "не найдены картинки:\n  " + "\n  ".join(missing) +
            "\nПоложите их по этим путям или запустите с --skip-missing-images, "
            "чтобы опубликовать без них."
        )

    for node, source, path in pending:
        stat = path.stat()
        cached = cache.get(source)
        if cached and cached.get("size") == stat.st_size and cached.get("mtime") == stat.st_mtime:
            node["children"][0]["attrs"]["src"] = cached["url"]
            print(f"  из кеша: {source}")
        else:
            try:
                url = upload_image(path)
            except Exception as error:  # noqa: BLE001 — нужен понятный текст
                raise SystemExit(
                    f"не удалось загрузить {source}: {error}\n"
                    "Скорее всего домен telegra.ph недоступен (в России бывает нужен "
                    "VPN) или изменился эндпоинт загрузки картинок.\n"
                    "Можно опубликовать без картинок: --skip-missing-images, "
                    "а сами картинки добавить вручную в редакторе Telegraph."
                ) from error
            cache[source] = {"url": url, "size": stat.st_size, "mtime": stat.st_mtime}
            node["children"][0]["attrs"]["src"] = url
            print(f"  загружено: {source}")

        del node["attrs"]["data-local"]
        # Пустой attrs Telegraph может не принять — убираем ключ целиком.
        if not node["attrs"]:
            del node["attrs"]

    if missing:
        # Убираем узлы без картинок, чтобы не осталось пустых рамок.
        nodes[:] = [
            node for node in nodes
            if node.get("tag") != "figure" or "data-local" not in node.get("attrs", {})
        ]
        print(f"пропущено картинок: {len(missing)}")

    return missing


def load_state() -> dict:
    if STATE.exists():
        return json.loads(STATE.read_text(encoding="utf-8"))
    return {}


def save_state(state: dict) -> None:
    STATE.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Публикация статьи в Telegraph")
    parser.add_argument("--dry-run", action="store_true",
                        help="показать содержимое, ничего не публикуя")
    parser.add_argument("--title", help="переопределить заголовок страницы")
    parser.add_argument("--skip-missing-images", action="store_true",
                        help="опубликовать без картинок, которых нет на диске")
    args = parser.parse_args()

    if not ARTICLE.exists():
        raise SystemExit(f"нет статьи: {ARTICLE}")

    title, nodes = markdown_to_nodes(ARTICLE.read_text(encoding="utf-8"))
    if args.title:
        title = args.title

    figures = [node for node in nodes if node.get("tag") == "figure"]

    if args.dry_run:
        print(f"заголовок: {title}")
        print(f"узлов: {len(nodes)}, картинок: {len(figures)}")
        for node in figures:
            caption = ""
            for child in node["children"]:
                if child.get("tag") == "figcaption":
                    caption = child["children"][0]
            print(f"  картинка: {node['attrs']['data-local']}" + (f" — {caption}" if caption else ""))
        return

    state = load_state()

    if figures:
        print(f"картинок к загрузке: {len(figures)}")
        cache = state.setdefault("images", {})
        prepare_images(nodes, args.skip_missing_images, cache)
        save_state(state)

    if not state.get("access_token"):
        account = call("createAccount", {"short_name": "praxis", "author_name": AUTHOR})
        if not account.get("ok"):
            raise SystemExit(f"не удалось создать аккаунт: {account}")
        state["access_token"] = account["result"]["access_token"]
        save_state(state)
        print("создан аккаунт Telegraph, токен сохранён в docs/.telegraph_state.json")

    payload = {
        "access_token": state["access_token"],
        "title": title,
        "author_name": AUTHOR,
        "content": json.dumps(nodes, ensure_ascii=False),
        "return_content": "false",
    }

    if state.get("path"):
        payload["path"] = state["path"]
        result = call("editPage", payload)
        action = "обновлена"
    else:
        result = call("createPage", payload)
        action = "опубликована"

    if not result.get("ok"):
        raise SystemExit(f"Telegraph ответил ошибкой: {result}")

    page = result["result"]
    state["path"] = page["path"]
    state["url"] = page["url"]
    save_state(state)

    print(f"страница {action}: {page['url']}")


if __name__ == "__main__":
    main()
