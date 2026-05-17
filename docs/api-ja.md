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
- `DrawModel3D(model, position, rotation, scale, color)`

## CameraData

`CameraData` は投影行列とビュー行列を管理します。`ApplicationContext::GetCamera()`
から参照し、必要に応じて次のメソッドで更新します。

- `buildPerspective(fovy, aspect, znear, zfar)`
- `buildModelView(eye, look, up)`
- `getProjectionMatrix()`
- `getModelViewMatrix()`
- `getEyePosition()`
- `getLookAt()`
- `getUpDirection()`

## Model

`Model` はGLBモデルの状態とアニメーションを扱うC++インターフェースです。

- `IsLoaded()`
- `AnimationCount()`
- `AnimationName(index)`
- `AnimationDuration(index)`
- `CurrentAnimationIndex()`
- `CurrentAnimationDuration()`
- `SetAnimation(index)`
- `SetAnimation(name)`
- `SetAnimationTime(seconds)`
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
