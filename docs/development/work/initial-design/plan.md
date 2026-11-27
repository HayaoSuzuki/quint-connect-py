# Quint Connect Python Implementation Plan

実行時は `quint-execute-spec` を使う。タスク単位で担当を分ける場合は `subagent-driven-development`、一つのセッションで進める場合は `executing-plans` を使う。

**目標** Rust で実装した再生処理を Python から呼び出し、Quint が生成した履歴と保存済み ITF を同じ規則で照合する。

**構成** Rust に値と ITF、再生と診断、Quint の起動と成果物の管理を置く。PyO3 は Python の値・コールバック・例外を Rust の処理につなぐ。Maturin で Python の公開 API とネイティブ拡張を配布する。

**仕様** [初期設計](design.md) · [動作仕様](../../../../spec/quint_connect.qnt) · [Quint シナリオ](../../../../spec/quint_connect_test.qnt)

## 制約と実装差分

- 配布名は `quint-connect-py`、import 名は `quint_connect`、`requires-python` は `>=3.14,<3.16`。GIL 有効の CPython 3.14・3.15 で同じプラットフォーム用の `abi3` wheel を検証する。配布物は追加の Python パッケージを要求しない。
- Quint 0.34.0 の Rust・TypeScript バックエンドを受け入れ試験で使う。CLI 実行ファイルは `run(..., quint=...)` で指定する。ITF の保存済み再生はネットワークおよび Quint、Node.js、Rust コンパイラのないインストール済み環境で確認する。
- Rust のクレートと Python パッケージを新規作成する。Quint の `calls` は Rust での各 API 呼び出し、`filesystem` は作業先ごとの出力と保持された失敗 ITF に対応する。状態を持つ Python ドライバーはトレースごとにファクトリーで作る。
- 検査に失敗した段階で後続作業を止め、反例と実装の対応を調べる。契約自体を変更する必要が出た場合は、Quint の仕様差分を先にレビューする。

## 検証

各タスクでは Rust の単体テストまたは Python の公開 API テストを先に追加し、対象の挙動で失敗することを確認する。変更後は同じテストと、対応する Quint の型検査、シナリオ、不変条件を実行する。検証後はタスク単位でコミットする。

```bash
cargo test --no-default-features
uv run --group test pytest -q
quint typecheck spec/quint_connect.qnt
quint test spec/quint_connect_test.qnt --match '<対象のテスト名または正規表現>'
quint run spec/quint_connect.qnt --main=quint_connect_sample --invariant=safety \
  --max-steps=34 --max-samples=5000 --seed=42 --verbosity=1
```

## レビューで重点を置く入力

1. ファイル列挙を逆順にしても、出力の 2 番が 10 番より先に再生される。タスク 4。
2. 壊れた ITF の末尾を、ファクトリーを呼ぶ前に検出する。タスク 2、3。
3. Python ドライバーが可変の操作引数を変更しても、診断では ITF の元の引数と期待値を確認できる。タスク 3。
4. 作業先の掃除後も失敗 ITF が残る。掃除にも失敗した場合は元の不一致または CLI エラーを保持する。タスク 4。
5. 同じモデルと seed で同じ保存先を使う xdist ワーカーが、独立したトレースを保存し、それぞれ同じ不一致を再現できる。タスク 5。

## タスク 1　Rust クレートとネイティブパッケージ

**ファイル** `Cargo.toml`、`Cargo.lock`、`pyproject.toml`、`.gitignore`、`src/lib.rs`、`src/python/mod.rs`、`python/quint_connect/__init__.py`、`tests/test_package.py`。

- [ ] `test_import_without_quint` で `import quint_connect` と `import quint_connect._native` に成功し、import 時に Quint のプロセスが起動しないことを確認する。テストの subprocess に Quint と Node.js を含まない検索パスを渡す。
- [ ] Python パッケージのメタデータにも `Apache-2.0` を指定し、sdist と wheel にルートの `LICENSE` を含める。
- [ ] PyO3 0.30 系の `abi3-py314` で拡張を構成する。単一の Rust クレートに `python` 機能を設け、Maturin の `bindings = "pyo3"`、`python-source = "python"`、`module-name = "quint_connect._native"`、`features = ["python"]` で拡張をビルドする。Cargo の既定では Rust の処理本体を Python と独立にテストできるようにする。pytest、Hypothesis、pytest-xdist は `test` 依存グループに置く。Rust の `target/` とビルドで生成する Python 拡張を成果物として扱う。
- [ ] `cargo test --no-default-features` と `uv run --python 3.14 --group test pytest -q tests/test_package.py` を実行する。Quint の初期状態の `safety` を `--max-steps=0` で検査する。

## タスク 2　Quint の値と ITF の検証

**ファイル** `src/value.rs`、`src/itf.rs`、`src/python/value.rs`、`src/python/mod.rs`、`python/quint_connect/__init__.py`、`python/quint_connect/_native.pyi`、`python/quint_connect/py.typed`、`tests/test_values.py`。

- [ ] Rust テストで真偽値と整数、リストとタプル、レコードとマップを区別する。レコードを含む集合と、レコードをキーにするマップは、順序を変えても一致させる。Python テストで `2**100` を含む値が Rust との境界を往復できることを確認する。
- [ ] Rust テストで、両取得元での引数直下の `Some` と `None`、ネスト内のレコード、明示操作の空タプル、予約メタデータと `vars` の重複、選択範囲内外の `#unserializable`、末尾の不正ステップ、空トレースを確認する。
- [ ] `Value` は `BigInt`、真偽値、文字列、順序付きのリストとタプル、レコード、順序を無視する集合とマップを持つ Rust の enum とする。集合とマップの表現には `BTreeSet<Value>` と `BTreeMap<Value, Value>` を使い、構造と型を維持する。匿名の MBT 操作名は空文字列として扱い、整数と集合をドライバーとの受け渡しでも正規化する。 `decode_trace(bytes: &[u8], selection: &Selection) -> Result<Vec<TraceStep>, ItfError>` は一件分のバイト列を検証済みのステップ列に変換する。UTF-8 と JSON の構文を検証する。JSON オブジェクトを読む段階で展開済みのキーの重複を検出し、`vars` の配列内の重複と区別する。JSON 数値は選択外のメタデータにも現れるため、構文の受理と ITF 値としての受理を別々に確認する。数値の構文は指数の大きさによらず受理し、コンテナーの深さは明示的なスタックなどで扱う。`serde_json` を使う場合は、既定の数値範囲と再帰制限に依存せず、重複キーと数値トークンの種別を保持できる構成を選ぶ。`TraceStep` は `Action` と `expected: Value` を保持する。[serde_json のデシリアライザー](https://docs.rs/serde_json/latest/serde_json/struct.Deserializer.html)
- [ ] Python に `Action(name, arguments)`、`QuintSet(values)`、`QuintMap(entries)` を公開する。後二者は要素またはキーと値の組を読み取れるようにし、Python の `QuintValue` が対応する組み込み型と二つの値型の和を表すようにする。変換は `src/python/value.rs` に限る。Rust 側の整数には `num-bigint` を使い、Python との変換にも同じ精度を保つ。
- [ ] `cargo test --no-default-features`、`uv run --group test pytest -q tests/test_values.py`、Quint の `invalidLaterStepBlocksFactoryTest|invalidNextTraceCannotReturnSuccessTest|emptyInputAndEmptyStatesAreDistinctTest` と `replayInOrder` を実行する。[UTF-8 と JSON](../../../../spec/quint_json_test.qnt)、[バイト列からの ITF 変換](../../../../spec/quint_itf_test.qnt)、[複合値の等値法則](../../../../spec/quint_values_test.qnt)の Quint シナリオも実行する。Rust では不正な UTF-8、先頭の BOM、孤立したサロゲート、直接記述とエスケープの等価性、エスケープ展開後の重複、大きな指数を持つ選択外のメタデータ、深さ 150 の JSON をバイト列から確認する。Unicode の操作名と選択パスが直接記述・エスケープの両方で一致し、合成済みの文字と結合文字を使った綴りを区別できることも確認する。

## タスク 3　保存済み ITF と Python ドライバーの再生

**ファイル** `src/replay.rs`、`src/python/mod.rs`、`src/python/error.rs`、`python/quint_connect/__init__.py`、`python/quint_connect/_native.pyi`、`tests/test_replay.py`。

- [ ] `test_replays_repeated_path_in_fresh_drivers` で同じパスを二回渡してファクトリー二回を確認する。`test_invalid_trace_has_no_driver_calls` は壊れた末尾でファクトリーが呼ばれないことを確認する。`test_stops_at_first_mismatch_with_original_arguments` は操作の省略と可変引数の変更を行い、期待値、実測値、元の操作引数が残り、後続操作とファイルへ進まないことを確認する。
- [ ] 存在しないファイルや読み取りに失敗したファイルで、指定したパスと原因が診断に残ることを確認する。二件目が破損している場合は一件目が完了してから二件目を開き、三件目を開かないことを確認する。別名と参照先を両方指定した場合はそれぞれで再生し、別名の参照先が欠ける場合や循環する場合は指定されたパスが診断に残ることを確認する。
- [ ] `test_driver_error_preserves_cause` はファクトリー、操作、観測の三段階それぞれで Python の元例外が `__cause__` に残ることを確認する。未対応の値を観測したときの段階も確認する。
- [ ] `replay<D: Driver>(paths: &[PathBuf], factory: impl FnMut() -> Result<D, D::Error>, selection: &Selection) -> Result<(), ReplayError<D::Error>>` を Rust の共通再生処理にする。内部の `Driver` trait は `type Error`、`apply(&mut self, action: &Action) -> Result<(), Self::Error>`、`observe(&mut self) -> Result<Value, Self::Error>` を持つ。ファクトリーは一件の ITF の検証後に呼ぶ。選択パスは API 呼び出し単位で固定し、各 ITF に同じパスを適用する。PyO3 側は Python の呼び出しごとに値を変換する。ドライバーは入れ子も含めた引数の Python 側のコピーを受け取る。引数の内部を変更した後の不一致で、検証済みの操作・引数・期待値が診断に残ることを確認する。
- [ ] `replay(traces, driver_factory, *, action_path=(), state_path=()) -> None` を公開する。Python の `Driver` は `step(action: Action) -> None` と `observe() -> QuintValue` を持つ。例外は `InvalidTraceError`、`EmptyTraceError`、`DriverError`、`StateMismatchError` に分ける。不一致は `AssertionError` のサブクラスで、`trace_path`、`trace_index`、`step_index`、`action`、`expected`、`actual` を提供する。
- [ ] `cargo test --no-default-features`、`uv run --group test pytest -q tests/test_replay.py`、Quint の `repeatedSavedPathGetsNewDriverTest|secondTraceUsesItsOwnOperationAndExpectedValueTest|cannotApplyAfterFirstMismatchTest` と `firstFailureStopsReplay` を実行する。`compoundEqualityDeterminesReplaySuccessTest` で再生と複合値比較の接続を確認し、[パス指定による保存済み ITF のシナリオ](../../../../spec/quint_saved_replay_test.qnt)で読み取り順とパス付き診断を確認する。

## タスク 4　Quint 起動、成果物、作業先

**ファイル** `src/quint.rs`、`src/python/mod.rs`、`src/python/error.rs`、`python/quint_connect/__init__.py`、`python/quint_connect/_native.pyi`、`tests/test_run.py`。

- [ ] Rust テストで数値順の `2 < 10`、終了失敗と部分出力の優先順、空出力と件数不足、名前付きテストの完全一致、先行エラーがある場合の掃除失敗を確認する。`test_seed_range_and_type` は Python API から `0` と `2**64 - 1` を渡し、範囲外と真偽値を拒否することを確認する。
- [ ] `max_samples < n_traces` と負の `max_steps` をシミュレーションで拒否し、名前付きテストでは 0 以下の `max_samples` を拒否する。件数と上限に共通の最大値 `2**53 - 1` と、その直上を確認する。いずれも作業先の作成と CLI の起動に進まないことを確認する。`max_samples=n_traces` を受理し、`max_steps=0` で初期状態だけを生成することを両評価器で確認する。
- [ ] `test_saved_bytes_survive_workspace_cleanup` で元のバイト列と保存後のバイト列を比較し、例外から取得した `artifact_path` を `replay()` に渡して同じ操作と値の不一致が再現されることを確認する。保存先を確保できない場合、作業先を作れない場合、掃除だけが失敗した場合もテストする。
- [ ] `Simulation(spec, *, main=None, init=None, step=None, n_traces=1, max_samples=None, max_steps=None)` と `NamedTest(spec, *, test, main=None, max_samples=None)` を公開する。`run(config, driver_factory, *, quint, seed=None, backend=None, action_path=(), state_path=(), artifact_dir=None) -> None` は Rust の `std::process::Command` に引数を渡す。予約した作業先を子プロセスのカレントディレクトリにし、`trace_{seq}.itf.json` を出力する。呼び出し時のカレントディレクトリを基準に、モデルと実行ファイルの相対パスを起動前に解決する。実行ファイルを名前で指定したときは呼び出し元の `PATH` を順番に調べ、最初に実行可能な候補を起動する。相対または空の項目も同じディレクトリを基準にする。候補が見つからない場合と候補の拒否を区別し、拒否の場合は最初の候補と原因を `QuintError` の診断に保持する。Quint が正常終了したら作業先の一覧を取得し、シンボリックリンクをたどらずに項目の種別を取得し、標準形式の出力名を持つ通常ファイルを数値順に並べてタスク 3 の再生処理へ渡す。項目種別を取得できない場合は一覧取得の失敗として扱う。一覧取得の失敗は作業先と原因を保持する `WorkspaceError`、生成物の読み取り失敗はファイルと原因を保持する `InvalidTraceError` とする。seed の省略時は OS の乱数を使って Rust 側で `u64` を選ぶ。Quint の起動やファイル処理の間は Python インタープリターから離れ、ドライバーを呼ぶときに再びアタッチする。
- [ ] 作業先と保存先には別々の専用ディレクトリを確保する。成果物ディレクトリを排他的に確保し、候補名が衝突した場合は次の候補へ進む。確保に失敗した場合は、元の不一致に保存先候補と原因を付記する。別の呼び出しの成果物を指すリンクを作業先に置き、作業先を掃除しても成果物が残ることを確認する。失敗 ITF は一時ファイルに全バイトをコピーしてから保存先のパスに公開する。部分コピーと全バイトを書いた後の公開失敗を注入し、いずれも保存先が公開されず、例外が元の不一致を保持することを確認する。CLI の失敗は `QuintError` とし、起動失敗では OS の原因、非ゼロ終了またはシグナル終了では終了情報と標準出力・標準エラーの元バイト列を保持する。両方とも作業先を掃除し、部分出力を処理しないことを確認する。起動後の待機・出力回収の失敗では、その段階と元の原因を保持する。終了を確認してから掃除する。追加確認後も終了が不明なら、作業先を残してパスと保留理由を診断に付ける。出力不足は `IncompleteGenerationError`、作業先の失敗は `WorkspaceError` とする。生成トレースの不一致には `seed` と `artifact_path` または `artifact_error` を付け、掃除で二次的な失敗があれば元の例外に付記する。
- [ ] `cargo test --no-default-features`、`uv run --group test pytest -q tests/test_run.py`、Quint の `generationErrorsBlockReplayTest|generatedAndSavedMismatchAgreeTest|saveFailureRetainsMismatchTest|cleanupOnlyBecomesPrimaryAfterPassingTest` と `mismatchKeepsEvidence`、`consistentResult`、`persistedEvidence` を実行する。CLI、ファイルシステム、生成後の I/O の Quint シナリオを実行し、`sortedGenerationAndSavedBytesReproduceMismatchTest` で再生までの接続を確認する。実プロセスでも、相対指定・名前指定で選んだ実行ファイルとモデルを確認する。`--flag=value` を一つの argv 要素として渡し、空白と Unicode を保持する。保存済みファイルと成果物の相対指定が呼び出し元を基準とすること、設定検証と実行ファイル選定が作業先の確保に先行することを確認する。一覧取得の失敗と、二件目の読み取り失敗から掃除へ進む順序も確認する。[CLI](../../../../spec/quint_cli_test.qnt) · [ファイルシステム](../../../../spec/quint_filesystem_test.qnt) · [生成後の I/O と成果物公開](../../../../spec/quint_runner_io_test.qnt)

- [ ] Rust のテスト用アダプターで、Quint が生成した入力の ITF バイト列、I/O 結果、ドライバー応答を実装へ渡す。操作履歴、診断、成果物と掃除後のファイルを比較する。複数呼び出しのケースでは、入力に含まれる呼び出し ID と順序に従って応答を与え、呼び出しごとの結果と共有ファイル状態を照合する。照合の起動方法と JSON の仕様は fixture の README を参照する。[照合データの仕様](../../../../spec/fixtures/README.md)

## タスク 5　実機、上流モデル、並列テスト

**ファイル** `examples/counter.qnt`、`examples/test_counter.py`、`tests/test_quint_integration.py`、`tests/test_xdist.py`、`tests/fixtures/`、[利用者向けガイド](../../../user/guides/usage.md)。

- [ ] カウンターモデルで保存済み ITF、`run --mbt`、明示操作の名前付きテスト、Hypothesis の `@given(st.integers(min_value=0, max_value=2**64 - 1))` を使う例を作る。生成は Quint 0.34.0 の Rust・TypeScript で成功することを確認する。
- [ ] 上流の `tictactoe.qnt` を指定リビジョンのまま fixture にし、出典とライセンスを記録する。Python ドライバーで `init`、`MoveX`、`MoveO`、`stuttered` を処理して再生する。[上流のモデル](https://github.com/quint-co/quint-connect/blob/3b9eab8d817cbcd6de64ca1b05a20f18b96797ef/connect/examples/tictactoe/spec/tictactoe.qnt)
- [ ] `pytest -n 2 --dist=each` で同じテストを二つのワーカーに実行させる。モデル、seed、成果物の親ディレクトリを共有し、分離した作業先と保存先で、どちらの不一致も再現できることを確認する。
- [ ] `uv run --group test pytest -q tests/test_quint_integration.py tests/test_xdist.py`、Quint の `interleavedRunsKeepSeparateArtifactsTest` と `isolatedResources` に加え、[四件の並行シナリオ](../../../../spec/quint_parallel_test.qnt)と[四つの作業先を確保した状態からのシミュレーション](../../../../spec/quint_parallel.qnt)を実行する。

## タスク 6　配布検証と設計レビュー

**ファイル** `pyproject.toml`、`tests/test_wheel_smoke.py`、[利用者向けガイド](../../../user/guides/usage.md)、[開発者向け目次](../../index.md)。

- [ ] Maturin を PEP 517 バックエンドにした `uv build` で sdist と `abi3` wheel を作る。同一プラットフォームの Python 3.14 と 3.15 の新規環境に同じ wheel をインストールし、作業ツリーの外で起動した Python から保存済み ITF を再生する。メタデータの Python 範囲、依存、ネイティブタグ、型情報を確認する。
- [ ] Rust のテスト、Python 3.14・3.15 の公開 API テスト、Quint の全シナリオと `safety` を実行する。`processingProgress` は有限の入力と外部の応答を前提に、未終了の段階が進み、各遷移が残り作業を減らすことを検査する。PyO3 の境界では、例外の型、属性と元の原因を公開 API から確認する。Rust 内の処理に PyO3 の型が浸透していないか、ITF と CLI の知識がそれぞれ一箇所に収まるかを見直し、設計評価を更新する。
