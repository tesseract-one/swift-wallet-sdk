//
//  Wallet.swift
//  Wallet
//
//  Created by Yehor Popovych on 2/27/19.
//  Copyright © 2019 Tesseract Systems, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import Serializable
import Keychain


public class Wallet {
    private var _networks: Dictionary<Network, NetworkSupportFactory>
    private var _privateData: Data
    private let _accountsLock: NSLock = NSLock()
    
    public let id: String
    public private(set) var networkSupport: Dictionary<Network, NetworkSupport>?
    public private(set) var accounts: Array<Account>
    
    public var networks: Set<Network> {
        return networkSupport != nil ? Set(networkSupport!.keys) : Set()
    }
    
    public var associatedData: Dictionary<AssociatedKeys, SerializableProtocol>
    
    public init(
        id: String, privateData: Data,
        networks: Dictionary<Network, NetworkSupportFactory>,
        accounts: Array<Account> = [],
        associatedData: Dictionary<AssociatedKeys, SerializableProtocol> = [:]
    ) {
        self.id = id
        self.accounts = accounts
        self._privateData = privateData
        self._networks = networks
        self.networkSupport = nil
        self.associatedData = associatedData
    }
    
    public var isLocked: Bool {
        return networkSupport == nil
    }
    
    public func lock() {
        _accountsLock.lock()
        defer { _accountsLock.unlock() }
        networkSupport = nil
    }
    
    public func unlock(password: String) throws {
        guard isLocked else { return }
        
        _accountsLock.lock()
        defer { _accountsLock.unlock() }
        
        let keychain = try Keychain(encrypted: _privateData, password: password)
        
        var support = Dictionary<Network, NetworkSupport>()
        
        for network in keychain.networks {
            if let factory = _networks[network] {
                support[network] = factory.withKeychain(keychain: keychain, for: self)
            }
        }
        for account in accounts {
            try account.setNetworkSupport(supported: support)
        }
        
        networkSupport = support
        //_networks = nil
    }
    
    public func checkPassword(password: String) -> Bool {
        return (try? Keychain(encrypted: _privateData, password: password)) != nil
    }
    
    public func changePassword(old: String, new: String) throws {
        _privateData = try Keychain.changePassword(encrypted: _privateData, oldPassword: old, newPassword: new)
    }
    
    public func addAccount() throws -> Account {
        _accountsLock.lock()
        defer { _accountsLock.unlock() }
        let id = UUID().uuidString
        let account = try Account(id: id, index: UInt32(accounts.count), networkSupport: networkSupport)
        accounts.append(account)
        return account
    }
}

extension Wallet {
    public struct AssociatedKeys: RawRepresentable, Codable, Hashable {
        public typealias RawValue = String
        public let rawValue: RawValue
        public init(rawValue: RawValue) {
            self.rawValue = rawValue
        }
    }
    
    public struct StorageData: Codable, Equatable {
        public let id: String
        public let privateKeys: Data
        public let accounts: Array<Account.StorageData>
        public let associatedData: Dictionary<String, SerializableValue>
        
        public init(
            id: String,
            privateKeys: Data,
            accounts: Array<Account.StorageData>,
            associatedData: Dictionary<String, SerializableValue>
        ) {
            self.id = id
            self.privateKeys = privateKeys
            self.accounts = accounts
            self.associatedData = associatedData
        }
    }
    
    internal convenience init(
        data: StorageData,
        networks: Dictionary<Network, NetworkSupportFactory>
    ) throws {
        let accounts = try data.accounts.map { try Account(storageData: $0) }
        var associatedData = Dictionary<AssociatedKeys, SerializableProtocol>()
        for (key, val) in data.associatedData {
            associatedData[AssociatedKeys(rawValue: key)] = val
        }
        self.init(
            id: data.id, privateData: data.privateKeys,
            networks: networks, accounts: accounts, associatedData: associatedData
        )
    }
    
    var storageData: StorageData {
        _accountsLock.lock()
        defer { _accountsLock.unlock() }
        var data = Dictionary<String, SerializableValue>()
        for (key, val) in associatedData {
            data[key.rawValue] = val.serializable
        }
        return StorageData(
            id: id, privateKeys: _privateData,
            accounts: accounts.map { $0.storageData }, associatedData: data
        )
    }
}

//extension Wallet {
//    public var distributedAPI: dAPI {
//        let dapi = dAPI()
//        dapi.signProvider = self
//        return dapi
//    }
//}

extension Wallet: Equatable {
    public static func == (lhs: Wallet, rhs: Wallet) -> Bool {
        return lhs.id == rhs.id
            && lhs.networks == rhs.networks
            && lhs.isLocked == rhs.isLocked
            && lhs.storageData == rhs.storageData
    }
}