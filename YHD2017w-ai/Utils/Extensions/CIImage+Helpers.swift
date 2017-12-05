//
//  CIImage+Helpers.swift
//  Coffee-TinyYOLO-demo
//
//  Created by j-morimoto on 2017/10/11.
//  Copyright © 2017年 t-fukamizu. All rights reserved.
//

import UIKit

public extension CIImage {
    var rotate: CIImage {
        get {
            return self.oriented(UIDevice.current.orientation.cameraOrientation())
        }
    }
}

private extension UIDeviceOrientation {
    func cameraOrientation() -> CGImagePropertyOrientation {
        switch self {
        case .landscapeLeft: return .up
        case .landscapeRight: return .down
        case .portraitUpsideDown: return .left
        default: return .right
        }
    }
}
