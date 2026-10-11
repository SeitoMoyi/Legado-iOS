#!/usr/bin/env python3
import os
import hashlib
import glob
import plistlib

def gen_uuid(name: str) -> str:
    return hashlib.md5(name.encode("utf-8")).hexdigest()[:24].upper()

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)

    core_files = sorted(glob.glob("Sources/LegadoCore/**/*.swift", recursive=True))
    app_files = sorted(glob.glob("Sources/LegadoApp/**/*.swift", recursive=True))
    all_swift_files = core_files + app_files
    res_files = sorted(glob.glob("Sources/LegadoApp/Resources/**/*.*", recursive=True))

    proj_dir = os.path.join(script_dir, "Legado.xcodeproj")
    os.makedirs(proj_dir, exist_ok=True)
    pbx_path = os.path.join(proj_dir, "project.pbxproj")

    # UUIDs
    proj_uuid = gen_uuid("Project_Legado")
    target_uuid = gen_uuid("Target_LegadoApp")
    main_group_uuid = gen_uuid("Group_Main")
    sources_group_uuid = gen_uuid("Group_Sources")
    products_group_uuid = gen_uuid("Group_Products")
    app_product_uuid = gen_uuid("Product_LegadoApp_app")

    sources_build_phase_uuid = gen_uuid("Phase_Sources")
    frameworks_build_phase_uuid = gen_uuid("Phase_Frameworks")
    resources_build_phase_uuid = gen_uuid("Phase_Resources")

    proj_config_list_uuid = gen_uuid("ConfigList_Project")
    target_config_list_uuid = gen_uuid("ConfigList_Target")
    proj_debug_cfg_uuid = gen_uuid("Cfg_Proj_Debug")
    proj_release_cfg_uuid = gen_uuid("Cfg_Proj_Release")
    target_debug_cfg_uuid = gen_uuid("Cfg_Target_Debug")
    target_release_cfg_uuid = gen_uuid("Cfg_Target_Release")

    swiftsoup_pkg_uuid = gen_uuid("Pkg_SwiftSoup")
    swiftsoup_prod_uuid = gen_uuid("Prod_SwiftSoup")
    swiftsoup_build_file_uuid = gen_uuid("BuildFile_SwiftSoup")

    zip_pkg_uuid = gen_uuid("Pkg_ZIPFoundation")
    zip_prod_uuid = gen_uuid("Prod_ZIPFoundation")
    zip_build_file_uuid = gen_uuid("BuildFile_ZIPFoundation")

    objects = {}

    # SwiftSoup Package
    objects[swiftsoup_pkg_uuid] = {
        "isa": "XCRemoteSwiftPackageReference",
        "repositoryURL": "https://github.com/scinfu/SwiftSoup.git",
        "requirement": {
            "kind": "upToNextMajorVersion",
            "minimumVersion": "2.6.0"
        }
    }
    objects[swiftsoup_prod_uuid] = {
        "isa": "XCSwiftPackageProductDependency",
        "package": swiftsoup_pkg_uuid,
        "productName": "SwiftSoup"
    }
    objects[swiftsoup_build_file_uuid] = {
        "isa": "PBXBuildFile",
        "productRef": swiftsoup_prod_uuid
    }

    # ZIPFoundation Package
    objects[zip_pkg_uuid] = {
        "isa": "XCRemoteSwiftPackageReference",
        "repositoryURL": "https://github.com/weichsel/ZIPFoundation.git",
        "requirement": {
            "kind": "upToNextMajorVersion",
            "minimumVersion": "0.9.16"
        }
    }
    objects[zip_prod_uuid] = {
        "isa": "XCSwiftPackageProductDependency",
        "package": zip_pkg_uuid,
        "productName": "ZIPFoundation"
    }
    objects[zip_build_file_uuid] = {
        "isa": "PBXBuildFile",
        "productRef": zip_prod_uuid
    }

    # Swift files
    file_ref_uuids = []
    build_file_uuids = []
    for f in all_swift_files:
        f_uuid = gen_uuid(f"FileRef_{f}")
        bf_uuid = gen_uuid(f"BuildFile_{f}")
        file_ref_uuids.append(f_uuid)
        build_file_uuids.append(bf_uuid)

        objects[f_uuid] = {
            "isa": "PBXFileReference",
            "lastKnownFileType": "sourcecode.swift",
            "path": f,
            "sourceTree": "<group>"
        }
        objects[bf_uuid] = {
            "isa": "PBXBuildFile",
            "fileRef": f_uuid
        }

    # Resource files
    res_file_ref_uuids = []
    res_build_file_uuids = []
    for f in res_files:
        f_uuid = gen_uuid(f"FileRef_{f}")
        bf_uuid = gen_uuid(f"BuildFile_{f}")
        res_file_ref_uuids.append(f_uuid)
        res_build_file_uuids.append(bf_uuid)

        objects[f_uuid] = {
            "isa": "PBXFileReference",
            "lastKnownFileType": "text.json" if f.endswith(".json") else "file",
            "path": f,
            "sourceTree": "<group>"
        }
        objects[bf_uuid] = {
            "isa": "PBXBuildFile",
            "fileRef": f_uuid
        }

    # Product
    objects[app_product_uuid] = {
        "isa": "PBXFileReference",
        "explicitFileType": "wrapper.application",
        "includeInIndex": "0",
        "path": "LegadoApp.app",
        "sourceTree": "BUILT_PRODUCTS_DIR"
    }

    # Build phases
    objects[sources_build_phase_uuid] = {
        "isa": "PBXSourcesBuildPhase",
        "buildActionMask": "2147483647",
        "files": build_file_uuids,
        "runOnlyForDeploymentPostprocessing": "0"
    }
    objects[frameworks_build_phase_uuid] = {
        "isa": "PBXFrameworksBuildPhase",
        "buildActionMask": "2147483647",
        "files": [swiftsoup_build_file_uuid, zip_build_file_uuid],
        "runOnlyForDeploymentPostprocessing": "0"
    }
    objects[resources_build_phase_uuid] = {
        "isa": "PBXResourcesBuildPhase",
        "buildActionMask": "2147483647",
        "files": res_build_file_uuids,
        "runOnlyForDeploymentPostprocessing": "0"
    }

    # Groups
    objects[sources_group_uuid] = {
        "isa": "PBXGroup",
        "children": file_ref_uuids + res_file_ref_uuids,
        "name": "Sources",
        "sourceTree": "<group>"
    }
    objects[products_group_uuid] = {
        "isa": "PBXGroup",
        "children": [app_product_uuid],
        "name": "Products",
        "sourceTree": "<group>"
    }
    objects[main_group_uuid] = {
        "isa": "PBXGroup",
        "children": [sources_group_uuid, products_group_uuid],
        "sourceTree": "<group>"
    }

    # Target
    objects[target_uuid] = {
        "isa": "PBXNativeTarget",
        "buildConfigurationList": target_config_list_uuid,
        "buildPhases": [
            sources_build_phase_uuid,
            frameworks_build_phase_uuid,
            resources_build_phase_uuid
        ],
        "buildRules": [],
        "dependencies": [],
        "name": "LegadoApp",
        "packageProductDependencies": [
            swiftsoup_prod_uuid,
            zip_prod_uuid
        ],
        "productName": "LegadoApp",
        "productReference": app_product_uuid,
        "productType": "com.apple.product-type.application"
    }

    # Project
    objects[proj_uuid] = {
        "isa": "PBXProject",
        "attributes": {
            "BuildIndependentTargetsInParallel": "1",
            "LastUpgradeCheck": "1420"
        },
        "buildConfigurationList": proj_config_list_uuid,
        "compatibilityVersion": "Xcode 14.0",
        "developmentRegion": "en",
        "hasScannedForEncodings": "0",
        "knownRegions": ["en", "Base"],
        "mainGroup": main_group_uuid,
        "packageReferences": [
            swiftsoup_pkg_uuid,
            zip_pkg_uuid
        ],
        "productRefGroup": products_group_uuid,
        "projectDirPath": "",
        "projectRoot": "",
        "targets": [target_uuid]
    }

    # Configurations
    objects[proj_debug_cfg_uuid] = {
        "isa": "XCBuildConfiguration",
        "name": "Debug",
        "buildSettings": {
            "ALWAYS_SEARCH_USER_PATHS": "NO",
            "CLANG_ENABLE_MODULES": "YES",
            "ENABLE_TESTABILITY": "YES",
            "GCC_DYNAMIC_NO_PIC": "NO",
            "GCC_OPTIMIZATION_LEVEL": "0",
            "IPHONEOS_DEPLOYMENT_TARGET": "15.0",
            "ONLY_ACTIVE_ARCH": "YES",
            "SDKROOT": "iphoneos",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
            "SWIFT_VERSION": "5.0"
        }
    }
    objects[proj_release_cfg_uuid] = {
        "isa": "XCBuildConfiguration",
        "name": "Release",
        "buildSettings": {
            "ALWAYS_SEARCH_USER_PATHS": "NO",
            "CLANG_ENABLE_MODULES": "YES",
            "IPHONEOS_DEPLOYMENT_TARGET": "15.0",
            "SDKROOT": "iphoneos",
            "SWIFT_COMPILATION_MODE": "wholemodule",
            "SWIFT_OPTIMIZATION_LEVEL": "-O",
            "SWIFT_VERSION": "5.0"
        }
    }
    objects[proj_config_list_uuid] = {
        "isa": "XCConfigurationList",
        "buildConfigurations": [proj_debug_cfg_uuid, proj_release_cfg_uuid],
        "defaultConfigurationIsVisible": "0",
        "defaultConfigurationName": "Release"
    }

    target_settings = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": "",
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_FILE": "Sources/LegadoApp/Info.plist",
        "INFOPLIST_KEY_CFBundleDisplayName": "Legado",
        "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
        "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
        "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
        "MARKETING_VERSION": "0.1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "io.legado.ios",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": "1,2"
    }

    objects[target_debug_cfg_uuid] = {
        "isa": "XCBuildConfiguration",
        "name": "Debug",
        "buildSettings": target_settings
    }
    objects[target_release_cfg_uuid] = {
        "isa": "XCBuildConfiguration",
        "name": "Release",
        "buildSettings": target_settings
    }
    objects[target_config_list_uuid] = {
        "isa": "XCConfigurationList",
        "buildConfigurations": [target_debug_cfg_uuid, target_release_cfg_uuid],
        "defaultConfigurationIsVisible": "0",
        "defaultConfigurationName": "Release"
    }

    root = {
        "archiveVersion": "1",
        "classes": {},
        "objectVersion": "54",
        "objects": objects,
        "rootObject": proj_uuid
    }

    with open(pbx_path, "wb") as f:
        plistlib.dump(root, f, fmt=plistlib.FMT_XML)

    # Generate shared scheme for LegadoApp
    schemes_dir = os.path.join(proj_dir, "xcshareddata", "xcschemes")
    os.makedirs(schemes_dir, exist_ok=True)
    scheme_path = os.path.join(schemes_dir, "LegadoApp.xcscheme")
    scheme_content = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1420"
   version = "1.3">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_uuid}"
               BuildableName = "LegadoApp.app"
               BlueprintName = "LegadoApp"
               ReferencedContainer = "container:Legado.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useRelativeToCommandLine = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_uuid}"
            BuildableName = "LegadoApp.app"
            BlueprintName = "LegadoApp"
            ReferencedContainer = "container:Legado.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
</Scheme>
"""
    with open(scheme_path, "w", encoding="utf-8") as f:
        f.write(scheme_content)

    print(f"Successfully generated XML {pbx_path} and scheme {scheme_path}")

if __name__ == "__main__":
    main()
