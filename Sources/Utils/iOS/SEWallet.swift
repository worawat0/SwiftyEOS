//
//  SEWallet.swift
//  SwiftyEOS
//
//  Created by croath on 2018/7/18.
//  Copyright © 2018 ProChain. All rights reserved.
//

import Foundation

@objcMembers class SEKeystoreService: NSObject {
    public class var sharedInstance: SEKeystoreService {
        struct Singleton {
            static let instance : SEKeystoreService = SEKeystoreService()
        }
        return Singleton.instance
    }
    
    lazy var keystore: SEKeystore! = {
        let libraryDirectory = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true)[0]
        return SEKeystore(keyDir: libraryDirectory.appending("/eos_keystore"))
    }()
    
    func importAccount(privateKey: String, passcode: String, succeed: ((_ account: SELocalAccount) -> Void)?, failed:((_ error: Error) -> Void)?) {
        DispatchQueue.global(qos: .background).async {
            do {
                let account = try self.keystore.importAccount(privateKey: privateKey, passcode: passcode)
                if succeed != nil {
                    DispatchQueue.main.async {
                        succeed!(account)
                    }
                }
            } catch {
                if failed != nil {
                    DispatchQueue.main.async {
                        failed!(error)
                    }
                }
            }
        }
    }
    
    func newAccount(passcode: String, succeed: ((_ account: SELocalAccount) -> Void)?, failed:((_ error: Error) -> Void)?) {
        DispatchQueue.global(qos: .background).async {
            do {
                let account = try self.keystore.newLocalAccount(passcode: passcode)
                if succeed != nil {
                    DispatchQueue.main.async {
                        succeed!(account)
                    }
                }
            } catch {
                if failed != nil {
                    DispatchQueue.main.async {
                        failed!(error)
                    }
                }
            }
        }
    }
    
    func deleteAccount(passcode: String, account: SELocalAccount, succeed: (() -> Void)?, failed:((_ error: Error) -> Void)?) {
        DispatchQueue.global(qos: .background).async {
            do {
                try self.keystore.deleteAccount(passcode: passcode, account: account)
                if succeed != nil {
                    DispatchQueue.main.async {
                        succeed!()
                    }
                }
            } catch {
                if failed != nil {
                    DispatchQueue.main.async {
                        failed!(error)
                    }
                }
            }
        }
    }
    
    func changeAccountPasscode(oldcode: String, newcode: String, account: SELocalAccount, succeed: (() -> Void)?, failed:((_ error: Error) -> Void)?) {
        DispatchQueue.global(qos: .background).async {
            do {
                let _ = try self.keystore.changeAccountPasscode(oldcode: oldcode, newcode: newcode, account: account)
                if succeed != nil {
                    DispatchQueue.main.async {
                        succeed!()
                    }
                }
            } catch {
                if failed != nil {
                    DispatchQueue.main.async {
                        failed!(error)
                    }
                }
            }
        }
    }
    
    func exportAccountPrivateKey(passcode: String, account: SELocalAccount, succeed: ((_ pk: String) -> Void)?, failed:((_ error: Error) -> Void)?) {
        DispatchQueue.global(qos: .background).async {
            do {
                let pk = try account.decrypt(passcode: passcode)
                if succeed != nil {
                    DispatchQueue.main.async {
                        succeed!(pk.wif())
                    }
                }
            } catch {
                if failed != nil {
                    DispatchQueue.main.async {
                        failed!(error)
                    }
                }
            }
        }
    }
    
    static func literalValid(keyString: String) -> Bool {
        return PrivateKey.literalValid(keyString:keyString)
    }
}

@objcMembers class SEKeystore: NSObject {
    let keyUrl: URL
    init(keyDir: String) {
        keyUrl = URL(fileURLWithPath: keyDir)
        do {
            try FileManager.default.createDirectory(at: keyUrl, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print(error)
        }
    }
    
    func importAccount(privateKey: String, passcode: String) throws -> SELocalAccount {
        let account = try SELocalAccount(privateKey: privateKey, passcode: passcode)
        try account.write(to: keyUrl.appendingPathComponent(account.publicKey!))
        return account
    }
    
    func newLocalAccount(passcode: String) throws -> SELocalAccount {
        let account = SELocalAccount(passcode: passcode)
        try account.write(to: keyUrl.appendingPathComponent(account.publicKey!))
        return account
    }
    
    func deleteAccount(passcode: String, account: SELocalAccount) throws {
        let _ = try account.decrypt(passcode: passcode)
        try FileManager.default.removeItem(at: keyUrl.appendingPathComponent(account.publicKey!))
    }
    
    func changeAccountPasscode(oldcode: String, newcode: String, account: SELocalAccount) throws -> SELocalAccount {
        let pk = try account.decrypt(passcode: oldcode)
        try FileManager.default.removeItem(at: keyUrl.appendingPathComponent(account.publicKey!))
        let account = SELocalAccount(pk: pk, passcode: newcode)
        try account.write(to: keyUrl.appendingPathComponent(account.publicKey!))
        return account
    }
    
    func defaultAccount() -> SELocalAccount? {
        do {
            let fileManager = FileManager.default
            let fileURLs = try fileManager.contentsOfDirectory(at: keyUrl, includingPropertiesForKeys: nil)
            // process files
            if fileURLs.count > 0 {
                let fileUrl = fileURLs.first
                let data = try Data(contentsOf: fileUrl!)
                let account = try SELocalAccount(fileData: data)
                return account
            } else {
                return nil
            }
        } catch {
            print("Error while enumerating files: \(error.localizedDescription)")
            return nil
        }
    }
    
    //    func accounts() -> [SELocalAccount] {
    //        let fileManager = FileManager.default
    //        do {
    //            let fileURLs = try fileManager.contentsOfDirectory(at: keyUrl, includingPropertiesForKeys: nil)
    //            // process files
    //        } catch {
    //            print("Error while enumerating files: \(error.localizedDescription)")
    //        }
    //    }
}

struct RawKeystore: Codable {
    var data: String
    var iv: String
    var publicKey: String
    
    func write(to: URL) throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let jsonData = try! encoder.encode(self)
        try jsonData.write(to: to)
    }
}

@objcMembers class SELocalAccount: NSObject {
    public class var currentAccount: SELocalAccount? {
        if __account == nil {
            __account = existingAccount()
        }
        return __account
    }
    
    public static var __account: SELocalAccount?
    class func existingAccount() -> SELocalAccount? {
        return SEKeystoreService.sharedInstance.keystore.defaultAccount()
    }
    
    
    static let aesIv = "A-16-Byte-String"
    
    var publicKey: String?
    var rawPublicKey: String? {
        get {
            let withoutDelimiter = publicKey?.components(separatedBy: "_").last
            guard withoutDelimiter!.hasPrefix("EOS") else {
                return "EOS\(withoutDelimiter!)"
            }
            return withoutDelimiter
        }
    }
    private var rawKeystore: RawKeystore
    
    convenience init(passcode: String) {
        let (pk, _) = generateRandomKeyPair(enclave: .Secp256k1)
        self.init(pk: pk!, passcode: passcode)
    }
    
    convenience init(privateKey: String, passcode: String) throws {
        let pk = try PrivateKey(keyString: privateKey)
        self.init(pk: pk!, passcode: passcode)
    }
    
    init(pk: PrivateKey, passcode: String) {
        let pub = PublicKey(privateKey: pk)
        publicKey = pub.wif()
        
        let pkData = pk.wif().data(using:String.Encoding.utf8)!
        let encrytedData = AESCrypt(inData: pkData,
                                    keyData: passcode.data(using:String.Encoding.utf8)!,
                                    ivData: SELocalAccount.aesIv.data(using:String.Encoding.utf8)!,
                                    operation: kCCEncrypt)
        rawKeystore = RawKeystore(data: String(data: encrytedData, encoding: .utf8)!,
                                  iv: SELocalAccount.aesIv,
                                  publicKey: publicKey!)
    }
    
    init(fileData: Data) throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let fileKeystore = try decoder.decode(RawKeystore.self, from: fileData)
        rawKeystore = fileKeystore
        publicKey = fileKeystore.publicKey
    }
    
    func write(to: URL) throws {
        try rawKeystore.write(to: to)
    }
    
    func getEosBalance(account: String, succeed: ((_ balance: NSDecimalNumber) -> Void)?, failed:((_ error: Error) -> Void)?) {
        EOSRPC.sharedInstance.getCurrencyBalance(account: account, symbol: "EOS", code: "eosio.token") { (balance: NSDecimalNumber?, error: Error?) in
            if error != nil {
                if failed != nil {
                    failed!(error!)
                }
                return
            }
            
            if succeed != nil {
                succeed!(balance!)
            }
        }
    }
    
    func getEpraBalance(account: String, succeed: ((_ balance: NSDecimalNumber) -> Void)?, failed:((_ error: Error) -> Void)?) {
        EOSRPC.sharedInstance.getCurrencyBalance(account: account, symbol: "EPRA", code: "eosio.token") { (balance: NSDecimalNumber?, error: Error?) in
            if error != nil {
                if failed != nil {
                    failed!(error!)
                }
                return
            }
            
            if succeed != nil {
                succeed!(balance!)
            }
        }
    }
    
    func decrypt(passcode: String) throws -> PrivateKey {
        let decryptedData = AESCrypt(inData:rawKeystore.data.data(using: .utf8)!,
                                     keyData:passcode.data(using:String.Encoding.utf8)!,
                                     ivData:rawKeystore.iv.data(using:String.Encoding.utf8)!,
                                     operation:kCCDecrypt)
        let pkString = String(data:decryptedData, encoding:String.Encoding.utf8)
        let pk = try PrivateKey(keyString: pkString!)
        let pub = PublicKey(privateKey: pk!)
        guard pub.wif() == rawKeystore.publicKey else {
            throw NSError(domain: "", code: 0, userInfo: nil)
        }
        return pk!
    }
}

class SEWallet: NSObject {
    //    static func newWallet(passcode: String) -> SEWallet {
    //
    //    }
}
