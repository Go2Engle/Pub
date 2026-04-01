import XCTest
@testable import Pub

final class HomebrewCatalogDecoderTests: XCTestCase {
    func testDecodeInstalledPackagesMarksOutdatedFormulaeAndCasks() throws {
        let infoJSON = """
        {
          "formulae": [
            {
              "name": "wget",
              "desc": "Internet file retriever",
              "homepage": "https://www.gnu.org/software/wget/",
              "aliases": [],
              "installed": [
                {
                  "version": "1.24.5",
                  "installed_on_request": true
                }
              ],
              "linked_keg": "1.24.5",
              "pinned": false,
              "outdated": true,
              "versions": {
                "stable": "1.25.0"
              },
              "tap": "homebrew/core",
              "dependencies": ["pcre2"],
              "caveats": null
            }
          ],
          "casks": [
            {
              "token": "ghostty",
              "name": ["Ghostty"],
              "desc": "Terminal emulator",
              "homepage": "https://ghostty.org/",
              "version": "1.3.1",
              "installed": "1.3.0",
              "outdated": false,
              "tap": "homebrew/cask",
              "caveats": null
            }
          ]
        }
        """

        let outdatedJSON = """
        {
          "formulae": [
            {
              "name": "wget",
              "current_version": "1.25.0"
            }
          ],
          "casks": []
        }
        """

        let packages = try HomebrewCatalogDecoder.decodeInstalledPackages(
            infoData: Data(infoJSON.utf8),
            outdatedData: Data(outdatedJSON.utf8)
        )

        XCTAssertEqual(packages.count, 2)
        XCTAssertEqual(packages.first?.name, "wget")
        XCTAssertEqual(packages.first?.latestVersion, "1.25.0")
        XCTAssertTrue(packages.first?.outdated == true)
        XCTAssertEqual(packages.last?.name, "ghostty")
        XCTAssertEqual(packages.last?.installedVersion, "1.3.0")
    }

    func testSearchTokenParsingDropsHeadingsAndDuplicates() {
        let output = """
        ==> Formulae
        git
        gh

        ==> Casks
        git
        ghostty
        """

        XCTAssertEqual(HomebrewCatalogDecoder.searchTokens(from: output), ["git", "gh", "ghostty"])
    }
}
