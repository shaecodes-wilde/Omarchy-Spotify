#!/usr/bin/env python3
"""Run the same isolated native Quickshell fixtures against two source trees."""
import argparse
import importlib.util
import json
import math
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import tempfile
import time

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('sampler', HERE / 'benchmark-processes.py')
sampler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sampler)


def wait_for(log, marker, process, timeout=120, occurrences=1):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        content = log.read_text()
        if process.poll() is not None:
            raise RuntimeError('fixture exited: ' + content[-5000:])
        if any(error in content for error in ('ReferenceError', 'TypeError', 'Failed to load configuration', 'Cannot assign', 'Unable to assign', 'BENCHMARK_INVALID', 'Binding loop', 'binding loop')):
            raise RuntimeError('invalid fixture: ' + content[-5000:])
        if content.count(marker) >= occurrences:
            return
        time.sleep(.1)
    raise RuntimeError('fixture timeout: ' + log.read_text()[-5000:])


def run_case(tree, mode, count, args, output, name):
    with tempfile.TemporaryDirectory(prefix='sb-', dir=os.environ.get('XDG_RUNTIME_DIR', '/tmp')) as short_runtime, \
            tempfile.TemporaryDirectory(prefix='omarchy-perf-') as temporary:
        temporary = Path(temporary)
        app = temporary / 'app'
        plugin = app / 'plugin'
        plugin.mkdir(parents=True)
        for pattern in ('*.qml', '*.js'):
            for source in tree.glob(pattern):
                shutil.copy2(source, plugin)
        panel_path = plugin / 'Panel.qml'
        panel_source = panel_path.read_text()
        if 'readonly property bool pageReady:' not in panel_source:
            # Give older base revisions the same read-only Loader observability.
            anchor = '  id: root'
            if anchor not in panel_source:
                raise RuntimeError('cannot instrument baseline Panel readiness')
            panel_source = panel_source.replace(anchor, anchor + '\n  readonly property bool pageReady: pageLoader.status === Loader.Ready && pageLoader.item !== null\n    && pageLoader.sourceComponent === root.pageComponent()', 1)
            panel_path.write_text(panel_source)
        for directory in ('Commons', 'Ui'):
            shutil.copytree(Path('/usr/share/omarchy/shell') / directory, app / directory)
        shutil.copy2(HERE.parent / 'tests/integration/PerformanceFixture.qml', app / 'shell.qml')
        shutil.copy2(HERE.parent / 'tests/integration/PerformanceMini.qml', app / 'mini.qml')
        # All application state and credentials are isolated; system session MPRIS is hidden.
        mock_bin = temporary / 'bin'
        mock_bin.mkdir()
        # Unix IPC socket paths must remain below the kernel's 108-byte limit.
        runtime = Path(short_runtime)
        (plugin / 'scripts').mkdir()
        for destination in (mock_bin / 'secret-tool', mock_bin / 'systemctl',
                            plugin / 'scripts/playback-runtime.sh', plugin / 'scripts/setup-playback.sh',
                            plugin / 'scripts/configure-spotifyd.sh'):
            destination.write_text('#!/bin/sh\nexit 1\n')
            destination.chmod(0o755)
        env = os.environ.copy()
        for variable in ('DBUS_SESSION_BUS_ADDRESS', 'DBUS_STARTER_ADDRESS', 'DBUS_STARTER_BUS_TYPE', 'WAYLAND_DISPLAY'):
            env.pop(variable, None)
        if args.platform == 'wayland':
            env['WAYLAND_DISPLAY'] = str(Path(os.environ['XDG_RUNTIME_DIR']) / os.environ['WAYLAND_DISPLAY'])
        env.update(QT_QPA_PLATFORM=args.platform, QT_QPA_PLATFORMTHEME='generic', NO_AT_BRIDGE='1',
                   BENCHMARK_MODE=mode, BENCHMARK_ROWS=str(count),
                   PATH=str(mock_bin)+os.pathsep+env['PATH'], XDG_RUNTIME_DIR=str(runtime),
                   DBUS_SYSTEM_BUS_ADDRESS='unix:path='+str(runtime / 'disabled-system-bus'),
                   XDG_CONFIG_HOME=str(temporary / 'config'), XDG_STATE_HOME=str(temporary / 'state'),
                   XDG_DATA_HOME=str(temporary / 'data'), XDG_CACHE_HOME=str(temporary / 'cache'))
        bus_config = temporary / 'dbus.conf'
        bus_config.write_text('<busconfig><type>session</type><listen>unix:tmpdir=' + str(runtime)
                              + '</listen><policy context="default"><allow send_destination="*"/>'
                              + '<allow receive_sender="*"/><allow own="*"/></policy></busconfig>')
        log = output / f'{name}-{mode}-{count}.log'
        with log.open('w') as stream:
            process = subprocess.Popen(['dbus-run-session', '--config-file='+str(bus_config), '--', 'qs', '--no-color', '-p', str(app)], env=env, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                wait_for(log, 'PERFORMANCE_READY', process)
                # dbus-run-session is a wrapper; find the one exact isolated qs command.
                pids = []
                for command in Path('/proc').glob('[0-9]*/cmdline'):
                    try:
                        argv = command.read_bytes().split(b'\0')
                        if str(app).encode() in argv and Path(os.readlink(command.parent / 'exe')).name in ('qs', 'quickshell'):
                            pids.append(int(command.parent.name))
                    except OSError:
                        pass
                if len(pids) != 1:
                    raise RuntimeError(f'expected one fixture Quickshell, found {pids}')
                pid = pids[0]
                if mode == 'navigation':
                    wait_for(log, 'PERFORMANCE_NAVIGATION_DONE', process)
                if mode not in ('closed', 'closed-after-use'):
                    wait_for(log, 'PERFORMANCE_FEEDBACK_DONE', process)
                time.sleep(args.settle)
                samples = []
                for sample_index in range(args.samples):
                    if mode == 'navigation' and sample_index:
                        subprocess.run(['qs', 'ipc', '--pid', str(pid), 'call', 'benchmark', 'navigate'],
                                       env=env, check=True, capture_output=True, timeout=10)
                        wait_for(log, 'PERFORMANCE_NAVIGATION_DONE', process, occurrences=sample_index+1)
                        wait_for(log, 'PERFORMANCE_FEEDBACK_DONE', process, occurrences=sample_index+1)
                        time.sleep(args.settle)
                    _, memory, elapsed, cpu, switches = sampler.sample('fixture', args.seconds, pid)
                    samples.append(dict(pss_kib=memory['shell'][0], rss_kib=memory['shell'][1], cpu_percent=cpu, switches_per_second=switches, seconds=elapsed))
                subprocess.run(['qs', 'ipc', '--pid', str(pid), 'call', 'benchmark', 'verify'],
                               env=env, check=True, capture_output=True, timeout=10)
                wait_for(log, 'PERFORMANCE_READY', process)
                feedback = [float(line.split('PERFORMANCE_FEEDBACK_MS ')[1]) for line in log.read_text().splitlines() if 'PERFORMANCE_FEEDBACK_MS ' in line]
                event_loop_lag = [float(line.split('PERFORMANCE_EVENT_LOOP_LAG_MS ')[1]) for line in log.read_text().splitlines() if 'PERFORMANCE_EVENT_LOOP_LAG_MS ' in line]
                navigation = [float(line.split('PERFORMANCE_NAVIGATION_MS ')[1]) for line in log.read_text().splitlines() if 'PERFORMANCE_NAVIGATION_MS ' in line]
                return dict(samples=samples, median={key: statistics.median(row[key] for row in samples) for key in samples[0]},
                            feedback_sample_count=len(feedback),
                            event_loop_lag_sample_count=len(event_loop_lag),
                            event_loop_lag_p95_ms=sorted(event_loop_lag)[max(0, math.ceil(len(event_loop_lag)*.95)-1)] if event_loop_lag else None,
                            feedback_p95_ms=sorted(feedback)[max(0, math.ceil(len(feedback)*.95)-1)] if feedback else None,
                            navigation_p95_ms=sorted(navigation)[max(0, math.ceil(len(navigation)*.95)-1)] if navigation else None,
                            plateau_growth_kib=samples[-1]['pss_kib']-samples[0]['pss_kib'])
            finally:
                import signal
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                process.wait(timeout=10)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--seconds', type=int, default=10)
    parser.add_argument('--samples', type=int, default=3)
    parser.add_argument('--settle', type=int, default=5)
    parser.add_argument('--platform', choices=('offscreen', 'wayland'), default='offscreen')
    parser.add_argument('--rows', type=int, nargs='+', default=[1000, 10000])
    parser.add_argument('--modes', nargs='+', choices=('closed', 'closed-after-use', 'mini', 'full', 'navigation'), default=['closed', 'closed-after-use', 'mini', 'full', 'navigation'])
    args = parser.parse_args()
    if not 2 <= args.seconds <= 60 or args.samples < 2 or args.settle < 0 or min(args.rows) < 1:
        parser.error('seconds 2–60, samples >=2, settle >=0 and positive row counts required')
    if any(not (tree / 'Service.qml').is_file() for tree in (args.baseline, args.candidate)):
        parser.error('both source trees must contain Service.qml')
    args.output.mkdir(parents=True, exist_ok=True)
    report = dict(status='running', measurement_profile='release-parameters' if args.seconds >= 10 and args.samples >= 3 and args.settle >= 20 else 'screening',
                  seconds=args.seconds, samples=args.samples, settle_seconds=args.settle,
                  platform=args.platform, metadata_only=True, artwork=False, live_account=False,
                  baseline=str(args.baseline.resolve()), candidate=str(args.candidate.resolve()),
                  limitations=['Offscreen measures native item creation and local event feedback, not compositor input-to-photon latency.',
                               'Fixture metadata has no artwork; use live benchmark.sh for actual artwork/playback costs.',
                               'Keyring, systemctl and playback setup commands are stubbed; runtime and DBus session are isolated.'], cases={}, skipped=[])
    (args.output / 'report.json').write_text(json.dumps(report, indent=2)+'\n')
    failed = False
    for mode in args.modes:
        if mode == 'mini' and args.platform == 'offscreen':
            report['skipped'].append('mini: real KeyboardPanel requires Wayland layer-shell; rerun --platform wayland')
            continue
        for count in args.rows:
            key = f'{mode}-{count}'
            print(f'Running {key}', flush=True)
            results = {}
            # Alternate fresh-process order so candidate is not always warmed second.
            order = [('baseline', args.baseline), ('candidate', args.candidate)]
            if len(report['cases']) % 2:
                order.reverse()
            for name, tree in order:
                try:
                    results[name] = run_case(tree.resolve(), mode, count, args, args.output, name)
                except Exception as error:
                    report['status'] = 'invalid'
                    report['error'] = str(error)
                    report['cases'][key] = results
                    (args.output / 'report.json').write_text(json.dumps(report, indent=2)+'\n')
                    raise
            delta = {metric: results['candidate']['median'][metric]-results['baseline']['median'][metric] for metric in ('pss_kib', 'cpu_percent', 'switches_per_second')}
            budget = 2048 if mode.startswith('closed') else 5120
            checks = dict(memory=delta['pss_kib'] <= budget,
                          hidden_cpu=not mode.startswith('closed') or delta['cpu_percent'] <= .1,
                          scheduler=not mode.startswith('closed') or delta['switches_per_second'] <= 2,
                          feedback=mode.startswith('closed') or (results['candidate']['feedback_sample_count'] >= 20
                            and results['candidate']['feedback_p95_ms'] <= 100),
                          event_loop_lag=mode.startswith('closed') or (results['candidate']['event_loop_lag_sample_count'] >= 20
                            and results['candidate']['event_loop_lag_p95_ms'] <= 100),
                          cache_plateau=mode != 'navigation' or results['candidate']['plateau_growth_kib'] <= 1024)
            if results['baseline']['navigation_p95_ms'] and results['candidate']['navigation_p95_ms'] is not None:
                delta['navigation_p95_ratio'] = results['candidate']['navigation_p95_ms'] / results['baseline']['navigation_p95_ms']
            report['cases'][key] = dict(**results, delta=delta, budget_pss_kib=budget, checks=checks)
            failed |= not all(checks.values())
            (args.output / 'report.json').write_text(json.dumps(report, indent=2)+'\n')
    report['status'] = 'fail' if failed else 'partial' if report['skipped'] else 'pass'
    (args.output / 'report.json').write_text(json.dumps(report, indent=2)+'\n')
    print(f"{report['status']}: {args.output / 'report.json'}")
    return 1 if failed else 0


if __name__ == '__main__':
    raise SystemExit(main())
