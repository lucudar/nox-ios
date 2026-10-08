#!/usr/bin/env python3
"""Generates Nox.xcodeproj (Xcode 16, folder-synchronized groups) and the Config/ plists.

Targets:
  Nox        — the SwiftUI app (folders Nox/ and Shared/), embeds NoxTunnel.appex
  NoxTunnel  — Packet Tunnel extension (folders NoxTunnel/ and Shared/) linking
               Frameworks/Libbox.xcframework (sing-box, built by tools/build_libbox.sh)

Bundle IDs and the App Group come from one build setting, NOX_BUNDLE_ID:
  app       $(NOX_BUNDLE_ID)
  extension $(NOX_BUNDLE_ID).tunnel
  group     group.$(NOX_BUNDLE_ID)

Run from anywhere: python3 tools/gen_project.py
"""
import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJ = os.path.join(ROOT, "Nox.xcodeproj")
CONFIG = os.path.join(ROOT, "Config")

BUNDLE_ID = "com.example.nox"
MARKETING_VERSION = "0.7"


def oid(name):
    return hashlib.md5(("nox." + name).encode()).hexdigest()[:24].upper()


NAMES = [
    "product", "rootgroup", "frameworks", "maingroup", "products", "target", "sources", "resources",
    "project", "cfg_target", "cfg_project", "t_debug", "t_release", "p_debug", "p_release",
    # new in 0.6
    "ext_product", "ext_rootgroup", "shared_rootgroup", "ext_target", "ext_sources", "ext_frameworks",
    "ext_resources", "ext_cfg", "e_debug", "e_release", "embed_phase", "embed_file", "proxy", "dependency",
    "fw_group", "libbox_ref", "libbox_file", "config_group", "ref_app_plist", "ref_ext_plist",
    "ref_app_ent", "ref_ext_ent",
]
I = {k: oid(k) for k in NAMES}

COMMON = """				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				"EXCLUDED_ARCHS[sdk=iphonesimulator*]" = x86_64;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MTL_FAST_MATH = YES;
				NOX_APP_GROUP = "group.$(NOX_BUNDLE_ID)";
				NOX_BUNDLE_ID = %s;
				SDKROOT = iphoneos;
""" % BUNDLE_ID
P_DEBUG = COMMON + """				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
"""
P_RELEASE = COMMON + """				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				MTL_ENABLE_DEBUG_INFO = NO;
				SWIFT_COMPILATION_MODE = wholemodule;
				VALIDATE_PRODUCT = YES;
"""
CAMERA = "Камера нужна, чтобы сканировать QR-коды с конфигурациями серверов."
LOCALNET = "Nox проверяет задержку до серверов и показывает состояние подключения."
APP = f"""				ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "AppIconDark AppIconLight AppIconNeon";
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES;
				CODE_SIGN_ENTITLEMENTS = Config/Nox.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = "Config/Nox-Info.plist";
				INFOPLIST_KEY_CFBundleDisplayName = Nox;
				INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.utilities";
				INFOPLIST_KEY_NSCameraUsageDescription = "{CAMERA}";
				INFOPLIST_KEY_NSLocalNetworkUsageDescription = "{LOCALNET}";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UIStatusBarStyle = UIStatusBarStyleLightContent;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait;
				INFOPLIST_KEY_UIUserInterfaceStyle = Dark;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = {MARKETING_VERSION};
				PRODUCT_BUNDLE_IDENTIFIER = "$(NOX_BUNDLE_ID)";
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
				SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 1;
"""
EXT = f"""				CODE_SIGN_ENTITLEMENTS = Config/NoxTunnel.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = "Config/NoxTunnel-Info.plist";
				INFOPLIST_KEY_CFBundleDisplayName = "Nox Tunnel";
				INFOPLIST_KEY_NSHumanReadableCopyright = "";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = {MARKETING_VERSION};
				OTHER_LDFLAGS = (
					"$(inherited)",
					"-lresolv",
					"-framework",
					Security,
					"-framework",
					SystemConfiguration,
				);
				PRODUCT_BUNDLE_IDENTIFIER = "$(NOX_BUNDLE_ID).tunnel";
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
				SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 1;
"""


def cfg(id_, name, body):
    return f"""		{id_} /* {name} */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{body}			}};
			name = {name};
		}};
"""


def synced(key, path):
    return f"""		{I[key]} /* {path} */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = {path};
			sourceTree = "<group>";
		}};
"""


def phase(key, isa, name, files=""):
    return f"""		{I[key]} /* {name} */ = {{
			isa = {isa};
			buildActionMask = 2147483647;
			files = (
{files}			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
"""


def conflist(key, title, debug, release):
    return f"""		{I[key]} /* Build configuration list for {title} */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I[debug]} /* Debug */,
				{I[release]} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
"""


pbx = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXBuildFile section */
		{I['embed_file']} /* NoxTunnel.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {I['ext_product']} /* NoxTunnel.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};
		{I['libbox_file']} /* Libbox.xcframework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {I['libbox_ref']} /* Libbox.xcframework */; }};
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		{I['proxy']} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {I['project']} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {I['ext_target']};
			remoteInfo = NoxTunnel;
		}};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
		{I['embed_phase']} /* Embed Foundation Extensions */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				{I['embed_file']} /* NoxTunnel.appex in Embed Foundation Extensions */,
			);
			name = "Embed Foundation Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
		{I['product']} /* Nox.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Nox.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I['ext_product']} /* NoxTunnel.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = NoxTunnel.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I['libbox_ref']} /* Libbox.xcframework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.xcframework; path = Libbox.xcframework; sourceTree = "<group>"; }};
		{I['ref_app_plist']} /* Nox-Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "Nox-Info.plist"; sourceTree = "<group>"; }};
		{I['ref_ext_plist']} /* NoxTunnel-Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "NoxTunnel-Info.plist"; sourceTree = "<group>"; }};
		{I['ref_app_ent']} /* Nox.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Nox.entitlements; sourceTree = "<group>"; }};
		{I['ref_ext_ent']} /* NoxTunnel.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = NoxTunnel.entitlements; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
{synced('rootgroup', 'Nox')}{synced('shared_rootgroup', 'Shared')}{synced('ext_rootgroup', 'NoxTunnel')}/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
{phase('frameworks', 'PBXFrameworksBuildPhase', 'Frameworks')}{phase('ext_frameworks', 'PBXFrameworksBuildPhase', 'Frameworks', f"				{I['libbox_file']} /* Libbox.xcframework in Frameworks */," + chr(10))}/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{I['maingroup']} = {{
			isa = PBXGroup;
			children = (
				{I['rootgroup']} /* Nox */,
				{I['ext_rootgroup']} /* NoxTunnel */,
				{I['shared_rootgroup']} /* Shared */,
				{I['config_group']} /* Config */,
				{I['fw_group']} /* Frameworks */,
				{I['products']} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{I['config_group']} /* Config */ = {{
			isa = PBXGroup;
			children = (
				{I['ref_app_plist']} /* Nox-Info.plist */,
				{I['ref_app_ent']} /* Nox.entitlements */,
				{I['ref_ext_plist']} /* NoxTunnel-Info.plist */,
				{I['ref_ext_ent']} /* NoxTunnel.entitlements */,
			);
			path = Config;
			sourceTree = "<group>";
		}};
		{I['fw_group']} /* Frameworks */ = {{
			isa = PBXGroup;
			children = (
				{I['libbox_ref']} /* Libbox.xcframework */,
			);
			path = Frameworks;
			sourceTree = "<group>";
		}};
		{I['products']} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{I['product']} /* Nox.app */,
				{I['ext_product']} /* NoxTunnel.appex */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{I['target']} /* Nox */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['cfg_target']} /* Build configuration list for PBXNativeTarget "Nox" */;
			buildPhases = (
				{I['sources']} /* Sources */,
				{I['frameworks']} /* Frameworks */,
				{I['resources']} /* Resources */,
				{I['embed_phase']} /* Embed Foundation Extensions */,
			);
			buildRules = (
			);
			dependencies = (
				{I['dependency']} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				{I['rootgroup']} /* Nox */,
				{I['shared_rootgroup']} /* Shared */,
			);
			name = Nox;
			packageProductDependencies = (
			);
			productName = Nox;
			productReference = {I['product']} /* Nox.app */;
			productType = "com.apple.product-type.application";
		}};
		{I['ext_target']} /* NoxTunnel */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['ext_cfg']} /* Build configuration list for PBXNativeTarget "NoxTunnel" */;
			buildPhases = (
				{I['ext_sources']} /* Sources */,
				{I['ext_frameworks']} /* Frameworks */,
				{I['ext_resources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{I['ext_rootgroup']} /* NoxTunnel */,
				{I['shared_rootgroup']} /* Shared */,
			);
			name = NoxTunnel;
			packageProductDependencies = (
			);
			productName = NoxTunnel;
			productReference = {I['ext_product']} /* NoxTunnel.appex */;
			productType = "com.apple.product-type.app-extension";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{I['project']} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
				TargetAttributes = {{
					{I['target']} = {{
						CreatedOnToolsVersion = 16.0;
					}};
					{I['ext_target']} = {{
						CreatedOnToolsVersion = 16.0;
					}};
				}};
			}};
			buildConfigurationList = {I['cfg_project']} /* Build configuration list for PBXProject "Nox" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				ru,
				Base,
			);
			mainGroup = {I['maingroup']};
			minimizedProjectReferenceProxies = 1;
			preferredProjectObjectVersion = 77;
			productRefGroup = {I['products']} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{I['target']} /* Nox */,
				{I['ext_target']} /* NoxTunnel */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
{phase('resources', 'PBXResourcesBuildPhase', 'Resources')}{phase('ext_resources', 'PBXResourcesBuildPhase', 'Resources')}/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
{phase('sources', 'PBXSourcesBuildPhase', 'Sources')}{phase('ext_sources', 'PBXSourcesBuildPhase', 'Sources')}/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		{I['dependency']} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {I['ext_target']} /* NoxTunnel */;
			targetProxy = {I['proxy']} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
{cfg(I['p_debug'], 'Debug', P_DEBUG)}{cfg(I['p_release'], 'Release', P_RELEASE)}{cfg(I['t_debug'], 'Debug', APP)}{cfg(I['t_release'], 'Release', APP)}{cfg(I['e_debug'], 'Debug', EXT)}{cfg(I['e_release'], 'Release', EXT)}/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
{conflist('cfg_project', 'PBXProject "Nox"', 'p_debug', 'p_release')}{conflist('cfg_target', 'PBXNativeTarget "Nox"', 't_debug', 't_release')}{conflist('ext_cfg', 'PBXNativeTarget "NoxTunnel"', 'e_debug', 'e_release')}/* End XCConfigurationList section */
	}};
	rootObject = {I['project']} /* Project object */;
}}
"""


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


write(os.path.join(PROJ, "project.pbxproj"), pbx)
write(os.path.join(PROJ, "project.xcworkspace", "contents.xcworkspacedata"),
      '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n')
write(os.path.join(PROJ, "project.xcworkspace", "xcshareddata", "IDEWorkspaceChecks.plist"),
      '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
      '<plist version="1.0">\n<dict>\n\t<key>IDEDidComputeMac32BitWarning</key>\n\t<true/>\n</dict>\n</plist>\n')

ref = f"""<BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{I['target']}"
               BuildableName = "Nox.app"
               BlueprintName = "Nox"
               ReferencedContainer = "container:Nox.xcodeproj">
            </BuildableReference>"""
scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            {ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
write(os.path.join(PROJ, "xcshareddata", "xcschemes", "Nox.xcscheme"), scheme)

# ---------- Config: partial Info.plists (merged with the generated keys) and entitlements ----------
HEAD = ('<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
        '<plist version="1.0">\n<dict>\n')
TAIL = '</dict>\n</plist>\n'
GROUP = '\t<key>NoxAppGroup</key>\n\t<string>$(NOX_APP_GROUP)</string>\n'
write(os.path.join(CONFIG, "Nox-Info.plist"), HEAD + GROUP +
      '\t<key>NSAppTransportSecurity</key>\n\t<dict>\n'
      '\t\t<key>NSAllowsLocalNetworking</key>\n\t\t<true/>\n\t</dict>\n' + TAIL)
write(os.path.join(CONFIG, "NoxTunnel-Info.plist"), HEAD + GROUP +
      '\t<key>NSExtension</key>\n\t<dict>\n'
      '\t\t<key>NSExtensionPointIdentifier</key>\n\t\t<string>com.apple.networkextension.packet-tunnel</string>\n'
      '\t\t<key>NSExtensionPrincipalClass</key>\n\t\t<string>$(PRODUCT_MODULE_NAME).PacketTunnelProvider</string>\n'
      '\t</dict>\n' + TAIL)
ENT = (HEAD +
       '\t<key>com.apple.developer.networking.networkextension</key>\n\t<array>\n'
       '\t\t<string>packet-tunnel-provider</string>\n\t</array>\n'
       '\t<key>com.apple.security.application-groups</key>\n\t<array>\n'
       '\t\t<string>$(NOX_APP_GROUP)</string>\n\t</array>\n' + TAIL)
write(os.path.join(CONFIG, "Nox.entitlements"), ENT)
write(os.path.join(CONFIG, "NoxTunnel.entitlements"), ENT)
print("ok:", PROJ)
