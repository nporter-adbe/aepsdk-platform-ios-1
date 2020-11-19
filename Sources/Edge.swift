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
    private var networkResponseHandler: NetworkResponseHandler = NetworkResponseHandler()
    private var hitQueue: HitQueuing?

    // MARK: - Extension
    public var name = Constants.EXTENSION_NAME
    public var friendlyName = Constants.FRIENDLY_NAME
    public static var extensionVersion = Constants.EXTENSION_VERSION
    public var metadata: [String: String]?
    public var runtime: ExtensionRuntime

    public required init(runtime: ExtensionRuntime) {
        self.runtime = runtime
        super.init()
        setupHitQueue()
    }

    public func onRegistered() {
        registerListener(type: Constants.EventType.EDGE,
                         source: EventSource.requestContent,
                         listener: handleExperienceEventRequest)
    }

    public func onUnregistered() {
        hitQueue?.close()
        print("Extension unregistered from MobileCore: \(Constants.FRIENDLY_NAME)")
    }

    public func readyForEvent(_ event: Event) -> Bool {
        if event.type == Constants.EventType.EDGE, event.source == EventSource.requestContent {
            let configurationSharedState = getSharedState(extensionName: Constants.SharedState.Configuration.STATE_OWNER_NAME,
                                                          event: event)
            let identitySharedState = getSharedState(extensionName: Constants.SharedState.Identity.STATE_OWNER_NAME,
                                                     event: event)
    
            return configurationSharedState?.status == .set && identitySharedState?.status == .set
        }

        return true
    }

    /// Handler for Experience Edge Request Content events.
    /// Valid Configuration and Identity shared states are required for processing the event (see `readyForEvent`). If a valid Configuration shared state is
    /// available, but no `edge.configId ` is found, the event is dropped.
    ///
    /// - Parameter event: an event containing ExperienceEvent data for processing
    func handleExperienceEventRequest(_ event: Event) {
        if event.data == nil {
            Log.trace(label: LOG_TAG, "Event with id \(event.id.uuidString) contained no data, ignoring.")
            return
        }

        Log.trace(label: LOG_TAG, "handleExperienceEventRequest - Queuing event with id \(event.id.uuidString).")

        guard let eventData = try? JSONEncoder().encode(event) else {
            Log.debug(label: LOG_TAG, "handleExperienceEventRequest - Failed to encode event with id: '\(event.id.uuidString)'.")
            return
        }

        let entity = DataEntity(uniqueIdentifier: event.id.uuidString, timestamp: event.timestamp, data: eventData)
        hitQueue?.queue(entity: entity)
    }

    /// Sets up the `PersistentHitQueue` to handle `EdgeHit`s
    private func setupHitQueue() {
        guard let dataQueue = ServiceProvider.shared.dataQueueService.getDataQueue(label: name) else {
            Log.error(label: "\(name):\(#function)", "Failed to create Data Queue, Edge could not be initialized")
            return
        }

        let hitProcessor = EdgeHitProcessor(networkService: networkService,
                                            networkResponseHandler: networkResponseHandler,
                                            getSharedState: getSharedState(extensionName:event:),
                                            readyForEvent: readyForEvent(_:))
        hitQueue = PersistentHitQueue(dataQueue: dataQueue, processor: hitProcessor)
        hitQueue?.beginProcessing()
    }
}
