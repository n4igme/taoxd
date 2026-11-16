#!/usr/bin/env python3
"""auto_record.py — automated demo recording loop via OBS WebSocket.

For each video (v02..v06):
  1. Start OBS recording
  2. Run demo_all.sh <video> inside Docker (streaming output live)
  3. Stop OBS recording
  4. Rename recording to out/demos/v0N-demo.mp4

Requires: OBS running with WebSocket server on 4455 (no auth),
          Window Capture source showing the Git Bash window,
          Docker Desktop running.
"""
import os
import subprocess
import sys
import time
from datetime import datetime

from obswebsocket import obsws, requests, exceptions

OBS_HOST = '127.0.0.1'
OBS_PORT = 4455
OBS_PASS = ''

DOCKER_HOST = 'npipe:////./pipe/docker_engine'
# On Git Bash (MSYS), this env var gets path-mangled. Test both forms:
#   npipe:////./pipe/docker_engine  (4 slashes — works in cmd/PowerShell)
#   npipe://///./pipe/docker_engine (5 slashes — MSYS adds one)
# auto-detect: try 4-slash, fall back to 5-slash
import platform as _platform


def _docker_works(host: str) -> bool:
    try:
        r = subprocess.run(
            ['docker', 'version', '--format', 'ok'],
            env={**os.environ, 'DOCKER_HOST': host},
            capture_output=True, timeout=15,
        )
        return r.returncode == 0
    except Exception:
        return False


_candidates = ['npipe:////./pipe/docker_engine', 'npipe://///./pipe/docker_engine']
for _h in _candidates:
    if _docker_works(_h):
        DOCKER_HOST = _h
        break
else:
    print('WARNING: no working DOCKER_HOST found — docker may not be running')
OUT_DIR = 'C:/Users/mhx_x/Project/taoxd-remotion/out/demos'
TAOXD = 'C:/Users/mhx_x/Project/taoxd'

VIDEOS = sys.argv[1:] or ['v02', 'v03', 'v04', 'v05', 'v06']

DOCKER_CMD = [
    'docker', 'run', '--rm', '-it', '--cap-add=SYS_PTRACE',
    '--security-opt', 'seccomp=unconfined',
    '-v', f'{TAOXD}:/work',
    '-w', '/work',
    'modern-exploit-dev-lab:24.04',
    'bash', 'demo_all.sh',
]


def connect_obs():
    c = obsws(OBS_HOST, OBS_PORT, OBS_PASS)
    c.connect()
    return c


def record_video(client, video):
    print(f'\n{"=" * 60}')
    print(f'  RECORDING {video}')
    print(f'{"=" * 60}')

    os.makedirs(OUT_DIR, exist_ok=True)
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    outfile = os.path.join(OUT_DIR, f'{video}-demo-{timestamp}.mp4')

    # 1. Start recording
    print('[1] OBS: start recording...')
    client.call(requests.StartRecord())
    time.sleep(1)  # give OBS a beat to initialize encoder

    # 2. Run demo inside Docker (streaming output to stdout, visible in terminal)
    print(f'[2] Docker: running demo_all.sh {video} (output visible in captured window)...')
    env = os.environ.copy()
    env['DOCKER_HOST'] = DOCKER_HOST
    result = subprocess.run(
        DOCKER_CMD + [video],
        env=env,
        capture_output=False,  # stream live — the OBS window shows it
    )
    print(f'[2] Docker exit code: {result.returncode}')

    # 3. Stop recording
    print('[3] OBS: stop recording...')
    stop = client.call(requests.StopRecord())
    saved_path = None
    if stop.datain:
        saved_path = stop.datain.get('outputPath')
    time.sleep(1)

    # 4. Rename/organize
    if saved_path and os.path.exists(saved_path):
        os.makedirs(OUT_DIR, exist_ok=True)
        os.replace(saved_path, outfile)
        size_mb = os.path.getsize(outfile) / 1e6
        print(f'[4] Saved: {outfile} ({size_mb:.1f} MB)')
        return outfile, result.returncode
    else:
        print(f'[4] WARNING: could not locate recording file (OBS reported: {saved_path})')
        return None, result.returncode


def main():
    print('Connecting to OBS...')
    client = connect_obs()
    print('OBS connected.')

    results = {}
    try:
        for video in VIDEOS:
            outfile, rc = record_video(client, video)
            results[video] = {'file': outfile, 'docker_rc': rc}
    finally:
        client.disconnect()

    print(f'\n{"=" * 60}')
    print('  RECORDING SUMMARY')
    print(f'{"=" * 60}')
    for video, info in results.items():
        status = 'OK' if info['docker_rc'] == 0 else f'docker_rc={info["docker_rc"]}'
        print(f'  {video}: {info["file"]} [{status}]')


if __name__ == '__main__':
    main()
