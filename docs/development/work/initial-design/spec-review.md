# Quint 仕様のレビュー

[再生モデル](../../../../spec/quint_connect.qnt) は複数の API 呼び出しの進行を表す。各呼び出しが選んだ操作パスと状態パスを固定し、CLI の計画、検証済みステップ、ドライバーの操作と観測、不一致の診断を記録する。共有のファイル状態では、作業先と保存先の所有関係を追跡する。

## 境界

| モジュール | 形式化した契約 | 実環境で確認する境界 |
| --- | --- | --- |
| [CLI](../../../../spec/quint_cli.qnt) | 実行ファイルの指定、モードごとの引数と既定値、符号なし 64 ビット seed、生成件数とサンプル・ステップの境界（最大値は JavaScript の安全な整数の上限）、名前付きテストの完全一致、生成ファイル名の認識と数値順 | OS 引数と文字列への変換、明示された相対パスの解決、子プロセスの実行と終了結果 |
| [UTF-8 と JSON](../../../../spec/quint_json.qnt) | UTF-8 の正当性、Unicode エスケープ、数値・文字列・リテラルの字句、配列とオブジェクトの構文、重複した項目を保持する節点列 | Rust のデコーダーが同じバイト列を受理・拒否すること |
| [ITF](../../../../spec/quint_itf.qnt) | 展開済みの同名キー、エンベロープと宣言変数、操作の取得元、選択パス、`#bigint` の十進構文、引数直下の `Some`・`None`、最初の不正ステップ | Rust の Unicode 文字列とモデルが扱うコードポイント列の対応 |
| [複合値](../../../../spec/quint_values.qnt) | 型を区別した等値性、反射律・対称律・推移律、順序付きのリストとタプル、順序に依存しない集合とマップ、任意精度の整数、複合キーの重複 | Rust の値表現と Python の値との変換 |
| [ファイルシステム](../../../../spec/quint_filesystem.qnt) | 一意な作業先、終了失敗後の部分出力、コピー途中の非公開状態、元バイト列の保存、掃除の対象範囲と部分失敗 | パスの解決、ディレクトリの排他的確保、OS の I/O エラー、ファイルの公開と削除 |
| [再生と診断](../../../../spec/quint_connect.qnt) | 構築したコマンドと予約先の対応、CLI 完了から ITF 選択への接続、保存済みパスの読み取り順と診断、検証後のドライバー生成、最初の不一致、保存後の同一バイト列からの再生 | pytest-xdist の実プロセス間分離、PyO3 を通した例外の型・属性・元の原因 |

JSON と複合値は、子を親より先に置いた有限の節点列で表す。JSON の文字とオブジェクトのキーは、UTF-8 やエスケープを展開したコードポイント列で表す。JSON 数値は文法を検査し、節点には数値であることを記録する。ITF の値として選んだ整数は `#bigint` の文字列から読む。ITF 入力では先頭の BOM と、対になっていないサロゲートのエスケープを拒否する。[RFC 3629 §4](https://www.rfc-editor.org/rfc/rfc3629#section-4) · [RFC 8259 §8](https://www.rfc-editor.org/rfc/rfc8259#section-8)

生成された ITF と、利用者が指定したパスの ITF は、同じ関数でバイト列を UTF-8、JSON、ITF の順に検証する。保存した成果物のパスも、利用者が指定したパスとして同じ手順で読み取る。Quint の文字列を操作名・選択パス・値に使うため、テストでは各コードポイント列に対応する文字列を有限の対応表で与える。その表が入力中の文字列をすべて含み、異なるコードポイント列に異なる文字列を割り当てることを検査する。Rust ではデコード時に対応する文字列を得る。

ファイルシステムは、解決済みのパスの識別、確保した専用ディレクトリの排他的な所有、呼び出しの外からのファイル変更がない状態を前提とする。クラッシュ時の永続性は OS 側の前提が必要となる。

Python 固有の契約として確認する項目は、例外の型、属性、元の原因に絞る。モデルが定める再生の振る舞いは公開 API から確認する。たとえば `StateMismatchError` の基底型は `AssertionError` で、トレース、ステップ、操作、期待値、実測値を読める。生成したトレースなら seed と保存先、または保存エラーを読める。ドライバーの例外は `__cause__` を確認する。配布とインストールは通常の受け入れ試験で確認する。[Rust 実装計画](plan.md)

## 不変条件

| 性質 | 検査すること |
| --- | --- |
| `replayInOrder` | 検証済みトレースごとにドライバーを生成し、操作名・引数・期待値を該当ステップと照合する |
| `firstFailureStopsReplay` | 最初の失敗から保存・掃除・結果の返却へ進む。保存済みパスの読み取りは先行 ITF の全ステップが一致した後に進む |
| `mismatchKeepsEvidence` | 元の不一致、対象トレース、seed、保存の結果を保持する |
| `consistentResult` | 成功には全トレースの検証と全ステップの一致を要求する。先行エラーと掃除失敗を保持する |
| `isolatedResources` | 予約した作業先とドライバーを呼び出し間で分離する。CLI の引数、seed と作業先を計画に照合する |
| `persistedEvidence` とファイル状態の不変条件 | 保存成功が元のバイト列を公開し、保存失敗が公開先を残さないことを確認する。掃除後も保存ファイルを読める |

## 実行結果

Quint 0.34.0 で全モジュールを型検査し、Rust と TypeScript の両評価器でそれぞれ **91 件**のシナリオが通った。内訳は生成と再生 24 件、保存済みパス 7 件、CLI 17 件、ファイルシステム 7 件、ITF 15 件、複合値 10 件、UTF-8 と JSON 10 件、四件の並行呼び出し 1 件。

複合値のテストでは、集合・マップ・リスト・タプルを対象に、要素数 0 から 3 までの順列の組をすべて照合した。入れ子を含む有効な 30 個の値を組み合わせ、等値性の反射律・対称律・推移律を検査した。

各評価器で、二件の呼び出しは最大 34 ステップで 5,000 サンプル、四件の呼び出しは最大 68 ステップで 1,000 サンプル、ファイルシステム単体は最大 28 ステップで 1,000 サンプルを検査した。二件のモデルは 15 個の観測条件すべてに到達し、各サンプルで二件とも終了した。四件のモデルはすべての作業先を確保してから各呼び出しの処理を進め、各サンプルで四件すべてが終了した。この範囲で不変条件の反例は出なかった。

結合シナリオでは、最大 seed で生成を開始し、10 番より 2 番を先に読み、不一致になった ITF を元のバイト列のまま保存する。作業先を掃除した後、返された保存先を通常のパス指定に渡し、同じ操作と値の不一致をパス付きで再現する。別のシナリオで、名前付きテストの明示操作、違うファイルのバイト列、構文エラー、CLI が失敗したときの部分出力を検査した。四件を並行させたシナリオでは、seed・ファイル名・成果物の親ディレクトリが同じ状態で異なるバイト列を使い、コピーと掃除の一部が失敗しても他の呼び出しのファイルが残ることを確認した。

```bash
for spec_file in spec/*.qnt; do
  quint typecheck "$spec_file"
done
for backend in rust typescript; do
  for test_file in spec/*_test.qnt; do
    quint test "$test_file" --backend="$backend" --match='Test$' --seed=42
  done
  quint run spec/quint_connect.qnt --main=quint_connect_sample --backend="$backend" \
    --invariant=safety --max-steps=34 --max-samples=5000 --seed=42 \
    --hide quint_connect_sample::quint_connect::calls quint_connect_sample::quint_connect::filesystem
  quint run spec/quint_parallel.qnt --main=quint_parallel_sample --backend="$backend" \
    --step=startTogether --invariant=safety --max-steps=68 --max-samples=1000 --seed=42 \
    --hide quint_parallel_sample::quint_connect::calls quint_parallel_sample::quint_connect::filesystem
  quint run spec/quint_filesystem.qnt --main=quint_filesystem_sample --backend="$backend" \
    --invariant=safety --max-steps=28 --max-samples=1000 --seed=42
done
```

観測可能な契約を変更する場合は、対応するモジュールとシナリオを更新し、不変条件を確認してから実装に反映する。
