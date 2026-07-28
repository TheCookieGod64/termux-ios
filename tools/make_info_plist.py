#!/usr/bin/env python3
"""Generates the app bundle's Info.plist."""

import argparse
import plistlib


def build(bundle_id: str, name: str, version: str, min_ios: str) -> dict:
    return {
        "CFBundleDevelopmentRegion": "en",
        "CFBundleDisplayName": name,
        "CFBundleExecutable": name,
        "CFBundleIdentifier": bundle_id,
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": name,
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": version,
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
        "MinimumOSVersion": min_ios,
        "UIDeviceFamily": [1, 2],
        "DTPlatformName": "iphoneos",
        "LSRequiresIPhoneOS": True,
        "UILaunchScreen": {
            "UIColorName": "",
            "UIImageName": "",
        },
        "UIRequiredDeviceCapabilities": ["arm64"],
        "UISupportedInterfaceOrientations": [
            "UIInterfaceOrientationPortrait",
            "UIInterfaceOrientationPortraitUpsideDown",
            "UIInterfaceOrientationLandscapeLeft",
            "UIInterfaceOrientationLandscapeRight",
        ],
        "UIStatusBarStyle": "UIStatusBarStyleLightContent",
        "UIViewControllerBasedStatusBarAppearance": True,
        "UIApplicationSupportsIndirectInputEvents": True,
        # Keep the terminal alive while a build runs in the background.
        "UIBackgroundModes": ["audio", "fetch", "processing"],
        # Let the Files app reach ~/ so users can move scripts in and out.
        "UIFileSharingEnabled": True,
        "LSSupportsOpeningDocumentsInPlace": True,
        "UISupportsDocumentBrowser": False,
        "NSHumanReadableCopyright": "Termux for iOS",
        # Hardware keyboard shortcut support.
        "UIApplicationSceneManifest": {
            "UIApplicationSupportsMultipleScenes": False,
        },
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bundle-id", required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--min-ios", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    plist = build(args.bundle_id, args.name, args.version, args.min_ios)
    with open(args.output, "wb") as fh:
        plistlib.dump(plist, fh, fmt=plistlib.FMT_XML)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
