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
import Foundation

/// Protocol used for defining hits to Experience Edge service
protocol EdgeHit: Codable {
    /// The Edge configuration identifier
    var configId: String { get }

    /// Unique identifier for this hit
    var requestId: String { get }

    /// Request headers for this hit
    var headers: [String: String] { get }

    /// Returns the list of `Event`s for this hit
    var listOfEvents: [Event]? { get }

    /// The `ExperienceEdgeRequestType` to be used for this `EdgeHit`
    func getType() -> ExperienceEdgeRequestType

    /// The network request payload for this `EdgeHit`
    func getPayload() -> String?

    /// Retrieves the `Streaming` settings for this `EdgeHit` or nil if not enabled
    func getStreamingSettings() -> Streaming?
}
