#!/usr/bin/env python3
"""Deterministic Xcode projects: both bundle identities run the same real local model."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--team-id', default=os.environ.get('LINGUAFRANCA_TEAM_ID'))
args = parser.parse_args()
# Keep an existing local selection when regenerating. The generated project is not committed.
existing = ROOT / 'LinguaFranca.xcodeproj/project.pbxproj'
if not args.team_id and existing.exists():
    teams = set(re.findall(r'DEVELOPMENT_TEAM\s*=\s*"?([A-Z0-9]{10})"?\s*;', existing.read_text()))
    if len(teams) == 1:
        args.team_id = teams.pop()
if args.team_id and not re.fullmatch(r'[A-Z0-9]{10}', args.team_id):
    parser.error('--team-id must be a 10-character Apple team identifier')
def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def quote(value):
    return json.dumps(str(value))
objects = []
def obj(name, body):
    objects.append(f'{uid(name)} = {{ {body} }};')
    return uid(name)

sources = sorted(p.relative_to(ROOT).as_posix() for directory in ['App', 'Features', 'UIComponents'] for p in (ROOT / directory).rglob('*.swift'))
resources = ['Resources/Models', 'Resources/LanguagePacks', 'Resources/THIRD-PARTY-NOTICES.txt', 'Resources/CC-BY-SA-4.0.txt', 'Resources/CC-BY-SA-3.0.txt']
refs = {}
for path in sources + resources:
    kind = 'sourcecode.swift' if path.endswith('.swift') else ('folder' if (ROOT / path).is_dir() else 'text')
    refs[path] = obj('file:' + path, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {quote(path)}; sourceTree = "<group>";')
package = obj('local_package', 'isa = XCLocalSwiftPackageReference; relativePath = .;')
package_products = {}
for name in ['LinguaFrancaCore', 'LinguaFrancaInference']:
    package_products[name] = obj('package:' + name, f'isa = XCSwiftPackageProductDependency; package = {package}; productName = {name};')

project_configs = []
for configuration in ['Debug', 'Release']:
    project_configs.append(obj('project:' + configuration, f'''isa = XCBuildConfiguration; name = {configuration}; buildSettings = {{
        CLANG_ENABLE_MODULES = YES; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SDKROOT = iphoneos;
        ONLY_ACTIVE_ARCH = {'YES' if configuration == 'Debug' else 'NO'};
        SWIFT_VERSION = 6.0; SWIFT_STRICT_CONCURRENCY = complete;
        SWIFT_OPTIMIZATION_LEVEL = "{'-Onone' if configuration == 'Debug' else '-O'}";
        DEBUG_INFORMATION_FORMAT = {'dwarf' if configuration == 'Debug' else '"dwarf-with-dsym"'};
    }};'''))
project_config_list = obj('project_config_list', f'isa = XCConfigurationList; buildConfigurations = ({",".join(project_configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

products, targets, target_schemes = [], [], []
for name, preview in [('LinguaFranca', False), ('LinguaFrancaPreviewApp', True)]:
    product = obj(name + ':product', f'isa = PBXFileReference; explicitFileType = wrapper.application; path = {name}.app; sourceTree = BUILT_PRODUCTS_DIR;')
    products.append(product)
    phases = []
    for kind, paths in [('Sources', sources), ('Resources', resources)]:
        builds = [obj(name + ':build:' + p, f'isa = PBXBuildFile; fileRef = {refs[p]};') for p in paths]
        phases.append(obj(name + ':phase:' + kind, f'isa = PBX{kind}BuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)}); runOnlyForDeploymentPostprocessing = 0;'))
    dependencies = [package_products['LinguaFrancaCore'], package_products['LinguaFrancaInference']]
    frameworks = [obj(name + ':framework:' + p, f'isa = PBXBuildFile; productRef = {p};') for p in dependencies]
    phases.append(obj(name + ':frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({",".join(frameworks)}); runOnlyForDeploymentPostprocessing = 0;'))
    configs = []
    for configuration in ['Debug', 'Release']:
        condition = ('DEVELOPMENT_TEAM = ' + quote(args.team_id) + ';') if args.team_id else ''
        bundle = 'com.linguafranca.app.preview' if preview else 'com.linguafranca.app'
        configs.append(obj(name + ':' + configuration, f'''isa = XCBuildConfiguration; name = {configuration}; buildSettings = {{
            PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = {bundle}; GENERATE_INFOPLIST_FILE = YES;
            INFOPLIST_KEY_CFBundleDisplayName = LinguaFranca; INFOPLIST_KEY_UILaunchScreen_Generation = YES;
            INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
            INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait;
            TARGETED_DEVICE_FAMILY = 1; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
            SUPPORTS_MACCATALYST = NO; MARKETING_VERSION = 0.1.0; CURRENT_PROJECT_VERSION = 1;
            CODE_SIGN_STYLE = Automatic; ENABLE_PREVIEWS = YES; SWIFT_EMIT_LOC_STRINGS = YES; {condition}
            LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
        }};'''))
    config_list = obj(name + ':configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    target = obj(name + ':target', f'''isa = PBXNativeTarget; name = {name}; productName = {name};
        productType = "com.apple.product-type.application"; productReference = {product};
        buildConfigurationList = {config_list}; buildPhases = ({",".join(phases)});
        buildRules = (); dependencies = (); packageProductDependencies = ({",".join(dependencies)});''')
    targets.append(target)
    target_schemes.append((name, 'LinguaFranca Local' if preview else name, target))

products_group = obj('products', f'isa = PBXGroup; children = ({",".join(products)}); name = Products; sourceTree = "<group>";')
root_group = obj('root_group', f'isa = PBXGroup; children = ({",".join(list(refs.values()) + [products_group])}); sourceTree = "<group>";')
project = obj('project', f'''isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }};
    buildConfigurationList = {project_config_list}; compatibilityVersion = "Xcode 14.0";
    developmentRegion = en; knownRegions = (en,Base); mainGroup = {root_group}; productRefGroup = {products_group};
    projectDirPath = ""; projectRoot = ""; targets = ({",".join(targets)}); packageReferences = ({package});''')
folder = ROOT / 'LinguaFranca.xcodeproj'
folder.mkdir(exist_ok=True)
(folder / 'project.pbxproj').write_text('// !$*UTF8*$!\n{\narchiveVersion = 1; classes = {}; objectVersion = 56;\nobjects = {\n' + '\n'.join(objects) + '\n};\nrootObject = ' + project + ';\n}\n')
schemes = folder / 'xcshareddata' / 'xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
for name, scheme, target in target_schemes:
    reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}.app" BlueprintName="{name}" ReferencedContainer="container:LinguaFranca.xcodeproj"/>'
    (schemes / (scheme + '.xcscheme')).write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"/>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
# Preserve the previous scheme selection as an alias, now backed by the real model too.
(schemes / 'LinguaFranca Preview.xcscheme').write_text((schemes / 'LinguaFranca Local.xcscheme').read_text())
print(f'Generated real-model app schemes in {folder}.')
