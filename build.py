"""Build Ruby Playground.

Writes index.html and the engine/ folder it loads Ruby from. Both are committed,
so a fresh clone runs as-is; run this after changing anything in src/.

The Ruby engine comes from the ruby.wasm project's npm packages. The first build
downloads the pinned files into vendor/ and checks their SHA-256.

    python3 build.py              # rebuild index.html and engine/
    python3 build.py --bare DIR   # also write DIR/ruby-playground.html without the
                                  # <html>/<head>/<body> skeleton, plus DIR/engine/,
                                  # for hosts that wrap pages in their own skeleton
"""
import argparse
import gzip
import hashlib
import json
import pathlib
import shutil
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent
VENDOR = ROOT / "vendor"
ENGINE = ROOT / "engine"
PIECES = 20

INPUTS = {
    "ruby.wasm": (
        "https://cdn.jsdelivr.net/npm/@ruby/4.0-wasm-wasi@2.10.1/dist/ruby.wasm",
        "84504b924bbaa5745c8280d711a1f0597d6374969b5a324d7e53994f32a94d32",
    ),
    "ruby-wasm-wasi.umd.js": (
        "https://cdn.jsdelivr.net/npm/@ruby/wasm-wasi@2.10.1/dist/browser.umd.js",
        "43d796d63912dc7bf45b0a442c2d05a1419249eacee6c188ea9460b31e41c779",
    ),
}

SKELETON = (
    '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
    '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
    "</head>\n<body>\n"
)


def vendored(name):
    url, digest = INPUTS[name]
    path = VENDOR / name
    if not path.exists():
        VENDOR.mkdir(exist_ok=True)
        print(f"downloading {url}")
        with urllib.request.urlopen(url, timeout=120) as response:
            path.write_bytes(response.read())
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != digest:
        path.unlink()
        raise SystemExit(f"{name}: SHA-256 is {actual}, expected {digest}. Deleted it; run the build again.")
    return path


def build_engine():
    shutil.rmtree(ENGINE, ignore_errors=True)
    ENGINE.mkdir()
    packed = gzip.compress(vendored("ruby.wasm").read_bytes(), compresslevel=9, mtime=0)
    size = -(-len(packed) // PIECES)
    names = []
    for index in range(PIECES):
        name = f"engine/ruby.part{index + 1:02d}.wasm"
        (ROOT / name).write_bytes(packed[index * size:(index + 1) * size])
        names.append(name)
    shutil.copy2(vendored("ruby-wasm-wasi.umd.js"), ENGINE / "ruby-wasm-wasi.umd.js")
    print(f"engine: {len(packed)} bytes in {PIECES} pieces of up to {size} bytes")
    return names, len(packed)


def build_page(names, total):
    page = (ROOT / "src/page.html").read_text()
    prelude = (ROOT / "src/prelude.rb").read_text().rstrip("\n")
    for marker in ("__PRELUDE__", "__ENGINE_PARTS__", "__ENGINE_BYTES__"):
        if marker not in page:
            raise SystemExit(f"src/page.html is missing {marker}")
    return (page.replace("__PRELUDE__", prelude)
                .replace("__ENGINE_PARTS__", json.dumps(names))
                .replace("__ENGINE_BYTES__", str(total)))


def main():
    parser = argparse.ArgumentParser(description="Build Ruby Playground.")
    parser.add_argument("--bare", metavar="DIR", help="also write a skeleton-free copy to DIR")
    args = parser.parse_args()

    names, total = build_engine()
    body = build_page(names, total)
    (ROOT / "index.html").write_text(SKELETON + body + "\n</body>\n</html>\n")
    print("wrote index.html")

    if args.bare:
        out = pathlib.Path(args.bare)
        shutil.rmtree(out, ignore_errors=True)
        out.mkdir(parents=True)
        (out / "ruby-playground.html").write_text(body)
        shutil.copytree(ENGINE, out / "engine")
        print(f"wrote {out}/ruby-playground.html and {out}/engine/")


if __name__ == "__main__":
    main()
