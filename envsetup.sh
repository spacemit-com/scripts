#!/bin/sh

#set -e 
export BIANBU_LINUX_ROOT_DIR=$PWD
m() {
    make -C $BIANBU_LINUX_ROOT_DIR  $@
}
