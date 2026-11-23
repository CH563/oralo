#!/usr/bin/env python3
"""Regenerate the portable Mac-only project; never edits the iOS project."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
objects = {}

def ident(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def add(key_name, isa, **kwargs):
    key = ident(key_name)
    objects[key] = dict(isa=isa, **kwargs)
    return key

def quote(value, level=0):
    indent = '\t' * level
    child_indent = '\t' * (level + 1)
    if isinstance(value, dict):
        if not value: return '{}'
        return '{\n' + '\n'.join(f'{child_indent}{json.dumps(k)} = {quote(v, level + 1)};' for k, v in value.items()) + '\n' + indent + '}'
    if isinstance(value, list):
        if not value: return '()'
        return '(\n' + '\n'.join(f'{child_indent}{quote(v, level + 1)},' for v in value) + '\n' + indent + ')'
    return json.dumps(str(value))

package = add('core-package', 'XCLocalSwiftPackageReference', relativePath='../oralo-ios/Packages/OraloCore')
products = []
groups = []
targets = []
base = dict(SDKROOT='macosx', MACOSX_DEPLOYMENT_TARGET='15.0', SWIFT_VERSION='6.0',
    SWIFT_APPROACHABLE_CONCURRENCY='YES', SWIFT_DEFAULT_ACTOR_ISOLATION='MainActor',
    CLANG_ENABLE_MODULES='YES', CODE_SIGN_STYLE='Automatic', CODE_SIGN_IDENTITY='-',
    GENERATE_INFOPLIST_FILE='YES', ENABLE_USER_SCRIPT_SANDBOXING='YES',
    SWIFT_EMIT_LOC_STRINGS='YES', PRODUCT_NAME='$(TARGET_NAME)',)

def configs(name, settings):
    refs=[]
    for config in ['Debug', 'Release']:
        values = base | settings | dict(SWIFT_OPTIMIZATION_LEVEL='-Onone' if config=='Debug' else '-O',
            SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG' if config=='Debug' else '',
            ENABLE_TESTABILITY='YES' if config=='Debug' else 'NO',
            ONLY_ACTIVE_ARCH='YES' if config=='Debug' else 'NO',
            DEBUG_INFORMATION_FORMAT='dwarf' if config=='Debug' else 'dwarf-with-dsym',
            DEPLOYMENT_POSTPROCESSING='NO' if config=='Debug' else 'YES',
            STRIP_INSTALLED_PRODUCT='NO' if config=='Debug' else 'YES',
            COPY_PHASE_STRIP='NO' if config=='Debug' else 'YES')
        refs.append(add(name+config, 'XCBuildConfiguration', buildSettings=values, name=config))
    return add(name+'config-list','XCConfigurationList',buildConfigurations=refs,defaultConfigurationIsVisible='0',defaultConfigurationName='Release')

app_target=ident('target-OraloMac')
for name, folder, product_type, extension in [
    ('OraloMac','OraloMac','com.apple.product-type.application','app'),
    ('OraloMacTests','OraloMacTests','com.apple.product-type.bundle.unit-test','xctest'),
    ('OraloMacUITests','OraloMacUITests','com.apple.product-type.bundle.ui-testing','xctest')]:
    children=[]; sources=[]; resources=[]
    for path in sorted((root/folder).rglob('*')):
        if not path.is_file() or any(p.startswith('.') for p in path.relative_to(root).parts): continue
        rel=path.relative_to(root).as_posix()
        filetype='text.json.xcstrings' if path.suffix=='.xcstrings' else 'sourcecode.swift' if path.suffix=='.swift' else 'text.xml' if path.suffix=='.xcprivacy' else 'image.icns' if path.suffix=='.icns' else 'image.pdf' if path.suffix=='.pdf' else 'text'
        file_ref=add(rel, 'PBXFileReference',lastKnownFileType=filetype,path=rel,sourceTree='<group>')
        children.append(file_ref)
        build=add(rel+'build','PBXBuildFile',fileRef=file_ref)
        (sources if path.suffix=='.swift' else resources).append(build)
    groups.append(add(name+'group','PBXGroup',children=children,name=name,sourceTree='<group>'))
    product=add(name+'product','PBXFileReference',explicitFileType='wrapper.application' if extension=='app' else 'wrapper.cfbundle',
        includeInIndex='0',path=('Oralo' if name=='OraloMac' else name)+'.'+extension,sourceTree='BUILT_PRODUCTS_DIR')
    products.append(product)
    packages=[]; framework_files=[]; dependencies=[]
    if name!='OraloMacUITests':
        dep=add(name+'core','XCSwiftPackageProductDependency',package=package,productName='OraloCore')
        packages.append(dep); framework_files.append(add(name+'core-build','PBXBuildFile',productRef=dep))
    if name!='OraloMac':
        proxy=add(name+'proxy','PBXContainerItemProxy',containerPortal=ident('project'),proxyType='1',remoteGlobalIDString=app_target,remoteInfo='OraloMac')
        dependencies.append(add(name+'depends','PBXTargetDependency',target=app_target,targetProxy=proxy))
    phases=[add(name+'sources','PBXSourcesBuildPhase',buildActionMask='2147483647',files=sources,runOnlyForDeploymentPostprocessing='0'),
        add(name+'frameworks','PBXFrameworksBuildPhase',buildActionMask='2147483647',files=framework_files,runOnlyForDeploymentPostprocessing='0'),
        add(name+'resources','PBXResourcesBuildPhase',buildActionMask='2147483647',files=resources,runOnlyForDeploymentPostprocessing='0')]
    settings=dict(PRODUCT_BUNDLE_IDENTIFIER='com.ch563.oralo.mac.dev'+('' if name=='OraloMac' else '.'+name.lower()),
        LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks')
    if name=='OraloMac':
        settings |= dict(PRODUCT_NAME='Oralo',PRODUCT_MODULE_NAME='OraloMac',INFOPLIST_FILE='Configurations/Info.plist',
            CODE_SIGN_ENTITLEMENTS='Configurations/OraloMac.entitlements',ENABLE_APP_SANDBOX='YES',ENABLE_HARDENED_RUNTIME='YES',
            MARKETING_VERSION='0.1.0',CURRENT_PROJECT_VERSION='12',INFOPLIST_KEY_CFBundleIconFile='Oralo.icns')
    elif name=='OraloMacTests':
        settings |= dict(TEST_HOST='$(BUILT_PRODUCTS_DIR)/Oralo.app/Contents/MacOS/Oralo',BUNDLE_LOADER='$(TEST_HOST)')
    else: settings |= dict(TEST_TARGET_NAME='OraloMac')
    targets.append(add('target-'+name,'PBXNativeTarget',buildConfigurationList=configs(name,settings),buildPhases=phases,buildRules=[],
        dependencies=dependencies,name=name,productName=name,productReference=product,productType=product_type,packageProductDependencies=packages))

product_group=add('products','PBXGroup',children=products,name='Products',sourceTree='<group>')
main_group=add('main','PBXGroup',children=groups+[product_group],sourceTree='<group>')
project=add('project','PBXProject',attributes=dict(LastUpgradeCheck='2710',BuildIndependentTargetsInParallel='1'),
    buildConfigurationList=configs('project',{}),compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings='0',
    knownRegions=['en','zh-Hans','zh-Hant','Base'],mainGroup=main_group,productRefGroup=product_group,projectDirPath='',projectRoot='',targets=targets,packageReferences=[package])
project_dir=root/'OraloMac.xcodeproj'
project_dir.mkdir(exist_ok=True)
(project_dir/'project.pbxproj').write_text('// !$*UTF8*$!\n'+quote(dict(archiveVersion='1',classes={},objectVersion='56',objects=objects,rootObject=project))+'\n')
schemes=project_dir/'xcshareddata/xcschemes'
schemes.mkdir(parents=True,exist_ok=True)
def reference(name, filename):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident("target-"+name)}" BuildableName="{filename}" BlueprintName="{name}" ReferencedContainer="container:OraloMac.xcodeproj"/>'
app_ref=reference('OraloMac','Oralo.app')
tests=''.join(f'<TestableReference skipped="NO">{reference(n,n+".xctest")}</TestableReference>' for n in ['OraloMacTests','OraloMacUITests'])
(schemes/'OraloMac.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2710" version="1.7">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>{tests}</Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated OraloMac.xcodeproj with app, unit, and UI-test targets.')
