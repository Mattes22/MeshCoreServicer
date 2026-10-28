#!/usr/bin/env python3
"""Deterministic Xcode project generator using only Python's standard library."""
import hashlib
from pathlib import Path
root = Path(__file__).resolve().parent.parent
objects = {}
def ident(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def add(name, body):
    i = ident(name); objects[i] = body; return i
def arr(items): return '(' + ', '.join(items) + ',)'
files = []
refs = []
for p in sorted((root/'Sources/MeshCoreServicer').glob('*.swift')):
    ref=add(str(p.relative_to(root)),f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{p.relative_to(root)}"; sourceTree = SOURCE_ROOT;')
    refs.append(ref)
    files.append(add('build'+p.name,f'isa = PBXBuildFile; fileRef = {ref};'))
product=add('product','isa = PBXFileReference; explicitFileType = wrapper.application; path = "MeshCore Servicer.app"; sourceTree = BUILT_PRODUCTS_DIR;')
pkg=add('package','isa = XCLocalSwiftPackageReference; relativePath = .;')
dep=add('dependency',f'isa = XCSwiftPackageProductDependency; package = {pkg}; productName = MeshCoreKit;')
sparkle=add('sparkle','isa = XCRemoteSwiftPackageReference; repositoryURL = \"https://github.com/sparkle-project/Sparkle\"; requirement = { kind = exactVersion; version = 2.10.1; };')
sparkledep=add('sparkledep',f'isa = XCSwiftPackageProductDependency; package = {sparkle}; productName = Sparkle;')
sparklebuild=add('sparklebuild',f'isa = PBXBuildFile; productRef = {sparkledep};')
pkgbuild=add('pkgbuild',f'isa = PBXBuildFile; productRef = {dep};')
sources=add('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(files)}; runOnlyForDeploymentPostprocessing = 0;')
frameworks=add('frameworks',f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {arr([pkgbuild,sparklebuild])}; runOnlyForDeploymentPostprocessing = 0;')
icon=add('icon','isa = PBXFileReference; lastKnownFileType = image.icns; path = Config/AppIcon.icns; sourceTree = SOURCE_ROOT;')
refs.append(icon)
iconbuild=add('iconbuild',f'isa = PBXBuildFile; fileRef = {icon};')
licenseref=add('license','isa = PBXFileReference; lastKnownFileType = text; path = Config/ThirdPartyNotices.txt; sourceTree = SOURCE_ROOT;')
refs.append(licenseref)
licensebuild=add('licensebuild',f'isa = PBXBuildFile; fileRef = {licenseref};')
resources=add('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {arr([iconbuild,licensebuild])}; runOnlyForDeploymentPostprocessing = 0;')
products=add('products',f'isa = PBXGroup; children = {arr([product])}; name = Products; sourceTree = "<group>";')
group=add('group',f'isa = PBXGroup; children = {arr(refs+[products])}; sourceTree = "<group>";')
def configs(prefix, settings):
    ids=[]
    for name in ['Debug','Release']:
        extra='ONLY_ACTIVE_ARCH = YES; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf;' if name=='Debug' else 'ONLY_ACTIVE_ARCH = YES; SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; DEPLOYMENT_POSTPROCESSING = YES; STRIP_INSTALLED_PRODUCT = YES; STRIP_STYLE = debugging;'
        ids.append(add(prefix+name,f'isa = XCBuildConfiguration; buildSettings = {{ {settings} {extra} }}; name = {name};'))
    return add(prefix+'configs',f'isa = XCConfigurationList; buildConfigurations = {arr(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
pc=configs('project','MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES;')
tc=configs('app','PRODUCT_NAME = "MeshCore Servicer"; PRODUCT_BUNDLE_IDENTIFIER = org.meshcoreservicer.app; INFOPLIST_FILE = Config/Info.plist; CODE_SIGN_ENTITLEMENTS = Config/MeshCoreServicer.entitlements; CODE_SIGN_STYLE = Manual; CODE_SIGN_IDENTITY = "-"; ENABLE_HARDENED_RUNTIME = YES; LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/../Frameworks"); GENERATE_INFOPLIST_FILE = NO; SWIFT_SERIALIZE_DEBUGGING_OPTIONS = NO; OTHER_SWIFT_FLAGS = ("$(inherited)", "-file-prefix-map", "$(SRCROOT)=/MeshCoreServicer", "-debug-prefix-map", "$(SRCROOT)=/MeshCoreServicer");')
target=add('target',f'isa = PBXNativeTarget; buildConfigurationList = {tc}; buildPhases = {arr([sources,frameworks,resources])}; buildRules = (); dependencies = (); name = MeshCoreServicer; packageProductDependencies = {arr([dep,sparkledep])}; productName = "MeshCore Servicer"; productReference = {product}; productType = "com.apple.product-type.application";')
project=add('project',f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; }}; buildConfigurationList = {pc}; compatibilityVersion = "Xcode 14.0"; developmentRegion = cs; knownRegions = (cs,en,Base); mainGroup = {group}; packageReferences = {arr([pkg,sparkle])}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {arr([target])};')
(root/'MeshCoreServicer.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+''.join(f'{i} = {{ {b} }};\n' for i,b in objects.items())+f'}}; rootObject = {project}; }}\n')
(root/'MeshCoreServicer.xcodeproj/xcshareddata/xcschemes/MeshCoreServicer.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="MeshCore Servicer.app" BlueprintName="MeshCoreServicer" ReferencedContainer="container:MeshCoreServicer.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="MeshCore Servicer.app" BlueprintName="MeshCoreServicer" ReferencedContainer="container:MeshCoreServicer.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
