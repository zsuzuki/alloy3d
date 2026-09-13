# モデルのUV変換と流れるテクスチャ

`ModelTextureTransform3D` は、モデルのベースカラーテクスチャのUVを拡縮・移動する描画設定です。
水流、流れる模様、ベルトなどに利用できます。

```cpp
alloy3d::ModelTextureTransform3D uv;
uv.scale = {1, 1};
uv.offset = {0, -std::fmod(seconds * .075f, 1.f)};
ctx.SetModelTextureTransform3D(uv);
ctx.DrawModel3D(water, position, rotation, scale);
ctx.SetModelTextureTransform3D({}); // 後続のモデルは通常のUVに戻す
```

計算式は `sampledUV = TEXCOORD_0 * scale + offset` です。既定値は scale=(1,1)、offset=(0,0)。
モデル内の全パーツに適用し、モデルや元のGLBは変更しません。
負のscaleによる反転、ゼロscaleによる固定座標も可能です。成分はすべて有限値である必要があります。
NaN・無限大は、組み込みホストでは `std::invalid_argument` として拒否し、直前の設定を維持します。

設定はフレームをまたいで維持され、`DrawModel3D` / `DrawModelInstances3D` 呼び出し時にコピーします。
その後設定を変更しても、登録済みの描画には影響しません。インスタンスのバッチ全体で共通です。
ベースカラー、MASKのアルファ判定と影、BLEND、スキニング、負スケール配置に同じUV変換を使います。
[カスタムシェーダー](custom-shaders-ja.md)の `ModelSurface::texcoord` も変換後の値です。

サンプラは従来どおりrepeat＋線形ミップ補間です。回転、パーツごとの設定、別のテクスチャスロットの
変換、glTFの `KHR_texture_transform` 読み込みを追加するAPIではありません。
長時間のスクロールは `fmod` などで小さなオフセットに保つと、floatの精度低下を抑えられます。
周期的に戻す場合は、カスタムシェーダーで作る模様も同じ周期にしてください。

追加のパス・テクスチャ・パイプラインは不要で、UVの計算と描画ごとの16バイトの設定を追加します。
既定値で従来の画像を維持します。未対応の独自ApplicationContextはfalseを返します。
利用側は新しい公開ヘッダとライブラリで再ビルドし、更新した `shaders.metallib` を配置してください。

`texture_transform_regression` でRGBテクスチャとMASKの移動、拡縮、恒等変換、無効値、
設定のコピー、スキニング・インスタンス、BLEND、3フレーム分の状態、影の切り抜きの整合性を検証します。
同テストは、水面の計算に用いるビュー位置・視線・光方向もハイライトOFFで確認します。
