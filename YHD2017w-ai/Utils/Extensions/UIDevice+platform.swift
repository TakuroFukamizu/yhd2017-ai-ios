//
//  UIDevice+platform.swift
//  TinyYOLO-CoreML
//
//  Created by t-fukamizu on 2017/10/11.
//  Copyright © 2017年 MachineThink. All rights reserved.
//

//import Foundation
import UIKit

// cf. http://www.enterpriseios.com/wiki/iOS_Devices
private let DeviceList = [
    /* iPod Touch 5 */    "iPod5,1": "iPod Touch 5",
    /* iPod Touch 6 */    "iPod7,1": "iPod Touch 6",
    /* iPhone 5S */       "iPhone6,1": "iPhone 5S", "iPhone6,2": "iPhone 5S",
    /* iPhone 6 */        "iPhone7,2": "iPhone 6",
    /* iPhone 6 Plus */   "iPhone7,1": "iPhone 6 Plus",
    /* iPhone 6S */       "iPhone8,1": "iPhone 6S",
    /* iPhone 6S Plus */  "iPhone8,2": "iPhone 6S Plus",
    /* iPhone SE */       "iPhone8,4": "iPhone SE",
    /* iPhone 7 */        "iPhone9,1": "iPhone 7",
    /* iPhone 7 Plus */   "iPhone9,2": "iPhone 7 Plus",
    /* iPhone 8 */        "iPhone10,4": "iPhone 8",
    /* iPhone 8 Plus */   "iPhone10,5": "iPhone 8 Plus",
    /* iPad 2 */          "iPad2,1": "iPad 2", "iPad2,2": "iPad 2", "iPad2,3": "iPad 2", "iPad2,4": "iPad 2",
    /* iPad 3 */          "iPad3,1": "iPad 3", "iPad3,2": "iPad 3", "iPad3,3": "iPad 3",
    /* iPad 4 */          "iPad3,4": "iPad 4", "iPad3,5": "iPad 4", "iPad3,6": "iPad 4",
    /* iPad Air */        "iPad4,1": "iPad Air", "iPad4,2": "iPad Air", "iPad4,3": "iPad Air",
    /* iPad Air 2 */      "iPad5,3": "iPad Air 2", "iPad5,4": "iPad Air 2",
    /* iPad Mini */       "iPad2,5": "iPad Mini", "iPad2,6": "iPad Mini", "iPad2,7": "iPad Mini",
    /* iPad Mini 2 */     "iPad4,4": "iPad Mini 2", "iPad4,5": "iPad Mini 2", "iPad4,6": "iPad Mini 2",
    /* iPad Mini 3 */     "iPad4,7": "iPad Mini 3", "iPad4,8": "iPad Mini 3", "iPad4,9": "iPad Mini 3",
    /* iPad Mini 4 */     "iPad5,1": "iPad Mini 4", "iPad5,2": "iPad Mini 4",
    /* iPad Pro */        "iPad6,7": "iPad Pro", "iPad6,8": "iPad Pro",
    /* Simulator */       "x86_64": "Simulator", "i386": "Simulator",
]

extension UIDevice {
    
    var platform: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        
        let mirror = Mirror(reflecting: systemInfo.machine)
        var identifier = ""
        
        for child in mirror.children {
            if let value = child.value as? Int8, value != 0 {
//                identifier.append(_: UnicodeScalar(UInt8(value)))
                identifier = identifier + String(UnicodeScalar(UInt8(value)))
            }
        }
        return identifier
    }
    
    var modelName: String {
        let identifier = platform
        return DeviceList[identifier] ?? identifier
    }
}
