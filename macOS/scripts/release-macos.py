#!/usr/bin/env python3
"""Build locally first; use Developer ID + Keychain credentials for distribution.

prepare: offline unsigned universal archive, no Apple account changes.
sign: Developer ID app and ZIP, ready to review; no notarization upload.
notarize/resume: explicitly upload app ZIP, staple app, build signed DMG,
then notarize/staple DMG. Publish to dist only after all checks pass.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
APP_NAME = 'MeshCore Servicer.app'
STATE_NAME = 'release-state.json'
REQUIRED_ENTITLEMENTS = {'com.apple.security.app-sandbox': True, 'com.apple.security.device.bluetooth': True, 'com.apple.security.device.serial': True,
                         'com.apple.security.files.user-selected.read-write': True, 'com.apple.security.network.client': True,
                         'com.apple.security.temporary-exception.mach-lookup.global-name': ['$(PRODUCT_BUNDLE_IDENTIFIER)-spks', '$(PRODUCT_BUNDLE_IDENTIFIER)-spki']}


def run(command, **kwargs):
    return subprocess.run([str(x) for x in command], check=True, **kwargs)


def capture(command):
    result = run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return result.stdout.decode('utf-8')


def digest(file):
    return hashlib.sha256(Path(file).read_bytes()).hexdigest()


def load_state(work):
    state = json.loads((work / STATE_NAME).read_text())
    if state.get('schema') != 1 or state.get('phase') not in ('prepared', 'signed', 'app-submitted', 'dmg-ready', 'dmg-submitted', 'complete'):
        raise ValueError('Neplatný stav vydání.')
    version = state.get('version', '')
    if not re.fullmatch(r'\d+(?:\.\d+){1,3}', version) or state.get('archive') != 'MeshCoreServicer.xcarchive':
        raise ValueError('Neplatná metadata archivu.')
    for key, expected in [('app', APP_NAME), ('zip', 'MeshCoreServicer-notarization.zip'), ('dmg', 'MeshCoreServicer-' + version + '-macOS-universal.dmg')]:
        if key in state and state[key] != expected:
            raise ValueError('Neplatná cesta v místním stavu vydání: ' + key)
    return state


def save_state(work, state):
    target = work / STATE_NAME
    temp = target.with_suffix('.tmp')
    temp.write_text(json.dumps(state, ensure_ascii=False, indent=2) + '\n')
    temp.replace(target)


def identities(text):
    return [(fingerprint, name) for fingerprint, name in re.findall(r'\b([A-Fa-f0-9]{40}) "([^"]+)"', text)
            if name.startswith('Developer ID Application: ')]


def choose_identity(available, requested):
    selected = [item for item in available if not requested or requested.casefold() in (item[0].casefold(), item[1].casefold())]
    if len(selected) != 1:
        raise ValueError('Chybí jednoznačná platná identita Developer ID Application. Vytvořte ji v Xcode → Settings → Accounts → Manage Certificates. Při více identitách použijte --identity SHA1.')
    return selected[0]


def validate_sparkle_linkage(load_commands, dependencies):
    # Validate the actual Mach-O, not only Xcode settings: a signed/notarized
    # bundle can still abort in dyld before its entry point is reached.
    paths = re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset \d+\)', load_commands)
    if not {'@executable_path/../Frameworks', '@loader_path/../Frameworks'}.intersection(paths):
        raise ValueError('Chybí přenositelná LC_RPATH cesta do Contents/Frameworks; Sparkle by při startu nebylo načteno.')
    if '@rpath/Sparkle.framework/Versions/B/Sparkle (' not in dependencies:
        raise ValueError('Aplikace není propojena s přibaleným Sparkle.framework.')


def verify_runtime_linkage(app, binary):
    framework = app / 'Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle'
    if not framework.is_file() or app.resolve() not in framework.resolve().parents:
        raise ValueError('Chybí binární knihovna Sparkle uvnitř aplikace.')
    if set(capture(['lipo', '-archs', framework]).split()) != {'arm64', 'x86_64'}:
        raise ValueError('Sparkle musí obsahovat obě architektury vydání.')
    for architecture in ('arm64', 'x86_64'):
        validate_sparkle_linkage(capture(['otool', '-arch', architecture, '-l', binary]),
                                capture(['otool', '-arch', architecture, '-L', binary]))


def app_info(app):
    with (app / 'Contents/Info.plist').open('rb') as file:
        info = plistlib.load(file)
    version = info.get('CFBundleShortVersionString', '')
    bundle = info.get('CFBundleIdentifier', '')
    if not re.fullmatch(r'\d+(?:\.\d+){1,3}', version) or not bundle or '$(' in bundle:
        raise ValueError('Neplatná verze nebo nevyřešený bundle identifier.')
    binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
    if set(capture(['lipo', '-archs', binary]).split()) != {'arm64', 'x86_64'}:
        raise ValueError('Vydání musí obsahovat arm64 i x86_64.')
    # Sparkle is the only permitted nested framework; all its executable pieces
    # are signed inside-out below. Unknown injected code fails closed.
    for folder in ('PlugIns', 'XPCServices', 'Helpers', 'Library/LoginItems'):
        location = app / 'Contents' / folder
        if location.exists() and any(location.iterdir()):
            raise ValueError('Neočekávaný vnořený kód: ' + folder)
    framework = app / 'Contents/Frameworks'
    if not framework.is_dir() or {p.name for p in framework.iterdir()} != {'Sparkle.framework'}:
        raise ValueError('Vydání musí obsahovat právě Sparkle.framework.')
    for relative in ('Autoupdate','Updater.app','XPCServices/Installer.xpc','XPCServices/Downloader.xpc'):
        if not (framework / 'Sparkle.framework/Versions/B' / relative).exists():
            raise ValueError('Neúplná distribuce Sparkle: ' + relative)
    verify_runtime_linkage(app, binary)
    return info


def verify_signature(app, team=None):
    run(['codesign', '--verify', '--all-architectures', '--deep', '--strict', app])
    result = run(['codesign', '--display', '--verbose=4', app], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    text = result.stderr.decode('utf-8') + result.stdout.decode('utf-8')
    if 'Authority=Developer ID Application:' not in text or 'Signature=adhoc' in text or 'runtime)' not in text or 'Timestamp=' not in text:
        raise ValueError('Chybí Developer ID podpis, Hardened Runtime nebo bezpečné časové razítko.')
    match = re.search(r'^TeamIdentifier=(\w+)$', text, re.MULTILINE)
    if match is None or team and match.group(1) != team:
        raise ValueError('Podpis neodpovídá týmu vydání.')
    data = run(['codesign', '--display', '--entitlements', ':-', app], stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout
    entitlements = plistlib.loads(data)
    validate_entitlements(entitlements, app_info(app)['CFBundleIdentifier'])
    return match.group(1)


def validate_entitlements(entitlements, bundle_id=None):
    expected = dict(REQUIRED_ENTITLEMENTS)
    if bundle_id:
        expected['com.apple.security.temporary-exception.mach-lookup.global-name'] = [bundle_id + '-spks', bundle_id + '-spki']
    if entitlements != expected:
        raise ValueError('Oprávnění se liší od očekávaného sandbox/Bluetooth/user-selected files. Zkontrolujte je před distribucí.')


def verify_artifact(work, state, key):
    artifact = work / state[key]
    if artifact.is_symlink() or artifact.resolve().parent != work.resolve() or not artifact.is_file() or digest(artifact) != state[key + '_sha256']:
        raise ValueError('Soubor se od vytvoření/odeslání změnil; nelze pokračovat: ' + key)
    return artifact


def prepare(work, bundle_id=None):
    if work.exists() and any(work.iterdir()):
        raise ValueError('Pracovní složka není prázdná. Pro nové sestavení použijte jiné --work; staré vydání se nemaže.')
    work.mkdir(parents=True, exist_ok=True)
    validate_entitlements(plistlib.loads((ROOT / 'Config/MeshCoreServicer.entitlements').read_bytes()))
    archive = work / 'MeshCoreServicer.xcarchive'
    with (work / 'build.log').open('w') as log:
        run(['xcodebuild', '-project', ROOT / 'MeshCoreServicer.xcodeproj', '-scheme', 'MeshCoreServicer', '-configuration', 'Release',
             '-destination', 'generic/platform=macOS', '-archivePath', archive, '-derivedDataPath', work / 'DerivedData',
             'ARCHS=arm64 x86_64', 'ONLY_ACTIVE_ARCH=NO', 'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO',
             'CODE_SIGN_IDENTITY=', 'CODE_SIGN_STYLE=Manual', 'DEVELOPMENT_TEAM=', *(['PRODUCT_BUNDLE_IDENTIFIER=' + bundle_id] if bundle_id else []), 'archive'], stdout=log, stderr=subprocess.STDOUT)
    app = archive / 'Products/Applications' / APP_NAME
    info = app_info(app)
    save_state(work, {'schema': 1, 'phase': 'prepared', 'version': info['CFBundleShortVersionString'], 'bundle_id': info['CFBundleIdentifier'],
                      'created_utc': datetime.now(timezone.utc).isoformat(), 'archive': archive.name})
    print('Lokální nepodepsaný univerzální archiv připraven. Zatím nebylo nic odesláno Applu ani publikováno.')


def sign(work, requested):
    state = load_state(work)
    if state['phase'] != 'prepared':
        raise ValueError('Podpis se provádí jen na nově připraveném archivu.')
    fingerprint, _ = choose_identity(identities(capture(['security', 'find-identity', '-v', '-p', 'codesigning'])), requested)
    app = work / APP_NAME
    if app.exists():
        raise ValueError('Podepisovaná kopie už existuje. Použijte nové pracovní vydání.')
    run(['ditto', work / state['archive'] / 'Products/Applications' / APP_NAME, app])
    app_info(app)
    sparkle = app / 'Contents/Frameworks/Sparkle.framework'
    base = sparkle / 'Versions/B'
    # Preserve Sparkle's reviewed helper sandbox entitlements; never use --deep
    # for signing, and never disable library validation on the host application.
    for relative in ('XPCServices/Downloader.xpc','XPCServices/Installer.xpc','Autoupdate','Updater.app'):
        component = base / relative
        entitlement_data = run(['codesign','--display','--entitlements',':-',component],stdout=subprocess.PIPE,stderr=subprocess.PIPE).stdout
        command = ['codesign','--force','--sign',fingerprint,'--options','runtime','--timestamp']
        with tempfile.TemporaryDirectory() as temp:
            if entitlement_data:
                plistlib.loads(entitlement_data)
                path = Path(temp) / 'helper.plist'; path.write_bytes(entitlement_data)
                command += ['--entitlements',path]
            run([*command,component])
    run(['codesign','--force','--sign',fingerprint,'--options','runtime','--timestamp',sparkle])
    info = app_info(app)
    entitlements = dict(REQUIRED_ENTITLEMENTS)
    entitlements['com.apple.security.temporary-exception.mach-lookup.global-name'] = [info['CFBundleIdentifier']+'-spks',info['CFBundleIdentifier']+'-spki']
    with tempfile.TemporaryDirectory() as temp:
        path=Path(temp)/'app.plist';path.write_bytes(plistlib.dumps(entitlements))
        run(['codesign','--force','--sign',fingerprint,'--options','runtime','--timestamp','--entitlements',path,app])
    team = verify_signature(app)
    zip_file = work / 'MeshCoreServicer-notarization.zip'
    run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, zip_file])
    state.update(phase='signed', identity=fingerprint, team=team, app=app.name, zip=zip_file.name, zip_sha256=digest(zip_file))
    save_state(work, state)
    print('Aplikace podepsána Developer ID. ZIP je připraven ke kontrole a odeslání, zatím není notarizovaný.')


def notary(command, profile):
    return json.loads(capture(['xcrun', 'notarytool', *command, '--keychain-profile', profile, '--output-format', 'json', '--no-progress']))


def accepted_log(work, job, profile, label):
    result = notary(['info', job], profile)
    if result.get('status') == 'In Progress':
        print('Apple vydání ještě zpracovává. Později opakujte příkaz resume. ID: ' + job)
        return False
    log_file = work / (label + '-notary-log.json')
    run(['xcrun', 'notarytool', 'log', job, '--keychain-profile', profile, log_file])
    log = json.loads(log_file.read_text())
    if result.get('status') != 'Accepted' or log.get('status') != 'Accepted' or log.get('issues'):
        raise ValueError('Notarizace není čistě schválená; prohlédněte místní log: ' + log_file.name)
    return True


def make_dmg(work, state):
    app = work / state['app']
    run(['xcrun', 'stapler', 'staple', app])
    run(['xcrun', 'stapler', 'validate', app])
    verify_signature(app, state['team'])
    dmg = work / ('MeshCoreServicer-' + state['version'] + '-macOS-universal.dmg')
    if dmg.exists():
        raise ValueError('Předchozí nedokončené DMG už existuje. Před pokračováním ho přesuňte mimo pracovní složku.')
    with tempfile.TemporaryDirectory(prefix='dmg-content-', dir=work) as directory:
        stage = Path(directory)
        run(['ditto', app, stage / APP_NAME])
        (stage / 'Applications').symlink_to('/Applications', target_is_directory=True)
        (stage / 'Nejprve si přečtěte.txt').write_text('MeshCore Servicer\n\nPřetáhněte aplikaci do složky Applications (Aplikace).\nPřed nahrazením starší verze ji ukončete. Osobní data a hesla zůstávají zachované.\nPři prvním spuštění povolte Bluetooth pro připojení vlastního companionu.\n')
        run(['hdiutil', 'create', '-volname', 'MeshCore Servicer', '-srcfolder', stage, '-format', 'UDZO', '-o', dmg])
    run(['codesign', '--sign', state['identity'], '--timestamp', dmg])
    run(['codesign', '--verify', '--strict', dmg])
    state.update(phase='dmg-ready', dmg=dmg.name, dmg_sha256=digest(dmg))
    save_state(work, state)


def publish(work, state):
    dmg = verify_artifact(work, state, 'dmg')
    run(['xcrun', 'stapler', 'staple', dmg])
    # Stapling changes bytes. Save the new hash before subsequent checks, so a
    # failed Gatekeeper check can be resumed without uploading the image again.
    state['dmg_sha256'] = digest(dmg)
    save_state(work, state)
    run(['xcrun', 'stapler', 'validate', dmg])
    run(['codesign', '--verify', '--strict', dmg])
    run(['hdiutil', 'verify', dmg])
    run(['spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=2', dmg])
    app = work / state['app']
    verify_signature(app, state['team'])
    run(['xcrun', 'stapler', 'validate', app])
    mount = plistlib.loads(run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-plist', dmg], stdout=subprocess.PIPE).stdout)
    mounted = next((entry['mount-point'] for entry in mount.get('system-entities', []) if 'mount-point' in entry), None)
    if mounted is None:
        raise ValueError('DMG se nepodařilo připojit pro kontrolu skutečně vložené aplikace.')
    try:
        embedded = Path(mounted) / APP_NAME
        app_info(embedded)
        verify_signature(embedded, state['team'])
        run(['xcrun', 'stapler', 'validate', embedded])
        run(['syspolicy_check', 'distribution', embedded])
    finally:
        run(['hdiutil', 'detach', mounted])
    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    target = dist / dmg.name
    if target.exists() and digest(target) != digest(dmg):
        raise ValueError('V dist už existuje jiné vydání tohoto názvu; nebude automaticky přepsáno.')
    shutil.copy2(dmg, target)
    target.with_suffix('.sha256').write_text(digest(target) + '  ' + target.name + '\n')
    report = {'version': state['version'], 'bundle_id': state['bundle_id'], 'team': state['team'], 'architectures': ['arm64', 'x86_64'],
              'app_notarization': state['app_job'], 'dmg_notarization': state['dmg_job'], 'stapled_app': True, 'stapled_dmg': True,
              'gatekeeper_checks': 'passed', 'downloaded_fresh_mac_test': 'not performed', 'sha256': digest(target)}
    target.with_suffix('.validation.json').write_text(json.dumps(report, indent=2) + '\n')
    state['phase'] = 'complete'
    save_state(work, state)
    print('Podepsané a notarizované DMG je připravené v dist: ' + target.name)


def advance(work, profile):
    state = load_state(work)
    if state['phase'] == 'signed':
        artifact = verify_artifact(work, state, 'zip')
        result = notary(['submit', artifact], profile)
        state.update(phase='app-submitted', app_job=result['id'])
        save_state(work, state)
        print('Aplikační ZIP odeslán Applu. ID: ' + state['app_job'])
    if state['phase'] == 'app-submitted':
        verify_artifact(work, state, 'zip')
        if not accepted_log(work, state['app_job'], profile, 'app'):
            return
        make_dmg(work, state)
    if state['phase'] == 'dmg-ready':
        artifact = verify_artifact(work, state, 'dmg')
        result = notary(['submit', artifact], profile)
        state.update(phase='dmg-submitted', dmg_job=result['id'])
        save_state(work, state)
        print('Podepsané DMG odesláno Applu. ID: ' + state['dmg_job'])
    if state['phase'] == 'dmg-submitted':
        verify_artifact(work, state, 'dmg')
        if accepted_log(work, state['dmg_job'], profile, 'dmg'):
            publish(work, state)
    if state['phase'] == 'prepared':
        raise ValueError('Nejdřív aplikaci podepište příkazem sign.')
    if state['phase'] == 'complete':
        print('Toto vydání už je dokončené; nic se znovu neodesílá.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['check', 'prepare', 'sign', 'notarize', 'resume'])
    parser.add_argument('--work', type=Path, default=ROOT / 'build/macos-release')
    parser.add_argument('--bundle-id', help='Override the generic source bundle identifier for a local Developer ID build')
    parser.add_argument('--identity', help='Developer ID Application SHA-1 fingerprint or full identity name')
    parser.add_argument('--keychain-profile', help='Named notarytool profile already stored in macOS Keychain')
    args = parser.parse_args()
    work = args.work.resolve()
    if args.command == 'check':
        available = identities(capture(['security', 'find-identity', '-v', '-p', 'codesigning']))
        for fingerprint, name in available:
            print(fingerprint + '  ' + name)
        choose_identity(available, args.identity)
        print('Developer ID Application je dostupný. Přihlašovací údaje notarizace se tímto příkazem nečtou.')
    elif args.command == 'prepare':
        prepare(work, args.bundle_id)
    elif args.command == 'sign':
        sign(work, args.identity)
    else:
        if not args.keychain_profile:
            parser.error('Pro notarizaci/resume je nutné --keychain-profile; heslo se nepředává v argumentech.')
        advance(work, args.keychain_profile)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, subprocess.CalledProcessError, OSError) as error:
        print('Vydání nebylo dokončeno: ' + str(error), file=sys.stderr)
        sys.exit(1)
