# 開発者向けドキュメント

## 現行の契約と検証

公開 API の使用例は [利用ガイド](../user/guides/usage.md) にあります。生成経路は Quint を実行して ITF を用意し、保存済み ITF と同じ再生処理に渡します。Rust は ITF の解釈、処理順、作業先と成果物を担当します。PyO3 は Python コールバックと例外を扱います。

| 対象 | Quint で表す契約 | 実装を検証するテスト |
| --- | --- | --- |
| `run()` の生成 | シミュレーション、名前の完全一致、正規表現による一括選択を CLI 引数に変換する。[CLI モデル](../../spec/quint_cli.qnt) | 両評価器での生成と一括選択。[Python 結合テスト](../../tests/test_quint_integration.py) |
| `run()` と `replay()` の ITF | 操作・引数・比較対象を読み取り、トレースをドライバー起動前に検証する。値の正規化と等値性を定める。[ITF モデル](../../spec/quint_itf.qnt) · [値モデル](../../spec/quint_values.qnt) | 不正な末尾、操作引数のスナップショット、複合値の照合。[Python 再生テスト](../../tests/test_replay.py) |
| 既定の状態比較と失敗の優先順位 | 操作の適用、観測、等値比較、最初の失敗への診断の付加を一連の処理として扱う。[主モデル](../../spec/quint_connect.qnt) | 同じランナーに生成済み fixture の入出力を与える。[Rust 照合テスト](../../src/conformance.rs) · [fixture の生成手順](../../spec/fixtures/README.md) |
| `comparison=None` と `StateComparison` | 操作だけの再生では観測を省略し、独自比較の採否や例外でステップの結果を決める。[比較モデル](../../spec/quint_replay_comparison_test.qnt) | 省略時の検証、期待値の変換、独自比較の採否、比較例外の ITF 保存と再生。[Python 再生テスト](../../tests/test_replay.py) · [Python 結合テスト](../../tests/test_quint_integration.py) |
| `driver_context=` と例外 | トレースごとの開始と終了を対応させ、終了に失敗しても先に確定した失敗を優先する。[寿命モデル](../../spec/quint_driver_lifecycle.qnt) | `__exit__` と呼び出し元での不一致例外の同一性、注記、終了失敗の扱い。[Python 再生テスト](../../tests/test_replay.py) |
| 作業先と失敗 ITF | 作業先の分離、保存先の排他確保、部分書き込み、コピー・清掃失敗時の優先順位を扱う。[ファイルシステムモデル](../../spec/quint_filesystem.qnt) · [成果物のシナリオ](../../spec/quint_artifact_directory_test.qnt) | 既存成果物の保持、失敗 ITF の再生、ワーカー間の保存先分離。[fixture](../../spec/fixtures/README.md) · [Python 結合テスト](../../tests/test_quint_integration.py) · [xdist テスト](../../tests/test_xdist.py) |

主モデルが照合 fixture にする比較方式は既定の等値比較です。比較モデルは一つのステップに絞り、観測と独自比較の結果を外部入力として扱います。比較とドライバーの終了、成果物保存の組み合わせは Python の結合テストで確認します。Python 例外の型・属性・同一性と、ログや差分の表示は [Python 再生テスト](../../tests/test_replay.py) が担当します。

## 設計履歴

- [初期設計と受け入れ条件](work/initial-design/design.md)
- [初版の Quint 仕様レビュー](work/initial-design/spec-review.md)
- [初版の実装計画](work/initial-design/plan.md)

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
