import Flutter
import UIKit
import CoreBluetooth

public class FlutterPosPrinterPlatformPlugin: NSObject, FlutterPlugin, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    let channel: FlutterMethodChannel
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral!
    private var printerCharacteristic: CBCharacteristic!
    private var devices: [CBPeripheral] = [CBPeripheral]()
    
    // we need to init this plugin to get the instance of centralmanager
    init (_ channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
        // In Swift, this is done in viewDidLoad()
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        
        
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_pos_printer_platform/methods", binaryMessenger: registrar.messenger())
        let instance = FlutterPosPrinterPlatformPlugin(channel)
        
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        //      guard let controller = UIApplication.shared.keyWindow?.rootViewController as? FlutterViewController else {
        //            fatalError("rootViewController is not type FlutterViewController")
        //          }
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getBluetoothState":
            getBluetoothState(result: result)
        case "startScan":
            print("Scanning...")
            centralManager?.scanForPeripherals(withServices: nil, options: nil)
            result(nil)
        case "stopScan":
            print("Stop scan")
            centralManager?.stopScan()
            result(nil)
        case "connect":
            print("Stop scan")
            if let args = call.arguments as? Dictionary<String, Any>,
               let name = args["name"] as? String {
                let address = args["address"] as? String
                // please check the "as" above  - wasn't able to test
                // handle the method
                connectDevice(name: name, address: address!, result: result)
                
            } else {
                result(FlutterError.init(code: "errorSetDebug", message: "data or format error", details: nil))
            }
        case "writeData":
            if let args = call.arguments as? Dictionary<String, Any>,
               let bytes: [UInt8] = args["bytes"] as? [UInt8] {
                //                let length = args["length"] as? Int
                sendData(bytes: bytes)
                result(nil)
            } else {
                result(FlutterError.init(code: "errorSetDebug", message: "data or format error", details: nil))
            }
            result(nil)
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    func connectDevice(name: String, address: String, result: FlutterResult){
        
        //stopScan
        centralManager.stopScan()
        
        
        if let peripheral = devices.first(where:{$0.identifier.uuidString == address})
        {
            decodePeripheralState(peripheralState: peripheral.state)
            if (peripheral.state != .connected){
                //connect
                centralManager.connect(peripheral, options: nil)
                self.peripheral = peripheral
            }
            result(true)
        }else{
            result(false)
        }
        
    }
    
    private func getBluetoothState(result: FlutterResult) {
        if(self.centralManager.state == .poweredOn) {
            result("Yes");
        } else {
            result("No");
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        //discover all service
        // Nil it’s going to discover all services
        peripheral.discoverServices(nil)
        peripheral.delegate = self
        
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard peripheral.name != nil else {return}
        
        if (peripheral.name != nil && !devices.contains(where: {$0.identifier.uuidString == peripheral.identifier.uuidString})){
            
            print("bt devices found: " + (peripheral.name ?? ""))
            
            let deviceMap = ["name":peripheral.name, "address": peripheral.identifier.uuidString]
            
            devices.append(peripheral)
            self.channel.invokeMethod("ScanResult", arguments: deviceMap)
        }
        //        if peripheral.name! == "MTP-2"
    }
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            
            print("BT on")
            break
        case .poweredOff:
            print("BT OFF")
            // Alert user to turn on Bluetooth
            break
        case .resetting:
            
            // Wait for next state update and consider logging interruption of Bluetooth service
            break
        case .unauthorized:
            
            // Alert user to enable Bluetooth permission in app Settings
            break
        case .unsupported:
            
            // Alert user their device does not support Bluetooth and app will not work as expected
            break
        case .unknown:
            break
        default:
            
            // Wait for next state update
            break
        }
    }
    
    public func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral) {
        
        switch event {
        case .peerConnected:
            print("connected")
        case .peerDisconnected:
            print("disconnected")
        default:
            break
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("peripheral: %@ failed to connect", peripheral)
    }
    
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        
        if let services = peripheral.services {
            
            //discover characteristics of services
            for service in services {
                
                // passing nil it's going to discover all characteristics.
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if (service.uuid.uuidString == "18F0" || service.uuid.uuidString == "18F1"){
            print("\n -------- SERVICE: " + service.description)
            
            if let charac = service.characteristics {
                for characteristic in charac {
                    
                    if characteristic.uuid.uuidString == "2AF1" {
                        print("characteristic: " + characteristic.description )
                        self.printerCharacteristic = characteristic
                    }
                }
            }
            
        }
    }
    
    func decodePeripheralState(peripheralState: CBPeripheralState) {
        
        switch peripheralState {
        case .disconnected:
            print("Peripheral state: disconnected")
        case .connected:
            print("Peripheral state: connected")
        case .connecting:
            print("Peripheral state: connecting")
        case .disconnecting:
            print("Peripheral state: disconnecting")
        default:
            break
        }
        
    } // END func decodePeripheralState(peripheralState
    
    fileprivate var ledMask: UInt8    = 0
    fileprivate let digitalBits       = 2
    
    func printTestData(characteristic: CBCharacteristic) {
        if let descriptors = characteristic.descriptors {
            for descriptor in descriptors {
                print("descriptor: " + descriptor.description )
            }
        }
        
        let dataToSend = "Print Success!" + characteristic.uuid.uuidString
        let buf: [UInt8] = Array(dataToSend.utf8)
        let data = Data(buf)
        
        let clearCommand: [UInt8] = [0x1B, 0x40]
        self.peripheral?.writeValue(Data(clearCommand), for: characteristic, type: .withResponse) // clear
        self.peripheral?.writeValue(Data([0x1B, 0x61, 0x01]), for: characteristic, type: .withResponse) // center
        self.peripheral?.writeValue(data, for: characteristic, type: .withResponse)
        self.peripheral?.writeValue(Data([0x0A]), for: characteristic, type: .withResponse) // Line Feed x 1
        
    }
    
    private func sendData(bytes: [UInt8]){
        self.peripheral?.writeValue(Data([0x1B, 0x40]), for: self.printerCharacteristic , type: .withResponse) // clear
        self.peripheral?.writeValue(Data(bytes), for: self.printerCharacteristic , type: .withResponse)
    }
    
}
