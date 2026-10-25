"""Native macOS preparation without requiring the iOS SDK or building a simulator runtime."""
import fcntl
from pathlib import Path
import plistlib
import sys
import tempfile
from bootstrap import BuildError,extract_archive,publish_tree

def prepare_mac(bootstrap):
    import platform
    import subprocess
    if platform.system()!='Darwin':raise BuildError('Native Mac builds require macOS and Xcode.')
    try:subprocess.run(['xcrun','--sdk','macosx','--show-sdk-path'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    except (OSError,subprocess.CalledProcessError) as error:raise BuildError('Install full Xcode and its macOS SDK.') from error
    with (bootstrap.cache/'bootstrap.lock').open('w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        bootstrap.grdb()
        spec=bootstrap.lock['llama.cpp']
        full=bootstrap.fingerprint(spec,['Tools/bootstrap.py'])
        fingerprint=bootstrap.fingerprint(spec,['Tools/mac_bootstrap.py'])
        if not bootstrap.current('llama',full) and not bootstrap.current('llama-mac',fingerprint):
            archive=bootstrap.download({'filename':'llama-'+spec['version']+'-xcframework.zip','url':spec['source'],'sha256':spec['archiveSHA256']})
            with tempfile.TemporaryDirectory(prefix='llama-mac-',dir=bootstrap.cache/'work') as temporary:
                extract_archive(archive,temporary)
                framework=Path(temporary)/'build-apple/llama.xcframework'
                info=plistlib.loads((framework/'Info.plist').read_bytes())
                if not any(lib.get('SupportedPlatform')=='macos' for lib in info['AvailableLibraries']):raise BuildError('The pinned llama runtime has no native macOS slice.')
                destination=bootstrap.root/spec['vendoredPath']
                publish_tree(framework,destination)
            bootstrap.remember('llama-mac',fingerprint,[destination])
        bootstrap.languages();bootstrap.english();bootstrap.model()
    print('Native Mac runtime and offline resources verified.',flush=True)
