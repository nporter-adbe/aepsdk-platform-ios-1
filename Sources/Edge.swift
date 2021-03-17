//
// Copyright 2020 Adobe. All rights reserved.
// This file is licensed to you under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License. You may obtain a copy
// of the License at http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
// OF ANY KIND, either express or implied. See the License for the specific language
// governing permissions and limitations under the License.
//

import AEPCore
import AEPServices
import Foundation

@objc(AEPMobileEdge)
public class Edge: NSObject, Extension {
    private let LOG_TAG = "Edge" // Tag for logging
    private var networkService: EdgeNetworkService = EdgeNetworkService()
    private var networkResponseHandler: NetworkResponseHandler?
    private var hitQueue: HitQueuing?
    private var currentPrivacyStatus: PrivacyStatus?

    // MARK: - Extension
    public let name = EdgeConstants.EXTENSION_NAME
    public let friendlyName = EdgeConstants.FRIENDLY_NAME
    public static let extensionVersion = EdgeConstants.EXTENSION_VERSION
    public let metadata: [String: String]? = nil
    public let runtime: ExtensionRuntime

    public required init(runtime: ExtensionRuntime) {
        self.runtime = runtime
        super.init()

        // set default on init for register/unregister use-case
        currentPrivacyStatus = EdgeConstants.DEFAULT_PRIVACY_STATUS
        networkResponseHandler = NetworkResponseHandler(getPrivacyStatus: getPrivacyStatus)
        setupHitQueue()
    }

    public func onRegistered() {
        registerListener(type: EventType.edge,
                         source: EventSource.requestContent,
                         listener: handleExperienceEventRequest)
        registerListener(type: EventType.configuration,
                         source: EventSource.responseContent,
                         listener: handleConfigurationResponse)
    }

    public func onUnregistered() {
        hitQueue?.close()
        print("Extension unregistered from MobileCore: \(EdgeConstants.FRIENDLY_NAME)")
    }

    public func readyForEvent(_ event: Event) -> Bool {
        if event.type == EventType.edge, event.source == EventSource.requestContent {
            let configurationSharedState = getSharedState(extensionName: EdgeConstants.SharedState.Configuration.STATE_OWNER_NAME,
                                                          event: event)
            let identitySharedState = getSharedState(extensionName: EdgeConstants.SharedState.Identity.STATE_OWNER_NAME,
                                                     event: event)

            return configurationSharedState?.status == .set && identitySharedState?.status == .set
        }

        return true
    }

    /// Handler for Experience Edge Request Content events.
    /// Valid Configuration and Identity shared states are required for processing the event (see `readyForEvent`). If a valid Configuration shared state is
    /// available, but no `edge.configId ` is found or `shouldIgnore` returns true, the event is dropped.
    ///
    /// - Parameter event: an event containing ExperienceEvent data for processing
    func handleExperienceEventRequest(_ event: Event) {
        guard !shouldIgnore(event: event) else { return }

        if event.data == nil {
            Log.trace(label: LOG_TAG, "Event with id \(event.id.uuidString) contained no data, ignoring.")
            return
        }

        Log.trace(label: LOG_TAG, "handleExperienceEventRequest - Queuing event with id \(event.id.uuidString).")

        // fetch config shared state, this should be resolved based on readyForEvent check
        guard let configId = getEdgeConfigId(event: event) else {
            Log.debug(label: LOG_TAG, "Unable to read Edge config id - Dropping event with id \(event.id.uuidString)")
            return // drop current event
        }

        // get ECID from Identity shared state
        guard let identityState =
                getSharedState(extensionName: EdgeConstants.SharedState.Identity.STATE_OWNER_NAME,
                               event: event)?.value else {
            Log.warning(label: LOG_TAG,
                        "handleExperienceEventRequest - Unable to process the event '\(event.id.uuidString)', " +
                            "Identity shared state is nil.")
            return // drop current event
        }

        // Build Request object
        let requestBuilder = RequestBuilder()
        requestBuilder.enableResponseStreaming(recordSeparator: EdgeConstants.Defaults.RECORD_SEPARATOR,
                                               lineFeed: EdgeConstants.Defaults.LINE_FEED)

        if let ecid = identityState[EdgeConstants.SharedState.Identity.ECID] as? String {
            requestBuilder.experienceCloudId = ecid
        } else {
            // This is not expected to happen. Continue without ECID
            Log.warning(label: LOG_TAG, "handleExperienceEventRequest - An unexpected error has occurred, ECID is nil.")
        }

        // Build and send the network request to Experience Edge
        let listOfEvents: [Event] = [event]
        guard let requestPayload = requestBuilder.getRequestPayload(listOfEvents) else {
            Log.debug(label: LOG_TAG,
                      "handleExperienceEventRequest - Failed to build the request payload, dropping current event '\(event.id.uuidString)'.")
            return
        }

        // get Assurance integration id and include it in to the requestHeaders
        var requestHeaders: [String: String] = [:]
        if let assuranceSharedState = getSharedState(extensionName: EdgeConstants.SharedState.Assurance.STATE_OWNER_NAME, event: event)?.value {
            if let assuranceIntegrationId = assuranceSharedState[EdgeConstants.SharedState.Assurance.INTEGRATION_ID] as? String {
                requestHeaders[EdgeConstants.NetworkKeys.HEADER_KEY_AEP_VALIDATION_TOKEN] = assuranceIntegrationId
            }
        }

        let edgeHit = EdgeHit(configId: configId,
                              requestId: UUID().uuidString,
                              request: requestPayload,
                              listOfEvents: listOfEvents,
                              headers: requestHeaders)
        guard let hitData = try? JSONEncoder().encode(edgeHit) else {
            Log.debug(label: LOG_TAG, "Failed to encode Edge hit, dropping current event '\(event.id.uuidString)'.")
            return
        }

        let entity = DataEntity(uniqueIdentifier: event.id.uuidString, timestamp: event.timestamp, data: hitData)
        hitQueue?.queue(entity: entity)
    }

    /// Handles the configuration response event and the privacy status change
    /// - Parameter event: the configuration response event
    func handleConfigurationResponse(_ event: Event) {
        if let privacyStatusStr = event.data?[EdgeConstants.EventDataKeys.GLOBAL_PRIVACY] as? String {
            let privacyStatus = PrivacyStatus(rawValue: privacyStatusStr) ?? EdgeConstants.DEFAULT_PRIVACY_STATUS
            currentPrivacyStatus = privacyStatus
            hitQueue?.handlePrivacyChange(status: privacyStatus)
            if privacyStatus == .optedOut {
                let storeResponsePayloadManager = StoreResponsePayloadManager(EdgeConstants.DataStoreKeys.STORE_NAME)
                storeResponsePayloadManager.deleteAllStorePayloads()
                Log.debug(label: LOG_TAG, "Device has opted-out of tracking. Clearing the Edge queue.")
            }
        }
    }

    /// Current privacy status set based on configuration update events
    /// - Returns: the current `PrivacyStatus` known by the Edge extension
    func getPrivacyStatus() -> PrivacyStatus {
        return currentPrivacyStatus ?? EdgeConstants.DEFAULT_PRIVACY_STATUS
    }

    /// Determines if the event should be ignored by the Edge extension. This method should be called after
    /// `readyForEvent` passed and a Configuration shared state is set.
    ///
    /// - Parameter event: the event to validate
    /// - Returns: true when Configuration shared state is nil or the new privacy status is opted out
    private func shouldIgnore(event: Event) -> Bool {
        guard let configSharedState = getSharedState(extensionName: EdgeConstants.SharedState.Configuration.STATE_OWNER_NAME,
                                                     event: event)?.value else {
            Log.debug(label: LOG_TAG, "Configuration is unavailable - unable to process event '\(event.id)'.")
            return true
        }

        let privacyStatusStr = configSharedState[EdgeConstants.EventDataKeys.GLOBAL_PRIVACY] as? String ?? ""
        let privacyStatus = PrivacyStatus(rawValue: privacyStatusStr) ?? EdgeConstants.DEFAULT_PRIVACY_STATUS
        return privacyStatus == .optedOut
    }

    /// Sets up the `PersistentHitQueue` to handle `EdgeHit`s
    private func setupHitQueue() {
        guard let dataQueue = ServiceProvider.shared.dataQueueService.getDataQueue(label: name) else {
            Log.error(label: "\(name):\(#function)", "Failed to create Data Queue, Edge could not be initialized")
            return
        }

        guard let networkResponseHandler = networkResponseHandler else {
            Log.warning(label: LOG_TAG, "Failed to create Data Queue, the NetworkResponseHandler is not initialized")
            return
        }

        let hitProcessor = EdgeHitProcessor(networkService: networkService,
                                            networkResponseHandler: networkResponseHandler)
        hitQueue = PersistentHitQueue(dataQueue: dataQueue, processor: hitProcessor)
        hitQueue?.handlePrivacyChange(status: EdgeConstants.DEFAULT_PRIVACY_STATUS)
    }

    /// Extracts the Edge Configuration identifier from the Configuration Shared State
    /// - Parameter event: current event for which the configuration is required
    /// - Returns: the Edge Configuration Id if found, nil otherwise
    private func getEdgeConfigId(event: Event) -> String? {
        guard let configSharedState =
                getSharedState(extensionName: EdgeConstants.SharedState.Configuration.STATE_OWNER_NAME,
                               event: event)?.value else {
            Log.warning(label: LOG_TAG,
                        "getEdgeConfigId - Unable to process the event '\(event.id.uuidString)', Configuration shared state is nil.")
            return nil
        }

        guard let configId =
                configSharedState[EdgeConstants.SharedState.Configuration.CONFIG_ID] as? String,
              !configId.isEmpty else {
            Log.warning(label: LOG_TAG,
                        "getEdgeConfigId - Unable to process the event '\(event.id.uuidString)' " +
                            "because of invalid edge.configId in configuration.")
            return nil
        }

        return configId
    }
}
