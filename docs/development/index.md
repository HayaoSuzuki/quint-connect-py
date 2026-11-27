# 開発者向けドキュメント

- [初期設計と受け入れ条件](work/initial-design/design.md) — 公開 API、モジュールの責務、Quint と Python の検証の対応。
- [Quint の仕様](../../spec/quint_connect.qnt) — 生成と再生、失敗の優先順位、呼び出しごとの分離。
- [ドライバーの寿命](../../spec/quint_driver_lifecycle.qnt) — トレースごとの開始と終了、先に起きた失敗の優先順位。
- [Quint の仕様レビュー](work/initial-design/spec-review.md) — 検証範囲、不変条件、実行結果。
- [Python 実装計画](work/initial-design/plan.md) — 仕様から実装と受け入れ試験への対応。

## 開発時の検証

hoimin と同じく Ruff は `ALL`、ty は全診断をエラーにする。Clippy は `all` と `pedantic` に加えて `nursery` を有効にする。検証にはリポジトリに記録したロックファイルを使う。

```sh
uv sync --locked --python 3.14 --group test --group lint --group release
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

[リリースワークフロー](../../.github/workflows/release.yml)は Linux x86-64、macOS ARM64、Windows x86-64 の wheel と sdist をビルドする。wheel は両方の Python で、sdist はそこからビルドした wheel で、オフライン再生を確認する。公開対象のファイル名・バージョンと、PyPI が表示するメタデータも検査する。

初回は PyPI と TestPyPI のアカウントに `quint-connect-py` の Pending Trusted Publisher を登録する。所有者は `HayaoSuzuki`、リポジトリは `quint-connect-py`、ワークフローファイルは `release.yml` とする。Environment には公開先に応じて `pypi` または `testpypi` を指定し、GitHub 側で両 Environment を `main` に制限する。

```sh
gh workflow run release.yml --ref main
gh workflow run release.yml --ref main -f publish_version="$(uv version --short)"
```

バージョンを指定した実行では、同じコミットの CI 成功を確認してから、検証済みの各ファイルに SLSA ビルド来歴を付ける。TestPyPI に Trusted Publishing でアップロードし、取得し直したファイルが同一であり、ビルド来歴と公開アテステーションが有効であることを確認する。この検証が通過してから、同じファイルを PyPI へ公開し、同じ検証を行う。バージョンを空にした手動実行と PR では、ビルドからメタデータ検査までを実行する。

公開後の検証や後続ジョブで失敗した場合は、同じ実行の失敗したジョブを再実行する。アップロードが途中で失敗した場合は、先にインデックスで受理されたファイルを確認する。
