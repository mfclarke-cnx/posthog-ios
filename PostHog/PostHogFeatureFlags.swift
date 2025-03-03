//
//  PostHogFeatureFlags.swift
//  PostHog
//
//  Created by Manoel Aranda Neto on 10.10.23.
//

import Foundation

class PostHogFeatureFlags {
    private let config: PostHogConfig
    private let storage: PostHogStorage
    private let api: PostHogApi

    private let isLoadingLock = NSLock()
    private let featureFlagsLock = NSLock()
    private var isLoadingFeatureFlags = false

    private let dispatchQueue = DispatchQueue(label: "com.posthog.FeatureFlags",
                                              target: .global(qos: .utility))

    init(_ config: PostHogConfig,
         _ storage: PostHogStorage,
         _ api: PostHogApi)
    {
        self.config = config
        self.storage = storage
        self.api = api
    }

    private func setLoading(_ value: Bool) {
        isLoadingLock.withLock {
            self.isLoadingFeatureFlags = value
        }
    }

    func loadFeatureFlags(
        distinctId: String,
        anonymousId: String,
        groups: [String: String],
        callback: @escaping () -> Void
    ) {
        isLoadingLock.withLock {
            if self.isLoadingFeatureFlags {
                return
            }
            self.isLoadingFeatureFlags = true
        }

        api.decide(distinctId: distinctId,
                   anonymousId: anonymousId,
                   groups: groups)
        { data, _ in
            self.dispatchQueue.async {
                guard let featureFlags = data?["featureFlags"] as? [String: Any],
                      let featureFlagPayloads = data?["featureFlagPayloads"] as? [String: Any]
                else {
                    hedgeLog("Error: Decide response missing correct featureFlags format")

                    self.notifyAndRelease()

                    return callback()
                }
                let errorsWhileComputingFlags = data?["errorsWhileComputingFlags"] as? Bool ?? false

                self.featureFlagsLock.withLock {
                    if errorsWhileComputingFlags {
                        let cachedFeatureFlags = self.storage.getDictionary(forKey: .enabledFeatureFlags) as? [String: Any] ?? [:]
                        let cachedFeatureFlagsPayloads = self.storage.getDictionary(forKey: .enabledFeatureFlagPayloads) as? [String: Any] ?? [:]

                        let newFeatureFlags = cachedFeatureFlags.merging(featureFlags) { _, new in new }
                        let newFeatureFlagsPayloads = cachedFeatureFlagsPayloads.merging(featureFlagPayloads) { _, new in new }

                        // if not all flags were computed, we upsert flags instead of replacing them
                        self.storage.setDictionary(forKey: .enabledFeatureFlags, contents: newFeatureFlags)
                        self.storage.setDictionary(forKey: .enabledFeatureFlagPayloads, contents: newFeatureFlagsPayloads)
                    } else {
                        self.storage.setDictionary(forKey: .enabledFeatureFlags, contents: featureFlags)
                        self.storage.setDictionary(forKey: .enabledFeatureFlagPayloads, contents: featureFlagPayloads)
                    }
                }

                self.notifyAndRelease()

                return callback()
            }
        }
    }

    private func notifyAndRelease() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: PostHogSDK.didReceiveFeatureFlags, object: nil)
        }

        setLoading(false)
    }

    func getFeatureFlags() -> [String: Any]? {
        var flags: [String: Any]?
        featureFlagsLock.withLock {
            flags = self.storage.getDictionary(forKey: .enabledFeatureFlags) as? [String: Any]
        }

        return flags
    }

    func isFeatureEnabled(_ key: String) -> Bool {
        var flags: [String: Any]?
        featureFlagsLock.withLock {
            flags = self.storage.getDictionary(forKey: .enabledFeatureFlags) as? [String: Any]
        }

        let value = flags?[key]

        if value != nil {
            let boolValue = value as? Bool
            if boolValue != nil {
                return boolValue!
            } else {
                return true
            }
        } else {
            return false
        }
    }

    func getFeatureFlag(_ key: String) -> Any? {
        var flags: [String: Any]?
        featureFlagsLock.withLock {
            flags = self.storage.getDictionary(forKey: .enabledFeatureFlags) as? [String: Any]
        }

        return flags?[key]
    }

    func getFeatureFlagPayload(_ key: String) -> Any? {
        var flags: [String: Any]?
        featureFlagsLock.withLock {
            flags = self.storage.getDictionary(forKey: .enabledFeatureFlagPayloads) as? [String: Any]
        }

        let value = flags?[key]

        guard let stringValue = value as? String else {
            return value
        }

        do {
            // The payload value is stored as a string and is not pre-parsed...
            // We need to mimic the JSON.parse of JS which is what posthog-js uses
            return try JSONSerialization.jsonObject(with: stringValue.data(using: .utf8)!, options: .fragmentsAllowed)
        } catch {
            hedgeLog("Error parsing the object \(String(describing: value)): \(error)")
        }

        // fallbak to original value if not possible to serialize
        return value
    }
}
