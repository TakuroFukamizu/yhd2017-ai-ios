//
//  BLECommand.swift
//  YHD2017w-ai
//
//  Created by Takuro on 2017/12/09.
//  Copyright © 2017年 MachineThink. All rights reserved.
//

import Foundation

public enum CommandKind {
    case forward
    case back
    case stop
    case spinTurn
    case turnLeft
    case turnRight
}

public class BLECommand {
    let kind: CommandKind
    let time: UInt16
    
    public init(kind: CommandKind, time: UInt16) {
        self.kind = kind
        self.time = time
    }

    public func build() -> Data {
        var bytes: [UInt8] = [0, 0,0]
        
        // kindのパース
        switch self.kind {
        case .forward:
            bytes[0] = 0x01
            break
        case .back:
            bytes[0] = 0x02
            break
        case .stop:
            bytes[0] = 0xFF
            break
        case .spinTurn:
            bytes[0] = 0x11
            break
        case .turnLeft:
            bytes[0] = 0x12
            break
        case .turnRight:
            bytes[0] = 0x13
            break
        }

        // timeのパース
        var intVal: UInt16 = self.time    //-- let変数をポインタとして利用する場合は var変数として代入し直す
        let ivData = Data(bytes: &intVal, count: MemoryLayout.size(ofValue: intVal))    //-- 2 bytes
        let ivBytes = [UInt8](ivData)
        bytes[1] = ivBytes[0]
        bytes[2] = ivBytes[1]
        
        let data = Data(bytes: bytes)
        return data
    }
}
