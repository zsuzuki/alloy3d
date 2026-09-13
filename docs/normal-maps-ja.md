# 法線マップ

GLBに内包したglTF `normalTexture` を読み取り、表面の凹凸に沿って拡散光・半球環境光・
ハイライトを計算します。`ModelSurface::normal` にも変更後のビュー座標法線を渡します。
法線マップがないモデル、Unlit素材の標準照明は従来どおりです。

`ctx.SetModelNormalMapping3D({0})` で無効、`{1}`（初期値）で素材の強度を使用します。
値はglTFの `normalTexture.scale` に掛ける倍率で、0〜8の有限値を受け付けます。
不正値は例外となり以前の設定を保ちます。設定は各描画・インスタンス群の登録時に保存します。

法線画像はsRGB変換を行わない線形データとして読み込み、ミップマップと選択した異方性フィルタを使用します。
ベースカラーと同じ `ModelTextureTransform3D` を画像の座標に適用します。
`TANGENT` がある場合はスキニング・配置の線形変換と向きの反転を反映し、法線と直交化して使います。
ない場合は変形後の位置と元のUVの画面微分から接線を求めます。UVが退化している部分は元の法線を保ちます。
これはMikkTSpaceによるオフライン接線生成とは異なるため、その方式で焼いたモデルでは接線の同梱を推奨します。
非一様スケール・反転配置・裏面にも対応します。幾何の輪郭や影の形状は変化しません。

現段階ではTEXCOORD_0、GLB内包画像に対応します。法線テクスチャ独自のKHR_texture_transformや
別のUVセットは診断を表示してその法線画像を使いません。ライブラリ・利用アプリ・metallibは同時に再ビルドしてください。

forestでは地面、幹・根の下部、岩、水面に適用し、`N`で比較できます。
色画像から高さを推定する代わりに、独立した周期関数から生成した凹凸データを使います。
樹皮の溝や水面の細波を表す補助的な材質であり、色画像と一対一に一致する高精細モデルのベイクではありません。
樹冠の高密度メッシュと焼き込み画像は維持しています。

```sh
python3 tools/generate_surface_maps.py --check
python3 tools/generate_normal_fixtures.py --check
python3 tools/generate_forest_assets.py --check
ctest --test-dir build -R 'normal_mapping|forest_scene' --output-on-failure
```
