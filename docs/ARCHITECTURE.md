# TrajectoryType Architecture

## 概要

TrajectoryType は、カメラ映像から細い line を切り出し、画面上で手描きしたドラッグ軌跡へ貼り込む iOS プロトタイプです。

現在の実装は ARKit の 6DoF pose tracking を使いません。入力は次の 2 つだけです。

- `AVCaptureSession` からのライブカメラフレーム
- `UIView` のタッチイベントから得た画面上のドラッグ位置

ストロークは AR ワールド空間には置かず、画面座標の 2D サンプル列として保持します。

## ファイル構成

```text
TrajectoryTypePackage/
  Sources/TrajectoryTypeFeature/
    ContentView.swift
    CameraSessionManager.swift
    CameraPreviewContainer.swift
    FrameCapture.swift
    ScreenStrokeRecorder.swift
    ScreenStroke.swift
    ScreenStrokeSample.swift
    StrokeCanvasView.swift
    StrokeTouchSurface.swift
  Tests/TrajectoryTypeFeatureTests/
    TrajectoryTypeFeatureTests.swift
```

## 主要コンポーネント

### `ContentView`

SwiftUI のルート画面です。

- カメラプレビューを全面表示する。
- `StrokeCanvasView` をカメラ上に重ねる。
- `StrokeTouchSurface` でドラッグを受ける。
- ドラッグ開始で `ScreenStrokeRecorder.begin(...)` を呼ぶ。
- ドラッグ移動ごとに `ScreenStrokeRecorder.record(...)` を呼ぶ。
- ストロークサンプル追加時だけ、`CameraSessionManager.makeLiveBrushSection(...)` でカメラ映像から断面画像を取得する。

### `CameraSessionManager`

AVFoundation のカメラ入力を管理します。

- `AVCaptureSession` を所有する。
- back camera を `.high` preset で起動する。
- `AVCaptureVideoDataOutput` で最新 `CVPixelBuffer` を保持する。
- `FrameCapture` を使って、指定された画面位置とブラシ角度に対応する line 断面を生成する。

フレームは毎回保存せず、最新の `CVPixelBuffer` だけをロック付きの小さな store に保持します。

### `CameraPreviewContainer`

`AVCaptureVideoPreviewLayer` を SwiftUI から表示するための UIKit bridge です。

プレビューは `.resizeAspectFill` で全面表示します。`FrameCapture.sourcePoint(...)` も同じ aspect-fill 前提で、画面座標をカメラ画像座標へ変換します。

### `FrameCapture`

カメラフレームからブラシ断面画像を生成します。

現在の流れは次の通りです。

1. `CVPixelBuffer` を縦持ち向きの `CIImage` として扱う。
2. タッチ位置の normalized screen point をカメラ画像上の座標へ変換する。
3. ブラシ角度に応じた line 周辺だけを小さく crop する。
4. crop 済みパッチだけを回転する。
5. サンプリング位置を通る幅 1px の断面を切り出す。
6. `1 x 320` の `CGImage` として返す。

全フレームを回転せず、line 周辺の patch だけを処理することで、ライブ動画サンプリングの負荷を抑えています。

### `ScreenStrokeRecorder`

画面上のストロークモデルを管理します。

- ドラッグ位置を normalized screen point として記録する。
- 前回サンプルからのドラッグ方向でブラシ角度を更新する。
- 移動距離、角度差、幅差が閾値を超えた時だけサンプルを追加する。
- サンプル追加時だけブラシ断面画像を要求する。
- ドラッグ終了で active samples を committed stroke に移す。
- undo は最後の committed stroke を削除する。

このレイヤーはカメラや AVFoundation を知らず、画面座標と `CGImage` 断面だけを扱います。

### `StrokeCanvasView`

`ScreenStrokeSample` の列を UIKit drawing で合成します。

- サンプル列からリボン形状を作り、clip する。
- サンプル間を細かい slice に分割する。
- 前後サンプルの `brushSectionImage` を補間しながら貼る。

描画結果は画面上の 2D 合成です。

### `StrokeTouchSurface`

透明な `UIViewRepresentable` で、タッチイベントを SwiftUI 側へ渡します。

- `touchesBegan` -> stroke begin
- `touchesMoved` -> stroke record
- `touchesEnded` -> final record + stroke end
- `touchesCancelled` -> stroke end

## 入力から描画まで

### 起動

1. `ContentView.onAppear` で `CameraSessionManager.start()` を呼ぶ。
2. カメラ権限が未決定なら iOS の permission prompt を出す。
3. 許可済みなら `AVCaptureSession` を開始する。
4. `CameraPreviewContainer` がライブプレビューを表示する。
5. `AVCaptureVideoDataOutput` が最新 `CVPixelBuffer` を更新し続ける。

### ドラッグ中

1. 指が画面に触れると `ScreenStrokeRecorder.begin(...)` を呼ぶ。
2. その地点を最初のサンプルとして `record(...)` する。
3. 指が動くたびに現在の touch point を `record(...)` する。
4. `ScreenStrokeRecorder` が前回サンプルとの差からブラシ角度を計算する。
5. サンプル追加が必要な時だけ、現在の touch point をカメラ画像座標に変換して line 断面を切り出す。
6. `StrokeCanvasView` が active stroke をカメラプレビュー上に再描画する。

### ドラッグ終了

1. 最後の touch point を record する。
2. `ScreenStrokeRecorder.end()` が active samples を committed stroke に移す。
3. 以後 undo 対象になる。

## パフォーマンス方針

- カメラフレームは最新 1 枚だけ保持する。
- サンプル追加しない touch event では画像処理しない。
- line 周辺 patch だけを crop してから回転する。
- `AVCaptureVideoDataOutput.alwaysDiscardsLateVideoFrames = true` で古いフレームを捨てる。
- active stroke は最大 260 サンプルに制限する。

今後さらに軽くするなら、断面生成と stroke compositing を Metal に寄せるのが本筋です。

## テスト方針

ユニットテストでは次を確認します。

- touch point が normalized screen point として記録されること
- ドラッグ方向からブラシ角度を決めること
- サンプル追加しない event ではブラシ断面を要求しないこと
- 画面座標からカメラ画像座標への変換
- aspect-fill crop 補正
- `CGImage` 入力からブラシ断面を切り出せること
- ブラシ断面処理が line 周辺 crop に制限されること
- ストローク終了時の描画順保持
- undo が最後の committed stroke だけを消すこと

ライブカメラの見た目と実機性能はユニットテストだけでは判断できないため、変更後は実機でドラッグ描画、カメラ権限、インストール、起動を確認します。
