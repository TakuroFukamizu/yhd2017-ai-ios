# yhd2017-ai-ios

Yahoo! HackDay 2017 で作成した Clappy Park用のiOSアプリです。

- CoreMLでTinyYOLOを動かし、カメラに写ったクラッピーを画像認識します
- 画像認識結果を解析てクラッピーの動体検知および動いた個体の位置判定をします
- 動いたクラッピーに向かって走るよう、 [ロボット(ESP32)](https://github.com/TakuroFukamizu/esp32-ble-with-tb6612)にBLEでコマンドを送信します

## requirements
- Xcode 9 or later
- iOS 11 or later
- Carthage

## commands

```sh
$ carthage update --platform iOS
```

```sh
$ carthage build --platform iOS
```

## coreml model

[TakuroFukamizu/yhd2017-ai](https://bitbucket.org/TakuroFukamizu/yhd2017-ai/)
