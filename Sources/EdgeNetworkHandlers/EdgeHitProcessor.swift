/*
 Copyright 2020 Adobe. All rights reserved.
 This file is licensed to you under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0
 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.
 */

import AEPCore
import AEPServices
import Foundation

class EdgeHitProcessor: HitProcessing {
    private let LOG_TAG = "EdgeHitProcessor"

    let retryInterval = TimeInterval(30)
    let networkService: EdgeNetworkService
    let networkResponseHandler: NetworkResponseHandler

    /// Creates a new `EdgeHitProcessor` where the `responseHandler` will be invoked after each successful processing of a hit
    /// - Parameter responseHandler: a function to be invoked with the `DataEntity` for a hit and the response data for that hit
    init(networkService: EdgeNetworkService, networkResponseHandler: NetworkResponseHandler) {
        self.networkService = networkService
        self.networkResponseHandler = networkResponseHandler
    }

    // MARK: HitProcessing

    func processHit(entity: DataEntity, completion: @escaping (Bool) -> Void) {
        guard let data = entity.data, let edgeHit = try? JSONDecoder().decode(EdgeHit.self, from: data) else {
            // failed to convert data to hit, unrecoverable error, move to next hit
            completion(true)
            return
        }

        let callback: ResponseCallback = NetworkResponseCallback(requestId: entity.uniqueIdentifier, responseHandler: networkResponseHandler)
        networkService.doRequest(url: edgeHit.url,
                                 requestBody: edgeHit.request,
                                 requestHeaders: edgeHit.headers,
                                 responseCallback: EdgeHitProcessorCallback(completion: completion, responseCallback: callback),
                                 retryTimes: Constants.Defaults.NETWORK_REQUEST_MAX_RETRIES)
    }

}

/// Helper struct to convert `ResponseCallback` into a callback compatible with `HitProcessing`
private struct EdgeHitProcessorCallback: ResponseCallback {
    let completion: (Bool) -> Void
    let responseCallback: ResponseCallback
    
    func onResponse(jsonResponse: String) {
        responseCallback.onResponse(jsonResponse: jsonResponse)
        completion(true) // hit processed successfully, move on
        
    }
    
    func onError(jsonError: String) {
        responseCallback.onError(jsonError: jsonError)
        completion(false) // hit processed failed, retry
    }
    
    func onComplete() {
        responseCallback.onComplete()
    }
    
}
