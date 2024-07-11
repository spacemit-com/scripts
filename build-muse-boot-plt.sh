#!/bin/bash -e

repos=()

while IFS= read -r repo
do
    repos+=("$repo")
done < <(repo list | awk -F ':' '{ gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); print $1 }')

for repo in "${repos[@]}"
do
    pushd $repo > /dev/null
    current=`git rev-parse --abbrev-ref HEAD`
    popd > /dev/null
    if [ "$repo" == "bsp-src/uboot-2022.10" -o "$repo" == "package-src/factorytest" ]
    then
        if [ "$current" != "muse-book" ]
        then
            echo "$repo not on muse-book branch"
            exit 1
        fi
    else
        if [ "$current" != "k1-dev" ]
        then
            echo "$repo not on k1-dev branch"
            exit 1
        fi
    fi
done

if [ -f env.mk ]
then
    . env.mk
else
    echo "env.mk not exist, 'make envconfig' firstly"
    exit 1
fi

if [ $MAKEFILE != "output/k1_plt/Makefile" ]
then
    echo "not plt environment"
    exit 1
fi

# make

pushd output/k1_plt/images > /dev/null
version=`cat ../target/etc/bianbu_version`
SDCARD_IMAGE=bianbu-linux-k1_plt-sdcard-MUSE-Book-$version.zip
rm -f $SDCARD_IMAGE
zip -r $SDCARD_IMAGE bianbu-linux-k1_plt-sdcard.img
IMAGE=bianbu-linux-k1_plt-MUSE-Book-$version.zip
rm -f $IMAGE
cp -v bianbu-linux-k1_plt.zip $IMAGE
popd > /dev/null