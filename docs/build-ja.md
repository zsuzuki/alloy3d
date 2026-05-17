# ビルドと利用方法

Alloy3DはmacOS Metal向けの軽量な描画ライブラリです。現在はApple Silicon
macOS環境を前提にしています。

## 必要環境

- Apple Silicon Mac、またはarm64 macOS向けビルド環境
- XcodeまたはCommand Line Tools
- macOS SDK
- `xcrun` から利用できる `metal` / `metallib`
- CMake 3.21以上

## サンプルビューアを含めてビルド

`samples/viewer/main.cpp` はライブラリ本体ではなく、動作確認用のサンプルビューアです。
デフォルトではこのビューアも一緒にビルドされます。

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build
```

生成される主なターゲット:

- `Alloy3D::application`: C++のアプリケーションループAPIとMetalホスト
- `Alloy3D::functions`: `Alloy3D::application` が使う実装ライブラリ
- `alloy3d_viewer`: サンプルビューア

## ライブラリだけをビルド

サンプルアプリを不要にする場合は `ALLOY3D_BUILD_VIEWER=OFF` を指定します。

```sh
cmake -S . -B build -DALLOY3D_BUILD_VIEWER=OFF
cmake --build build
```

## インストール

インストールルールはデフォルトで有効です。無効にする場合は
`-DALLOY3D_INSTALL=OFF` を指定します。

```sh
cmake --install build --prefix /path/to/prefix
```

インストール後はCMakeの利用側プロジェクトから次のように参照できます。

```cmake
find_package(Alloy3D CONFIG REQUIRED)

add_executable(my_viewer main.cpp)
target_link_libraries(my_viewer PRIVATE Alloy3D::application)
```

新規コードでは次のようにインクルードします。

```cpp
#include <alloy3d/application.h>
```

公開ヘッダは `include/alloy3d` 配下のC++ APIだけです。Objective-C++の内部ヘッダは
インストール対象に含めません。

## シェーダーリソース

Alloy3Dの描画には `shaders.metallib` が必要です。サンプルビューアでは
ビルド後にアプリバンドル内の `Resources/shaders/shaders.metallib` へコピーします。

ライブラリとして組み込むアプリでは、同じように実行時バンドルから
`shaders/shaders.metallib` として読める場所へ配置してください。

## 現在の制約

- macOS / Metal専用です。
- arm64 macOSビルドのみを想定しています。
- 低レベルObjective-C++ APIは内部実装で、公開・インストール対象ではありません。
- 外部利用では基本的に `Alloy3D::application` をリンクしてください。
