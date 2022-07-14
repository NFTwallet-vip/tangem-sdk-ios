//
//  SecureStorageService.swift
//  TangemSdk
//
//  Created by Alexander Osokin on 23.01.2020.
//  Copyright © 2020 Tangem AG. All rights reserved.
//

import Foundation
import Security

/// Helper class for Keychain
@available(iOS 13.0, *)
public struct SecureStorage {
    
    public init() {}
    
    public func get(_ account: String) throws -> Data? {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: account,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain: true,
            kSecReturnData: true,
        ] as [String: Any]
        
        var result: AnyObject?
        
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            
            return data
        case errSecItemNotFound:
            return nil
        case let status:
            throw KeyStoreError("Keychain read failed: \(status.message)")
        }
    }
    
    public func store(_ object: Data, forKey account: String, overwrite: Bool = true) throws {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: account,
            kSecValueData: object,
            kSecUseDataProtectionKeychain: true,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ] as [String: Any]
        
        var status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecDuplicateItem && overwrite {
            let searchQuery = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrAccount: account,
            ] as [String: Any]
            
            let attributes = [kSecValueData: object] as [String: Any]
            
            status = SecItemUpdate(searchQuery as CFDictionary, attributes as CFDictionary)
        }
        
        guard status == errSecSuccess else {
            throw KeyStoreError("Unable to store item: \(status.message)")
        }
    }
    
    public func delete(_ account: String) throws {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain: true,
            kSecAttrAccount: account,
        ] as [String: Any]
        
        switch SecItemDelete(query as CFDictionary) {
        case errSecItemNotFound, errSecSuccess: break // Okay to ignore
        case let status:
            throw KeyStoreError("Unexpected deletion error: \(status.message)")
        }
    }
    
    func get(_ storageKey: SecureStorageKey) throws -> Data? {
        try get(storageKey.rawValue)
    }
    
    func store(_ object: Data, forKey storageKey: SecureStorageKey, overwrite: Bool = true) throws  {
       try store(object, forKey: storageKey.rawValue)
    }
    
    func delete(_ storageKey: SecureStorageKey) throws {
        try delete(storageKey.rawValue)
    }
}

@available(iOS 13.0, *)
extension SecureStorage {
    /// Stores a CryptoKit key in the keychain as a generic password.
    func storeKey<T: GenericPasswordConvertible>(_ key: T, forKey storageKey: SecureStorageKey) throws {
        try store(key.rawRepresentation, forKey: storageKey, overwrite: true)
    }
    
    /// Reads a CryptoKit key from the keychain as a generic password.
    func readKey<T: GenericPasswordConvertible>(_ storageKey: SecureStorageKey) throws -> T? {
        if let data = try get(storageKey) {
            return try T(rawRepresentation: data)
        }
        
        return nil
    }
}
