//
//  PostHogSDKTest.swift
//  PostHogTests
//
//  Created by Manoel Aranda Neto on 31.10.23.
//

import Foundation
import Nimble
import Quick

@testable import PostHog

class PostHogSDKTest: QuickSpec {
    func getSut(preloadFeatureFlags: Bool = false,
                sendFeatureFlagEvent: Bool = false,
                flushAt: Int = 1,
                optOut: Bool = false) -> PostHogSDK
    {
        let config = PostHogConfig(apiKey: "123", host: "http://localhost:9001")
        config.flushAt = flushAt
        config.preloadFeatureFlags = preloadFeatureFlags
        config.sendFeatureFlagEvent = sendFeatureFlagEvent
        config.disableReachabilityForTesting = true
        config.disableQueueTimerForTesting = true
        config.optOut = optOut
        return PostHogSDK.with(config)
    }

    override func spec() {
        var server: MockPostHogServer!

        func deleteDefaults() {
            let userDefaults = UserDefaults.standard
            userDefaults.removeObject(forKey: "PHGVersionKey")
            userDefaults.removeObject(forKey: "PHGBuildKeyV2")
            userDefaults.synchronize()

            deleteSafely(applicationSupportDirectoryURL())
        }

        beforeEach {
            deleteDefaults()
            server = MockPostHogServer()
            server.start()
        }
        afterEach {
            server.stop()
            server = nil
        }

        it("captures the capture event") {
            let sut = self.getSut()

            sut.capture("test event",
                        properties: ["foo": "bar"],
                        userProperties: ["userProp": "value"],
                        userPropertiesSetOnce: ["userPropOnce": "value"],
                        groupProperties: ["groupProp": "value"])

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "test event"

            expect(event.properties["foo"] as? String) == "bar"

            let set = event.properties["$set"] as? [String: Any] ?? [:]
            expect(set["userProp"] as? String) == "value"

            let setOnce = event.properties["$set_once"] as? [String: Any] ?? [:]
            expect(setOnce["userPropOnce"] as? String) == "value"

            let groupProps = event.properties["$groups"] as? [String: Any] ?? [:]
            expect(groupProps["groupProp"] as? String) == "value"

            sut.reset()
            sut.close()
        }

        it("captures an identify event") {
            let sut = self.getSut()

            sut.identify("distinctId",
                         userProperties: ["userProp": "value"],
                         userPropertiesSetOnce: ["userPropOnce": "value"])

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "$identify"

            expect(event.distinctId) == "distinctId"
            let anonId = sut.getAnonymousId()
            expect(event.properties["$anon_distinct_id"] as? String) == anonId

            let set = event.properties["$set"] as? [String: Any] ?? [:]
            expect(set["userProp"] as? String) == "value"

            let setOnce = event.properties["$set_once"] as? [String: Any] ?? [:]
            expect(setOnce["userPropOnce"] as? String) == "value"

            sut.reset()
            sut.close()
        }

        it("captures an alias event") {
            let sut = self.getSut()

            sut.alias("theAlias")

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "$create_alias"

            expect(event.properties["alias"] as? String) == "theAlias"

            sut.reset()
            sut.close()
        }

        it("captures a screen event") {
            let sut = self.getSut()

            sut.screen("theScreen", properties: ["prop": "value"])

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "$screen"

            expect(event.properties["$screen_name"] as? String) == "theScreen"
            expect(event.properties["prop"] as? String) == "value"

            sut.reset()
            sut.close()
        }

        it("captures a group event") {
            let sut = self.getSut()

            sut.group(type: "some-type", key: "some-key", groupProperties: [
                "name": "some-company-name",
            ])

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let groupEvent = events.first!
            expect(groupEvent.event) == "$groupidentify"
            expect(groupEvent.properties["$group_type"] as? String?) == "some-type"
            expect(groupEvent.properties["$group_key"] as? String?) == "some-key"
            expect((groupEvent.properties["$group_set"] as? [String: String])?["name"] as? String) == "some-company-name"

            sut.reset()
            sut.close()
        }

        it("setups default IDs") {
            let sut = self.getSut()

            expect(sut.getAnonymousId()).toNot(beNil())
            expect(sut.getDistinctId()) == sut.getAnonymousId()

            sut.reset()
            sut.close()
        }

        it("setups optOut") {
            let sut = self.getSut()

            sut.optOut()

            expect(sut.isOptOut()) == true

            sut.optIn()

            expect(sut.isOptOut()) == false

            sut.reset()
            sut.close()
        }

        it("sets opt out via config") {
            let sut = self.getSut(optOut: true)

            sut.optOut()

            expect(sut.isOptOut()) == true

            sut.reset()
            sut.close()
        }

        it("calls reloadFeatureFlags") {
            let sut = self.getSut()

            let group = DispatchGroup()
            group.enter()

            sut.reloadFeatureFlags {
                group.leave()
            }

            group.wait()

            expect(sut.isFeatureEnabled("bool-value")) == true

            sut.reset()
            sut.close()
        }

        it("identify sets distinct and anon Ids") {
            let sut = self.getSut()

            let distId = sut.getDistinctId()

            sut.identify("newDistinctId")

            expect(sut.getDistinctId()) == "newDistinctId"
            expect(sut.getAnonymousId()) == distId

            sut.reset()
            sut.close()
        }

        it("loads feature flags automatically") {
            let sut = self.getSut(preloadFeatureFlags: true)

            waitDecideRequest(server)
            expect(sut.isFeatureEnabled("bool-value")) == true

            sut.reset()
            sut.close()
        }

        it("send feature flag event for isFeatureEnabled when enabled") {
            let sut = self.getSut(preloadFeatureFlags: true, sendFeatureFlagEvent: true)

            waitDecideRequest(server)
            expect(sut.isFeatureEnabled("bool-value")) == true

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "$feature_flag_called"
            expect(event.properties["$feature_flag"] as? String) == "bool-value"
            expect(event.properties["$feature_flag_response"] as? Bool) == true

            sut.reset()
            sut.close()
        }

        it("send feature flag event for getFeatureFlag when enabled") {
            let sut = self.getSut(preloadFeatureFlags: true, sendFeatureFlagEvent: true)

            waitDecideRequest(server)
            expect(sut.getFeatureFlag("bool-value") as? Bool) == true

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "$feature_flag_called"
            expect(event.properties["$feature_flag"] as? String) == "bool-value"
            expect(event.properties["$feature_flag_response"] as? Bool) == true

            sut.reset()
            sut.close()
        }

        it("capture AppBackgrounded") {
            let sut = self.getSut()

            sut.captureAppBackgrounded()

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "Application Backgrounded"

            sut.reset()
            sut.close()
        }

        it("capture AppInstalled") {
            let sut = self.getSut()

            sut.captureAppInstallLifecycle()

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "Application Installed"
            expect(event.properties["version"] as? String) != nil
            expect(event.properties["build"] as? String) != nil

            sut.reset()
            sut.close()
        }

        it("capture AppUpdated") {
            let sut = self.getSut()

            let userDefaults = UserDefaults.standard
            userDefaults.setValue("1.0.0", forKey: "PHGVersionKey")
            userDefaults.setValue("1", forKey: "PHGBuildKeyV2")
            userDefaults.synchronize()

            sut.captureAppInstallLifecycle()

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "Application Updated"
            expect(event.properties["version"] as? String) != nil
            expect(event.properties["build"] as? String) != nil
            expect(event.properties["previous_version"] as? String) != nil
            expect(event.properties["previous_build"] as? String) != nil

            sut.reset()
            sut.close()
        }

        it("capture AppOpenedFromBackground from_background should be false") {
            let sut = self.getSut()

            sut.captureAppOpened()

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "Application Opened"
            expect(event.properties["from_background"] as? Bool) == false

            sut.reset()
            sut.close()
        }

        it("capture AppOpenedFromBackground from_background should be true") {
            let sut = self.getSut(flushAt: 2)

            sut.captureAppOpened()
            sut.captureAppOpened()

            let events = getBatchedEvents(server)

            expect(events.count) == 2

            let event = events.last!
            expect(event.event) == "Application Opened"
            expect(event.properties["from_background"] as? Bool) == true

            sut.reset()
            sut.close()
        }

        it("capture captureAppOpened") {
            let sut = self.getSut()

            sut.captureAppOpened()

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            let event = events.first!
            expect(event.event) == "Application Opened"
            expect(event.properties["from_background"] as? Bool) == false
            expect(event.properties["version"] as? String) != nil
            expect(event.properties["build"] as? String) != nil

            sut.reset()
            sut.close()
        }

        it("reloadFeatureFlags adds groups if any") {
            let sut = self.getSut()

            sut.group(type: "some-type", key: "some-key", groupProperties: [
                "name": "some-company-name",
            ])

            let events = getBatchedEvents(server)

            expect(events.count) == 1

            sut.reloadFeatureFlags()

            let requests = getDecideRequest(server)

            expect(requests.count) == 1
            let request = requests.first

            let groups = request!["$groups"] as? [String: Any]
            expect(groups!["some-type"] as? String) == "some-key"

            sut.reset()
            sut.close()
        }

        it("merge groups when group is called") {
            let sut = self.getSut(flushAt: 3)

            sut.group(type: "some-type", key: "some-key")

            sut.group(type: "some-type-2", key: "some-key-2")

            sut.capture("event")

            let events = getBatchedEvents(server)

            expect(events.count) == 3
            let event = events.last!

            let groups = event.properties["$groups"] as? [String: Any]
            expect(groups!["some-type"] as? String) == "some-key"
            expect(groups!["some-type-2"] as? String) == "some-key-2"

            sut.reset()
            sut.close()
        }

        it("register and unregister properties") {
            let sut = self.getSut(flushAt: 1)

            sut.register(["test1": "test"])
            sut.register(["test2": "test"])
            sut.unregister("test2")
            sut.register(["test3": "test"])

            sut.capture("event")

            let events = getBatchedEvents(server)

            expect(events.count) == 1
            let event = events.last!

            expect(event.properties["test1"] as? String) == "test"
            expect(event.properties["test3"] as? String) == "test"
            expect(event.properties["test2"] as? String) == nil

            sut.reset()
            sut.close()
        }

        it("add active feature flags as part of the event") {
            let sut = self.getSut()

            sut.reloadFeatureFlags()
            waitDecideRequest(server)

            sut.capture("event")

            let events = getBatchedEvents(server)

            expect(events.count) == 1
            let event = events.first!

            let activeFlags = event.properties["$active_feature_flags"] as? [Any] ?? []
            expect(activeFlags.contains { $0 as? String == "bool-value" }) == true
            expect(activeFlags.contains { $0 as? String == "disabled-flag" }) == false

            expect(event.properties["$feature/bool-value"] as? Bool) == true
            expect(event.properties["$feature/disabled-flag"] as? Bool) == false

            sut.reset()
            sut.close()
        }

        it("sanitize properties") {
            let sut = self.getSut(flushAt: 1)

            sut.register(["boolIsOk": true,
                          "test5": UserDefaults.standard])

            sut.capture("test event",
                        properties: ["foo": "bar",
                                     "test1": UserDefaults.standard,
                                     "arrayIsOk": [1, 2, 3],
                                     "dictIsOk": ["1": "one"]],
                        userProperties: ["userProp": "value",
                                         "test2": UserDefaults.standard],
                        userPropertiesSetOnce: ["userPropOnce": "value",
                                                "test3": UserDefaults.standard],
                        groupProperties: ["groupProp": "value",
                                          "test4": UserDefaults.standard])

            let events = getBatchedEvents(server)

            expect(events.count) == 1
            let event = events.first!

            expect(event.properties["test1"]) == nil
            expect(event.properties["test2"]) == nil
            expect(event.properties["test3"]) == nil
            expect(event.properties["test4"]) == nil
            expect(event.properties["test5"]) == nil
            expect(event.properties["arrayIsOk"]) != nil
            expect(event.properties["dictIsOk"]) != nil
            expect(event.properties["boolIsOk"]) != nil

            sut.reset()
            sut.close()
        }
    }
}
