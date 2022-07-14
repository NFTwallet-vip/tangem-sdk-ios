//
//  AccessCodeRepository.swift
//  TangemSdk
//
//  Created by Andrey Chukavin on 13.05.2022.
//  Copyright © 2022 Tangem AG. All rights reserved.
//

@available(iOS 13.0, *)
public class AccessCodeRepository {
    private let secureStorage: SecureStorage = .init()
    private let biometricsStorage: BiometricsStorage  = .init()
    private var accessCodes: [String: Data] = .init()
    
    public init() {}
    
    deinit {
        Log.debug("AccessCodeRepository deinit")
    }
    
    public func save(_ accessCode: Data, for cardIds: [String], completion: @escaping (Result<Void, TangemSdkError>) -> Void) {
        guard BiometricsUtil.isAvailable else {
            completion(.failure(.biometricsUnavailable))
            return
        }
        
        let shouldSave = process(accessCode, for: cardIds)
        
        guard shouldSave else {
            completion(.success(())) //Nothing changed. Return
            return
        }
        
        do {
            let data = try JSONEncoder().encode(accessCodes)
            
            biometricsStorage.store(data, forKey: .accessCodes) { result in
                switch result {
                case .success:
                    self.saveCards()
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } catch {
            Log.error(error)
            completion(.failure(error.toTangemSdkError()))
        }
    }
    
    public func save(_ accessCode: Data, for cardId: String, completion: @escaping (Result<Void, TangemSdkError>) -> Void) {
        save(accessCode, for: [cardId], completion: completion)
    }
    
    public func clear() {
        do {
            try biometricsStorage.delete(.accessCodes)
            try secureStorage.delete(.cardsWithSavedCodes)
        } catch {
            Log.error(error)
        }
    }
    
    func hasItem(for cardId: String) -> Bool {
        let savedCards = getCards()
        return savedCards.contains(cardId)
    }
    
    func hasItems() -> Bool {
        let savedCards = getCards()
        return !savedCards.isEmpty
    }
    
    func unlock(completion: @escaping (Result<Void, TangemSdkError>) -> Void) {
        guard BiometricsUtil.isAvailable else {
            completion(.failure(.biometricsUnavailable))
            return
        }
        
        accessCodes = .init()
        
        biometricsStorage.get(.accessCodes) { result in
            switch result {
            case .success(let data):
                if let data = data,
                   let codes = try? JSONDecoder().decode([String: Data].self, from: data) {
                    self.accessCodes = codes
                }
                completion(.success(()))
            case .failure(let error):
                Log.error(error)
                completion(.failure(error))
            }
        }
    }
    
    func lock() {
        accessCodes = .init()
    }
    
    func fetch(for cardId: String) -> Data? {
        return accessCodes[cardId]
    }
    
    private func process(_ accessCode: Data, for cardIds: [String]) -> Bool {
        var shouldSave: Bool = false
        
        for cardId in cardIds {
            let existingCode = accessCodes[cardId]
            
            if existingCode == accessCode {
                continue //We already know this code. Ignoring
            }
            
            //We found default code
            if accessCode == UserCodeType.accessCode.defaultValue.sha256() {
                if existingCode == nil {
                    continue //Ignore default code
                } else {
                    accessCodes[cardId] = nil //User deleted the code. We should update the storage
                    shouldSave = true
                }
            } else {
                accessCodes[cardId] = accessCode //Save a new code
                shouldSave = true
            }
        }
        
        return shouldSave
    }
    
    private func getCards() -> [String] {
        if let data = try? secureStorage.get(.cardsWithSavedCodes) {
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        
        return []
    }
    
    private func saveCards() {
        if let data = try? JSONEncoder().encode(Array(accessCodes.keys)) {
            try? secureStorage.store(data, forKey: .cardsWithSavedCodes)
        }
    }
}
