import UIKit
import Vision
import AVFoundation
import CoreMedia
import VideoToolbox
import UserNotifications
import CoreBluetooth
import SocketIO

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
        self.doRobotReset()
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
    var charcteristic2UUID: CBUUID! = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    var botService : CBService!
    var botCmdChara : CBCharacteristic! //挙動制御用
    var botManChara : CBCharacteristic! //マニュアル操作用
    
    // for Control Robot
    var cluppies : [Player] = []
    var cmdQueueItrt : CommandQueueIterator?
    var cmdExecTimer : Timer?
    var cmdNextDelay : TimeInterval = 0.0
    
    // for WebSocket
    let manager = SocketManager(socketURL: URL(string: "ws://fr-test03.mybluemix.net/ws/boxtalk")!, config: [.log(true), .compress, .forceWebsockets(true)])
    
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
//        self.setupWS()
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
    
    private func setupWS() {
        let socket = self.manager.defaultSocket
        socket.on(clientEvent: .connect) {data, ack in
            print("socket connected")
        }
//        socket.on(clientEvent: )
        
        socket.on("message") {data, ack in
            print("websocket onMessage \(data)")
            if let message = data as? [String] {
                switch message[0] {
                case "event7": //「ダルマさんが転んだ」
                    self.doRobotDMSCD()
                    break
                case "start":
                    break
                case "reset":
                    self.doRobotReset()
                    break
                default:
                    print("undefined command from websocket : \(message[0])")
                }
            }

//            guard let cur = data[0] as? Double else { return }
//
////            socket.emitWithAck("canUpdate", cur).timingOut(after: 0) {data in
////                socket.emit("update", ["amount": cur + 2.50])
////            }
////
//            ack.with("Got your currentAmount", "dude")
        }
//        CFRunLoopRun()
        socket.connect()
    }
    
    func getBleNotifyManualCmd(data: Data) {
        self.doRobotDMSCD()
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




