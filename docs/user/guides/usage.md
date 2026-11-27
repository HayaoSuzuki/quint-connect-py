# Quint トレースの生成と再生

対応する Python は 3.14 と 3.15 で、パッケージの import 名は `quint_connect`。

## ドライバー

テスト対象の公開 API で操作を実行する `step(action)` と、比較対象の状態を返す `observe()` を用意する。`action.name` が操作名、`action.arguments` が名前付き引数を表す。初期化もステップ 0 の操作名に従って処理する。Quint が匿名操作として記録した `action.name` は空文字列になる。ファクトリーは呼び出されるたびに新しいドライバーを返す。

## 保存済み ITF

```python
from quint_connect import replay

replay("counter.itf.json", CounterDriver, state_path=("count",))
```

この例では、トレースの各状態から `count` を取り出して `observe()` の戻り値と比較する。`CounterDriver` はテスト対象に合わせて用意する。保存済み ITF は、対応する wheel をインストールした Python 環境でオフライン再生できる。

## Quint で生成

```python
from quint_connect import Simulation, run

run(
    Simulation("counter.qnt", n_traces=10),
    CounterDriver,
    quint="/path/to/quint",
    seed=42,
    state_path=("count",),
)
```

初版では Quint 0.34.0 の Rust と TypeScript のバックエンドを検証対象とする。名前付きテストを使う場合は、たとえば `NamedTest("counter.qnt", test="roundTripTest")` を渡し、モデルが記録した操作の位置を `action_path` に指定する。状態不一致の例外から seed と失敗 ITF の保存先を確認し、その ITF を `replay()` に渡せる。

## pytest から呼ぶ

テスト関数の中から `run()` と `replay()` を呼ぶ。`pytest -n 2` を使う場合も呼び出し方は同じである。`run()` の生成先は呼び出しごとに確保され、保存済み ITF は複数のワーカーで読み取れる。ドライバーが書き込む DB やファイルも、必要に応じてテスト側のファクトリーで分ける。

Hypothesis を使う場合は、`@given` で選んだ 0 以上 `2**64 - 1` 以下の整数を `run()` の `seed` に渡す。Hypothesis が縮小する入力は seed である。

```python
from hypothesis import given, strategies as st
from quint_connect import Simulation, run


@given(seed=st.integers(min_value=0, max_value=2**64 - 1))
def test_counter_follows_model(seed: int) -> None:
    run(
        Simulation("examples/counter.qnt", max_steps=2),
        CounterDriver,
        quint="quint",
        seed=seed,
        action_path=("op",),
        state_path=("count",),
    )
```
