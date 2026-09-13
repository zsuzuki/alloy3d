# 高さフォグ

`ctx.SetHeightFog3D(fog)` で低い場所にたまる霧を設定できます。初期値は無効です。

```cpp
alloy3d::HeightFog3D fog;
fog.enabled = true;
fog.color = {.55f, .65f, .6f};
fog.density = .02f;
fog.baseHeight = 0;
fog.falloff = .5f;
fog.maxOpacity = .6f;
ctx.SetHeightFog3D(fog);
```

ワールドY方向に上がるほど指数的に密度が下がります。densityはbaseHeightでの密度、
falloffは高さ方向の減衰率です。視線の経路上で密度を積分し、透視投影ではカメラ位置、
正射影ではカメラ平面上の各平行な視線から計算します。カメラを傾けても霧の上下は変わりません。
falloffが0なら均一密度の距離に応じた霧です。maxOpacityで濃さの上限を設定します。

線形の距離フォグと併用でき、その後に適用します。通常モデル・基本図形・3D文字・
カスタムシェーダー・インスタンスに対応し、アルファと深度は変更しません。2D UIには掛かりません。
フレームの描画時点のシーン設定を使います。追加パスや画像は不要です。

全値は有限で、RGB/density/maxOpacityは0〜1、falloffは0〜100、baseHeightはワールド座標です。
不正な設定は例外となり以前の状態を保ちます。ライブラリ・metallib・利用側を同時に再ビルドしてください。
forestは薄い高さフォグを追加し、`J`で高さフォグのみ、`G`で距離フォグと合わせて切り替えます。
これは枝による光路の遮蔽やボリューム散乱を計算するものではありません。
