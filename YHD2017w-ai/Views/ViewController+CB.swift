//
//  ViewController+CB.swift
//  YHD2017w-ai
//
//  Created by Takuro on 2017/12/09.
//  Copyright © 2017年 MachineThink. All rights reserved.
//

import Foundation
import CoreBluetooth

//MARK : - CBCentralManagerDelegate
extension ViewController: CBCentralManagerDelegate {
//    let serviceUUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
//    let charcteristicUUID = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        //電源ONを待って、スキャンする
        if (central.state == .poweredOn) {
            print("BLE central is poweredOn")
            let services: [CBUUID] = [serviceUUID]
            print(services)
//            centralManager?.scanForPeripherals(withServices: services, options: nil)
            centralManager?.scanForPeripherals(withServices: nil, options: nil)
        }
    }
    
    /// STEP-1 ペリフェラルを発見すると呼ばれる
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
//        print("Found peripheral : \(String(describing: peripheral.name))")
        if (peripheral.name != "YHD2017W-CP-ONI") { //念のため、名前みておく
            return
        }
        print("Found peripheral : \(String(describing: peripheral.name)), \(RSSI)")
        print(peripheral.services ?? "no services" )
        
        self.peripheral = peripheral
        centralManager?.stopScan()
        
        //接続開始
        central.connect(peripheral, options: nil)
    }
    
    /// STEP-2 接続されると呼ばれる
    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }
}

//MARK : - CBPeripheralDelegate
extension ViewController: CBPeripheralDelegate {
    
    /// STEP-3 サービス発見時に呼ばれる
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        
        if error != nil {
            print(error.debugDescription)
            return
        }
        
        //キャリアクタリスティク探索開始
        peripheral.discoverCharacteristics([charcteristicUUID, charcteristic2UUID],
                                           for: (peripheral.services?.first)!)
        
        let services = peripheral.services
        print("Found \(String(describing: services?.count)) services! :\(String(describing: services))")
        self.botService = services![0]
    }
    
    /// STEP-4 キャリアクタリスティク発見時に呼ばれる
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        
        if error != nil {
            print(error.debugDescription)
            return
        }
        let characteristics = self.botService.characteristics
        print("Found \(String(describing: characteristics?.count)) characteristics! : \(String(describing: characteristics))")
        
//        self.botCmdChara = characteristics![0]

        for c in characteristics! {
            if charcteristicUUID.isEqual(c.uuid) {
                print(charcteristicUUID)
                self.botCmdChara = c
            }
            if charcteristic2UUID.isEqual(c.uuid) {
                print(charcteristic2UUID)
                self.botManChara = c
                peripheral.setNotifyValue(true, for: c)
            }
        }
        
        // ロボット初期化
        self.doRobotReset()
    }
    
    /// データ更新時に呼ばれる
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        print("notify is incoming : \(characteristic.value!)")
        if error != nil {
            print(error.debugDescription)
            return
        }
        if !charcteristic2UUID.isEqual(characteristic.uuid) {
           return
        }
        self.getBleNotifyManualCmd(data: characteristic.value!)
    }
    
    public func sendCommand(data : Data) {
        print("\(#function) - \([UInt8](data))")
        
//        self.peripheral.writeValue(data, for: self.botCmdChara, type: CBCharacteristicWriteType.withoutResponse) //ESP32 が withoutResponseだと通らない
        self.peripheral.writeValue(data, for: self.botCmdChara, type: CBCharacteristicWriteType.withResponse)
    }
}
