import UIKit
import Vision
import AVFoundation
import CoreMedia
import VideoToolbox
import UserNotifications
import CoreBluetooth

enum DriveMode {
    case waiting //反転中, 動作中
    case detecting //ダルマさんが転んだ
    case terminator //狩りにいく
}

class ViewController: UIViewController {
    @IBOutlet weak var videoPreview: UIView!
    @IBOutlet weak var timeLabel: UILabel!
    @IBOutlet weak var debugImageView: UIImageView!
    
    @IBOutlet weak var resetButton: UIButton!
    
    @IBAction func onResetButonClick() {
        self.cluppies = []
        if self.currentMode == .waiting {
            self.currentMode = .detecting
        }
    }

    let yolo = YOLO()

    var videoCapture: VideoCapture!
    var request: VNCoreMLRequest!
    var startTimes: [CFTimeInterval] = []

    var boundingBoxes = [BoundingBox]()
    var colors: [UIColor] = []

    let ciContext = CIContext()
    var resizedPixelBuffer: CVPixelBuffer?

    var framesDone = 0
    var frameCapturingStartTime = CACurrentMediaTime()
    let semaphore = DispatchSemaphore(value: 2)

    let detects = DetectQueue()

    var isNeedRotate = false
    
    var currentMode = DriveMode.waiting
    
    // for BLE Central
    var centralManager: CBCentralManager!
    var peripheral: CBPeripheral!
    var serviceUUID : CBUUID! = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    var charcteristicUUID: CBUUID! = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    var botService : CBService!
    var botCmdChara : CBCharacteristic!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        timeLabel.text = ""

        setUpBoundingBoxes()
        setUpCoreImage()
        setUpVision()
        setUpCamera()

        frameCapturingStartTime = CACurrentMediaTime()

        let device = UIDevice.current
        print(device.platform, device.modelName)
         // NOTE: iPhone 8 plusで認識率悪い問題の対策で必要な気がしたが、そもそもそういう問題ではない気がするので一旦マスクしておく
        //    switch device.modelName {
        //    case "iPhone 8 Plus":
        //        isNeedRotate = true
        //    default:
        //        isNeedRotate = false
        //    }

        self.setupBLE()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        print(#function)
    }
    
    // MARK: - BLE
    
    /// セントラルマネージャー、UUIDの初期化
    private func setupBLE() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
//        serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
//        charcteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    }

    // MARK: - Initialization
    
    func setUpBoundingBoxes() {
        for _ in 0..<YOLO.maxBoundingBoxes {
            boundingBoxes.append(BoundingBox())
        }
        
        // Make colors for the bounding boxes. There is one color for each class,
        // 20 classes in total.
        for r: CGFloat in [0.2, 0.4, 0.6, 0.8, 1.0] {
            for g: CGFloat in [0.3, 0.7] {
                for b: CGFloat in [0.4, 0.8] {
                    let color = UIColor(red: r, green: g, blue: b, alpha: 1)
                    colors.append(color)
                }
            }
        }
    }



    // MARK: - UI stuff

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        resizePreviewLayer()
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    func resizePreviewLayer() {
        videoCapture.previewLayer?.frame = videoPreview.bounds
    }

    // MARK: - Doing inference

    /**
        VNCoreMLRequest の処理完了
    */
    func visionRequestDidComplete(request: VNRequest, error: Error?) {
        if let observations = request.results as? [VNCoreMLFeatureValueObservation],
            let features = observations.first?.featureValue.multiArrayValue {

            let boundingBoxes = yolo.computeBoundingBoxes(features: features)
            let elapsed = CACurrentMediaTime() - startTimes.remove(at: 0)
            
//            var fCoffee = false
//            var fItem01 = false
//            var fItem02 = false
//            for box in boundingBoxes {
//                if (box.classIndex < 6) { //缶コーヒー
//                    fCoffee = true
//                } else if (box.classIndex == 6) { //カップヌードル
//                    fItem01 = true
//                } else if (box.classIndex == 7) { //コアラのマーチ
//                    fItem02 = true
//                }
//            }
//            detects.enqueue(hasCoffee: fCoffee, hasItem01: fItem01, hasItem02: fItem02) //検出した種類を記録
            
            showOnMainThread(boundingBoxes, elapsed)
        }
    }
    
    // MARK : -- 発見時の処理
    
    var hideAICMsgCount = 30 //発見後の30フレームは遅延評価する
    func showOnMainThread(_ boundingBoxes: [YOLO.Prediction], _ elapsed: CFTimeInterval) {
        DispatchQueue.main.async {
            self.show(predictions: boundingBoxes)

            let fps = self.measureFPS()
            self.timeLabel.text = String(format: "Elapsed %.5f seconds - %.2f FPS", elapsed, fps)

            self.semaphore.signal()
        }
    }

    func measureFPS() -> Double {
        // Measure how many frames were actually delivered per second.
        framesDone += 1
        let frameCapturingElapsed = CACurrentMediaTime() - frameCapturingStartTime
        let currentFPSDelivered = Double(framesDone) / frameCapturingElapsed
        if frameCapturingElapsed > 1 {
            framesDone = 0
            frameCapturingStartTime = CACurrentMediaTime()
        }
        return currentFPSDelivered
    }
    
    //------
    
    struct Player {
        let classIndex: Int
        var center: CGPoint
        var rect: CGRect
    }

    var cluppies : [Player] = []
    
    func createDummyPlayer() -> Player {
        return Player(classIndex: 999, center:CGPoint(x:0, y:0), rect:CGRect(x:0, y:0, width:0, height:0))
    }
    
    func createPlayerFromPrediction(from: YOLO.Prediction) -> Player {
        let pointX = from.rect.midX
        let pointY = from.rect.midY
        
        let center = CGPoint(x:pointX, y:pointY)
        return Player(classIndex: from.classIndex, center: center, rect:from.rect)
    }
    
    // 中心点を比較して、差分が許容値を超えたら移動したと判定する
    func getCenterDiff(p1: Player, p2: Player) -> Bool {
        var diffX:CGFloat = 50 //差分許容値(X)
        var diffY:CGFloat = 100 //差分許容値(Y) クラッピーの構造上、下方向のズレは大きい
        
        // TODO : スケール計算
        
        let point1 = p1.center
        let point2 = p2.center
        if point1.x < point2.x && diffX < (point2.x - point1.x) {
            return true
        }
        if point2.x < point1.x && diffX < (point1.x - point2.x) {
            return true
        }
        if point1.y < point2.y && diffY < (point2.y - point1.y) {
            return true
        }
        if point2.y < point1.y && diffY < (point1.y - point2.y) {
            return true
        }
        return false
    }
    
    /// 同一判断する, 差分確認する, 追いかける
    func detectPlayerAndDiff(predictions: [YOLO.Prediction]) {
        if self.cluppies.count == 0 { //初回 or クリア後
            for i in 0..<boundingBoxes.count {
                if i < predictions.count {
                    let prediction = predictions[i]
                    if (prediction.classIndex == 0) { //クラッピーを検知
                        cluppies.append(self.createPlayerFromPrediction(from: prediction))
                    }
                }
            }
        } else { //2回目以降 : 確認処理
            var flgFire = false
            var targetCluppy: Player!
            var findIndexes: [Bool] = []
            for _ in cluppies {
                findIndexes.append(false)
            }
            // クラッピー(0, 1) のみフィルターして Playerに変換
            let currentCluppies = predictions.filter { $0.classIndex == 0 || $0.classIndex == 1 }.map { self.createPlayerFromPrediction(from: $0) } //クラッピーを検知
            
            // 同一オブジェクト判定 & 移動判定
            for cru in currentCluppies {
                
                // TODO : n回分で平均取る
                
                var isMatch = false
                for i in 0..<self.cluppies.count {
                    let old = self.cluppies[i]
                    if findIndexes[i] {
                        print("すでに発見ずみ　\(i)")
                        continue //すでに発見済み
                        // FIXME: 認識率悪かったら取る
                    }
                    
                    let rect = cru.rect
                    print("x:\(rect.origin.x), y:\(rect.origin.y), width:\(rect.size.width), height:\(rect.size.height), midX:\(rect.midX), midY:\(rect.midY)")
                    //                    //x:177.569534301758, y:31.5921630859375, width:197.188385009766, height:407.814971923828, midX:276.163726806641, midY:235.499649047852
                    
                    // 既存のエントリーと同じものか確認 (含まれているか, 重なりがあるか)
                    if old.rect.contains(cru.rect) || old.rect.intersects(cru.rect) {
                        print("\(old.classIndex):(\(old.center.x),\(old.center.y)) vs \(cru.classIndex):(\(cru.center.x),\(cru.center.y))")
                        // TODO : すでにrectが重ならないくらい動いてるとまずい
                        if self.getCenterDiff(p1: old, p2: cru) { // 座標の変更量が閾値を超えたら動いたと判断
                            print("target is detected! - 1")
                            flgFire = true
                            targetCluppy = cru
                        } // else : 動きなし
                        
                        findIndexes[i] = true
                        self.cluppies[i].rect = cru.rect //ジリジリ動いたときに検出できない場合は外す
                        isMatch = true
                        break
                    }
                }
                if !isMatch { //見つからなかった = 新規
                    self.cluppies.append(cru)
                }
                if flgFire { //見つかった&動いてる
                    break
                }
            }
            if flgFire { // TODO : ダルマさんが転んだ
                print("target is detected! - 2")
                self.currentMode = .terminator
                
                // TODO : XYでどの領域に居るか判断
                // targetCluppy.rect or targetCluppy.center
                
                let width = CGFloat(YOLO.inputWidth)
                let height = CGFloat(YOLO.inputHeight)
                
                // TODO : LEFT, CNTER, RIGHT くらいは分けたい
                let center = CGPoint(x: width / 2, y: height / 2)
                
                var commandQueue : [BLECommand] = []
                if targetCluppy.center.x < center.x { // 右
                    commandQueue.append(BLECommand(kind: CommandKind.turnLeft, time:3000))
                } else if center.x < targetCluppy.center.x { //左
                    commandQueue.append(BLECommand(kind: CommandKind.turnRight, time:3000))
                }
                commandQueue.append(BLECommand(kind: CommandKind.forward, time:10000))
                
                // BLE コマンド送信
                for cmd in commandQueue {
                    self.sendCommand(data: cmd.build())
                    // TODO : cmd.time 分だけ次の送信をdelayする
                }
            }
        }
    }
    
    func detectAndTrace(predictions: [YOLO.Prediction]) {
        // TODO : リアルタイム追尾
        // TODO : 必要なだけ近づいたら止まる or 時間で止める
    }
    
    // TODO : WebSocketで event7 を受けたら CommandKind.spinTurnを発火する & mode を detecting へ
    
    func show(predictions: [YOLO.Prediction]) {
        switch self.currentMode {
        case .detecting:
            self.detectPlayerAndDiff(predictions: predictions)
            break
        case .terminator:
            self.detectAndTrace(predictions: predictions) //追尾する
            break
        default:
            break
            // 無視
//            print("waiting mode")
        }
        
        
        for i in 0..<boundingBoxes.count {
          if i < predictions.count {
            let prediction = predictions[i]

            // The predicted bounding box is in the coordinate space of the input
            // image, which is a square image of 416x416 pixels. We want to show it
            // on the video preview, which is as wide as the screen and has a 4:3
            // aspect ratio. The video preview also may be letterboxed at the top
            // and bottom.
            let width = view.bounds.width
            let height = width * 4 / 3
            let scaleX = width / CGFloat(YOLO.inputWidth)
            let scaleY = height / CGFloat(YOLO.inputHeight)
            let top = (view.bounds.height - height) / 2

            // Translate and scale the rectangle to our own coordinate system.
            var rect = prediction.rect
            rect.origin.x *= scaleX
            rect.origin.y *= scaleY
            rect.origin.y += top
            rect.size.width *= scaleX
            rect.size.height *= scaleY

            // Show the bounding box.
    //        let label = String(format: "%@ %.1f", labels[prediction.classIndex], prediction.score * 100)
            let label = String(format: "%@ %.1f", YOLO.getLabelByClassIndex(index: prediction.classIndex), prediction.score * 100)
            let color = colors[prediction.classIndex]
            boundingBoxes[i].show(frame: rect, label: label, color: color)
          } else {
            boundingBoxes[i].hide()
          }
        }
  }
}




