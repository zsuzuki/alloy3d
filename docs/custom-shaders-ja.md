# モデルのカスタムシェーダー

`ApplicationContext::CreateModelShader` でモデルのRGBを計算するMetal関数を登録できます。
トゥーン調の陰影、色の変換、UVを使った模様などに使えます。
頂点のスキニング、インスタンス配置、マテリアルの透過・両面判定、影用の深度描画は
ライブラリが担当します。プリミティブ・文字・2Dには適用されません。

## 作成と描画

```cpp
// Startなどで一度作成し、メンバー変数に保持する。
std::string diagnostics;
auto toon = ctx.CreateModelShader(R"metal(
float3 alloy3dShade(ModelSurface s, float4 p)
{
  if (s.unlit) return s.baseColor;
  float bands = max(p.x, 1.0);
  float diffuse = floor(s.diffuse * bands + 0.5) / bands;
  return s.baseColor * (s.ambientColor + diffuse * s.shadow * s.lightColor);
}
)metal", diagnostics);
if (!toon) {
  // diagnosticsを表示するなど。既定の描画は引き続き使える。
}

// Updateで設定し、必要なモデルを描画する。
ctx.SetModelShader(toon, simd_make_float4(3, 0, 0, 0));
ctx.DrawModel3D(model, position, rotation, scale);
ctx.DrawModelInstances3D(model, placements);
ctx.SetModelShader(nullptr); // 以降のモデルを標準描画に戻す。
```

`ModelShaderPtr` はコンパイル済み資源を共有する不変ハンドルです。
作成は同期処理で、通常・半透明・インスタンス用の3つのパイプラインを用意します。
毎フレーム作成せず、数値の変更には `SetModelShader` の `simd_float4` を使ってください。
ソース文字列は作成中に読み取り、呼び出し後に保持する必要はありません。
同じソースを再度作成しても、ライブラリ側に無期限のキャッシュは残しません。

コンパイルやパイプライン作成に失敗するとnullを返し、`diagnostics` に理由が入ります。
成功時は空文字列になります。ソースはUTF-8で、空文字列や埋め込みnullは受け付けません。
ユーザー関数のコンパイルエラーは `model_surface_user.metal` の行番号で確認できます。
作成だけでは現在の描画設定は変わりません。

`SetModelShader` は次の描画から適用される状態で、フレームをまたいで維持されます。
各 `DrawModel3D` / `DrawModelInstances3D` は、呼び出し時点のハンドルと4つの数値を保存します。
同じモデルを別の設定で繰り返し描画でき、透明パーツの並べ替えでも設定は保たれます。
パラメーターにNaNや無限大がある場合、または別のコンテキストで作ったハンドルの場合は
falseを返し、以前の設定を維持します。モデルのアニメーション姿勢は従来どおり描画時点のものです。

## Metal関数の入力

ソースには `float3 alloy3dShade(ModelSurface s, float4 parameters)` を定義します。
`metal_stdlib`、`using namespace metal`、次の `ModelSurface` はライブラリが供給します。
追加の純粋な計算用ヘルパー関数も同じソースに定義できます。

| フィールド | 型 | 意味 |
| --- | --- | --- |
| `baseColor` | `float3` | 素材・頂点色、テクスチャ、配置色を乗算したRGB |
| `litColor` | `float3` | 標準描画のRGB。ライティング、影、Unlitを反映済み |
| `normal` | `float3` | ビュー座標の単位法線。裏面は反転し、法線がなければゼロ |
| `texcoord` | `float2` | 補間されたTEXCOORD_0 |
| `lightColor` | `float3` | 平行光源のRGB |
| `ambient` | `float` | 従来の平行光設定のambient値（互換用） |
| `ambientColor` | `float3` | 空・地面の環境光を反映した有効な環境光RGB |
| `diffuse` | `float` | max(N・L, 0) × 拡散光強度。影を掛ける前の値 |
| `shadow` | `float` | 影の可視率。0で影、1で明部。影OFF・範囲外・Unlitでは1 |
| `unlit` | `bool` | Unlit素材、または利用できる法線がない場合にtrue |

標準描画と同じ出力にする最小関数は `return s.litColor;` です。
Unlitの扱いと影の掛け方は関数で選べます。上の例は両方を維持しています。
計算は既存の線形色の描画経路で行われます。出力はRGBのみで、アルファ値は変更しません。
`litColor` は環境光を反映済みです。[距離フォグ](environment-ja.md)はカスタム関数の後に
ライブラリが適用します。`ambient` を使う既存関数で空・地面の色を反映するには、
`ambientColor` へ変更してください。

OPAQUE / MASK / BLEND、MASKのcutoff、片面の裏面判定、配置アルファによるフェードは
関数を呼ぶ前に適用します。BLENDは既存の奥から手前への順序で合成されます。
影の形状は元の頂点とMASKから作るため、独自の `discard_fragment()`、頂点変更、
追加リソースの宣言、内部のマクロ・型・エントリーポイントの上書きは対応範囲外です。
Metal関数はRGB計算のみを行い、有限の値を返す形で記述してください。

## 資源と互換性

描画予約はハンドルを保持し、エンコード後はMetalのコマンドバッファがGPU処理に必要な資源を保持します。
そのため呼び出し側でハンドルを破棄しても予約済み描画は有効です。
設定中のハンドルは `SetModelShader(nullptr)` または別の設定で解除するまで保持されます。
`ReleaseUnusedMemory` は有効なハンドルを破棄しません。
パイプラインのドライバー内部メモリ量は取得していないため、`RenderMemoryStats` には含めません。

既存の `ApplicationContext` 派生クラスにもソース互換の既定実装があります。
未対応コンテキストは作成時にnullと診断を返し、null以外の設定をfalseで拒否します。
公開クラスに仮想関数が増えるため、利用側もライブラリとともに再ビルドしてください。
通常どおり更新した `shaders.metallib` を配置します。カスタム関数用の共通ソースは
ビルド時に実装ライブラリへ埋め込むため、実行時にリポジトリのソースや追加ヘッダは不要です。

この段階ではモデルの表面RGBが対象です。カスタム頂点処理、追加テクスチャ、
複数光源、ポストエフェクト、PBRマテリアル全体の差し替えは提供していません。

## 動作確認

ビューワーの `C` キーで標準／トゥーン調の陰影を切り替えます。
通常展示、`I` のインスタンス展示、`M` のマテリアル展示のどれでも使用でき、
`H` の影切り替えと併用できます。

`shader_regression` はコンパイル診断、RGB・UV入力、設定の保存・復元、
別コンテキストの拒否、負スケールのスキニング、インスタンス数、半透明、
ハンドル破棄・描画破棄・3フレーム同時実行をGPU画像で検証します。
`shader_material` は標準色を返すカスタム関数で既存マテリアルテストを実行し、
`shader_shadow` は光源・影入力からRGBを組み立てる関数で既存の影テストを実行します。

実行時のコンパイルにはAppleの
[Metalソースからのライブラリ作成API](https://developer.apple.com/documentation/metal/mtldevice/makelibrary%28source%3Aoptions%3A%29?language=objc)
を使用しています。
