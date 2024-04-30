#!/bin/bash -e

export BIANBU_LINUX_ARCHIVE=bianbu-linux-k1_plt-stability

WESTON_INI=buildroot-ext/board/spacemit/k1/plt_overlay/etc/xdg/weston/weston.ini

if [ -f $WESTON_INI ]
then
    sed -i 's/gui-main/stability/' $WESTON_INI
    make
    sed -i 's/stability/gui-main/' $WESTON_INI
else
    echo 'Missing $WESTON_INI'
    exit -1
fi
