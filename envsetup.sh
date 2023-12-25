#!/bin/sh

#set -e
export BIANBU_LINUX_ROOT_DIR=$(dirname $(readlink -f ${BASH_SOURCE[0]}))/..
m() {
    make -C $BIANBU_LINUX_ROOT_DIR  $@
}
