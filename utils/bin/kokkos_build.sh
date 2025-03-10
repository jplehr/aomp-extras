#!/bin/bash
# Copyright(C) 2020 Advanced Micro Devices, Inc. All rights reserved. 
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
# of the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
# DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.
#
#  kokkos_build.sh: Script to clone and build kokkos for a specific GPU 
#                   This will build kokkos in directory $HOME/kokkos_build.<GPUNAME>
#
#
#  Written by Greg Rodgers  Gregory.Rodgers@amd.com
#
PROGVERSION="X.Y-Z"
#

AOMP=${AOMP:-_AOMP_INSTALL_DIR_}
if [ ! -d $AOMP ] ; then
   echo "ERROR:  AOMP is not installed in $AOMP"
   exit 1
fi

GIT_DIR=${GIT_DIR:-$HOME/git}
KOKKOS_SOURCE_DIR=${KOKKOS_SOURCE_DIR:-$GIT_DIR/kokkos}
KOKKOS_URL=https://github.com/kokkos/kokkos.git
KOKKOS_BRANCH=develop
KOKKOS_TAG=7c76889
NUM_THREADS=${NUM_THREADS:-8}

if [[ "$AOMP" =~ "opt" ]]; then
  echo Set AOMP_GPU with rocm_agent_enumerator.
  export DETECTED_GPU=$($AOMP/../bin/rocm_agent_enumerator | grep -m 1 -E gfx[^0]{1}.{2})
else
  echo Set AOMP_GPU with mygpu.
  if [ -a $AOMP/bin/mygpu ]; then
    export DETECTED_GPU=$($AOMP/bin/mygpu)
  else
    export DETECTED_GPU=$($AOMP/../bin/mygpu)
  fi
fi

AOMP_GPU=${AOMP_GPU:-$DETECTED_GPU}

# Determine if AOMP_GPU is supported in KOKKOS. Currently looks for AMD only.
kokkos_regex="gfx(.*)"
supported_arch="900 906 908"
declare -A arch_array
echo "Supported KOKKOS GFX: $supported_arch"

# Store arch in associative array
for arch in $supported_arch; do
  arch_array[$arch]=""
done

if [[ "$AOMP_GPU" =~ $kokkos_regex ]]; then
  matched_arch=${BASH_REMATCH[1]}
else
  echo "Error: Cannot determine KOKKOS_ARCH"
fi

# Check if matched_arch is present in array
if [[  -v arch_array[$matched_arch] ]]; then
  KOKKOS_ARCH=${KOKKOS_ARCH:-$matched_arch}
else
  echo "Error: gfx"$matched_arch" is currently not supported in KOKKOS"
  exit 1
fi

echo AOMP_GPU    = $AOMP_GPU
echo KOKKOS_ARCH = $KOKKOS_ARCH
echo AOMP        = $AOMP

if [ "$AOMP_GPU" == "" ] || [ "$AOMP_GPU" == "unknown" ]; then
  echo Error: AOMP_GPU not properly set...exiting.
  exit 1
fi

KOKKOS_BUILD_PREFIX=${KOKKOS_BUILD_PREFIX:-$HOME}

if [ -f /usr/local/cmake/bin/cmake ] ; then
  AOMP_CMAKE=${AOMP_CMAKE:-/usr/local/cmake/bin/cmake}
else
  AOMP_CMAKE=${AOMP_CMAKE:-cmake}
fi

if [ "$1" == "hip" ] ; then
   kokkos_backend="hip"
   KOKKOS_BUILD_DIR=${KOKKOS_BUILD_DIR:-$KOKKOS_BUILD_PREFIX/kokkos_build_hip.$AOMP_GPU}
   KOKKOS_INSTALL_DIR=${KOKKOS_INSTALL_DIR:-$KOKKOS_BUILD_PREFIX/kokkos_hip.$AOMP_GPU}
else
   kokkos_backend="openmp"
   KOKKOS_BUILD_DIR=${KOKKOS_BUILD_DIR:-$KOKKOS_BUILD_PREFIX/kokkos_build_omp.$AOMP_GPU}
   KOKKOS_INSTALL_DIR=${KOKKOS_INSTALL_DIR:-$KOKKOS_BUILD_PREFIX/kokkos_omp.$AOMP_GPU}
fi

# Clean install, build and source directories
if [ "$1" == "clean" ] ; then
  echo Cleaning:
  echo SOURCE_DIR: $KOKKOS_SOURCE_DIR
  echo BUILD_DIR: $KOKKOS_BUILD_DIR
  echo INSTALL_DIR: $KOKKOS_INSTALL_DIR
  rm -rf $KOKKOS_SOURCE_DIR
  rm -rf $KOKKOS_BUILD_DIR
  rm -rf $KOKKOS_INSTALL_DIR
  exit 0
fi

function patchkokkos(){
patchfile1=/tmp/kokkos1_$$.patch
/bin/cat >$patchfile1 <<"EOF"
diff --git a/core/unit_test/CMakeLists.txt b/core/unit_test/CMakeLists.txt
index b616e80f..0495f630 100644
--- a/core/unit_test/CMakeLists.txt
+++ b/core/unit_test/CMakeLists.txt
@@ -138,7 +138,7 @@ foreach(Tag Threads;Serial;OpenMP;Cuda;HPX;OpenMPTarget;HIP;SYCL)
         Reducers_a
         Reducers_b
         Reducers_c
-        Reducers_d
+        #Reducers_d
         Reductions_DeviceView
         Scan
         SharedAlloc
@@ -309,7 +309,7 @@ IF(KOKKOS_ENABLE_OPENMPTARGET
     ${CMAKE_CURRENT_BINARY_DIR}/openmptarget/TestOpenMPTarget_Reducers_a.cpp
     ${CMAKE_CURRENT_BINARY_DIR}/openmptarget/TestOpenMPTarget_Reducers_b.cpp
     ${CMAKE_CURRENT_BINARY_DIR}/openmptarget/TestOpenMPTarget_Reducers_c.cpp
-    ${CMAKE_CURRENT_BINARY_DIR}/openmptarget/TestOpenMPTarget_Reducers_d.cpp
+#    ${CMAKE_CURRENT_BINARY_DIR}/openmptarget/TestOpenMPTarget_Reducers_d.cpp
     ${CMAKE_CURRENT_BINARY_DIR}/openmptarget/TestOpenMPTarget_ViewMapping_b.cpp
     ${CMAKE_CURRENT_BINARY_DIR}/openmptarget/TestOpenMPTarget_TeamBasic.cpp
     ${CMAKE_CURRENT_BINARY_DIR}/openmptarget/TestOpenMPTarget_Scan.cpp
EOF
  echo patch -p1 $patchfile1
  patch -p1 < $patchfile1
  rm $patchfile1
}

mkdir -p $GIT_DIR
cd $GIT_DIR
if [ ! -d $KOKKOS_SOURCE_DIR ] ; then 
   echo git clone -b develop $KOKKOS_URL
   git clone -b $KOKKOS_BRANCH $KOKKOS_URL
   if [ $? != 0 ] ; then 
      echo
      echo "ERROR: Could not git clone $KOKKOS_URL "
      echo
      exit 1
   fi
   cd $KOKKOS_SOURCE_DIR
   git checkout $KOKKOS_TAG
   if [ "$PATCH" != 0 ]; then
     echo "patching..."
     patchkokkos
   else
     echo "PATCH=0 - not patching KOKKOS"
   fi
else 
   echo
   echo "  WARNING: Directory $KOKKOS_SOURCE_DIR already exists."
   echo "           No changes will be made to the sources"
   echo
fi

if [ -d $KOKKOS_BUILD_DIR ] ; then 
   echo
   echo " FRESH START:  Removing $KOKKOS_BUILD_DIR"
   echo "               rm -rf $KOKKOS_BUILD_DIR"
   echo
   rm -rf  $KOKKOS_BUILD_DIR
fi
if [ -d $KOKKOS_INSTALL_DIR ] ; then 
   echo "               rm -rf $KOKKOS_INSTALL_DIR"
   echo
   rm -rf  $KOKKOS_INSTALL_DIR
fi
mkdir -p $KOKKOS_BUILD_DIR
cd $KOKKOS_BUILD_DIR

UNAMEP=`uname -m`
AOMP_CPUTARGET="${UNAMEP}-pc-linux-gnu"
if [ "$UNAMEP" == "ppc64le" ] ; then
   AOMP_CPUTARGET="ppc64le-linux-gnu"
fi

if [ "$kokkos_backend" == "hip" ] ; then
   echo "ERROR: hip backend for kokkos not supported yet"
   exit 1
else
   # ensure kokkos finds AOMP clang first
   export PATH=$AOMP/bin:$PATH
   ARGS=( 
    -D CMAKE_BUILD_TYPE=Debug
    -D CMAKE_CXX_STANDARD=17
    -D CMAKE_CXX_EXTENSIONS=OFF
    -D CMAKE_INSTALL_PREFIX=$KOKKOS_INSTALL_DIR
    -D Kokkos_ARCH_VEGA"$KOKKOS_ARCH"=ON
    -D CMAKE_CXX_COMPILER=$AOMP/bin/clang++
    -D Kokkos_ENABLE_OPENMP=ON
    -D Kokkos_ENABLE_OPENMPTARGET=ON
    -D Kokkos_ENABLE_COMPILER_WARNINGS=ON
    -D Kokkos_ENABLE_TESTS=ON
   )
   cmake "${ARGS[@]}" $KOKKOS_SOURCE_DIR
fi
if [ $? != 0 ] ; then 
   echo
   echo "ERROR in Kokkos cmake"
   echo "If HWLOC is not found, set environment variable HWLOC_DIR=/path/to/hwloc."
   echo
   exit 1
fi

echo
echo "CMAKE done in directory $KOKKOS_BUILD_DIR"
echo
echo "Starting build ..."

echo make -j$NUM_THREADS
make -j$NUM_THREADS

if [ $? != 0 ] ; then 
   echo "ERROR in Kokkos build"
   exit 1
fi

make install
if [ $? != 0 ] ; then 
   echo "ERROR in Kokkos install"
   exit 1
fi
echo
echo " Kokkos Version $KOKKOS_TAG installed successfully into directory "
echo " $KOKKOS_INSTALL_DIR"
echo
