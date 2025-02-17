//
//  NALI_Migraine_Log_macOSUITestsLaunchTests.swift
//  NALI Migraine Log macOSUITests
//
//  Created by Vincent S. DeOrchis on 2/8/25.
//

import XCTest

final class NALI_Migraine_Log_macOSUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
