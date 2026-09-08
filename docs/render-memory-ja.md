# 描画メモリの管理

文字キャッシュをバイト数で制限し、シーン切替時に一時頂点バッファのピーク容量を
返却できるようにした。通常のフレームでは確保済み領域を再利用する。

## 公開API

`ApplicationContext` に次の3メソッドを追加した。`Start` / `Update` の
コールバック内から呼び出す。コンテキストを保存して別スレッドから操作しない。

```cpp
void Start(alloy3d::ApplicationContext &ctx) override
{
  alloy3d::TextCacheBudget budget;
  budget.bitmapBytes = 8 * 1024 * 1024;   // CPU画像: 8 MiB（既定値）
  budget.textureBytes = 16 * 1024 * 1024; // GPUテクスチャ: 16 MiB（既定値）
  ctx.SetTextCacheBudget(budget);
}

void Update(alloy3d::ApplicationContext &ctx) override
{
  if (sceneChanged) // アプリ側で管理する、シーン切替が起きたフレームのフラグ
    ctx.ReleaseUnusedMemory();

  const auto memory = ctx.GetRenderMemoryStats();
  // memory.releasePending が false なら、要求した全ページの解放処理が完了。
  // この後で通常どおり描画命令を登録する。
}
```

メソッドは付属のMetalホストが実装する。独自の `ApplicationContext` 派生クラスでは、
追加メソッドの既定実装は何もせず、統計は0を返す。既存の派生クラスは実装を追加せず
再コンパイルできるが、仮想メソッドの追加があるため利用側も再ビルドする。

## 文字キャッシュの予算

CPU画像とGPUテクスチャは別々の予算を持つ。それぞれを2D用と3D用に半分ずつ
固定配分する。奇数バイトの端数は3Dに配分し、未使用予算の融通は行わない。
既定では2D・3DそれぞれCPU 4 MiB、GPU 8 MiBを上限とする。

- 上限を超えそうな場合、最後の利用が最も古い項目から取り除く（LRU）。
- 1件でそのキャッシュの上限を超える文字は、描画だけ行ってキャッシュに保存しない。
- 予算を減らすと、その呼び出し内で上限以下まで取り除く。0ならキャッシュを無効化する。
- 小さい項目の管理コストを抑えるため、各キャッシュの最大512件の制限も併用する。
- CPU画像のサイズは行バイト数×高さ、GPUテクスチャはMetalの `allocatedSize` で数える。

予算は**キャッシュに残すデータ**の上限であり、描画のために一時生成する画像や、
登録済みの描画命令・GPUが保持するテクスチャまで含めた上限ではない。
大量の異なる文字を1フレームに描く場合、一時的な使用量は予算を超えることがある。

## 不要メモリの解放

`ReleaseUnusedMemory()` は文字キャッシュをその場で空にし、一時頂点バッファの
3ページすべてに解放を予約する。GPU用フレーム枠を取得した後、各ページを次に
再利用するタイミングでバッファを解放する。追加の同期GPU待ちは行わない。
登録済みの描画命令は維持し、モデルやスプライトはアンロードしない。

通常は呼び出し後の3回の描画フレームで全ページの解放処理が終わる。
`Start` で既に頂点が登録されているページは、その描画が終わるまで処理を延期する。
描画停止中や描画先を取得できない間はページが進まず、完了が遅れる場合がある。
再び描けば必要な容量を確保し直すので、毎フレームではなくシーン切替などに使う。

## 統計の範囲

`GetRenderMemoryStats()` は2Dと3Dを合算した値を返す。

| フィールド | 内容 |
| --- | --- |
| `vertexBufferBytes` | 一時頂点バッファの全3ページの確保容量。使用頂点数ではない |
| `shadowMapBytes` | 深度マップ全ページのテクセル容量。無効時用の1テクセルを含む |
| `instanceBufferBytes` | インスタンス描画の変換・色バッファの全3ページの確保容量 |
| `textBitmapCacheBytes` | キャッシュに残るCPU画像のバイト数 |
| `textTextureCacheBytes` | キャッシュに残るGPUテクスチャの割当バイト数 |
| `textCacheEntries` | CPU画像・GPUテクスチャの項目数の合計。同じ文字も別々に数える |
| `releasePending` | 解放を予約した頂点ページが残っているか |

これらはプロセスのRSSではない。モデル、スプライト、uniform、文字キーなどの
管理情報、描画命令だけが保持するリソース、ドライバー内の領域は含めない。
解放後も現在のシーンが使う容量は再確保されるため、`releasePending == false` は
`vertexBufferBytes == 0` を意味しない。

## 検証

`memory_regression` は小さい予算でLRU順序、上限変更、0予算、過大な項目、
オブジェクトの所有権を検証する。Metalでは3ページを拡張し、コマンド送信前の
キャッシュ解放、軽いシーンへの変更、頂点バッファの解放・再拡張を実行する。
可視文字が描かれ、各段階の描画ピクセルが一致することも確認する。

2026-09-09のローカルMetal実行では、一時頂点バッファ容量が
**22,216,704 bytes → 61,440 bytes** に減少し、再拡張後も描画ピクセルは一致した。
ReleaseとAddressSanitizerの両構成で、既存3種類と新規メモリ回帰テストの
計4種類がすべて成功した（スキップなし）。この数値はテストシーンのバッファ容量である。

```sh
cmake -S . -B build-test -DCMAKE_BUILD_TYPE=Release -DALLOY3D_BUILD_TESTS=ON
cmake --build build-test -j8
ctest --test-dir build-test --output-on-failure
```

テストはMetal API Validationを有効にする。Metalデバイスのない環境ではGPUテストは
スキップされるため、合否とスキップを区別する。

テクスチャの計上はAppleの
[`allocatedSize`](https://developer.apple.com/documentation/metal/mtlresource/allocatedsize)、
コマンド送信前にキャッシュから取り除ける根拠は、通常の
[`commandBuffer`](https://developer.apple.com/documentation/metal/mtlcommandqueue/makecommandbuffer%28%29?language=objc)
が参照リソースを保持する仕様による。

影の解像度変更・無効化による解放もフレームページの安全な再利用時に行います。詳細は[シャドウマップ](shadows-ja.md)を参照してください。
