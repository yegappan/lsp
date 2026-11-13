#!/usr/bin/env python3
"""Stub language server used to test stopping a language server.

Usage: stub_lspserver.py {logfile} [--ignore-exit]

Each received message is appended to {logfile} as a line of JSON.  A
"shutdown" request with a "params" member is rejected, like strict servers
do.  With --ignore-exit the server exits only when stdin is closed.
"""
import json
import sys


def read_message():
    length = 0
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        line = line.strip()
        if not line:
            break
        name, _, value = line.partition(b':')
        if name.lower() == b'content-length':
            length = int(value)
    return json.loads(sys.stdin.buffer.read(length))


def send_message(msg):
    msg['jsonrpc'] = '2.0'
    body = json.dumps(msg).encode()
    sys.stdout.buffer.write(b'Content-Length: %d\r\n\r\n' % len(body) + body)
    sys.stdout.buffer.flush()


def main():
    logfile = sys.argv[1]
    ignore_exit = '--ignore-exit' in sys.argv
    shutdown_ok = False
    while True:
        msg = read_message()
        if msg is None:
            break
        with open(logfile, 'a') as log:
            log.write(json.dumps(msg) + '\n')
        method = msg.get('method')
        if method == 'initialize':
            send_message({'id': msg['id'], 'result': {'capabilities': {}}})
        elif method == 'shutdown':
            if 'params' in msg:
                send_message({'id': msg['id'], 'error': {
                    'code': -32602, 'message': 'Unexpected params'}})
            else:
                shutdown_ok = True
                send_message({'id': msg['id'], 'result': None})
        elif method == 'exit' and not ignore_exit:
            break
        elif 'id' in msg and method:
            send_message({'id': msg['id'], 'error': {
                'code': -32601, 'message': 'Method not found'}})
    sys.exit(0 if shutdown_ok else 1)


main()
