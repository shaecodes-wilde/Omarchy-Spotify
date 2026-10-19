#!/usr/bin/env python3
"""Exercise the actual Quickshell socket client against a private fake backend."""
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]


def check_case(case):
    with tempfile.TemporaryDirectory(prefix="spotify-backend-test-") as directory:
        test = Path(directory)
        (test / "omarchy-spotify").mkdir()
        for name in ("BackendClient.qml", "Api.js"):
            shutil.copyfile(ROOT / name, test / name)
        server = socket.socket(socket.AF_UNIX)
        server.bind(str(test / "omarchy-spotify/backend.sock"))
        server.listen(1)
        server.settimeout(5)
        failures = []

        def serve():
            try:
                with server.accept()[0] as client:
                    stream = client.makefile("r")
                    hello = json.loads(stream.readline())
                    assert hello["command"] == "hello", hello
                    version = 2 if case == "version" else 1
                    client.sendall((json.dumps({"type": "response", "v": version,
                        "id": hello["id"], "ok": True,
                        "result": {"protocol_version": version}}) + "\n").encode())
                    if case == "version":
                        assert stream.readline() == ""
                        return
                    request = json.loads(stream.readline())
                    assert request["command"] == "load"
                    if case == "disconnect":
                        return
                    assert stream.readline() == ""  # Timeout closes the fixture, without a retry.
            except Exception as error:
                failures.append(error)
            finally:
                server.close()

        worker = threading.Thread(target=serve, daemon=True)
        worker.start()
        (test / "shell.qml").write_text('''import QtQuick
import Quickshell
ShellRoot {
  id: tests
  property int callbacks: 0
  property int ticks: 0
  property bool sent: false
  BackendClient {
    id: client
    wanted: true
    requestTimeoutMs: 120
  }
  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      tests.ticks++
      if (tests.ticks > 150) throw new Error("Client test timed out")
      if ("CASE" === "version") {
        if (client.errorMessage.indexOf("unsupported") < 0) return
        if (client.ready || client.pendingCount) throw new Error("Unsupported backend accepted")
        client.wanted = false
        console.log("BACKEND_CLIENT_PASS")
        Qt.quit()
      } else if (client.ready && !tests.sent) {
        tests.sent = true
        client.sendCommand("load", { uris: ["spotify:track:test"] }, function(ok, result, error, unknown) {
          tests.callbacks++
          if (ok || !unknown) throw new Error("Uncertain load was reported as safe to retry")
          if (client.pendingCount) throw new Error("Pending callbacks survived failure")
          // A late reply and an obsolete socket cannot complete the callback twice.
          client.handleLine(JSON.stringify({v:1,type:"response",id:2,ok:true,result:{}}))
          client.handleLine(JSON.stringify({v:1,type:"event",state:{protocol_version:1,lifecycle:"error"}}), tests)
          if (client.lifecycle === "error") throw new Error("Stale socket event accepted")
          client.wanted = false
          finish.start()
        })
      }
    }
  }
  Timer {
    id: finish
    interval: 40
    onTriggered: {
      if (tests.callbacks !== 1 || client.pendingCount) throw new Error("Callback did not fail exactly once")
      console.log("BACKEND_CLIENT_PASS")
      Qt.quit()
    }
  }
}
'''.replace("CASE", case))
        env = dict(os.environ, XDG_RUNTIME_DIR=directory, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="generic", NO_AT_BRIDGE="1")
        env.pop("WAYLAND_DISPLAY", None)
        result = subprocess.run(["qs", "--no-color", "-p", directory], env=env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=8)
        worker.join(timeout=1)
        assert result.returncode == 0 and "BACKEND_CLIENT_PASS" in result.stdout, result.stdout
        assert not failures, failures
        assert not worker.is_alive(), "Fake backend did not finish"
        print(f"Backend client {case} passed")


if __name__ == "__main__":
    for scenario in ("disconnect", "timeout", "version"):
        check_case(scenario)
