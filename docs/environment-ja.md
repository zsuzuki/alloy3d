# 距離フォグと空・地面の環境光

追加の描画パスやテクスチャを使わず、既存の3D描画に奥行きと色付きの環境光を加えます。
両方とも既定では無効です。ビューアーでは **G** でフォグ、**L** で環境光を切り替えます。

## 距離フォグ

```cpp
alloy3d::Fog3D fog;
fog.enabled = true;
fog.color = {.02f, .025f, .035f}; // 背景色に合わせた線形RGB
fog.start = 8;
fog.end = 30;
ctx.SetFog3D(fog);
```

カメラ前方への奥行き `d = -viewPosition.z` を使う線形フォグです。
開始距離以下は元の色、終了距離以上はフォグ色、その間を線形補間します。
カメラからの球状の距離ではないため、広角の画面端では球状フォグと差が出ます。
透視投影・平行投影のどちらでも、距離の単位はワールド座標と同じです。

モデル、インスタンス、基本図形、線、3D文字に適用します。2D描画や背景色は変更しません。
Unlit素材にも適用し、標準／カスタムの陰影計算の**後**にRGBだけを補間します。
アルファ、MASKの切り抜き判定、半透明の描画順は保持します。
フォグだけでは描画を省略しません。影の深度パスにもフォグを適用しません。

色は各成分が有限の0〜1、距離は有限の `0 <= start < end` が必要です。
幅が小さすぎて逆数をfloatで表現できない範囲も拒否します。

## 空・地面の環境光

```cpp
alloy3d::HemisphereLight3D ambient;
ambient.enabled = true;
ambient.skyColor = {.65f, .8f, 1};
ambient.groundColor = {.3f, .25f, .2f};
ambient.up = {0, 1, 0}; // ワールド座標の「空」の方向
ambient.intensity = .35f;
ctx.SetHemisphereLight3D(ambient);
```

上を向いた面には空色、下を向いた面には地面色を使い、中間の向きは色を補間します。
法線とup方向の内積から比率を計算するため、実際の反射・遮蔽や新しい影は生成しません。
upは設定時に正規化し、カメラと一緒には回転しません。非一様スケール、スキニング、
両面素材の裏面は既存の補正済み法線を使います。

有効時は `DirectionalLight3D::ambient` を**置き換えます**。平行光の拡散光と影はそのままです。
例えば空色・地面色を両方 `{1,1,1}`、intensityを従来のambientと同じにすると、
従来と同じ均一な環境光になります。無効にすると最新の `SetLight3D` /
`SetDirectionalLight3D` で指定したambientへ戻ります。
Unlit素材、法線のない線・モデル、3D文字には環境光を適用しません。

色とintensityは有限の0〜1、upは有限かつ長さが0でない必要があります。
色はフォグ・環境光ともに線形RGBです。sRGBの画像や16進カラーから値を取る場合は、
利用側で線形RGBに変換してください。

## 状態とカスタムシェーダー

両APIはシーン全体の永続状態です。平行光と同様、**描画実行時の最後の設定**がそのフレームの
全3D描画に適用されます。モデルごとの描画予約時に保存する `SetModelShader` とは異なります。
フレーム内でON/OFFを挟んでオブジェクト単位に使い分けるAPIではありません。

無効化は `ctx.SetFog3D({})` / `ctx.SetHemisphereLight3D({})` です。
同梱Metalホストでは成功時にtrue、無効な値は無効設定時も `std::invalid_argument` を投げ、
以前の設定を維持します。未対応の独自ApplicationContextでは既定実装がfalseを返します。
公開API追加のため利用側も再ビルドし、更新した `shaders.metallib` を配置してください。

カスタムモデルシェーダーの `s.litColor` は環境光・簡易ハイライトを反映済み、フォグは未適用です。
`return s.litColor;` なら標準描画と一致します。陰影を自分で組み立てる場合は、
新しい `s.ambientColor`（float3）を使います。

```metal
if (s.unlit) return s.baseColor;
return s.baseColor * (s.ambientColor + s.diffuse * s.shadow * s.lightColor) + s.specularColor;
```

従来の `s.ambient` は互換性のため、平行光設定のスカラー値のままです。
これを使い続ける既存のカスタムシェーダーは、空・地面の色を自動では反映しません。
フォグはカスタム関数の返り値にライブラリが適用するため、関数内で重ねて計算する必要はありません。

## 負荷と検証

距離範囲の逆数とup方向の正規化は設定時に計算します。GPUでは少量の演算・色の補間と、
シーン共通の有効フラグによる分岐を使います。無効時はフォグ用の奥行き計算と色補間、
環境光の内積・色補間をスキップします。ただし分岐、頂点出力の1成分とUniformsの80バイト増加は
あるため、「無効なら完全にゼロコスト」とはしていません。
インスタンスのバッチ分割、追加パス、追加テクスチャ、毎フレームの新規資源確保は行いません。

`environment_regression` は実GPUの画素でフォグの開始・中間・終了、投影方式、Unlit、
BLEND、MASK、カスタム関数、線・3D文字、環境光の向き、カメラ回転、裏面、
スキニング・非一様／負スケールのインスタンス一致、入力検証、3フレームの状態分離を確認します。

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DALLOY3D_BUILD_TESTS=ON
cmake --build build -j 8
ctest --test-dir build --output-on-failure
```

比較用の `alloy3d_environment_probe` は1536×1536で144個のモデルをインスタンス描画し、
床と球を加えた同一シーンを、OFF／フォグ／環境光／両方ONで描きます。
最初の20フレームを除いた80フレームのCPU・GPU時間と画素ハッシュ、PPM画像を出力します。
性能計測ではMetal API Validationを無効にしてください。

```sh
build/tests/alloy3d_environment_probe build/shaders/shaders.metallib \
  assets/samples/models/sample_cube.glb /tmp/alloy3d-environment
```

2026-09-11、Apple M3 Ultra、Release、影OFF・MSAAなし・Metal API Validationなしでの計測です。
変更前はコミット `67385bf` を別ディレクトリでビルドし、同じ比較用シーンを実行しました。
同じ条件を2回実行した各80フレームのGPU中央値の範囲を示します。

| 状態 | GPU中央値 |
|---|---:|
| 変更前 | 0.0944〜0.0953 ms |
| 追加後・両方OFF | 0.1050〜0.1054 ms |
| フォグのみ | 0.1048〜0.1056 ms |
| 環境光のみ | 0.1049〜0.1065 ms |
| 両方ON | 0.1057〜0.1071 ms |

このシーンでは、変更前から約0.01 msの増加があり、両方OFFでも完全にはなくなりません。
ON/OFF間の小さな差は計時のばらつきも含みます。他のGPU・解像度・モデル数や画面占有率での
負荷はこの数値から保証しません。CPUの描画予約＋エンコードの中央値は約0.034〜0.040 msです。
モデル描画は全状態で1回のインスタンス描画を維持しました。
変更前と追加後OFFの画素ハッシュはともに `c5d572df0f9686b9` で一致しました。
Metal API Validationを有効にした回帰テストは16件すべて成功しています。
