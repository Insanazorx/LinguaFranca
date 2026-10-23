#!/usr/bin/env python3
"""One command: restore dependencies, generate project, test/build, verify app bundle."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
from bootstrap import Bootstrap, BuildError, ROOT, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['simulator', 'device'], default='simulator')
    parser.add_argument('--configuration', choices=['Debug', 'Release'], default='Debug')
    parser.add_argument('--cache-dir', type=Path)
    parser.add_argument('--offline', action='store_true')
    parser.add_argument('--bootstrap-only', action='store_true')
    parser.add_argument('--test', action='store_true', help='Run build-tool and Swift package tests.')
    parser.add_argument('--team-id', default=os.environ.get('LINGUAFRANCA_TEAM_ID'),
                        help='Optional Apple team for signed device builds; never stored in Git.')
    args = parser.parse_args()
    bootstrap = Bootstrap(cache=args.cache_dir, offline=args.offline)
    bootstrap.prepare()
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
    sdk = 'iphonesimulator' if args.platform == 'simulator' else 'iphoneos'
    destination = 'generic/platform=iOS Simulator' if args.platform == 'simulator' else 'generic/platform=iOS'
    derived = ROOT / 'build/DerivedData'
    command = ['xcrun', 'xcodebuild', '-project', ROOT / 'LinguaFranca.xcodeproj',
        '-scheme', 'LinguaFranca', '-configuration', args.configuration, '-sdk', sdk,
        '-destination', destination, '-derivedDataPath', derived]
    if args.platform == 'device' and args.team_id:
        command += ['-allowProvisioningUpdates', '-allowProvisioningDeviceRegistration',
                    'DEVELOPMENT_TEAM=' + args.team_id]
    else:
        command += ['CODE_SIGNING_ALLOWED=NO']
    run(command + ['build'], cwd=ROOT, log=bootstrap.cache / 'logs/app-build.log')
    app = derived / 'Build/Products' / (args.configuration + '-' + sdk) / 'LinguaFranca.app'
    run([sys.executable, ROOT / 'Tools/verify_app_bundle.py', app, '--checksums'], cwd=ROOT)
    if args.platform == 'device' and args.team_id:
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
