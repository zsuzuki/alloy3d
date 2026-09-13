# Forest向け描画機能の導入記録

既存のforestを `c94c45a` に保存した後、次の順で実装・検証・コミットした。ライブラリの高度な機能は明示的に有効にする構成。forestでは比較用キーを備える。

| コミット | 機能 | 設計・利用方法 |
| --- | --- | --- |
| 2042a31 | MSAA | [描画品質](render-quality-ja.md) |
| 03a367d | 異方性フィルタ | [描画品質](render-quality-ja.md) |
| 2496b29 | glTF法線マップ | [法線マップ](normal-maps-ja.md) |
| 03ec7b1 | 粗さ・AO | [表面詳細](surface-detail-ja.md) |
| e5912b6 | 草葉の透過光 | [透過光](transmission-ja.md) |
| 2d02e8d | 高さフォグ | [高さフォグ](height-fog-ja.md) |
| 9c2d780 | ソート順を保つ透明バッチ | [透明バッチ](transparent-batching-ja.md) |
| 89bb0cc | 視錐台カリング | [可視判定](visibility-ja.md) |
| 7cd47f1 | 投影サイズLOD・ディザー遷移 | [LOD](lod-ja.md) |
| c8908b7 | 根元を固定するGPU風変形 | [風](wind-ja.md) |
| a4c24a5 | MASKのAlpha-to-Coverage | [描画品質](render-quality-ja.md) |
| ce3d7b7 | PCF・シャドウ安定化 | [影](shadows-ja.md) |
| dd918f6 | 照明前の材質シェーダー | [材質フック](material-shaders-ja.md) |
| 2dc519b | HDR・トーンマッピング | [HDR](hdr-ja.md) |
| 8e059c0 | ブルーム | [HDR](hdr-ja.md) |
| 7502c79 | 影の表示制御・独立LOD | [影](shadows-ja.md) |
| dcb4ff0 | 不透明色・深度とソフトパーティクル | [シーン参照](scene-effects-ja.md) |
| ae145cc | 水面の画面内反射・屈折 | [シーン参照](scene-effects-ja.md) |
| e5c9836 | 影による遮蔽付きボリューム光芒 | [光芒](volumetric-light-ja.md) |

Apple M3 Ultra、1000×1000、4×MSAA、HDRで、全機能有効のオフスクリーン計測はGPU中央値約6.37 ms、CPU登録・エンコード約0.33 ms、モデル描画77回。これは実ウィンドウのフレーム時間ではなく、この視点とアセットの参考値。画面サイズ・視点・GPUによって変わる。

ライブラリは単一の方向光・シャドウマップを継続使用する。風は専用APIで、任意の頂点シェーダーの注入ではない。カスケードシャドウ、時間方向AA、平面反射カメラ、流体計算は今後の拡張候補。ディザー遷移の粒状感と、画面内反射の欠落は各機能の制約として残る。

最終検証: CTest 35件すべて成功（Metal API Validation有効）。forest、ビルボード、表面マップ、法線・粗さ/AO・ミップマップ・材質の計7生成スクリプトの `--check` も成功。実アプリで4×MSAA/HDR描画、HUD、停止、ウィンドウのリサイズ、光芒・水面・トーンマップのキー切り替え、通常終了・再起動を確認した。
