# 粗さと環境遮蔽

`ctx.SetModelMaterialDetail3D({true})` を有効にするとglTFのroughnessFactorと
metallicRoughnessTextureのG成分、occlusionTextureのR成分とstrengthを使用します。
初期値は無効で従来の照明を維持します。描画登録時に設定を保存し、インスタンス群にも対応します。

これは既存の簡易照明の拡張です。ハイライトの強さは `ModelHighlight3D::strength` を使い、
指数は `clamp(2 / max(roughness², .015) - 2, 1, 128)` とします。
粗い部分では広く、滑らかな部分では狭いハイライトになります。有効時はshininessの指定に代わります。
金属度、エネルギー保存を含む完全なPBR、IBLはこの機能には含みません。
AOは環境光だけに掛け、直接光や鏡面反射には掛けません。Unlitは影響を受けません。
画面空間AOと異なり、置いた別の物体との接触は自動検出しません。

画像は線形データ・ミップマップで読み込み、モデルのUV変換と異方性フィルタを使います。
同じ画像を粗さとAOで使う場合はテクスチャを共有します。モデル複製でも共有します。
TEXCOORD_0・GLB内包画像に対応し、個別のKHR_texture_transformは未対応です。
カスタムシェーダーには `ModelSurface::roughness` と `occlusion` を渡します。
無効時は両方1です。ライブラリとmetallibを同時に更新してください。

forestの地面・岩は周期関数による独立した粗さ／AOマスクを使用します。
再生成は `tools/generate_surface_maps.py`、検証用素材は `tools/generate_surface_fixtures.py`。
いずれも `--check` で一致を確認できます。
