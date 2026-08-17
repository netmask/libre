//
//  CLIRefresh.swift
//  libre-cli
//
//  Background refresh: fetches fresh data from LibreLinkUp API
//  and writes it to the shared SwiftData store.
//
//  This runs in a detached child process spawned by the main CLI,
//  with stdout/stderr redirected to /dev/null.
//

import Foundation
import SwiftData

/// Performs a full API refresh cycle.
func performBackgroundRefresh() async {
    // File-based lock to prevent concurrent refreshes
    let lockURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("libre-cli-refresh.lock")

    if let lockData = try? Data(contentsOf: lockURL),
       let lockTime = String(data: lockData, encoding: .utf8),
       let lockDate = Double(lockTime),
       Date.now.timeIntervalSince1970 - lockDate < 30 {
        return // Another refresh is already running
    }

    // Write lock
    try? "\(Date.now.timeIntervalSince1970)".data(using: .utf8)?.write(to: lockURL)
    defer { try? FileManager.default.removeItem(at: lockURL) }

    let keychain = KeychainService()

    let regionStr = (try? keychain.load(key: LibreKeychainKey.region)) ?? "us"
    guard let patientId = try? keychain.load(key: LibreKeychainKey.patientId) else {
        return
    }

    do {
        let api = LibreLinkAPI()
        await api.setRegion(regionStr)

        guard await authenticate(api: api, keychain: keychain) else { return }

        let result = try await api.getGlucoseDataWithHistory(patientId: patientId)

        // Write to the shared SwiftData store
        let container = try createModelContainer()
        let context = ModelContext(container)
        try GlucoseCacheStore(context: context).save(current: result.current, history: result.history)
    } catch {
        // Silently fail -- next CLI invocation will retry
    }
}

/// Prefers the session token the app persisted (no password round-trip);
/// falls back to a credential login, saving the fresh token for next time.
private func authenticate(api: LibreLinkAPI, keychain: KeychainService) async -> Bool {
    if let token = try? keychain.load(key: LibreKeychainKey.token),
       let expiryString = try? keychain.load(key: LibreKeychainKey.tokenExpiry),
       let expiryEpoch = Double(expiryString),
       Date(timeIntervalSince1970: expiryEpoch) > .now,
       let userId = try? keychain.load(key: LibreKeychainKey.userId) {
        await api.restoreSession(
            token: token,
            expiry: Date(timeIntervalSince1970: expiryEpoch),
            userId: userId
        )
        return true
    }

    guard let email = try? keychain.load(key: LibreKeychainKey.email),
          let password = try? keychain.load(key: LibreKeychainKey.password) else {
        return false
    }

    guard let response = try? await api.login(email: email, password: password),
          let authData = response.data else {
        return false
    }

    let expiry = LibreLinkAPI.expiryDate(from: authData.authTicket)
    try? keychain.save(key: LibreKeychainKey.token, value: authData.authTicket.token)
    try? keychain.save(key: LibreKeychainKey.tokenExpiry, value: String(expiry.timeIntervalSince1970))
    try? keychain.save(key: LibreKeychainKey.userId, value: authData.user.id)
    return true
}
