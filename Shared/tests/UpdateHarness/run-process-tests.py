#!/usr/bin/env python3
"""Publisher-only, isolated process tests on macOS; never run real product UI.

Uses a temporary copy with only the Linux install-directory provider replaced,
because macOS .NET ignores XDG_DATA_HOME. Shipping sources remain unchanged.
Requires the publisher's signing key; ordinary unit tests use disposable keys.
All fixture versions are 0.0.x, never part of a release feed.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parents[3]


def run(args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    if result.returncode:
        raise RuntimeError(result.stdout.decode(errors='replace'))


def main(dotnet, key):
    with tempfile.TemporaryDirectory(prefix='meshcore-process-', dir='/private/tmp') as temporary:
        root = Path(temporary)
        shared = root / 'Shared'
        for name in ('MeshCore.Updates', 'MeshCore.Launcher', 'Assets'):
            shutil.copytree(REPO / 'Shared' / name, shared / name, ignore=shutil.ignore_patterns('bin', 'obj'))
        shutil.copy2(REPO / 'Shared/Directory.Build.props', shared / 'Directory.Build.props')
        actor_source = shared / 'tests/UpdateHarness'
        shutil.copytree(Path(__file__).parent, actor_source, ignore=shutil.ignore_patterns('bin', 'obj', '__pycache__'))
        session_file = shared / 'MeshCore.Updates/UpdateSession.cs'
        source = session_file.read_text()
        original = 'Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"MeshCoreServicer","Install")'
        assert source.count(original) == 1
        session_file.write_text(source.replace(original, 'Environment.GetEnvironmentVariable("MESHCORE_HARNESS_ROOT") ?? throw new InvalidOperationException("Test root missing")'))
        for project, destination in ((actor_source, root / 'actor'), (shared / 'MeshCore.Launcher', root / 'launcher')):
            run([dotnet, 'publish', str(project), '-c', 'Release', '-r', 'osx-arm64', '--self-contained', 'false', '-o', str(destination)])
        for mode in ('success', 'fail'):
            case = root / mode
            install, bootstrap, feed = case / 'install', case / 'bootstrap', case / 'feed'
            shutil.copytree(root / 'launcher', bootstrap)
            for version, actor_mode in (('0.0.1', 'old'), ('0.0.2', mode)):
                tree = install / 'versions' / version
                shutil.copytree(root / 'actor', tree)
                config = dict(Mode=actor_mode, Feed=str(feed), Result=str(case / 'result'), Triggered=str(case / 'triggered'), Requests=str(case / 'requests'))
                (tree / 'actor.json').write_text(json.dumps(config))
                run([dotnet, 'run', '--project', str(REPO / 'tools/UpdatePublisher'), '-c', 'Release', '--', 'publish', str(tree), 'linux-arm64', version, str(feed), key])
            pointer = json.dumps(dict(Version='0.0.1', Platform='linux-arm64'))
            (install / 'current.json').write_text(pointer)
            (bootstrap / 'current.json').write_text(pointer)
            shutil.copytree(install / 'versions/0.0.1', bootstrap / 'versions/0.0.1')
            sentinel = case / 'history-sentinel.json'
            sentinel.write_text('preserve local history')
            env = dict(os.environ, MESHCORE_HARNESS_ROOT=str(install), DOTNET_ROOT=str(Path(dotnet).parent))
            expected = 'new-ready' if mode == 'success' else 'old-restored'
            with (case / 'actor.log').open('wb') as log:
                process = subprocess.Popen([str(bootstrap / 'MeshCoreLauncher')], env=env, stdout=log, stderr=subprocess.STDOUT)
                process.wait(timeout=15)
                deadline = time.monotonic() + 30
                while time.monotonic() < deadline:
                    if (case / 'result').exists() and (case / 'result').read_text() == expected:
                        break
                    time.sleep(0.1)
                else:
                    print((case / 'actor.log').read_text())
                    if (case / 'result').exists():
                        print((case / 'result').read_text())
                    raise AssertionError('Process test did not reach ' + expected)
            time.sleep(2.5)  # Both short-lived test actors/helpers must finish before cleanup.
            active = json.loads((install / 'current.json').read_text())['Version']
            assert active == ('0.0.2' if mode == 'success' else '0.0.1'), active
            assert sentinel.read_text() == 'preserve local history'
            requests = (case / 'requests').read_text().splitlines()
            assert len(requests) == 2 and requests[0] == 'stable/linux-arm64.json' and requests[1].startswith('objects/'), requests
            print('PASS isolated process', mode, ': one changed object, restart/rollback, history preserved')
        print('2 process tests passed on macOS with substituted temporary storage; no Windows/Linux runtime or BLE/LoRa test.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dotnet', required=True)
    parser.add_argument('--key', required=True)
    a = parser.parse_args()
    main(a.dotnet, str(Path(a.key).resolve()))
