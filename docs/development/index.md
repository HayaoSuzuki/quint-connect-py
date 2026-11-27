# 開発者向けドキュメント

- [初期設計と受け入れ条件](work/initial-design/design.md) — 公開 API、モジュールの責務、Quint と Python の検証の対応。
- [Quint の仕様](../../spec/quint_connect.qnt) — 生成と再生、失敗の優先順位、呼び出しごとの分離。
- [Quint の仕様レビュー](work/initial-design/spec-review.md) — 検証範囲、不変条件、実行結果。
- [Python 実装計画](work/initial-design/plan.md) — 仕様から実装と受け入れ試験への対応。

## 開発時の検証

hoimin と同じく Ruff は `ALL`、ty は全診断をエラーにする。Clippy は `all` と `pedantic` に加えて `nursery` を有効にする。検証にはリポジトリに記録したロックファイルを使う。

```sh
uv sync --locked --python 3.14 --group test --group lint
uv run --locked --group lint ruff check
uv run --locked --group lint ruff format --check
uv run --locked --group lint ty check
cargo fmt --check
cargo clippy --locked --no-default-features --all-targets -- -D warnings
PYO3_PYTHON="$PWD/.venv/bin/python" cargo clippy --locked --all-targets --all-features -- -D warnings
cargo test --locked --no-default-features
cargo test --locked --test upstream_reference -- --ignored
uv run --locked --group test pytest -q
python3 tools/export_quint_fixtures.py --check
```

`cargo test --lib conformance` は、Quint が生成したスキーマ v2 の各ケースを一つずつ本番の再生処理に渡す。公式 `quint-connect` の参照テストと Python の実機テストには、Quint 0.34.0 が必要となる。

## 配布物の検証

Maturin で sdist を作り、sdist から wheel をビルドする。同じ `cp314-abi3` wheel を CPython 3.14 と 3.15 の隔離環境に入れ、Quint と Node.js を探索できない状態で保存済み ITF を再生する。

```sh
uv build --python 3.14
python3 tools/check_wheel.py dist/quint_connect_py-*-cp314-abi3-*.whl
```

PyPI リリースでは、hoimin と同様に、プラットフォームごとの配布物を先にビルドして検証し、検証済みの同じファイルを TestPyPI と PyPI へ順に公開する。公開用の GitHub Actions 環境と Trusted Publishing はリリース時に設定する。
