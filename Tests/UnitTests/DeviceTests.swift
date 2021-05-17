//
// Copyright 2021 Adobe. All rights reserved.
// This file is licensed to you under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License. You may obtain a copy
// of the License at http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
// OF ANY KIND, either express or implied. See the License for the specific language
// governing permissions and limitations under the License.
//

@testable import AEPEdge
import AEPServices
import XCTest

class DeviceTests: XCTestCase {

    private func buildAndSetMockInfoService() {
        let mockSystemInfoService = MockSystemInfoService()
        mockSystemInfoService.deviceName = "test-device-name"
        mockSystemInfoService.displayInformation = (100, 200)
        mockSystemInfoService.orientation = .PORTRAIT
        mockSystemInfoService.deviceType = .PHONE
        ServiceProvider.shared.systemInfoService = mockSystemInfoService
    }

    func testFromDirectData() {
        // setup
        buildAndSetMockInfoService()

        // test
        let device = Device.fromDirect(data: [:]) as? Device

        // verify
        XCTAssertEqual("apple", device?.manufacturer)
        XCTAssertEqual("test-device-name", device?.model)
        XCTAssertEqual(100, device?.screenWidth)
        XCTAssertEqual(200, device?.screenHeight)
        XCTAssertEqual(ScreenOrientation.portrait, device?.screenOrientation)
        XCTAssertEqual(DeviceType.mobile, device?.type)
    }

    // MARK: Encodable Tests
    
    func testEncodeEnvironment() throws {
        // setup
        buildAndSetMockInfoService()
        let device = Device.fromDirect(data: [:]) as? Device

        // test
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try XCTUnwrap(encoder.encode(device))
        let dataStr = try XCTUnwrap(String(data: data, encoding: .utf8))

        // verify
        let expected = """
        {
          "manufacturer" : "apple",
          "model" : "test-device-name",
          "screenHeight" : 200,
          "screenWidth" : 100,
          "screenOrientation" : "portrait",
          "type" : "mobile"
        }
        """

        XCTAssertEqual(expected, dataStr)
    }
}
