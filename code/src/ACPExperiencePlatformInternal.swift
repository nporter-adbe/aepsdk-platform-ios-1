//
// ADOBE CONFIDENTIAL
//
// Copyright 2020 Adobe
// All Rights Reserved.
//
// NOTICE: All information contained herein is, and remains
// the property of Adobe and its suppliers, if any. The intellectual
// and technical concepts contained herein are proprietary to Adobe
// and its suppliers and are protected by all applicable intellectual
// property laws, including trade secret and copyright laws.
// Dissemination of this information or reproduction of this material
// is strictly forbidden unless prior written permission is obtained
// from Adobe.
//


import Foundation
import ACPCore

class ACPExperiencePlatformInternal : ACPExtension {
    // Tag for logging
    private let TAG = "ACPExperiencePlatformInternal"
    
    // Event queue
    private var eventQueue = [ACPExtensionEvent]()
    
    override init() {
        super.init()
        
        ACPCore.log(ACPMobileLogLevel.debug, tag: TAG, message: "init")
        do {
            try api.registerListener(ExperiencePlatformExtensionListener.self,
                                     eventType: ACPExperiencePlatformConstants.eventTypeAdobeHub,
                                     eventSource: ACPExperiencePlatformConstants.eventSourceAdobeSharedState)
        } catch {
            ACPCore.log(ACPMobileLogLevel.error, tag: TAG, message: "There was an error registering Extension Listener for shared state events: \(error)")
        }
        
        do {
            try api.registerListener(ExperiencePlatformExtensionListener.self,
                                     eventType: ACPExperiencePlatformConstants.eventTypeExperiencePlatform,
                                     eventSource: ACPExperiencePlatformConstants.eventSourceExtensionRequestContent)
        } catch {
            ACPCore.log(ACPMobileLogLevel.error, tag: TAG, message: "There was an error registering Extension Listener for extension request content events: \(error)")

        }
        
    }
    
    override func name() -> String? {
        "com.adobe.ExperiencePlatform"
    }
    
    override func version() -> String? {
        "1.0.0-alpha-2"
    }
    
    override func onUnregister() {
        super.onUnregister()
        
        // if the shared states are not used in the next registration they can be cleared in this method
        try? api.clearSharedEventStates()
    }
    
    override func unexpectedError(_ error: Error) {
        super.unexpectedError(error)
        
        ACPCore.log(ACPMobileLogLevel.warning, tag: TAG, message: "Oh snap! An unexpected error occured: \(error.localizedDescription)")
    }
    
    /**
     Adds an event to the event queue and starts processing the queue.  Events with no event data are ignored.
     - Parameter event: The event to add to the event queue for processing
     */
    func processAddEvent(_ event: ACPExtensionEvent) {
        
        if event.eventData == nil {
            ACPCore.log(ACPMobileLogLevel.debug, tag: TAG, message: "Event with id \(event.eventUniqueIdentifier) contained no data, ignoring.")
            return;
        }
        
        // TODO add to task executor
        self.eventQueue.append(event)
        ACPCore.log(ACPMobileLogLevel.verbose, tag: TAG, message: "Event with id \(event.eventUniqueIdentifier) added to queue.")
        
        // kick event queue
        self.processEventQueue()
        
    }
    
    /**
     Processes the events in the event queue in the order they were received.
     
     A valid Configuration shared state is required for processing events and if one is not available, processing the queue is halted without removing events from
     the queue. If a valid Configuration shared state is available but no `experiencePlatform.configId ` is found, the event is dropped.
     */
    func processEventQueue() {
        if (eventQueue.isEmpty) {
            return;
        }
        
        // TODO add to task executor
        while !eventQueue.isEmpty {
        
            // get next event to process
            guard let event = eventQueue.last else {
                // unexpected to have nil events
                _ = eventQueue.dropLast()
                continue
            }
            
            let configSharedState: [AnyHashable:Any]?
            do {
                configSharedState = try api.getSharedEventState(ACPExperiencePlatformConstants.SharedState.configuration, event: event)
            } catch {
                ACPCore.log(ACPMobileLogLevel.warning, tag: TAG, message: "Failed to retrieve config shared state: \(error)")
                return
            }
            
            if (configSharedState == nil) {
                ACPCore.log(ACPMobileLogLevel.debug, tag: TAG, message: "Could not process queued events, configuration shared state is pending.")
                return
            }
            
            let configId: String? = configSharedState![ACPExperiencePlatformConstants.SharedState.Configuration.experiencePlatformConfigId] as? String
            if (configId ?? "").isEmpty {
                ACPCore.log(ACPMobileLogLevel.warning, tag: TAG, message: "Removed event '\(event.eventUniqueIdentifier)' because of invalid experiencePlatform.configId in configuration.")
                _ = eventQueue.dropLast()
                return
            }
            
            // TODO Request Builder
        }
        
        ACPCore.log(ACPMobileLogLevel.debug, tag: TAG, message: "Finished processing and sending events to Platform.")

        
        
    }
}
