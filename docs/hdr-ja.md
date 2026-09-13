# HDR描画とトーンマッピング

`ApplicationLoop::GetRenderOptions()` で `{4, true}` を返すと、4x MSAAとHDR中間描画を要求します。
初期値はHDR無効です。起動時の設定で、実行中のHDR有無の切替は行いません。
`SetPostProcessing3D({exposure, ToneMapping3D::ACES})` で露出を変更できます。
トーンマッピングはNone（出力先でクリップ）、Reinhard、ACES近似を選べます。露出は0〜16です。

3Dを線形RGBA16Floatへ描き、MSAAを解決してから通常の描画先へトーンマッピングします。
sRGB出力への符号化は描画先のフォーマットが行います。HDRディスプレイへのEDR出力ではありません。
2D・文字・HUDは処理後に重ねます。既存の影・フォグ・材質・透明ソートは3D中間描画内で使用します。

描画先サイズごとに3フレーム分を遅延確保し、サイズ変更と`ReleaseUnusedMemory()`に対応します。
追加容量は`RenderMemoryStats.postProcessBytes`で確認できます。1000×1000・4x MSAAは色だけで概ね120MB/3フレームです。
深度・ステンシルは描画先と共有します。HDR無効時は中間ターゲットを確保しません。

forestはHDRとACES（露出1）を使用します。`hdr_regression`は1を超える色を露出前に保持すること、
数値変換、1/4サンプル、フレーム再利用、設定の拒否、2D色の保持を検証します。

forestのMSAA画像比較は、浮動小数点の解決後に生じる8bit丸め境界を考慮し、
最大0.01%の画素に各チャンネル1段階の差だけを許容します。1サンプルと低水準の描画回帰は完全一致のままです。
