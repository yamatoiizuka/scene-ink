# TrajectoryType アーキテクチャ

この文書は、現在の `TrajectoryType` の設計意図と実装上の責務分担を残すためのメモです。元のセットアップ文書では AR 空間上の線描画を想定していましたが、現在の実装は「iOS 画面上に、カメラ画像から切り出したブラシ断面をストロークとして伸ばす」方向に寄せています。

## 目的

`TrajectoryType` は、iPhone のカメラ画像を素材にして、端末の移動軌跡を画面上のストロークへ変換する iOS アプリです。

ユーザー操作は、ストローク開始前の画面ドラッグに集約します。

- カメラプレビュー上のドラッグ開始位置: サンプリング位置とストローク開始位置を決める。
- ドラッグ開始位置から終了位置までの距離: ブラシ幅を決める。
- ドラッグ開始位置から終了位置への方向: ブラシ角度を決める。
- 録画中の画面タッチ終了: 現在のストロークを終了する。

ストローク中は背景カメラ画像を非表示にし、黒背景の上に描画済みストロークと現在のストロークだけを表示します。複数ストロークは保持され、後から描いたものが上に重なります。

## プロジェクト構成

```text
TrajectoryType/
├── TrajectoryType.xcworkspace
├── TrajectoryType.xcodeproj
├── TrajectoryType/
│   └── TrajectoryTypeApp.swift
├── TrajectoryTypePackage/
│   ├── Sources/TrajectoryTypeFeature/
│   │   ├── ContentView.swift
│   │   ├── ARSessionManager.swift
│   │   ├── ARViewContainer.swift
│   │   ├── FrameCapture.swift
│   │   ├── ScreenStrokeRecorder.swift
│   │   ├── StrokeCanvasView.swift
│   │   ├── StrokeTouchSurface.swift
│   │   ├── BrushDragConfiguration.swift
│   │   ├── BrushDragGuideView.swift
│   │   ├── ScreenStroke.swift
│   │   ├── ScreenStrokeSample.swift
│   │   └── CameraPose.swift
│   └── Tests/TrajectoryTypeFeatureTests/
└── docs/
    └── ARCHITECTURE.md
```

アプリターゲットは薄く保ち、実装の中心は Swift Package の `TrajectoryTypeFeature` に置いています。

## 主要コンポーネント

### `ContentView`

画面全体の合成と状態連携を担当します。

- `ARViewContainer` を背面に配置し、録画中だけ透明にする。
- 録画中は黒背景を表示する。
- `StrokeCanvasView` で確定済みストロークとアクティブストロークを描画する。
- `StrokeTouchSurface` で画面ドラッグを受け、開始点・幅・角度を決めてストローク開始へつなぐ。
- 録画中の画面タッチでストローク終了へ切り替える。
- AR フレーム更新ごとに `ScreenStrokeRecorder.record(...)` を呼ぶ。

`ContentView` はアプリのオーケストレーション層で、座標変換や画像切り出しの詳細は持たせていません。

### `ARSessionManager`

ARKit セッションのライフサイクルと最新フレームの状態を管理します。

- `ARSession` を所有する。
- `ARWorldTrackingConfiguration` を起動する。
- `ARSessionDelegate.session(_:didUpdate:)` で `CameraPose` を更新する。
- 最新のカメラフレームから `FrameCapture` を使ってブラシ断面を生成する。
- ストローク開始時に指定されたドラッグ開始位置を、ブラシ断面のサンプリング位置として保持する。

`ARSessionManager` は `@MainActor` / `@Observable` で、SwiftUI 側から最新状態を監視できるようにしています。

### `FrameCapture`

AR カメラフレームからブラシ断面画像を生成します。

現在の断面生成は次の流れです。

1. `CVPixelBuffer` を `CIImage` に変換する。
2. 縦持ち画面に合わせて `.oriented(.right)` を適用する。
3. 画面ドラッグ開始位置をカメラ画像上のサンプリング位置へ変換する。
4. ブラシ角度に合わせて画像を回転する。
5. サンプリング位置を通る幅 1px の縦断面を切り出す。
6. `1 x 320` の `CGImage` として返す。

サンプリング位置は `normalizedPreviewPoint` と `previewSize` を使って、AR プレビューの aspect-fill 表示に合わせて補正しています。画面座標は左上原点、Core Image 側は下方向が反転するため、Y 座標は変換時に反転します。

### `ScreenStrokeRecorder`

AR の移動量を画面上のストロークサンプルへ変換します。

ストローク開始時には以下を保存します。

- ドラッグ開始位置
- 開始時点の AR カメラ transform
- ドラッグで決めた初回ブラシ角度
- 現在のデバイス角度デルタ
- アクティブストロークの空配列

AR フレームごとに、開始 transform から現在 transform までの相対移動量を求め、開始時点の画面に並行な平面へ投影します。ストロークサンプルは画面上の `x/y` 正規化座標だけを持ち、奥行き方向の `z` 変化量は保存も描画もしません。ブラシ角度は、初回ブラシ角度に開始 transform から現在 transform までのデバイス角度デルタを足して更新します。

デバイス角度デルタは relative rotation の XY 投影ではなく、quaternion の swing-twist 分解でローカル Z 軸まわりの twist だけを取り出します。これにより、画面に並行な平面上の回転だけを反映し、端末を奥行き方向へ傾ける pitch/yaw 成分はストローク回転へ入れません。

```swift
screenTranslation = SIMD2(relativeTranslation.y, relativeTranslation.x)
```

この変換では `relativeTranslation.z` を意図的に捨てます。現在の実機確認で「順方向」として扱っている軸対応は `relativeY -> screenX`、`relativeX -> screenY` です。表示時にはアクティブストローク全体をドラッグ開始点まわりに現在のデバイス角度デルタで 2D 回転し、ストローク終了時にはその見た目の座標で確定します。必要に応じてこの 1 行や回転方向を変えることで、上下左右の反転や回転補正を調整できます。

サンプル追加は毎フレームではなく、以下のいずれかを満たす場合だけ行います。

- 前回描画点から 3pt 以上動いた。
- ブラシ角度が 2 度以上変化した。
- ブラシ幅が 1px 以上変化した。

これにより、AR フレームレートに対して描画データが過剰に増えないようにしています。

### `StrokeCanvasView`

ストローク配列を UIKit の `UIView.draw(_:)` で合成描画します。現在は Metal ではなく Core Graphics / UIKit ベースです。

描画はセグメント単位です。

1. 隣り合う 2 つの `ScreenStrokeSample` を取り出す。
2. 2 点間の方向をストローク接線として使う。
3. ブラシ角度から断面方向ベクトルを作る。
4. 2 サンプルの幅と角度から四角形のクリップ領域を作る。
5. 単位矩形 `1 x 1` を、ストローク接線方向と断面方向へアフィン変換する。
6. 断面画像をその矩形に描画する。

後続ストロークほど配列の後ろに入り、描画時も後から描かれるため、画面上では上に重なります。

### `BrushDragConfiguration`

画面ドラッグの開始点と終了点からブラシ設定を作る値オブジェクトです。

- 開始点を画面上のストローク開始位置として使う。
- 開始点から終了点までの距離をブラシ幅にする。
- 開始点から終了点への方向をブラシ角度にする。
- 左方向を 0 度、下方向を 90 度、右方向を 180 度、上方向を 270 度に対応させる。

角度はブラシ描画の断面方向と、カメラ画像からサンプリングする断面角度の両方に使われます。

### `StrokeTouchSurface`

画面全体に重ねる透明な UIKit view です。ストローク開始前はドラッグを受け取り、開始点・終了点・view size を `ContentView` に渡します。

ドラッグ中は `BrushDragGuideView` が開始点と終了点を結ぶガイドを表示します。ドラッグ終了時にブラシ設定を確定し、録画中は画面タッチの終了でアクティブストロークを確定します。

## データモデル

### `CameraPose`

ARKit の `simd_float4x4` から位置、回転、timestamp を取り出した値オブジェクトです。デバッグ表示や相対 transform 計算の入力になります。

### `ScreenStrokeSample`

画面上の 1 サンプル点です。

- `normalizedPoint`: 画面サイズに依存しない `0...1` の正規化座標
- `brushAngleRadians`: サンプル時点のブラシ角度
- `width`: サンプル時点のブラシ幅
- `timestamp`: AR フレーム時刻
- `brushSectionImage`: カメラフレームから切り出した断面画像

### `ScreenStroke`

`ScreenStrokeSample` の配列です。1 回の開始ドラッグから終了タッチまでが 1 ストロークです。

## 処理フロー

### 起動

1. `ContentView.onAppear` で `ARSessionManager.start()` を呼ぶ。
2. `ARViewContainer` が `ARSCNView` を作り、`ARSessionManager.session` をセットする。
3. ARKit がフレームを更新し始める。
4. `ARSessionManager` が `latestPose` と `latestBrushSection` を更新する。

### ストローク開始

1. ユーザーが背景カメラ画像上をドラッグする。
2. `StrokeTouchSurface` が開始点・終了点・view size を返す。
3. `ContentView` が `BrushDragConfiguration` からブラシ開始位置・幅・角度を確定する。
4. `ContentView` が `ARSessionManager.setBrushSamplePoint(startPoint, in: size)` を呼ぶ。
5. `ContentView` が `ScreenStrokeRecorder.begin(at:in:pose:brushAngleRadians:)` を呼ぶ。
6. AR プレビューは非表示になり、黒背景になる。

この時点で、ドラッグ開始位置は「画面上のストローク開始位置」と「カメラ画像のサンプリング位置」の両方として使われます。

### ストローク中

1. AR フレーム更新ごとに `latestPose` が変わる。
2. `ContentView.onChange(of: latestPose.timestamp)` が発火する。
3. `ScreenStrokeRecorder.record(...)` が現在 pose から画面上の点とブラシ角度を計算する。
4. `ContentView` が現在ブラシ角度でカメラ断面を切り出す。
5. 必要な間隔を満たしていれば `ScreenStrokeSample` を追加する。
6. `ScreenStrokeRecorder.displayStrokes` がアクティブストロークを現在のデバイス角度デルタで回転した表示用サンプルとして返す。
7. `StrokeCanvasView` がアクティブストロークを再描画する。

### ストローク終了

1. ユーザーが画面をタッチして離す。
2. `ScreenStrokeRecorder.end()` が呼ばれる。
3. `activeSamples` が `strokes` に移動する。
4. AR プレビューが再表示される。

## 座標系

### 画面座標

- 左上原点
- X は右が正
- Y は下が正
- `ScreenStrokeSample.normalizedPoint` は view size に対する正規化値

### AR 相対移動

`ScreenStrokeRecorder.relativeTranslation(from:to:)` で、開始 transform から現在 transform へのローカル移動を求めます。

現在の画面投影は以下です。

```swift
screenX = relativeY
screenY = relativeX
depthZ = discarded
```

スケールは `min(viewportWidth, viewportHeight) * 3` points per meter です。

### ブラシ角度

ドラッグ方向は左方向を 0 度とします。内部ではラジアンで保持します。ストローク中のサンプル角度は `初回ブラシ角度 + 初回からの画面法線まわりのデバイス角度デルタ` です。

`FrameCapture.crossVector(forBrushAngle:)` は断面方向ベクトルを返します。

```swift
dx = -cos(angle)
dy =  sin(angle)
```

このベクトルは、描画時のストローク幅方向と、カメラ断面を切り出す角度の基準として共通利用します。

### カメラ画像サンプリング座標

ドラッグ開始座標は `normalizedPreviewPoint` として `0...1` に正規化されます。`FrameCapture.sourcePoint(...)` は、プレビュー view の aspect-fill クロップを考慮して、カメラ画像上の点へ変換します。

画面 Y 座標と Core Image の Y 座標は向きが異なるため、変換時に `1 - y` を使って反転します。

## 現在の制約

- ARKit の実挙動はシミュレータでは確認できないため、実機確認が必須です。
- 現在の描画は Core Graphics ベースです。長いストロークや高解像度出力が必要になったら Metal 化を検討します。
- アクティブストロークは最大 260 サンプルに制限しています。非常に長いストロークを保存したい場合は、セグメント単位の確定やタイル化が必要です。
- ブラシ断面は現在 `1 x 320` の `CGImage` です。画面サイズや高密度出力に合わせるなら、出力高さを動的にする余地があります。
- カメラ画像の端付近をサンプリングする場合、回転後の crop が画像外へ出る可能性があります。端の見た目が不自然なら crop rect のクランプや余白処理を追加します。
- ストローク開始時にサンプリング位置を固定します。ストローク中に右手位置でサンプリング位置を更新する設計ではありません。

## テスト方針

ユニットテストは `TrajectoryTypePackage/Tests/TrajectoryTypeFeatureTests/` に置きます。現状は以下を中心に確認しています。

- `CameraPose` の transform 分解
- AR 相対移動から画面座標への変換
- 奥行き方向の移動量が画面投影へ混ざらないこと
- デバイス角度デルタによるブラシ角度更新
- 奥行き方向の端末傾きがデバイス角度デルタへ混ざらないこと
- デバイス角度デルタによるアクティブストローク表示回転
- ドラッグ方向の左 0 度定義
- ドラッグ開始位置からカメラ画像座標への変換
- aspect-fill クロップ補正
- ストローク終了時の描画順保持

ARKit と実カメラの見た目はユニットテストでは十分に検証できないため、変更後は実機で以下を確認します。

- ドラッグ開始位置の背景画像がストローク断面に反映されるか
- 端末移動方向とストローク方向が意図どおりか
- ドラッグ方向変更時にサンプリング断面と描画断面が同時に変わるか
- 複数ストロークの重なり順が自然か

## ビルドと実機確認

シミュレータでは AR カメラ挙動を確認できませんが、コンパイルとユニットテストには使えます。

```sh
xcodebuildmcp simulator test \
  --workspace-path /Users/yamatoiizuka/develop/trajectory-type/TrajectoryType.xcworkspace \
  --scheme TrajectoryType \
  --simulator-name "iPhone 17"
```

実機確認は接続済み iPhone に対して行います。

```sh
xcodebuildmcp device build-and-run \
  --workspace-path /Users/yamatoiizuka/develop/trajectory-type/TrajectoryType.xcworkspace \
  --scheme TrajectoryType \
  --device-id 0470429F-6B10-5D07-B85C-7165EB7117CD
```

## 今後の設計メモ

- UI 上の debug overlay は開発用です。制作向け UI にする段階で非表示化または開発モード化します。
- 保存/書き出し機能を追加する場合、`ScreenStroke` 配列をドキュメントモデルとして扱い、レンダリング出力とは分離します。
- ブラシ断面の連結品質を上げる場合、現在のセグメント単位描画から、ストローク全体のメッシュ生成または GPU テクスチャマッピングへ移行します。
- 画像素材としてのカメラフレームを固定するか、AR フレームごとに更新し続けるかは表現上の選択です。現在は AR フレームごとに最新断面を使います。
