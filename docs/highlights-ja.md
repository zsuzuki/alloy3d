# モデルの簡易ハイライト

Blinn–Phong方式の鏡面ハイライトを、モデルごとに追加できます。
表面の法線・平行光・視線方向からツヤを計算します。新しい画像やアセットの加工は不要です。
既定の強さは0（OFF）。ビューアーの **P** で強さ0.3、鋭さ32のハイライトを切り替えます。

## 使い方

```cpp
alloy3d::ModelHighlight3D highlight;
highlight.strength = .3f;
highlight.shininess = 32;
ctx.SetModelHighlight3D(highlight);
ctx.DrawModel3D(model, position, rotation, scale);
ctx.SetModelHighlight3D({}); // 以降のモデルはハイライトOFF
```

| 設定 | 範囲・効果 |
|---|---|
| `strength` | 有限の0〜1。0で無効。大きいほど明るいツヤ |
| `shininess` | 有限の1〜128。大きいほど狭く鋭いツヤ。既定32 |

設定は次のモデル描画から持続し、`DrawModel3D` / `DrawModelInstances3D` の予約時に保存します。
同じモデルを異なるツヤで描けます。1回のインスタンス描画では全配置に同じ設定を適用し、
バッチを分割しません。モデル内の各マテリアルにも共通の設定です。
設定後に `SetModelShader(nullptr)` を呼んでも、ハイライト設定は解除されません。

同梱ホストは成功時にtrue、未対応の独自ApplicationContextの既定実装はfalseを返します。
範囲外・NaN・無限大の値は `std::invalid_argument` を投げ、以前の状態を維持します。
無効化時にも入力値を検証します。

## 光・影・透過との関係

- ハイライトの色は平行光の色、明るさは `strength × diffuse強度 × 影の可視率` に従います。
  鏡面反射の色にはベースカラーや配置のRGB色を掛けません。
- 光源または視線に背を向けた面には加算しません。影の中では既存の影に応じて減衰します。
- 透視投影では各ピクセルからカメラへの方向、平行投影では平行な視線を使います。
  スキニング、非一様／負スケール、両面の裏面は既存の補正済み法線を使います。
- Unlit素材と法線がないモデルには適用しません。基本図形・線・文字・2Dも対象外です。
- アルファとMASKの切り抜き、透過順、影を落とす形状は変更しません。
  配置のアルファによるフェードはハイライトにも通常のブレンドとして効きます。
- フォグはハイライト込みのRGBに適用します。環境光も併用できます。

これは一定のツヤを足す簡易方式です。金属度・粗さのglTFマテリアルの再現、環境の映り込み、
鏡面マップ、リムライトは含みません。強い設定では明るい部分が表示範囲を超えて白飛びします。
石や布などにも一律に設定すると材質感が変わるため、必要なモデルの描画時に有効にしてください。

## カスタムシェーダー

`ModelSurface::litColor` はハイライト込みです。`return s.litColor;` で標準描画と一致します。
新しい `s.specularColor`（float3）は、そのうち鏡面ハイライトだけのRGBです。
陰影を組み直す場合に加算できます。

```metal
if (s.unlit) return s.baseColor;
return s.baseColor * (s.ambientColor + s.diffuse * s.shadow * s.lightColor)
       + s.specularColor;
```

`litColor + specularColor` とすると二重加算になる点に注意してください。
カスタム関数が独自の固定色などを返す場合、その後にハイライトを強制加算しません。
フォグは従来どおりカスタム関数の後に適用します。
公開API追加のため利用側も再ビルドし、`shaders.metallib` を一緒に更新してください。

## 負荷と検証

追加のテクスチャ・描画パス・パイプライン種類・GPU資源確保はありません。
有効時に視線とハーフベクトルの正規化、内積、指数計算を行います。
強さ0ならこれらの計算をスキップしますが、分岐・頂点出力の3成分と、
マテリアル定数の16バイト増加などは残るため、完全なゼロコストではありません。

2026-09-11、Apple M3 Ultra、Release、1536×1536、影・フォグ・空と地面の環境光・MSAAを無効にし、
3968三角形の球を1回描画して比較しました。Metal API Validationなし、
最初の20フレームを除いた80フレームのGPU時間中央値です。

| 状態 | GPU中央値 |
|---|---:|
| 変更前 `20c2648` | 0.0850 ms |
| 追加後OFF | 0.0856 ms |
| 強さ0.3・鋭さ32 | 0.0899 ms |
| 強さ0.8・鋭さ96 | 0.0903 ms |

OFF時の画素ハッシュは変更前と同じ `b7e159aef6d9f745` でした。
このシーンではONにすると約0.004〜0.005 ms増えています。値はこの端末・シーンの計測結果で、
他のGPU・モデル数・画面占有率での負荷を保証するものではありません。
比較用の球の画像も出力し、弱い広がりのあるツヤと、鋭いツヤを目視確認しています。

既存の256×256・1000回の個別モデル描画ベンチマークでは、OFF時の命令構築は
変更前0.2409 ms／追加後0.2326 ms、GPUは0.0185 ms／0.0205 msでした。
この条件ではCPU負荷の増加は観測していませんが、計時のばらつきがあるため高速化とは判断しません。

Metal API Validation付きの回帰テストは18件すべて成功しました。
`highlight_regression` は強度、鋭さ、視線・投影、光源色、Unlit、BLEND、影・フォグ、
カスタム関数、入力検証、予約時の状態保存、スキニング・インスタンス、3フレーム同時実行を確認します。

```sh
python3 tools/generate_highlight_fixture.py --check
cmake --build build -j 8
ctest --test-dir build --output-on-failure
build/tests/alloy3d_highlight_probe build/shaders/shaders.metallib \
  assets/tests/highlights/sphere.glb /tmp/alloy3d-highlight
```
