#!/usr/bin/env python

import tarfile
import os
import requests
import sys

update='dl_update.tar'
server='http://archive.spacemit.com/'
dl_dir='buildroot/dl'

args = sys.argv[1:]

for i in range(0, len(args), 2):
    if args[i] == '-d':
        dl_dir=args[i+1]
    else:
        print(f'Usage: {sys.argv[0]} [-d DIR]')
        sys.exit(1)

if os.path.exists(update):
    print(f'{update} is exits, remove it first')
    sys.exit(1)

print('checking update...')
files = []
ignore_dirs = [
    f'{dl_dir}/toolchain-external-custom',
    f'{dl_dir}/onnx-runtime'
]

for root, dirs, filenames in os.walk(dl_dir):
    if root in ignore_dirs:
        print(f'ignore {root}')
        continue

    for filename in filenames:
        if filename != '.lock':
            file = root + '/' + filename
            try:
                url = server + '/' + file
                response = requests.head(url)
                if response.status_code == 200:
                    continue
                elif response.status_code == 404:
                    files.append(file)
                else:
                    print(f'Request error: {url}')
                    sys.exit(1)
            except requests.RequestException as e:
                print(f'Request error: {e}')
                sys.exit(1)

if not files:
    print('nothing update')
    sys.exit(0)

with tarfile.open(update, 'w') as tar:
    print(f'create {update}...')
    for file in files:
        print(f'add {file}')
        tar.add(file)
