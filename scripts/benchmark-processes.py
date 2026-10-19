#!/usr/bin/env python3
"""Strict Linux /proc sampler shared by live and isolated fixture benchmarks."""
import argparse
import csv
import os
from pathlib import Path
import sys
import time


class InvalidSample(RuntimeError):
    pass


def stat(pid, proc=Path('/proc')):
    try:
        fields = (proc / str(pid) / 'stat').read_text().rsplit(')', 1)[1].split()
        return int(fields[19]), int(fields[11]) + int(fields[12])
    except (OSError, ValueError, IndexError) as error:
        raise InvalidSample(f'cannot read process identity/CPU counters for {pid}') from error


def counters(pid, identity, memory=False, proc=Path('/proc')):
    before, ticks = stat(pid, proc)
    if before != identity:
        raise InvalidSample(f'process {pid} restarted')
    try:
        fields = dict(line.split(':', 1) for line in (proc / str(pid) / 'status').read_text().splitlines() if ':' in line)
        switches = sum(int(fields[key]) for key in ('voluntary_ctxt_switches', 'nonvoluntary_ctxt_switches'))
        pss = rss = 0
        if memory:
            fields = dict(line.split(':', 1) for line in (proc / str(pid) / 'smaps_rollup').read_text().splitlines() if ':' in line)
            pss, rss = (int(fields[key].split()[0]) for key in ('Pss', 'Rss'))
        if stat(pid, proc)[0] != identity:
            raise InvalidSample(f'process {pid} restarted while counters were read')
        return ticks, switches, pss, rss
    except (OSError, ValueError, KeyError, IndexError) as error:
        raise InvalidSample(f'cannot read required counters for {pid}') from error


def processes(kind, pid=None, proc=Path('/proc')):
    found = {}
    shell = []
    if kind == 'fixture':
        return {pid: ('shell', stat(pid, proc)[0])}
    for directory in proc.glob('[0-9]*'):
        try:
            executable = os.readlink(directory / 'exe')
            if kind == 'desktop' and executable == '/opt/spotify/spotify':
                role = 'spotify'
            elif kind == 'plugin' and executable.endswith(('/omarchy-spotify-backend', '/spotifyd')):
                role = 'backend' if executable.endswith('/omarchy-spotify-backend') else 'spotifyd'
            elif kind == 'plugin' and Path(executable).name in ('quickshell', 'qs'):
                command = (directory / 'cmdline').read_bytes().replace(b'\0', b' ').decode()
                if ' -n -p /usr/share/omarchy/shell' not in command:
                    continue
                role = 'shell'
                shell.append(int(directory.name))
            else:
                continue
        except (OSError, UnicodeError):
            continue
        process_id = int(directory.name)
        found[process_id] = role, stat(process_id, proc)[0]
    if kind == 'plugin' and len(shell) != 1:
        raise InvalidSample(f'expected exactly one Omarchy quickshell process; found {len(shell)}')
    if not found:
        raise InvalidSample('official Spotify client is not running')
    return found


def sample(kind, duration, pid=None, discover=processes, read=counters, sleep=time.sleep, clock=time.monotonic):
    initial = discover(kind, pid)
    before = {p: read(p, identity) for p, (_, identity) in initial.items()}
    if discover(kind, pid) != initial:
        raise InvalidSample('process set or start identity changed before sample')
    start = clock()
    sleep(duration)
    elapsed = clock() - start
    if discover(kind, pid) != initial:
        raise InvalidSample('process set or start identity changed during sample')
    after = {p: read(p, identity, True) for p, (_, identity) in initial.items()}
    if discover(kind, pid) != initial:
        raise InvalidSample('process set or start identity changed while memory was read')
    delta = [sum(after[p][i] - before[p][i] for p in initial) for i in (0, 1)]
    if min(delta) < 0:
        raise InvalidSample('process counters decreased')
    memory = {}
    for p, (role, _) in initial.items():
        group = 'shell' if role == 'shell' else 'playback'
        values = memory.setdefault(group, [0, 0])
        values[0] += after[p][2]
        values[1] += after[p][3]
    return initial, memory, elapsed, delta[0] / os.sysconf('SC_CLK_TCK') * 100 / elapsed, delta[1] / elapsed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('kind', choices=('plugin', 'desktop', 'fixture'))
    parser.add_argument('state')
    parser.add_argument('seconds', type=int, nargs='?', default=10)
    parser.add_argument('--pid', type=int)
    args = parser.parse_args()
    if not args.state or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-' for c in args.state) or not 2 <= args.seconds <= 60:
        parser.error('state must be an alphanumeric label; seconds must be 2–60')
    if args.kind == 'fixture' and not args.pid:
        parser.error('--pid is required for fixture sampling')
    try:
        identities, memory, elapsed, cpu, switches = sample(args.kind, args.seconds, args.pid)
    except InvalidSample as error:
        print(f'benchmark: invalid sample: {error}', file=sys.stderr)
        return 1
    writer = csv.writer(sys.stdout, lineterminator='\n')
    shell = memory.get('shell', [0, 0])
    playback = memory.get('playback', [0, 0])
    if args.kind == 'desktop':
        writer.writerow(['state', 'seconds', 'spotify_pids', 'process_count', 'spotify_pss_kib', 'spotify_rss_kib', 'cpu_percent', 'scheduler_switches_per_second'])
        writer.writerow([args.state, f'{elapsed:.6f}', '+'.join(map(str, sorted(identities))), len(identities), *playback, f'{cpu:.3f}', f'{switches:.3f}'])
    else:
        shell_pid = next(p for p, (role, _) in identities.items() if role == 'shell')
        others = sorted(p for p in identities if p != shell_pid)
        roles = {identities[p][0] for p in others}
        runtime = next(iter(roles)) if len(roles) == 1 else 'mixed' if roles else 'none'
        writer.writerow(['state', 'seconds', 'shell_pid', 'playback_runtime', 'playback_pid', 'shell_pss_kib', 'shell_rss_kib', 'playback_pss_kib', 'playback_rss_kib', 'total_pss_kib', 'total_rss_kib', 'cpu_percent', 'scheduler_switches_per_second'])
        writer.writerow([args.state, f'{elapsed:.6f}', shell_pid, runtime, '+'.join(map(str, others)) or 'none', *shell, *playback, shell[0]+playback[0], shell[1]+playback[1], f'{cpu:.3f}', f'{switches:.3f}'])
    return 0


if __name__ == '__main__':
    sys.exit(main())
