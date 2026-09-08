# インスタンス描画とモデル資源の共有

2026-09-09。法線変換の修正、同じ姿勢をまとめて描くAPI、資源を共有して
個別にアニメーションできるモデル複製を追加した。

## 同じ姿勢をまとめて描く

```cpp
// Startで1回ロードし、配置配列もアプリ側で保持しておく。
model = ctx.LoadModel("models/tree.glb");

// Updateで呼ぶ。std::vector / std::array もそのまま渡せる。
std::array<alloy3d::ModelInstance, 2> placements{};
placements[0].position = {-2, 0, 0};
placements[1].position = { 2, 0, 0};
placements[1].scale = {1, 2, 1};
placements[1].color = {.7f, 1, .7f, 1};
ctx.DrawModelInstances3D(model, placements);
```

`ModelInstance` は位置・回転・スケール・色を持つ。既定値は原点、回転0、
スケール1、白。回転の単位・順序は既存の `DrawModel3D` と同じ。
配列は登録時にコピーするため、呼び出し後に変更・破棄できる。
空配列、nullまたは未ロードのモデルは何も描かない。

同じ呼び出し内の個体は、モデルの**描画実行時の姿勢**を共有する。
同じモデルに別の時刻を設定して何度も登録しても、姿勢のスナップショットにはならない。
これは既存の単体描画と同じ扱いであり、異なる姿勢には下記の複製を使う。

通常は1パーツにつき1回のMetal描画命令になる。個体ごとの変換・色は専用の
動的バッファへまとめて転送する。バッファは3ページを再利用し、既存の
`ReleaseUnusedMemory()` と統計の `instanceBufferBytes` にも対応する。
デバイス上限を超える個体データは `std::length_error` で通知する。

単体描画と一括描画の呼び出し順は維持する。一括描画内で複数パーツをまとめる
場合は、パーツ→配列内の個体の順になる。半透明の複数パーツは順序の影響があるため、
次の条件では自動的に個別描画へ戻す。

- 複数パーツのいずれかが半透明、または配置色のアルファが1未満。
- 複数パーツのいずれかがテクスチャを持つ。現在のローダーは画像の不透明性を
  記録しないため、アルファを含む可能性があるものとして扱う。

1パーツのモデルは個体の順序が変わらず、テクスチャ・半透明も一括描画する。
不透明／半透明のマテリアル仕様や自動ソートは、この変更では追加していない。

## 異なる姿勢で描くモデルを複製する

```cpp
// Startで生成し、それぞれModelPtrとして保持する。
modelA = ctx.LoadModel("models/rig_25.glb");
modelB = ctx.CreateModelInstance(modelA);

// Updateではそれぞれ独立に更新する。
modelA->SetAnimationTime(time);
modelB->SetAnimationTime(time + .5f);
ctx.DrawModel3D(modelA, {-2, 0, 0}, {0, 0, 0}, {1, 1, 1});
ctx.DrawModel3D(modelB, { 2, 0, 0}, {0, 0, 0}, {1, 1, 1});
```

`CreateModelInstance(source)` は現在の姿勢（ブレンド中も含む）をコピーする。
その後のクリップ選択・時刻・ブレンド変更は互いに干渉しない。

| 共有するもの | 個別に保持するもの |
| --- | --- |
| 頂点・インデックス・テクスチャ | 現在の姿勢・関節行列 |
| ノード構造・基準姿勢・スキン定義・アニメーション定義 | 再生状態・姿勢計算の作業領域・GPU関節バッファ3ページ |

複製時にファイルを読み直さず、形状用GPUバッファを再生成しない。
複製元を破棄しても、残ったモデルは描画・更新できる。複製からさらに複製しても共有を維持する。
`LoadModel` の繰り返しは従来どおり独立ロードであり、共有には明示的にこのAPIを使う。
異なる姿勢のモデルを1回のGPU命令にまとめる機能は今回の対象外。

付属のMetalホストでは、null・未ロード・対応しないモデルの複製はnullを返す。
独自 `ApplicationContext` の既定実装では複製はnull、一括描画は既存の単体描画を
繰り返す。公開仮想メソッドとシェーダーの変更があるため、利用側とシェーダーも再ビルドする。

## 陰影の修正

モデル配置とノード・スキニングの非一様スケールに対し、法線を逆転置変換する。
スキニングはウェイトで合成した変形行列を使い、頂点法線を正規化してから補間する。
負のスケールにも対応する。特異、または数値的に特異に近い変換では法線を0とし、
既存の法線なし描画と同じく照明を適用しない。NaNを描画へ流さないための扱いである。

`SetLight3D` の方向は光が進む向きの**ワールド座標**と定義した。
ビュー座標の法線と比較する前に光源方向も変換し、カメラの回転で陰影が変わる問題を修正した。
このため、従来の不正確な陰影を前提にした画像とは見え方が変わる。

## 計測と検証

Release / Apple M3 Ultra、256×256の画面へ小さな三角形モデルを格子状に配置。
同じ修正後ライブラリ内の個別描画と一括描画を比較した。
60フレームのうち先頭10を除く50フレームの中央値。
性能計測ではMetal検証レイヤーとAddressSanitizerを無効にする。
命令登録時間にはレンダーパスとエンコーダーの準備も含む。

| 個体数 | 描画方式 | GPU描画命令数 | CPU要求生成 ms | CPU命令登録 ms | GPU ms |
| ---: | --- | ---: | ---: | ---: | ---: |
| 1,000 | 個別 | 1,000 | 0.0073 | 0.2223 | 0.0733 |
| 1,000 | 一括 | 1 | 0.0015 | 0.0225 | 0.0397 |
| 10,000 | 個別 | 10,000 | 0.0615 | 1.8490 | 0.2941 |
| 10,000 | 一括 | 1 | 0.0109 | 0.1350 | 0.0495 |

これは小さい形状で命令登録の負荷を見る測定で、一般的なモデルやアプリ全体の
FPS改善率ではない。フレームごとにGPU完了を待ち、画像を読み戻すため、
通常の3フレーム並列動作のスループット測定でもない。

ReleaseとDebug＋AddressSanitizerの両方で、Metal検証レイヤー付きCTest全5件が成功した
（GPUテストのスキップなし）。ビューワーの通常展示と `I` キーによるデモ表示も実機で確認した。

`instance_regression` は次を検証する。

- 外部からの非一様／負のスケール、ノード変形、複数関節のウェイトを含む法線。
  形状から独立に計算した陰影の明るさとGPU画素を比較する。
- カメラを回転してもワールド光源による明るさが変わらないこと。
- 個別／一括描画の画素一致と命令数、空配列、混在する要求の順序、入力配列とモデルの寿命。
- 半透明・テクスチャ付き複数パーツのフォールバック。
- 10,000個のデータで3ページを使い、縮小・再拡張後も画像が一致すること。
- 実際のGPU資源と定義データの共有、ブレンド姿勢の複製、独立した更新、複製元破棄後の描画。

```sh
python3 tools/generate_render_fixtures.py --check
cmake -S . -B build-test -DCMAKE_BUILD_TYPE=Release -DALLOY3D_BUILD_TESTS=ON
cmake --build build-test -j8
ctest --test-dir build-test --output-on-failure

MTL_DEBUG_LAYER=0 build-test/tests/alloy3d_instance_regression \
  build-test/shaders/shaders.metallib assets/tests/rendering \
  assets/tests/animation/rig_25.glb --benchmark
```

ビューワーは `I` キーでデモに切り替える。81個を同じ姿勢で一括描画し、
手前の3体は資源を共有しながら別々にアニメーションする。もう一度 `I` で元の展示に戻る。

Metalの呼び出し仕様はAppleの
[`drawIndexedPrimitives` / `instanceCount`](https://developer.apple.com/documentation/metal/mtlrendercommandencoder/drawindexedprimitives%28type%3Aindexcount%3Aindextype%3Aindexbuffer%3Aindexbufferoffset%3Ainstancecount%3Abasevertex%3Abaseinstance%3A%29)、
法線変換はKhronosの
[The Mathematics of Skinning](https://github.khronos.org/Vulkan-Site/tutorial/latest/Advanced_glTF/Skeletal_Compute_Skinning/02_skinning_math.html)
を参照。
