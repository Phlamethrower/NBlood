#!/bin/bash

get_abs_path()
{
    echo "$(cd "$1" && pwd)"
}

get_num_logical_cpus()
{
    getconf _NPROCESSORS_ONLN 2>/dev/null || getconf NPROCESSORS_ONLN 2>/dev/null || echo 1
}


# Change directory to the NBlood root:

sourcedir="$(dirname "${BASH_SOURCE[0]}")"
sourcedir="$(get_abs_path "$sourcedir/..")"

pushd "${sourcedir}" >/dev/null

# Build:

cpus=$(get_num_logical_cpus)

make blood PLATFORM=LINUX SUBPLATFORM=RISCOS USE_OPENGL=0 NOASM=1 WITHOUT_GTK=1 USE_LIBVPX=0 HAVE_GTK2=0 SDL_TARGET=1 HAVE_FLAC=0 -j ${cpus}
