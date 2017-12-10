//
//  ViewController+RobotLogic.swift
//  YHD2017w-ai
//
//  Created by Takuro on 2017/12/10.
//  Copyright © 2017年 MachineThink. All rights reserved.
//

import Foundation
import UIKit
import Vision
import AVFoundation
import CoreMedia
import VideoToolbox
import UserNotifications
//import CoreBluetooth
import SocketIO

extension ViewController {
    
    // コマンドキューを順番に送信
    func setNextCommand() {
        let cmdSendBuffer = 500.0 //ms
        if cmdQueueItrt == nil {
            return
        }
        let cmd = self.cmdQueueItrt?.next()
        if cmd == nil { // queue終了
            print("queue is end")
            if self.currentMode == .terminator {
                self.currentMode = .detecting // or waiting // or finish
            } else if self.currentMode == .waiting {
                self.currentMode = .detecting
            }
            return
        }
        self.sendCommand(data: (cmd?.build())!)
        self.cmdNextDelay = (Double(cmd!.time) + cmdSendBuffer) / 1000.0 //cmd.time 分だけ次の送信をdelayする
        self.cmdExecTimer = setTimeout(self.cmdNextDelay) {
            self.setNextCommand()
        }
        // TODO: cmdExecTimer のキャンセル処理
        // timer.invalidate()      // cancel it.
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
    
    func doRobotReset() {
        var commandQueue : [BLECommand] = []
        commandQueue.append(BLECommand(kind: CommandKind.servomotorOff, time:1000)) //クラッピーを倒す
        commandQueue.append(BLECommand(kind: CommandKind.servomotorOn, time:1000)) //クラッピーを起こす
        commandQueue.append(BLECommand(kind: CommandKind.servomotorOff, time:0)) //クラッピーを倒す
        // 180度回転ここ？
        
        // BLE コマンド送信 開始
        self.cmdQueueItrt = CommandQueueIterator(commandQueue)
        self.setNextCommand()
        
        self.cluppies = []
        self.currentMode = .waiting
//        if self.currentMode == .waiting {
//            self.currentMode = .detecting
//        }
    }
    
    /// 「ダルマさんが転んだ」 is detected
    func doRobotDMSCD() {
        print(#function)
        if self.currentMode == .terminator {
            print("追いかけている最中は無視")
            return
        }
        
        var commandQueue : [BLECommand] = []
        commandQueue.append(BLECommand(kind: CommandKind.servomotorOff, time:0)) //クラッピーを倒す
        commandQueue.append(BLECommand(kind: CommandKind.spinTurn, time:5000)) //超信地旋回
        
        // BLE コマンド送信 開始
        self.cmdQueueItrt = CommandQueueIterator(commandQueue)
        self.setNextCommand()
        self.currentMode = .waiting
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
                commandQueue.append(BLECommand(kind: CommandKind.servomotorOn, time:0)) //クラッピーを起こす
                if targetCluppy.center.x < center.x { // 右
                    commandQueue.append(BLECommand(kind: CommandKind.turnLeft, time:500))
                } else if center.x < targetCluppy.center.x { //左
                    commandQueue.append(BLECommand(kind: CommandKind.turnRight, time:500))
                }
                commandQueue.append(BLECommand(kind: CommandKind.forward, time:2500)) //前進して迫る
                
                // BLE コマンド送信 開始
                self.cmdQueueItrt = CommandQueueIterator(commandQueue)
                self.setNextCommand()
            }
        }
    }
    
    func detectAndTrace(predictions: [YOLO.Prediction]) {
        // TODO : リアルタイム追尾
        // TODO : 必要なだけ近づいたら止まる or 時間で止める
    }

}
