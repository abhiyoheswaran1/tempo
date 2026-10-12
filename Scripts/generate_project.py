#!/usr/bin/env python3
"""Deterministic Xcode project generator; no external dependencies."""
from pathlib import Path
import hashlib, json, plistlib
root=Path(__file__).resolve().parents[1]
objects={}
def uid(key): return hashlib.sha1(key.encode()).hexdigest()[:24].upper()
def obj(key, body):
    ident=uid(key);objects[ident]=body;return ident
def q(x): return json.dumps(str(x))
def array(items):return '('+','.join(items)+',)'
files={}
for path in sorted(list((root/'Tempo').rglob('*.swift'))+list((root/'Shared').rglob('*.swift'))+list((root/'TempoWidgets').rglob('*.swift'))+list((root/'Tests/TempoUITests').rglob('*.swift'))):
    rel=str(path.relative_to(root));files[rel]=obj('file:'+rel,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(rel)}; sourceTree = "<group>";')
appProduct=obj('appProduct','isa = PBXFileReference; explicitFileType = wrapper.application; path = Tempo.app; sourceTree = BUILT_PRODUCTS_DIR;')
testProduct=obj('testProduct','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = TempoUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
widgetProduct=obj('widgetProduct','isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; path = TempoWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR;')
products=obj('products',f'isa = PBXGroup; children = {array([appProduct,widgetProduct,testProduct])}; name = Products; sourceTree = "<group>";')
mainGroup=obj('mainGroup',f'isa = PBXGroup; children = {array(list(files.values())+[products])}; sourceTree = "<group>";')
package=obj('localPackage','isa = XCLocalSwiftPackageReference; relativePath = .;')
product=obj('coreProduct',f'isa = XCSwiftPackageProductDependency; package = {package}; productName = TempoCore;')
coreBuild=obj('coreBuild',f'isa = PBXBuildFile; productRef = {product};')
def sources(name,prefixes):
    builds=[]
    for rel,f in files.items():
        if any(rel.startswith(p) for p in prefixes): builds.append(obj('build:'+name+rel,f'isa = PBXBuildFile; fileRef = {f};'))
    return obj(name+'Sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(builds)}; runOnlyForDeploymentPostprocessing = 0;')
appSources=sources('App',['Tempo/','Shared/']);widgetSources=sources('Widget',['TempoWidgets/','Shared/']);testSources=sources('UITests',['Tests/TempoUITests/'])
assets=obj('assets','isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Tempo/Resources/Assets.xcassets; sourceTree = "<group>";')
privacyApp=obj('privacyApp','isa = PBXFileReference; lastKnownFileType = text.xml; path = Tempo/Resources/PrivacyInfo.xcprivacy; sourceTree = "<group>";')
privacyWidget=obj('privacyWidget','isa = PBXFileReference; lastKnownFileType = text.xml; path = TempoWidgets/PrivacyInfo.xcprivacy; sourceTree = "<group>";')
assetBuild=obj('assetBuild',f'isa = PBXBuildFile; fileRef = {assets};')
privacyAppBuild=obj('privacyAppBuild',f'isa = PBXBuildFile; fileRef = {privacyApp};')
widgetAssets=obj('widgetAssets','isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = TempoWidgets/Assets.xcassets; sourceTree = "<group>";')
widgetAssetBuild=obj('widgetAssetBuild',f'isa = PBXBuildFile; fileRef = {widgetAssets};')
privacyWidgetBuild=obj('privacyWidgetBuild',f'isa = PBXBuildFile; fileRef = {privacyWidget};')
appResources=obj('appResources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {array([assetBuild,privacyAppBuild])}; runOnlyForDeploymentPostprocessing = 0;')
widgetResources=obj('widgetResources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {array([privacyWidgetBuild,widgetAssetBuild])}; runOnlyForDeploymentPostprocessing = 0;')
appFrameworks=obj('appFrameworks',f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {array([coreBuild])}; runOnlyForDeploymentPostprocessing = 0;')
widgetFrameworks=obj('widgetFrameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
embedBuild=obj('embedBuild',f'isa = PBXBuildFile; fileRef = {widgetProduct}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy,);}};')
embed=obj('embed',f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = {array([embedBuild])}; name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0;')
configFile=obj('configFile','isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Configuration.xcconfig; sourceTree = "<group>";')
def configs(name,extra):
    ids=[]
    for mode in ['Debug','Release']:
        settings={'ALWAYS_SEARCH_USER_PATHS':'NO','SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'26.0','TARGETED_DEVICE_FAMILY':'1','SWIFT_VERSION':'5.0','SWIFT_STRICT_CONCURRENCY':'complete','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if mode=='Debug' else '', 'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O','CODE_SIGN_STYLE':'Automatic','CURRENT_PROJECT_VERSION':'1','MARKETING_VERSION':'0.1.0','GENERATE_INFOPLIST_FILE':'NO','PRODUCT_NAME':'$(TARGET_NAME)','ENABLE_USER_SCRIPT_SANDBOXING':'YES','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO'}
        settings.update(extra)
        body='isa = XCBuildConfiguration; baseConfigurationReference = '+configFile+'; buildSettings = {'+' '.join(f'{k} = {q(v)};' for k,v in settings.items())+'}; name = '+mode+';'
        ids.append(obj(name+mode,body))
    return obj(name+'Configs',f'isa = XCConfigurationList; buildConfigurations = {array(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
appConfigs=configs('App',{'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','PRODUCT_BUNDLE_IDENTIFIER':'$(TEMPO_BUNDLE_ID)','INFOPLIST_FILE':'Tempo/Resources/Info.plist','CODE_SIGN_ENTITLEMENTS':'Tempo/Resources/Tempo.entitlements'})
widgetConfigs=configs('Widget',{'PRODUCT_BUNDLE_IDENTIFIER':'$(TEMPO_BUNDLE_ID).widgets','INFOPLIST_FILE':'TempoWidgets/Info.plist','CODE_SIGN_ENTITLEMENTS':'TempoWidgets/TempoWidgets.entitlements','SKIP_INSTALL':'YES','APPLICATION_EXTENSION_API_ONLY':'YES'})
projectConfigs=configs('Project',{})
widgetTarget=obj('widgetTarget',f'isa = PBXNativeTarget; buildConfigurationList = {widgetConfigs}; buildPhases = {array([widgetSources,widgetFrameworks,widgetResources])}; buildRules = (); dependencies = (); name = TempoWidgets; productName = TempoWidgets; productReference = {widgetProduct}; productType = "com.apple.product-type.app-extension";')
proxy=obj('widgetProxy',f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {widgetTarget}; remoteInfo = TempoWidgets;')
dep=obj('widgetDependency',f'isa = PBXTargetDependency; target = {widgetTarget}; targetProxy = {proxy};')
appTarget=obj('appTarget',f'isa = PBXNativeTarget; buildConfigurationList = {appConfigs}; buildPhases = {array([appSources,appFrameworks,appResources,embed])}; buildRules = (); dependencies = {array([dep])}; name = Tempo; packageProductDependencies = {array([product])}; productName = Tempo; productReference = {appProduct}; productType = "com.apple.product-type.application";')
testConfigs=configs('UITests',{'PRODUCT_BUNDLE_IDENTIFIER':'$(TEMPO_BUNDLE_ID).uitests','GENERATE_INFOPLIST_FILE':'YES','TEST_TARGET_NAME':'Tempo','SKIP_INSTALL':'YES'})
testProxy=obj('testProxy',f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {appTarget}; remoteInfo = Tempo;')
testDep=obj('testDep',f'isa = PBXTargetDependency; target = {appTarget}; targetProxy = {testProxy};')
testTarget=obj('testTarget',f'isa = PBXNativeTarget; buildConfigurationList = {testConfigs}; buildPhases = {array([testSources])}; buildRules = (); dependencies = {array([testDep])}; name = TempoUITests; productName = TempoUITests; productReference = {testProduct}; productType = "com.apple.product-type.bundle.ui-testing";')
project=obj('project',f'isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600;}}; buildConfigurationList = {projectConfigs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base,); mainGroup = {mainGroup}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; packageReferences = {array([package])}; targets = {array([appTarget,widgetTarget,testTarget])};')
p=root/'Tempo.xcodeproj';p.mkdir(exist_ok=True)
(p/'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 60; objects = {\n'+''.join(f'{k} = {{{v}}};\n' for k,v in objects.items())+'}; rootObject = '+project+'; }\n')
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{appTarget}" BuildableName="Tempo.app" BlueprintName="Tempo" ReferencedContainer="container:Tempo.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{testTarget}" BuildableName="TempoUITests.xctest" BlueprintName="TempoUITests" ReferencedContainer="container:Tempo.xcodeproj"/></TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{appTarget}" BuildableName="Tempo.app" BlueprintName="Tempo" ReferencedContainer="container:Tempo.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>'''
(p/'xcshareddata/xcschemes').mkdir(parents=True,exist_ok=True);(p/'xcshareddata/xcschemes/Tempo.xcscheme').write_text(scheme)
def plist(path,data):
    with (root/path).open('wb') as f:plistlib.dump(data,f)
common={'CFBundleDevelopmentRegion':'en','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(PRODUCT_NAME)','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)','TempoAppGroup':'$(TEMPO_APP_GROUP)'}
plist('Tempo/Resources/Info.plist',common|{'CFBundlePackageType':'APPL','CFBundleDisplayName':'Tempo','LSRequiresIPhoneOS':True,'UILaunchScreen':{},'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait'],'UIBackgroundModes':['bluetooth-central'],'NSBluetoothAlwaysUsageDescription':'Tempo reads measurements directly from the bands you register.','NSHealthShareUsageDescription':'Import only the Health measurements you choose to complement your personal history.','NSHealthUpdateUsageDescription':'Export supported measured data only when you choose.','NSSupportsLiveActivities':True,'TempoCloudContainer':'$(TEMPO_CLOUD_CONTAINER)','CFBundleURLTypes':[{'CFBundleURLSchemes':['tempo']}]})
plist('TempoWidgets/Info.plist',common|{'CFBundlePackageType':'XPC!','NSExtension':{'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'}})
plist('Tempo/Resources/Tempo.entitlements',{'com.apple.developer.icloud-container-identifiers':['$(TEMPO_CLOUD_CONTAINER)'],'com.apple.developer.icloud-services':['CloudKit'],'com.apple.developer.healthkit':True,'com.apple.security.application-groups':['$(TEMPO_APP_GROUP)']})
plist('TempoWidgets/TempoWidgets.entitlements',{'com.apple.security.application-groups':['$(TEMPO_APP_GROUP)']})
print('Generated Tempo.xcodeproj with native app and widget/Live Activity extension')
