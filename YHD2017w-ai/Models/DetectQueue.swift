//
//  DetectQueue.swift
//  TinyYOLO-CoreML
//
//  Created by t-fukamizu on 2017/10/10.
//  Copyright © 2017年 MachineThink. All rights reserved.
//

import Foundation

public class DetectQueue {

    private var queueList:[UInt8] = []
    private let queueLimit = 30
    
    // bitmask
    private let maskCoffee:UInt8 = 0b00001111 //缶コーヒー
    private let maskItem01:UInt8 = 0b00110000 //カップヌードル
    private let maskItem02:UInt8 = 0b11000000 //コアラのマーチ

    public init () {
        queueList = []
    }
    
    /// Add a new item to the back of the queue.
    public func enqueue (hasCoffee: Bool, hasItem01: Bool, hasItem02: Bool) {
        var value: UInt8 = 0b00000000
        if (hasCoffee) { //缶コーヒー
            value |= 0b00000001
        }
        if (hasItem01) { //カップヌードル
            value |= 0b00010000
        }
        if (hasItem02) { //コアラのマーチ
            value |= 0b01000000
        }
//    public func enqueue (value: UInt8) {
        queueList.append(value)
        if queueList.count > queueLimit { //先頭の古いものを削除
            queueList.removeSubrange(0..<queueList.count-queueLimit)
        }
    }
    
    public func hasCoffee() -> Bool {
        var count = 0
        for queue in queueList {
            if queue & maskCoffee > 0 {
                count+=1
            }
        }
        return count > (queueList.count / 2)
    }
    public func hasItem01() -> Bool {
        var count = 0
        for queue in queueList {
            if queue & maskItem01 > 0 {
                count+=1
            }
        }
        return count > (queueList.count / 2)
    }
    public func hasItem02() -> Bool {
        var count = 0
        for queue in queueList {
            if queue & maskItem02 > 0 {
                count+=1
            }
        }
        return count > (queueList.count / 2)
    }
}
