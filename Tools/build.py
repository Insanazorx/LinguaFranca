#!/usr/bin/env python3
"""One command: restore dependencies, generate project, test/build, verify app bundle."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
from bootstrap import Bootstrap, BuildError, ROOT, run
from semitic_bootstrap import prepare_semitic
from aggressive_bootstrap import prepare_aggressive
from dictionary_bootstrap import prepare_dictionary
from mac_bootstrap import prepare_mac
from narration_bootstrap import prepare_narration
from additional_language_bootstrap import prepare_additional_languages
from latin_vocabulary_bootstrap import prepare_latin_vocabulary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['simulator', 'device', 'mac'], default='simulator')
    parser.add_argument('--configuration', choices=['Debug', 'Release'], default='Debug')
    parser.add_argument('--cache-dir', type=Path)
    parser.add_argument('--offline', action='store_true')
    parser.add_argument('--bootstrap-only', action='store_true')
    parser.add_argument('--test', action='store_true', help='Run build-tool and Swift package tests.')
    parser.add_argument('--team-id', default=os.environ.get('LINGUAFRANCA_TEAM_ID'),
                        help='Optional Apple team for signed device builds; never stored in Git.')
    args = parser.parse_args()
    if args.platform=='mac' and args.configuration=='Release' and not args.team_id:
        raise BuildError('A hardened Mac Release needs an Apple signing team. Pass --team-id YOUR_APPLE_TEAM_ID, or build Debug for local development. Library validation remains enabled.')
    bootstrap = Bootstrap(cache=args.cache_dir, offline=args.offline)
    if args.platform == 'mac':prepare_mac(bootstrap)
    else:bootstrap.prepare()
    prepare_semitic(bootstrap)
    prepare_aggressive(bootstrap)
    prepare_additional_languages(bootstrap)
    prepare_latin_vocabulary(bootstrap)
    prepare_dictionary(bootstrap)
    prepare_narration(bootstrap)
    run(['xcrun','swift',ROOT/'Tools/prepare_mac_icon.swift',ROOT/'Resources/Mac/LinguaFranca.icns',ROOT/'Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png'],cwd=ROOT,log=bootstrap.cache/'logs/app-icon.log')
    command = [sys.executable, ROOT / 'Tools/generate_project.py']
    if args.team_id:
        command += ['--team-id', args.team_id]
    run(command, cwd=ROOT)
    if args.bootstrap_only:
        return
    if args.test:
        run([sys.executable, '-m', 'unittest', 'discover', '-s', 'Tests/BuildTests', '-v'], cwd=ROOT,
            log=bootstrap.cache / 'logs/build-tool-tests.log')
        run(['swift', 'test', '--scratch-path', ROOT / '.build'], cwd=ROOT,
            log=bootstrap.cache / 'logs/swift-tests.log')
    sdk = {'simulator':'iphonesimulator','device':'iphoneos','mac':'macosx'}[args.platform]
    destination = 'generic/platform=iOS Simulator' if args.platform == 'simulator' else 'generic/platform=iOS'
    if args.platform == 'mac':destination='platform=macOS'
    derived = ROOT / 'build/DerivedData'
    command = ['xcrun', 'xcodebuild', '-project', ROOT / 'LinguaFranca.xcodeproj',
        '-scheme', 'LinguaFranca Mac' if args.platform=='mac' else 'LinguaFranca', '-configuration', args.configuration, '-sdk', sdk,
        '-destination', destination, '-derivedDataPath', derived]
    if args.platform == 'device' and args.team_id:
        command += ['-allowProvisioningUpdates', '-allowProvisioningDeviceRegistration',
                    'DEVELOPMENT_TEAM=' + args.team_id]
    elif args.platform=='mac':
        command += ['CODE_SIGN_IDENTITY='+('Apple Development' if args.team_id else '-'),'CODE_SIGN_STYLE=Manual']
        if args.team_id:command += ['DEVELOPMENT_TEAM='+args.team_id]
    else:
        command += ['CODE_SIGNING_ALLOWED=NO']
    run(command + ['build'], cwd=ROOT, log=bootstrap.cache / 'logs/app-build.log')
    app = derived / 'Build/Products' / (args.configuration if args.platform=='mac' else args.configuration+'-'+sdk) / 'LinguaFranca.app'
    run([sys.executable, ROOT / 'Tools/verify_app_bundle.py', app, '--checksums'], cwd=ROOT)
    if args.platform=='mac' or (args.platform == 'device' and args.team_id):
        run(['codesign', '--verify', '--deep', '--strict', app], cwd=ROOT)
    print('Ready: ' + str(app), flush=True)
    if args.platform == 'device' and not args.team_id:
        print('Unsigned build. For phone installation, rerun with --team-id YOUR_APPLE_TEAM_ID.')


if __name__ == '__main__':
    try:
        main()
    except (BuildError, subprocess.CalledProcessError) as error:
        print('Build failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
