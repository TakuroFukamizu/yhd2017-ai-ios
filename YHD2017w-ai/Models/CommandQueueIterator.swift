//
//  CommandQueueIterator.swift

//  YHD2017w-ai
//
//  Created by Takuro on 2017/12/10.
//  Copyright © 2017年 MachineThink. All rights reserved.
//

import Foundation

struct CommandQueueIterator: IteratorProtocol, Sequence {
    var curr = 0
    let queue : [BLECommand]
    
    init(_ queue: [BLECommand]) {
        self.queue = queue
    }
    
    mutating func next() -> BLECommand? {
        defer { curr += 1 }
        
        return curr < queue.count ? queue[curr] : nil
    }
}
