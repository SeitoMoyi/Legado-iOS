"""Compile the production core and selected UI helpers into a temporary simulator app."""
import os
import hashlib
import plistlib
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
products = Path(sys.argv[1])
objects = Path(sys.argv[2])
output = Path(sys.argv[3])
base_url = Path(sys.argv[4]).read_text().strip()
if not base_url.startswith('http://127.0.0.1:'):
    raise ValueError('Only loopback fixtures are allowed')
output.mkdir(parents=True, exist_ok=True)
arch = os.uname().machine
if objects.name != arch:
    raise ValueError('Object directory must match the native simulator architecture: ' + arch)
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
source_files = sorted((root / 'Sources/LegadoCore').rglob('*.swift'))
source_files += [root / name for name in [
    'Runtime/LegadoRuntime/QuickJSRuntime.swift',
    'Sources/LegadoApp/Services/BookStore.swift',
    'Sources/LegadoApp/Services/SourceWebSession.swift',
    'Sources/LegadoApp/Views/RssHTMLView.swift',
    'Sources/LegadoApp/Views/SourceBrowserView.swift',
    'tools/native_probe/NativeVerification.swift',
]]
link_objects = [products / 'SwiftSoup.o', products / 'ZIPFoundation.o']
link_objects += [objects / (name + '.o') for name in ['LegadoQuickJS', 'quickjs', 'dtoa', 'libregexp', 'libunicode', 'cutils']]
for path in link_objects:
    if not path.is_file():
        raise FileNotFoundError(path)
command = ['xcrun', '--sdk', 'iphonesimulator', 'swiftc', '-parse-as-library', '-whole-module-optimization', '-module-name', 'LegadoNativeVerification',
           '-target', arch + '-apple-ios15.0-simulator', '-sdk', sdk,
           '-I', str(products), '-I', str(root / 'Runtime/CQuickJS/include'),
           '-F', str(products / 'PackageFrameworks'), '-lz', '-o', str(output / 'LegadoNativeVerification')]
subprocess.run(command + list(map(str, source_files + link_objects)), check=True)
digest = hashlib.sha256()
for path in source_files:
    digest.update(str(path.relative_to(root)).encode() + b'\0' + path.read_bytes())
info = {
    'CFBundleIdentifier': 'org.legado.NativeVerification', 'CFBundleName': 'Legado Verify',
    'CFBundleExecutable': 'LegadoNativeVerification', 'CFBundlePackageType': 'APPL',
    'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0', 'MinimumOSVersion': '15.0',
    'LSRequiresIPhoneOS': True, 'UILaunchScreen': {}, 'UIDeviceFamily': [1, 2],
    'NSAppTransportSecurity': {'NSAllowsArbitraryLoads': True, 'NSAllowsLocalNetworking': True},
    'VerificationBaseURL': base_url, 'VerificationSourceSHA256': digest.hexdigest(),
    'VerificationProductionVersion': (root / 'VERSION').read_text().strip(),
}
(output / 'Info.plist').write_bytes(plistlib.dumps(info))
shutil.copy(root / 'Runtime/LICENSE.QuickJS', output / 'LICENSE.QuickJS')
subprocess.run(['codesign', '--force', '--sign', '-', str(output)], check=True)
print('Native verification app built:', output)
