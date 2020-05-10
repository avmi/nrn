#!/bin/bash
set -xe
# A script to loop over the available pythons installed
# on Linux/OSX and build wheels
#
# Note: It should be involed from nrn directory
#
# PREREQUESITES:
#  - cmake (>=3.5)
#  - flex
#  - bison
#  - python >= 3.5
#  - cython
#  - MPI
#  - X11
#  - C/C++ compiler
#  - ncurses

set -e

if [ ! -f setup.py ]; then
    echo "Error: setup.py not found. Please launch $0 from the nrn root dir"
    exit 1
fi

setup_venv() {
    local py_bin="$1"
    local py_ver=$("$py_bin" -c "import sys; print('%d%d' % tuple(sys.version_info)[:2])")
    local venv_dir="nrn_build_venv$py_ver"

    if [ "$py_ver" -lt 35 ]; then
        echo "[SKIP] Python $py_ver no longer supported"
        skip=1
        return 0
    fi

    echo " - Creating $venv_dir: $py_bin -m venv $venv_dir"
    "$py_bin" -m venv "$venv_dir"
    . "$venv_dir/bin/activate"

    if ! pip install -U pip setuptools wheel; then
        curl https://bootstrap.pypa.io/get-pip.py | python
        pip install -U setuptools wheel
    fi
}


build_wheel_linux() {
    echo "[BUILD WHEEL] Building with interpreter $1"
    local skip=
    setup_venv "$1"
    (( $skip )) && return 0

    echo " - Installing build requirements"
    pip install git+https://github.com/ferdonline/auditwheel@fix/rpath_append
    pip install -i https://nero-mirror.stanford.edu/pypi/web/simple -r packaging/python/build_requirements.txt

    echo " - Building..."
    rm -rf dist build
    if [ "$2" == "--bare" ]; then
        python setup.py bdist_wheel
    else
        python setup.py build_ext --cmake-prefix=/opt/ncurses --cmake-defs="NRN_MPI_DYNAMIC=$3" bdist_wheel
    fi

    if [ "$TRAVIS" = true ] ; then
        echo " - Skipping repair on Travis..."
        mkdir wheelhouse && cp dist/*.whl wheelhouse/
    else
        echo " - Repairing..."
        auditwheel repair dist/*.whl
    fi

    deactivate
}


build_wheel_osx() {
    echo "[BUILD WHEEL] Building with interpreter $1"
    local skip=
    setup_venv "$1"
    (( $skip )) && return 0

    echo " - Installing build requirements"
    pip install -U delocate -r packaging/python/build_requirements.txt

    echo " - Building..."
    rm -rf dist build
    if [ "$2" == "--bare" ]; then
        python setup.py bdist_wheel
    else
        python setup.py build_ext --cmake-defs="NRN_MPI_DYNAMIC=$3" bdist_wheel
    fi

    echo " - Repairing..."
    delocate-wheel -w wheelhouse -v dist/*.whl  # we started clean, there's a single wheel

    deactivate
}


# MAIN

case "$1" in

  linux)
    MPI_INCLUDE_HEADERS="/opt/openmpi/include;/opt/mpich/include"
    for py_bin in /opt/python/cp3*/bin/python; do
        build_wheel_linux "$py_bin" "$2" "$MPI_INCLUDE_HEADERS"
    done
    ;;

  osx)
    MPI_INCLUDE_HEADERS="/usr/local/opt/openmpi/include;/usr/local/opt/mpich/include"
    for py_bin in /Library/Frameworks/Python.framework/Versions/3*/bin/python3; do
        build_wheel_osx "$py_bin" "$2" "$MPI_INCLUDE_HEADERS"
    done
    ;;

  travis)
    if [ "$TRAVIS_OS_NAME" == "osx" ]; then
        MPI_INCLUDE_HEADERS="/usr/local/opt/openmpi/include;/usr/local/opt/mpich/include"
        build_wheel_osx $(which python3) "$2" "$MPI_INCLUDE_HEADERS"
    else
        MPI_INCLUDE_HEADERS="/usr/lib/x86_64-linux-gnu/openmpi/include;/usr/include/mpich"
        build_wheel_linux $(which python3) "$2" "$MPI_INCLUDE_HEADERS"
    fi
    ls wheelhouse/
    ;;

  *)
    echo "Usage: $(basename $0) < linux | osx > [--bare]"
    exit 1
    ;;

esac