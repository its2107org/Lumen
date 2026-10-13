#!/usr/bin/env python3
"""A pretend WiZ colour bulb for the build checks. Answers on port 38899 like a real one."""
import json
import socket
import sys

state = {"mac": "a8bb50aabbcc", "rssi": -52, "state": True, "sceneId": 0, "temp": 2700, "dimming": 80}
log = open(sys.argv[1] if len(sys.argv) > 1 else "fake_bulb.log", "a", buffering=1)

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(("0.0.0.0", 38899))
print("Pretend bulb listening on 38899", flush=True)

while True:
    data, addr = sock.recvfrom(4096)
    try:
        msg = json.loads(data)
    except ValueError:
        continue
    method, params = msg.get("method"), msg.get("params", {})
    log.write(f"{addr[0]} {method} {json.dumps(params, sort_keys=True)}\n")
    if method == "getPilot":
        reply = {"method": method, "env": "pro", "result": dict(state)}
    elif method == "setPilot":
        if "temp" in params or "r" in params or "sceneId" in params:
            for key in ("temp", "r", "g", "b", "c", "w", "sceneId", "speed"):
                state.pop(key, None)
            state["sceneId"] = 0
        state.update(params)
        reply = {"method": method, "env": "pro", "result": {"success": True}}
    elif method == "getSystemConfig":
        reply = {"method": method, "env": "pro", "result": {"mac": state["mac"], "homeId": 1, "roomId": 1,
                 "moduleName": "ESP01_SHRGB1C_31", "fwVersion": "1.31.0", "groupId": 0, "ping": 0}}
    elif method == "getModelConfig":
        reply = {"method": method, "env": "pro", "result": {"cctRange": [2200, 2700, 6500, 6500], "renderFactor": [255] * 10}}
    else:
        reply = {"method": method, "env": "pro", "error": {"code": -32601, "message": "Method not found"}}
    sock.sendto(json.dumps(reply).encode(), addr)
