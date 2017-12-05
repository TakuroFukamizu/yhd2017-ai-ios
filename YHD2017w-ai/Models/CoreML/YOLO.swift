import Foundation
import UIKit
import CoreML

class YOLO {
    // ---------
    
    public static let inputWidth = 416
    public static let inputHeight = 416
    public static let maxBoundingBoxes = 10

    // Tweak these values to get more or fewer predictions.
    let confidenceThreshold: Float = 0.3
    let iouThreshold: Float = 0.5
    
    // The labels for the classes.
    public static let labels = [
        "トールくん(赤)",
        "トールくん(黄)",
        "ヒミツのクマちゃん",
        "シルバニアのうさぎ",
        "Masawo Yamazaki"
    ]
    
    let blockSize: Float = 32 //入力画像の32 x 32ピクセルが特徴マップ上の1ピクセルに対応する
    let gridHeight = 13
    let gridWidth = 13
    let boxesPerCell = 5 //anchorbox
    let numClasses = YOLO.labels.count
    
//    let model = CoffeeTinyYOLO()
    let model = TinyYOLOClpy()
    
    let anchors: [Float] = [1.08, 1.19, 3.42, 4.41, 6.63, 11.38, 9.42, 5.11, 16.62, 10.52]
    
//    let layerSize = boxesPerCell * (4 + 1 + YOLO.labels.count) //anchorbox(5)  x (座標(4) + 確率(1) + classes）
    var layerSize = 0
    
    let logging = false
    
    // ---------

    struct Prediction {
        let classIndex: Int
        let score: Float
        let rect: CGRect
    }

    public init() {
        self.layerSize = boxesPerCell * (4 + 1 + YOLO.labels.count) //anchorbox(5)  x (座標(4) + 確率(1) + classes）
    }
    
    public static func getLabelByClassIndex(index: Int) -> String {
        return labels[index]
    }

    public func predict(image: CVPixelBuffer) throws -> [Prediction] {
        if let output = try? model.prediction(image: image) {
            print("output.grid.count is \(output.grid.count)")
            return computeBoundingBoxes(features: output.grid)
        } else {
            return []
        }
    }

  public func computeBoundingBoxes(features: MLMultiArray) -> [Prediction] {
    assert(features.count == layerSize*13*13)
    if logging { print("  - layerSize: \(layerSize), features.count: \(features.count)") }

    var predictions = [Prediction]()


    // The 416x416 image is divided into a 13x13 grid. Each of these grid cells
    // will predict 5 bounding boxes (boxesPerCell). A bounding box consists of
    // five data items: x, y, width, height, and a confidence score. Each grid
    // cell also predicts which class each bounding box belongs to.
    //
    // The "features" array therefore contains (numClasses + 5)*boxesPerCell
    // values for each grid cell, i.e. 125 channels. The total features array
    // contains 125x13x13 elements.

    // NOTE: It turns out that accessing the elements in the multi-array as
    // `features[[channel, cy, cx] as [NSNumber]].floatValue` is kinda slow.
    // It's much faster to use direct memory access to the features.
    let featurePointer = UnsafeMutablePointer<Double>(OpaquePointer(features.dataPointer))
    let channelStride = features.strides[0].intValue
    let yStride = features.strides[1].intValue
    let xStride = features.strides[2].intValue

    func offset(_ channel: Int, _ x: Int, _ y: Int) -> Int {
      return channel*channelStride + y*yStride + x*xStride
    }

    for cy in 0..<gridHeight {
      for cx in 0..<gridWidth {
        for b in 0..<boxesPerCell {

          // For the first bounding box (b=0) we have to read channels 0-24,
          // for b=1 we have to read channels 25-49, and so on.
          let channel = b*(numClasses + 5)

          // The slow way:
          /*
          let tx = features[[channel    , cy, cx] as [NSNumber]].floatValue
          let ty = features[[channel + 1, cy, cx] as [NSNumber]].floatValue
          let tw = features[[channel + 2, cy, cx] as [NSNumber]].floatValue
          let th = features[[channel + 3, cy, cx] as [NSNumber]].floatValue
          let tc = features[[channel + 4, cy, cx] as [NSNumber]].floatValue
          */

          // The fast way:
          let tx = Float(featurePointer[offset(channel    , cx, cy)])
          let ty = Float(featurePointer[offset(channel + 1, cx, cy)])
          let tw = Float(featurePointer[offset(channel + 2, cx, cy)])
          let th = Float(featurePointer[offset(channel + 3, cx, cy)])
          let tc = Float(featurePointer[offset(channel + 4, cx, cy)])

          // The predicted tx and ty coordinates are relative to the location
          // of the grid cell; we use the logistic sigmoid to constrain these
          // coordinates to the range 0 - 1. Then we add the cell coordinates
          // (0-12) and multiply by the number of pixels per grid cell (32).
          // Now x and y represent center of the bounding box in the original
          // 416x416 image space.
          let x = (Float(cx) + sigmoid(tx)) * blockSize
          let y = (Float(cy) + sigmoid(ty)) * blockSize

          // The size of the bounding box, tw and th, is predicted relative to
          // the size of an "anchor" box. Here we also transform the width and
          // height into the original 416x416 image space.
          let w = exp(tw) * anchors[2*b    ] * blockSize
          let h = exp(th) * anchors[2*b + 1] * blockSize

          // The confidence value for the bounding box is given by tc. We use
          // the logistic sigmoid to turn this into a percentage.
          let confidence = sigmoid(tc)

          // Gather the predicted classes for this anchor box and softmax them,
          // so we can interpret these numbers as percentages.
          var classes = [Float](repeating: 0, count: numClasses)
          for c in 0..<numClasses {
            // The slow way:
            //classes[c] = features[[channel + 5 + c, cy, cx] as [NSNumber]].floatValue

            // The fast way:
            classes[c] = Float(featurePointer[offset(channel + 5 + c, cx, cy)])
            if logging {
                print("    - channel:\(channel), c:\(c), cx:\(cx), cy:\(cy), offset:\(offset(channel + 5 + c, cx, cy)) = value:\(classes[c]) ->  classIndex:\(c)")
            }
          }
          classes = softmax(classes)

          // Find the index of the class with the largest score.
          let (detectedClass, bestClassScore) = classes.argmax()

          // Combine the confidence score for the bounding box, which tells us
          // how likely it is that there is an object in this box (but not what
          // kind of object it is), with the largest class prediction, which
          // tells us what kind of object it detected (but not where).
          let confidenceInClass = bestClassScore * confidence

          // Since we compute 13x13x5 = 845 bounding boxes, we only want to
          // keep the ones whose combined score is over a certain threshold.
          if confidenceInClass > confidenceThreshold {
            let rect = CGRect(x: CGFloat(x - w/2), y: CGFloat(y - h/2),
                              width: CGFloat(w), height: CGFloat(h))

            let prediction = Prediction(classIndex: detectedClass,
                                        score: confidenceInClass,
                                        rect: rect)
            predictions.append(prediction)
//            print("OK  " + String(detectedClass) + "  " + String(confidenceInClass))
          } else {
//            print("NG  " + String(detectedClass) + "  " + String(confidenceInClass))
          }
        }
      }
    }

    // We already filtered out any bounding boxes that have very low scores,
    // but there still may be boxes that overlap too much with others. We'll
    // use "non-maximum suppression" to prune those duplicate bounding boxes.
    return nonMaxSuppression(boxes: predictions, limit: YOLO.maxBoundingBoxes, threshold: iouThreshold)
  }
}
