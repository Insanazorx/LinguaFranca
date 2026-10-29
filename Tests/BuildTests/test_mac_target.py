"""A Mac UI change must never become an iOS compile input."""
import json
import plistlib
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


@unittest.skipUnless(sys.platform == 'darwin', 'Xcode project validation uses macOS plutil')
class MacTargetTests(unittest.TestCase):
    def test_mac_and_ios_have_separate_ui_sources_and_native_platforms(self):
        repository = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory(prefix='LinguaFranca targets ') as temporary:
            root = Path(temporary)
            (root/'Tools').mkdir()
            shutil.copy2(repository/'Tools/generate_project.py', root/'Tools/generate_project.py')
            for name in ['App/IOSOnly.swift', 'Mac/App/MacOnly.swift']:
                path = root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('// Target membership fixture\n')
            subprocess.run([sys.executable, str(root/'Tools/generate_project.py')], check=True, capture_output=True)
            project = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(root/'LinguaFranca.xcodeproj/project.pbxproj')]))
            objects = project['objects']
            targets = {value['name']: value for value in objects.values() if value.get('isa') == 'PBXNativeTarget'}
            def sources(target):
                phase = next(objects[key] for key in target['buildPhases'] if objects[key]['isa'] == 'PBXSourcesBuildPhase')
                return {objects[objects[key]['fileRef']]['path'] for key in phase['files']}
            self.assertEqual(sources(targets['LinguaFrancaMac']), {'Mac/App/MacOnly.swift'})
            for name in ['LinguaFranca', 'LinguaFrancaPreviewApp']:
                self.assertEqual(sources(targets[name]), {'App/IOSOnly.swift'})
            for name, target in targets.items():
                configurations = objects[target['buildConfigurationList']]['buildConfigurations']
                for key in configurations:
                    settings = objects[key]['buildSettings']
                    self.assertEqual(settings['SUPPORTS_MACCATALYST'], 'NO')
                    if name == 'LinguaFrancaMac':
                        self.assertEqual(settings['SDKROOT'], 'macosx')
                        self.assertEqual(settings['SUPPORTED_PLATFORMS'], 'macosx')
                        self.assertEqual(settings['ENABLE_APP_SANDBOX'], 'YES')
                        self.assertEqual(settings['ENABLE_HARDENED_RUNTIME'], 'YES')
                        self.assertEqual(settings['GENERATE_INFOPLIST_FILE'], 'NO')
                        self.assertEqual(settings['INFOPLIST_FILE'], 'Resources/Mac/Info.plist')
                        with (repository/settings['INFOPLIST_FILE']).open('rb') as stream:
                            info=plistlib.load(stream)
                        self.assertEqual(info['CFBundleIconFile'], 'LinguaFranca.icns')
                        resources=next(objects[phase] for phase in target['buildPhases'] if objects[phase]['isa']=='PBXResourcesBuildPhase')
                        paths={objects[objects[key]['fileRef']]['path'] for key in resources['files']}
                        self.assertIn('Resources/Mac/'+info['CFBundleIconFile'], paths)
                        self.assertNotIn(settings['INFOPLIST_FILE'], paths)
                    else:
                        self.assertEqual(settings['SUPPORTED_PLATFORMS'], 'iphoneos iphonesimulator')
                        self.assertEqual(settings['GENERATE_INFOPLIST_FILE'], 'YES')
                        self.assertNotIn('INFOPLIST_FILE', settings)
                        self.assertEqual(settings['ASSETCATALOG_COMPILER_APPICON_NAME'], 'AppIcon')
