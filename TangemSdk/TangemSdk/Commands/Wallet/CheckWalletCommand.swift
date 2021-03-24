//
//  CheckWalletCommand.swift
//  TangemSdk
//
//  Created by Alexander Osokin on 03/10/2019.
//  Copyright © 2019 Tangem AG. All rights reserved.
//

import Foundation

/// Deserialized response from the Tangem card after `CheckWalletCommand`.
public struct CheckWalletResponse: JSONStringConvertible {
    /// Unique Tangem card ID number
    public let cardId: String
    /// Random salt generated by the card
    public let salt: Data
    /// Challenge and salt signed with the wallet private key.
    public let walletSignature: Data
}

/// This command proves that the wallet private key from the card corresponds to the wallet public key.  Standard challenge/response scheme is used
public final class CheckWalletCommand: Command {
    deinit {
        Log.debug("CheckWalletCommand deinit")
    }
    
    public typealias CommandResponse = CheckWalletResponse
	
    public var preflightReadSettings: PreflightReadSettings {
        .readWallet(index: walletIndex)
    }
    
	private var walletIndex: WalletIndex
	
    /// Random challenge generated by application
    private var challenge: Data? = nil
    private let curve: EllipticCurve
    private let publicKey: Data
	
    
	public init(curve: EllipticCurve, publicKey: Data) {
        self.curve = curve
        self.publicKey = publicKey
        self.walletIndex = .publicKey(publicKey)
    }
    
    func performPreCheck(_ card: Card) -> TangemSdkError? {
        if card.status == .notPersonalized {
            return .notPersonalized
        }
        
        if card.isActivated {
            return .notActivated
        }
        
        return nil
    }

    public func run(in session: CardSession, completion: @escaping CompletionResult<CheckWalletResponse>) {
        transieve(in: session) {result in
            switch result {
            case .success(let checkWalletResponse):
                guard let challenge = self.challenge else {
                    completion(.failure(.failedToGenerateRandomSequence))
                    return
                }
                
                guard let verifyResult = self.verify(response: checkWalletResponse, challenge: challenge) else {
                    completion(.failure(.cryptoUtilsError))
                    return
                }
                
                if verifyResult {
                    completion(.success(checkWalletResponse))
                } else {
                    completion(.failure(.cardVerificationFailed))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func serialize(with environment: SessionEnvironment) throws -> CommandApdu {
        challenge = try CryptoUtils.generateRandomBytes(count: 16)
        let tlvBuilder = try createTlvBuilder(legacyMode: environment.legacyMode)
            .append(.pin, value: environment.pin1.value)
            .append(.cardId, value: environment.card?.cardId)
            .append(.challenge, value: challenge)
        
		try walletIndex.addTlvData(to: tlvBuilder)
		
        return CommandApdu(.checkWallet, tlv: tlvBuilder.serialize())
    }
    
    func deserialize(with environment: SessionEnvironment, from apdu: ResponseApdu) throws -> CheckWalletResponse {
        guard let tlv = apdu.getTlvData(encryptionKey: environment.encryptionKey) else {
            throw TangemSdkError.deserializeApduFailed
        }
        
        let decoder = TlvDecoder(tlv: tlv)
        return CheckWalletResponse(
            cardId: try decoder.decode(.cardId),
            salt: try decoder.decode(.salt),
            walletSignature: try decoder.decode(.walletSignature))
    }
    
    private func verify(response: CheckWalletResponse, challenge: Data) -> Bool? {
        return CryptoUtils.verify(curve: curve,
                                  publicKey: publicKey,
                                  message: challenge + response.salt,
                                  signature: response.walletSignature)
    }
}
