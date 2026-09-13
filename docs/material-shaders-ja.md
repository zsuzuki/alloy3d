# ライティング前のマテリアル関数

`CreateModelMaterialShader(source, diagnostics)` でマテリアルの入力を編集する関数を作成し、
既存の `SetModelShader(handle, parameters)` で選択します。既存のRGB出力関数もそのまま使えます。

```metal
ModelMaterial alloy3dMaterial(ModelMaterial m, ModelMaterialContext c, float4 p)
{
  m.roughness = .18;
  m.emissive = float3(.02, .04, .01);
  return m;
}
```

編集対象はbaseColor、ビュー空間のnormal、roughness、occlusion、emissiveです。
コンテキストは変換後UV、ビュー位置、視線方向、unlitを渡します。法線マップの後、ライティングの前に実行します。
粗さを変更するとハイライトの指数へ変換し、AOは環境光にだけ適用します。発光は影の影響を受けず、フォグは適用されます。
既存のアルファ・深度・影投影・片面判定は維持します。UnlitをLitへ変更する機能ではありません。
非有限の出力は元の値を使用し、RGB/発光は0〜64、粗さ/AOは0〜1へ制限します。

forestの水はこの入口へ移行しました。独自の光・影・ハイライト計算を廃し、
波の法線・粗さ・基礎色をライブラリ共通のライティングへ渡しています。
`material_shader_regression` は恒等関数の画素一致、法線/AO/発光、フォグ、材質と一括描画の整合を確認します。
