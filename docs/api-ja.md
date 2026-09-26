# API概要

この文書は、Alloy3Dを単体ライブラリとして使うための主要APIの入口をまとめます。
公開APIは `include/alloy3d` 配下のC++ヘッダだけです。MetalやCocoaに触れる
Objective-C++ヘッダは内部実装に閉じ込め、インストール対象には含めません。

## C++アプリケーションAPI

通常の利用では `alloy3d/application.h` をインクルードし、`ApplicationLoop` を
継承したクラスを実装します。すべての公開C++ APIは `alloy3d::` 名前空間にあります。

```cpp
#include <alloy3d/application.h>

class MyLoop : public alloy3d::ApplicationLoop
{
public:
  const char *GetApplicationName() const override { return "My Alloy3D App"; }

  void Start(alloy3d::ApplicationContext &ctx) override
  {
    ctx.SetTextFontSize(24.0f);
  }

  void Update(alloy3d::ApplicationContext &ctx) override
  {
    ctx.DrawBox3D({0.0f, 0.0f, 0.0f}, {1.0f, 1.0f, 1.0f}, {1.0f, 1.0f, 1.0f, 1.0f});
  }
};
```

アプリケーションの開始には `LaunchApplication` を使います。

```cpp
int main()
{
  alloy3d::LaunchApplication(std::make_shared<MyLoop>());
}
```

## ApplicationLoop

`ApplicationLoop` はアプリケーション側が実装するライフサイクルです。

- `GetApplicationName()`: ウィンドウタイトルを返します。
- `InitialWindowSize(width, height, border)`: 初期ウィンドウサイズを設定します。
- `WindowClearColor(red, green, blue, alpha)`: クリアカラーを設定します。
- `ResizeWindow(width, height)`: ウィンドウサイズ変更時に呼ばれます。
- `DroppedFiles(paths)`: ファイルドロップ時に呼ばれます。
- `Start(ctx)`: Metalビュー初期化後、最初の更新前に呼ばれます。
- `Update(ctx)`: 毎フレーム呼ばれる描画・更新処理です。
- `WillCloseWindow()`: ウィンドウ終了時に呼ばれます。

## ApplicationContext

`ApplicationContext` は1フレーム内で描画・リソース作成に使うAPIです。

2D描画:

- `Print(msg, x, y)`
- `SetTextColor(red, green, blue, alpha)`
- `SetTextFont(fontName)`
- `SetTextFontSize(fontSize)`
- `DrawLine(from, to, color)`
- `DrawRect(from, to, color)`
- `DrawRoundRect(from, to, radius, color)`
- `FillRect(from, to, color)`
- `FillRoundRect(from, to, radius, color)`
- `DrawPolygon(pos, radius, rotate, sides, color)`
- `FillPolygon(pos, radius, rotate, sides, color)`
- `CreateSprite(fname)`
- `DrawSprite(sprite)`

3D描画:

- `GetCamera()`
- `SetLight3D(direction, ambient, diffuse)`
- `SetDirectionalLight3D(light)`: 色・方向・環境光・拡散光を設定します。
- `SetDirectionalShadow3D(shadow)`: 影の有効化・範囲・解像度・バイアスを設定します。
- `SetFog3D(fog)`: カメラ前方の奥行きによる線形フォグを設定します（既定OFF）。
- `SetModelTextureTransform3D(transform)`: モデルのベースカラーテクスチャのUVを拡縮・移動します（既定は恒等変換）。[詳細](model-texture-ja.md)。
- `SetModelHighlight3D(highlight)`: モデル描画のツヤの強さ・鋭さを設定します（既定OFF）。
  描画予約時に保存します。詳細は[簡易ハイライト](highlights-ja.md)を参照してください。
- `SetHemisphereLight3D(light)`: 空色・地面色による環境光を設定します（既定OFF）。
  詳細は[フォグと環境光](environment-ja.md)を参照してください。
- `DrawLine3D(from, to, color)`
- `DrawTriangle3D(p0, p1, p2, color)`
- `DrawPlane3D(p0, p1, p2, p3, color)`
- `DrawSphere3D(center, radius, color, slices, stacks)`
- `DrawBox3D(center, size, color)`
- `DrawBox3D(center, size, rotationY, color)`
- `DrawBox3D(center, size, rotation, color)`
- `DrawCylinder3D(center, radius, height, color, segments)`
- `DrawCone3D(center, radius, height, color, segments)`
- `DrawText3D(msg, position, lineHeight, color, align)`
- `LoadModel(fname)`
- `CreateModelInstance(source)`: 形状・テクスチャ・定義を共有し、現在の姿勢から独立したモデルを作成します。
- `DrawModel3D(model, position, rotation, scale, color)`
- `DrawModelInstances3D(model, instances)`: 同じ姿勢のモデルを配置配列でまとめて描画します。

使い分けと制約は[インスタンス描画とモデル資源の共有](model-instances-ja.md)を参照してください。
`SetLight3D` の方向はワールド座標で光が進む向きです。
光源と影の入力制約・描画対象・資源管理は[シャドウマップ](shadows-ja.md)を参照してください。
GLBの透明モード・両面・Unlitは自動反映します。[基本マテリアル](materials-ja.md)も参照してください。

描画メモリの管理:

- `SetTextCacheBudget(budget)`: CPU画像・GPUテクスチャの文字キャッシュ予算を設定します。
- `GetRenderMemoryStats()`: 一時頂点バッファと文字キャッシュの保持量・解放予約状態を返します。
- `ReleaseUnusedMemory()`: 文字キャッシュを空にし、安全に再利用できる順に頂点ページを解放します。

既定の文字キャッシュ予算は2D・3D合計でCPU 8 MiB、GPU 16 MiBです。
使用例と統計の範囲は[描画メモリの管理](render-memory-ja.md)を参照してください。

## モデルのカスタムシェーダー

- `CreateModelShader(source, diagnostics)`: Metal関数を同期コンパイルしてハンドルを返します。
- `SetModelShader(shader, parameters = {0,0,0,0})`: 以降のモデルのRGB計算を変更します。nullで標準に戻ります。

ハンドルと数値は描画予約ごとに保存します。透過・スキニング・影の形状は既存処理を使います。
入力と制約は[モデルのカスタムシェーダー](custom-shaders-ja.md)を参照してください。

## CameraData

`CameraData` は投影行列とビュー行列を管理します。`ApplicationContext::GetCamera()`
から参照し、必要に応じて次のメソッドで更新します。

- `buildPerspective(fovy, aspect, znear, zfar)`: 垂直画角はラジアン、奥行きはMetalの `[0, 1]`。
- `buildOrthographic(height, aspect, znear, zfar)`
- `setAspectRatio(aspect)`: 他の投影設定を保持して更新。
- `fitBounds(worldBounds, padding = 1.1f)`: 現在の視線方向から境界全体を収めます。
- `buildModelView(eye, look, up)`
- `getProjectionMatrix()`
- `getModelViewMatrix()`
- `getEyePosition()`
- `getLookAt()`
- `getUpDirection()`
- `getProjectionMode()` / `getFieldOfView()` / `getOrthographicHeight()`
- `getNearPlane()` / `getFarPlane()` / `getAspect()`

入力制約、境界の取得と配置変換は[カメラとモデルの全体表示](camera-ja.md)を参照してください。

## Model

`Model` はGLBモデルの状態とアニメーションを扱うC++インターフェースです。

- `GetBounds(bounds)`: 現在の姿勢を反映したモデル座標の境界を取得します。

- `IsLoaded()`
- `AnimationCount()`
- `AnimationName(index)`
- `AnimationDuration(index)`
- `CurrentAnimationIndex()`
- `CurrentAnimationDuration()`
- `SetAnimation(index)`
- `SetAnimation(name)`
- `SetAnimationTime(seconds)`
- `SetAnimationBlend(animationA, timeASeconds, animationB, timeBSeconds, weight)`
- `RigCount()`
- `RigName(index)`
- `RigIndex(name)`
- `RigTransform(index, transform)`
- `RigPosition(index, position)`

## Sprite

`Sprite` は2Dスプライト描画用のC++インターフェースです。

- `IsLoaded()`
- `SetAlign(align)`
- `SetScale(scale)`
- `SetRotate(rotate)`
- `SetPosition(x, y)`
- `SetFaceColor(red, green, blue, alpha)`

## 入力ヘルパー

`alloy3d/keyboard.h` と `alloy3d/game_pad.h` は現在公開ヘッダに含まれています。

- `alloy3d::keyboard::Fetch(callback)`: キー状態を取得します。
- `alloy3d::gamepad::InitGamePad(...)`: ゲームパッド更新コールバックを設定します。
- `alloy3d::gamepad::GetPadState(index, state)`: 毎フレームポーリング向けに状態を取得します。

これらは便利なヘルパーですが、今後ライブラリ本体の公開APIとして固定するか、
サンプル支援APIとして分離するかは検討対象です。

## 内部Objective-C++ API

`Draw2D`、`Draw3D`、`Texture` などのObjective-C++ヘッダは `functions/internal`
配下の内部実装です。外部利用者向けの安定APIではありません。

## 広域シーン向けの追加API

- `CreateModelLoader()`：コールバックの寿命から独立したバックグラウンドロード用関数。
- `GetModelResourceStats(models)`：共有分を重複排除したモデル集合のMetal資源量。
- `SetShadowCulling3D(true)`：ライト視錐台で影の対象を絞る任意の機能。初期値OFF。
- `StreamingCache<T>`：要求数とフレームごとの反映件数を制限する任意の非同期キャッシュ。

寿命・計測対象・サンプルの説明は[5km四方のサンプル](open-world-ja.md)を参照してください。
