# Rust 実装との照合データ

`runner-conformance.json` は、`../quint_conformance.qnt` のシナリオを実行して生成する。
各シナリオは、呼び出しごとの要求と応答を一つの実行順序に並べてランナーに渡す。
エクスポーターは実行時の ITF トレースから呼び出しごとの最終結果とイベント履歴、
全呼び出しが完了した時点でのファイルの内容を抽出する。
TypeScript と Rust の両評価器から得た JSON が一致した場合に、照合データを更新する。

リポジトリのルートで次のコマンドを実行する。Python 3.10 以降と Quint 0.34.0 が必要になる。
1 行目は JSON を生成し、2 行目は評価器間とリポジトリに保存した JSON との一致を検証する。

```sh
python3 tools/export_quint_fixtures.py
python3 tools/export_quint_fixtures.py --check
```

## アダプターの入出力

検証スクリプトはケースごとにアダプターを起動し、標準入力に JSON オブジェクトを一つ渡す。
アダプターは `serde_json` などで入力を読み込み、実装の実行結果を JSON オブジェクト一つとして
標準出力に書く。診断メッセージは標準エラーに書ける。アダプターの終了コードが非ゼロの場合、
標準出力を JSON として読めない場合、または期待結果と差分がある場合は検証に失敗する。

```sh
python3 tools/export_quint_fixtures.py --adapter ./path/to/runner-fixture-adapter
```

入力のフィールドは `schema_version`（`2`）、`name`、`input_files`、`schedule` である。
`schedule` は `call_id` と `input` を持つステップの配列で、アダプターは配列の順に進める。
`input` の `Start` は指定の呼び出しを開始し、`Respond` はその呼び出しが待つ子プロセス、
ファイル操作、ドライバーなどの応答を渡す。`Start` の後も、後続のステップで応答を渡せるように
呼び出しを保持する。ケース内の呼び出しは保存先を含むファイルシステムを共有する。

`Start` の要求が `ReplayPaths` の場合、パスの並びは呼び出し元の指定順であり、
同じパスの繰り返しや存在しないパスも含む。`RunQuint` の場合は CLI の要求、seed の入力値、
成果物のルート、操作と状態の選択パスを指定する。
保存済み ITF のバイト列は `input_files` にあり、生成された ITF のバイト列は
子プロセスに対応する `Respond` に含まれる。

アダプターの出力は、ケースの `expected` に含まれる次のフィールドで構成する。

| フィールド | 内容 |
| --- | --- |
| `calls` | `call_id`、`events`、`outcome` を持つオブジェクトの配列。`call_id` の昇順に並ぶ。 |
| `saved_files` | 全呼び出しが完了した時点で保存されている成果物のパスと全バイト列。 |
| `remaining_workspace_files` | 全呼び出しが完了した時点で作業先に残っているファイルのパスと全バイト列。 |

`events` は各呼び出しにおけるコマンドの準備、プロセスの処理、ファイルの読み込み、
ドライバーの呼び出し、保存先の確保と保存、掃除などのイベントで、発生順に並ぶ。
`outcome` は最終結果の `Passed` または `Failed` であり、失敗時は診断と掃除に関する付記事項を含む。

`overlappingArtifactReservation` では、二つの呼び出しが同じ seed とファイル名を使い、
同じ成果物ルートで最初の保存先候補を取り合う。アダプターは確保済みの候補に対して衝突を報告し、
空きがある候補に対して `ArtifactReservation` の結果を使う。
先に保存した呼び出しが掃除を終えた後も、もう一方はコピーを続ける。
照合では、各呼び出しの診断が参照する保存先と、各保存先にある元のバイト列を確認する。

`waitFailureWithDeferredCleanup` では、`ChildIoFailed` の `ExitUnconfirmed` に続き、
`WorkspaceCleanupWasDeferred` で終了を確認できなかった理由と作業先に残っているバイト列を渡す。
照合では、待機失敗の診断、掃除を延期した作業先、その作業先に残したファイルを確認する。

`outputCollectionFailureAfterExitConfirmation` でも子プロセスの終了が未確認となる。
`ChildExitWasConfirmed` で終了の確認と作業先のバイト列を渡し、続く `WorkspaceCleanup` で
掃除を完了する。掃除後も主診断には出力収集の失敗が残る。

`nestedArgumentMutationMismatch` では、`DriverApplyWithMutation` の `arguments` に
ドライバーが書き換えた後の引数を指定する。アダプターはドライバーに渡された引数の中の
値を書き換えてから `result` を返す。照合では、ドライバーが書き換えた値と、
状態不一致の診断に残る操作呼び出し時の値を確認する。

Quint のバリアントは `tag` と `value` を持つオブジェクトで表し、値のない場合は
`value` を `null` とする。パスには `SavedFile`、`WorkingFile`、`EvidenceFile` を使う。
位置のインデックスは 0 から始まる。トレース ID は再生順のインデックスとは独立にファイルを識別する。

ファイルの内容と子プロセスの出力は、0 から 255 の整数の配列で表す。操作名と選択パスの
各要素は JSON 文字列である。操作の引数は引数名をキーとする JSON オブジェクトで表す。
操作の各引数、期待状態、ドライバーが観測した状態は ITF の値表現に従う。整数は
`#bigint` 内の十進文字列で表し、タプル、集合、マップには ITF のタグを使う。
集合の要素とマップの項目は、オブジェクトのキーを整列して空白なしで
JSON に変換したときの文字列順に並べる。照合時も集合とマップは同じ規則で整列する。
ファイルの配列は同じ規則をパスに適用して並べる。イベントとバイト列は配列の順序も照合する。
