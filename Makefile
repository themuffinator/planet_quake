# Quake3 Unix Makefile
#
# Nov '98 by Zoid <zoid@idsoftware.com>
#
# Loki Hacking by Bernd Kreimeier
#  and a little more by Ryan C. Gordon.
#  and a little more by Rafael Barrero
#  and a little more by the ioq3 cr3w
#
# GNU Make required
#
COMPILE_PLATFORM=$(shell uname | sed -e 's/_.*//' | tr '[:upper:]' '[:lower:]' | sed -e 's/\//_/g')
COMPILE_ARCH=$(shell uname -m | sed -e 's/i.86/x86/' | sed -e 's/^arm.*/arm/')

ifeq ($(COMPILE_PLATFORM),mingw32)
  ifeq ($(COMPILE_ARCH),i386)
    COMPILE_ARCH=x86
  endif
endif

BUILD_CLIENT     = 1
BUILD_SERVER     = 1

USE_SDL          = 0
USE_CURL         = 1
USE_LOCAL_HEADERS= 0
USE_VULKAN       = 0
#USE_VULKAN_API   = 0

USE_RENDERER_DLOPEN = 0

CNAME            = quake3e
DNAME            = quake3e.ded

RENDERER_PREFIX  = $(CNAME)

ifeq ($(V),1)
echo_cmd=@:
Q=
else
echo_cmd=@echo
Q=@
endif

#############################################################################
#
# If you require a different configuration from the defaults below, create a
# new file named "Makefile.local" in the same directory as this file and define
# your parameters there. This allows you to change configuration without
# causing problems with keeping up to date with the repository.
#
#############################################################################
-include Makefile.local

ifeq ($(COMPILE_PLATFORM),cygwin)
  PLATFORM=mingw32
endif

ifndef PLATFORM
PLATFORM=$(COMPILE_PLATFORM)
endif
export PLATFORM

ifeq ($(PLATFORM),mingw32)
  MINGW=1
endif
ifeq ($(PLATFORM),mingw64)
  MINGW=1
endif

ifeq ($(COMPILE_ARCH),i86pc)
  COMPILE_ARCH=x86
endif

ifeq ($(COMPILE_ARCH),amd64)
  COMPILE_ARCH=x86_64
endif
ifeq ($(COMPILE_ARCH),x64)
  COMPILE_ARCH=x86_64
endif

ifndef ARCH
ARCH=$(COMPILE_ARCH)
endif
export ARCH

ifneq ($(PLATFORM),$(COMPILE_PLATFORM))
  CROSS_COMPILING=1
else
  CROSS_COMPILING=0

  ifneq ($(ARCH),$(COMPILE_ARCH))
    CROSS_COMPILING=1
  endif
endif
export CROSS_COMPILING

ifndef COPYDIR
COPYDIR="/usr/local/games/quake3"
endif

ifndef DESTDIR
DESTDIR=/usr/local/games/quake3
endif

ifndef MOUNT_DIR
MOUNT_DIR=code
endif

ifndef BUILD_DIR
BUILD_DIR=build
endif

ifndef GENERATE_DEPENDENCIES
GENERATE_DEPENDENCIES=1
endif

ifndef USE_CCACHE
USE_CCACHE=0
endif
export USE_CCACHE

ifndef USE_CODEC_VORBIS
USE_CODEC_VORBIS=0
endif

ifndef USE_LOCAL_HEADERS
USE_LOCAL_HEADERS=1
endif

ifndef USE_CURL
USE_CURL=1
endif

ifndef USE_CURL_DLOPEN
  ifdef MINGW
    USE_CURL_DLOPEN=0
  else
    USE_CURL_DLOPEN=1
  endif
endif

ifneq ($(USE_RENDERER_DLOPEN),0)
USE_VULKAN=1
endif

ifneq ($(USE_VULKAN),0)
USE_VULKAN_API=1
endif


#############################################################################

BD=$(BUILD_DIR)/debug-$(PLATFORM)-$(ARCH)
BR=$(BUILD_DIR)/release-$(PLATFORM)-$(ARCH)
ADIR=$(MOUNT_DIR)/asm
CDIR=$(MOUNT_DIR)/client
SDIR=$(MOUNT_DIR)/server
RCDIR=$(MOUNT_DIR)/renderercommon
R1DIR=$(MOUNT_DIR)/renderer
R2DIR=$(MOUNT_DIR)/renderer2
RJSDIR=$(MOUNT_DIR)/rendererjs
RVDIR=$(MOUNT_DIR)/renderervk
RVSDIR=$(MOUNT_DIR)/renderervk/shaders/spirv
SDLDIR=$(MOUNT_DIR)/sdl
OGGDIR=$(MOUNT_DIR)/ogg
VORBISDIR=$(MOUNT_DIR)/vorbis
OPUSDIR=$(MOUNT_DIR)/opus-1.2.1
OPUSFILEDIR=$(MOUNT_DIR)/opusfile-0.9
CMDIR=$(MOUNT_DIR)/qcommon
UDIR=$(MOUNT_DIR)/unix
W32DIR=$(MOUNT_DIR)/win32
QUAKEJS=$(MOUNT_DIR)/xquakejs
BLIBDIR=$(MOUNT_DIR)/botlib
UIDIR=$(MOUNT_DIR)/ui
JPDIR=$(MOUNT_DIR)/jpeg-8c
LOKISETUPDIR=$(UDIR)/setup

bin_path=$(shell which $(1) 2> /dev/null)

STRIP=strip

ifneq ($(PKG_CONFIG_PATH),)
  PKG_CONFIG ?= pkg-config
endif

ifneq ($(call bin_path, $(PKG_CONFIG)),)
  SDL_INCLUDE ?= $(shell $(PKG_CONFIG) --silence-errors --cflags-only-I sdl2)
  SDL_LIBS ?= $(shell $(PKG_CONFIG) --silence-errors --libs sdl2)
  X11_INCLUDE ?= $(shell $(PKG_CONFIG) --silence-errors --cflags-only-I x11)
  X11_LIBS ?= $(shell $(PKG_CONFIG) --silence-errors --libs x11)
endif

# supply some reasonable defaults for SDL/X11?
ifeq ($(X11_INCLUDE),)
X11_INCLUDE = -I/usr/X11R6/include
endif
ifeq ($(X11_LIBS),)
X11_LIBS = -lX11
endif
ifeq ($(SDL_LIBS),)
SDL_LIBS = -lSDL2
endif

# extract version info
VERSION=$(shell grep "\#define Q3_VERSION" $(CMDIR)/q_shared.h | \
  sed -e 's/.*".* \([^ ]*\)"/\1/')

# common qvm definition
ifeq ($(ARCH),x86_64)
  HAVE_VM_COMPILED = true
else
ifeq ($(ARCH),x86)
  HAVE_VM_COMPILED = true
else
  HAVE_VM_COMPILED = false
endif
endif

BASE_CFLAGS =

ifdef DEFAULT_BASEDIR
  BASE_CFLAGS += -DDEFAULT_BASEDIR=\\\"$(DEFAULT_BASEDIR)\\\"
endif

ifeq ($(USE_LOCAL_HEADERS),1)
  BASE_CFLAGS += -DUSE_LOCAL_HEADERS=1
endif

ifeq ($(USE_CURL),1)
  BASE_CFLAGS += -DUSE_CURL
ifeq ($(USE_CURL_DLOPEN),1)
  BASE_CFLAGS += -DUSE_CURL_DLOPEN
else
  BASE_CFLAGS += -DCURL_STATICLIB
endif
endif

ifeq ($(USE_VULKAN_API),1)
  BASE_CFLAGS += -DUSE_VULKAN_API
endif

ifeq ($(GENERATE_DEPENDENCIES),1)
  BASE_CFLAGS += -MMD
endif

#############################################################################
# SETUP AND BUILD -- LINUX
#############################################################################

## Defaults
INSTALL=install
MKDIR=mkdir

ARCHEXT=

CLIENT_EXTRA_FILES=

ifeq ($(PLATFORM),linux)

  BASE_CFLAGS += -Wall -fno-strict-aliasing -Wimplicit -Wstrict-prototypes -pipe

  BASE_CFLAGS += -I/usr/include

  OPTIMIZE = -O2 -fvisibility=hidden

  ifeq ($(ARCH),x86_64)
    ARCHEXT = .x64
  else
  ifeq ($(ARCH),x86)
    OPTIMIZE += -march=i586 -mtune=i686
  endif
  endif

  SHLIBEXT = so
  SHLIBCFLAGS = -fPIC
  SHLIBLDFLAGS = -shared $(LDFLAGS)

  LDFLAGS=-ldl -lm -Wl,--hash-style=both

  ifeq ($(USE_SDL),1)
    BASE_CFLAGS += $(SDL_INCLUDE)
    CLIENT_LDFLAGS = $(SDL_LIBS)
  else
    BASE_CFLAGS += $(X11_INCLUDE)
    CLIENT_LDFLAGS = $(X11_LIBS)
  endif

  ifeq ($(USE_CODEC_VORBIS),1)
    CLIENT_LDFLAGS += -lvorbisfile -lvorbis -logg
  endif

  ifeq ($(ARCH),x86)
    # linux32 make ...
    BASE_CFLAGS += -m32
    LDFLAGS += -m32
  endif
	
  DEBUG_CFLAGS = $(BASE_CFLAGS) -DDEBUG -D_DEBUG -ggdb -O0
  RELEASE_CFLAGS = $(BASE_CFLAGS) -DNDEBUG $(OPTIMIZE)

else # ifeq Linux


#############################################################################
# SETUP AND BUILD -- MAC OS X
#############################################################################

ifeq ($(PLATFORM),darwin)
  HAVE_VM_COMPILED = 0
  USE_SDL = 1
	
  USE_RENDERER_DLOPEN = 0
  BUILD_RENDERER_OPENGL2 = 1
  USE_LOCAL_HEADERS = 0
  USE_CODEC_OPUS=0
  USE_CODEC_VORBIS=0
  LIBS = -framework Cocoa
  CLIENT_LIBS=
  RENDERER_LIBS=
  OPTIMIZEVM = -O3

  # Default minimum Mac OS X version
  ifeq ($(MACOSX_VERSION_MIN),)
    MACOSX_VERSION_MIN=10.7
  endif

  MACOSX_MAJOR=$(shell echo $(MACOSX_VERSION_MIN) | cut -d. -f1)
  MACOSX_MINOR=$(shell echo $(MACOSX_VERSION_MIN) | cut -d. -f2)
  ifeq ($(shell test $(MACOSX_MINOR) -gt 9; echo $$?),0)
    # Multiply and then remove decimal. 10.10 -> 101000.0 -> 101000
    MAC_OS_X_VERSION_MIN_REQUIRED=$(shell echo "$(MACOSX_MAJOR) * 10000 + $(MACOSX_MINOR) * 100" | bc | cut -d. -f1)
  else
    # Multiply by 100 and then remove decimal. 10.7 -> 1070.0 -> 1070
    MAC_OS_X_VERSION_MIN_REQUIRED=$(shell echo "$(MACOSX_VERSION_MIN) * 100" | bc | cut -d. -f1)
  endif

  LDFLAGS += -mmacosx-version-min=$(MACOSX_VERSION_MIN) -I/usr/local/include/SDL2 -L/usr/local/lib -lSDL2
  BASE_CFLAGS += -mmacosx-version-min=$(MACOSX_VERSION_MIN) \
                 -DMAC_OS_X_VERSION_MIN_REQUIRED=$(MAC_OS_X_VERSION_MIN_REQUIRED)

  ifeq ($(ARCH),ppc)
    BASE_CFLAGS += -arch ppc
  endif
  ifeq ($(ARCH),ppc64)
    BASE_CFLAGS += -arch ppc64
  endif
  ifeq ($(ARCH),x86)
    ARCHEXT = .x86
    OPTIMIZEVM += -march=prescott -mfpmath=sse
    # x86 vm will crash without -mstackrealign since MMX instructions will be
    # used no matter what and they corrupt the frame pointer in VM calls
    BASE_CFLAGS += -arch i386 -m32 -mstackrealign
  endif
  ifeq ($(ARCH),x86_64)
    ARCHEXT = .x86_64
    OPTIMIZEVM += -mfpmath=sse
    BASE_CFLAGS += -arch x86_64
  endif

  # When compiling on OSX for OSX, we're not cross compiling as far as the
  # Makefile is concerned, as target architecture is specified as a compiler
  # argument
  ifeq ($(COMPILE_PLATFORM),darwin)
    CROSS_COMPILING=0
  endif

  ifeq ($(CROSS_COMPILING),1)
    ifeq ($(ARCH),x86_64)
      CC=x86_64-apple-darwin13-cc
      RANLIB=x86_64-apple-darwin13-ranlib
    else
      ifeq ($(ARCH),x86)
        CC=i386-apple-darwin13-cc
        RANLIB=i386-apple-darwin13-ranlib
      else
        $(error Architecture $(ARCH) is not supported when cross compiling)
      endif
    endif
  endif

  BASE_CFLAGS += -fno-strict-aliasing -fno-common -pipe

  ifeq ($(USE_OPENAL),1)
    ifneq ($(USE_LOCAL_HEADERS),1)
      CLIENT_CFLAGS += -I/System/Library/Frameworks/OpenAL.framework/Headers
    endif
    ifneq ($(USE_OPENAL_DLOPEN),1)
      CLIENT_LIBS += -framework OpenAL
    endif
  endif

  ifeq ($(USE_CURL),1)
    BASE_CFLAGS += -DUSE_CURL
    ifneq ($(USE_CURL_DLOPEN),1)
      BASE_CFLAGS += -DUSE_CURL_DLOPEN
    endif
  endif

  BASE_CFLAGS += -D_THREAD_SAFE=1

  CLIENT_LIBS += -framework IOKit
  RENDERER_LIBS += -framework OpenGL

  ifeq ($(USE_LOCAL_HEADERS),1)
    # libSDL2-2.0.0.dylib for PPC is SDL 2.0.1 + changes to compile
    ifneq ($(findstring $(ARCH),ppc ppc64),)
      BASE_CFLAGS += -I$(SDLHDIR)/include-macppc
    else
      BASE_CFLAGS += -I$(SDLHDIR)/include
    endif

    # We copy sdlmain before ranlib'ing it so that subversion doesn't think
    #  the file has been modified by each build.
    LIBSDLMAIN=$(B)/libSDL2main.a
    LIBSDLMAINSRC=$(LIBSDIR)/macosx/libSDL2main.a
    CLIENT_LIBS += $(LIBSDIR)/macosx/libSDL2-2.0.0.dylib
    RENDERER_LIBS += $(LIBSDIR)/macosx/libSDL2-2.0.0.dylib
    CLIENT_EXTRA_FILES += $(LIBSDIR)/macosx/libSDL2-2.0.0.dylib
  else
    BASE_CFLAGS += -Wall \
		  -I/Library/Frameworks/SDL2.framework/Headers \
			-I/usr/local/include/SDL2
    CLIENT_LIBS += -framework SDL2 -framework OpenGL
    RENDERER_LIBS += -framework SDL2 -framework OpenGL
  endif

  OPTIMIZE = $(OPTIMIZEVM) -ffast-math

  SHLIBEXT=dylib
  SHLIBCFLAGS=-fPIC -fno-common
  SHLIBLDFLAGS=-dynamiclib $(LDFLAGS) -Wl,-U,_com_altivec

  NOTSHLIBCFLAGS=-mdynamic-no-pic
	
  DEBUG_CFLAGS=$(BASE_CFLAGS)
  RELEASE_CFLAGS=$(BASE_CFLAGS) \
		$(OPTIMIZE)
		
  LDFLAGS += $(CLIENT_LIBS)

else # ifeq darwin


#############################################################################
# SETUP AND BUILD -- MINGW32
#############################################################################

ifdef MINGW

  ifeq ($(CROSS_COMPILING),1)
    # If CC is already set to something generic, we probably want to use
    # something more specific
    ifneq ($(findstring $(strip $(CC)),cc gcc),)
      CC=
    endif

    # We need to figure out the correct gcc and windres
    ifeq ($(ARCH),x86_64)
      MINGW_PREFIXES=x86_64-w64-mingw32 amd64-mingw32msvc
      STRIP=x86_64-w64-mingw32-strip
    endif
    ifeq ($(ARCH),x86)
      MINGW_PREFIXES=i686-w64-mingw32 i586-mingw32msvc i686-pc-mingw32
    endif

    ifndef CC
      CC=$(firstword $(strip $(foreach MINGW_PREFIX, $(MINGW_PREFIXES), \
         $(call bin_path, $(MINGW_PREFIX)-gcc))))
    endif

#   STRIP=$(MINGW_PREFIX)-strip -g

    ifndef WINDRES
      WINDRES=$(firstword $(strip $(foreach MINGW_PREFIX, $(MINGW_PREFIXES), \
         $(call bin_path, $(MINGW_PREFIX)-windres))))
    endif
  else
    # Some MinGW installations define CC to cc, but don't actually provide cc,
    # so check that CC points to a real binary and use gcc if it doesn't
    ifeq ($(call bin_path, $(CC)),)
      CC=gcc
    endif

  endif

  # using generic windres if specific one is not present
  ifndef WINDRES
    WINDRES=windres
  endif

  ifeq ($(CC),)
    $(error Cannot find a suitable cross compiler for $(PLATFORM))
  endif

  BASE_CFLAGS += -Wall -fno-strict-aliasing -Wimplicit -Wstrict-prototypes \
    -DUSE_ICON -DMINGW=1

  ifeq ($(ARCH),x86_64)
    ARCHEXT = .x64
    BASE_CFLAGS += -m64
    OPTIMIZE = -O2 -ffast-math -fstrength-reduce
  endif
  ifeq ($(ARCH),x86)
    BASE_CFLAGS += -m32
    OPTIMIZE = -O2 -march=i586 -mtune=i686 -ffast-math -fstrength-reduce
  endif

  SHLIBEXT = dll
  SHLIBCFLAGS = -fPIC -fvisibility=hidden
  SHLIBLDFLAGS = -shared $(LDFLAGS)

  BINEXT = .exe

  LDFLAGS = -mwindows -Wl,--dynamicbase -Wl,--nxcompat  -fvisibility=hidden
  LDFLAGS += -lwsock32 -lgdi32 -lwinmm -lole32 -lws2_32 -lpsapi -lcomctl32

  CLIENT_LDFLAGS=$(LDFLAGS)

  ifeq ($(USE_SDL),1)
    BASE_CFLAGS += -DUSE_LOCAL_HEADERS=1 -I$(MOUNT_DIR)/libsdl/windows/include/SDL2
    ifeq ($(ARCH),x86)
      CLIENT_LDFLAGS += -L$(MOUNT_DIR)/libsdl/windows/mingw/lib32
      CLIENT_LDFLAGS += -lSDL2
      CLIENT_EXTRA_FILES += $(MOUNT_DIR)/libsdl/windows/mingw/lib32/SDL2.dll
    else
      CLIENT_LDFLAGS += -L$(MOUNT_DIR)/libsdl/windows/mingw/lib64
      CLIENT_LDFLAGS += -lSDL264
      CLIENT_EXTRA_FILES += $(MOUNT_DIR)/libsdl/windows/mingw/lib64/SDL264.dll
    endif
  endif

  ifeq ($(USE_CODEC_VORBIS),1)
    CLIENT_LDFLAGS += -lvorbisfile -lvorbis -logg
    BASE_CFLAGS += -DUSE_CODEC_VORBIS=1
  endif

  ifeq ($(USE_CURL),1)
    BASE_CFLAGS += -I$(MOUNT_DIR)/libcurl/windows/include
    ifeq ($(ARCH),x86)
      CLIENT_LDFLAGS += -L$(MOUNT_DIR)/libcurl/windows/mingw/lib32
    else
      CLIENT_LDFLAGS += -L$(MOUNT_DIR)/libcurl/windows/mingw/lib64
    endif
    CLIENT_LDFLAGS += -lcurl -lwldap32 -lcrypt32
  endif

  DEBUG_CFLAGS = $(BASE_CFLAGS) -DDEBUG -D_DEBUG -ggdb -O0
  RELEASE_CFLAGS = $(BASE_CFLAGS) -DNDEBUG $(OPTIMIZE)

else # ifeq mingw32

#############################################################################
# SETUP AND BUILD -- FREEBSD
#############################################################################

ifeq ($(PLATFORM),freebsd)

  BASE_CFLAGS += -Wall -fno-strict-aliasing -Wimplicit -Wstrict-prototypes \
                -I/usr/X11R6/include -I/usr/local/include \
                -fvisibility=hidden

  DEBUG_CFLAGS=$(BASE_CFLAGS) -g

  ifeq ($(ARCH),x86_64)
    RELEASE_CFLAGS=$(BASE_CFLAGS) -DNDEBUG -O3 -ffast-math -funroll-loops \
      -fomit-frame-pointer -fexpensive-optimizations
  else
  ifeq ($(ARCH),x86)
    RELEASE_CFLAGS=$(BASE_CFLAGS) -DNDEBUG -O3 -mtune=pentiumpro \
      -march=pentium -fomit-frame-pointer -pipe -ffast-math \
      -funroll-loops -fstrength-reduce
  endif
  endif

  SHLIBEXT = so
  SHLIBCFLAGS = -fPIC -fvisibility=hidden
  SHLIBLDFLAGS = -shared $(LDFLAGS)

  # don't need -ldl (FreeBSD)
  LDFLAGS=-lm -lGL -lX11 -L/usr/local/lib -L/usr/X11R6/lib -lX11 -lXext

  CLIENT_LDFLAGS =-lm -lGL -lX11 -L/usr/local/lib -L/usr/X11R6/lib -lX11 -lXext

else # ifeq freebsd

#############################################################################
# SETUP AND BUILD -- OPENBSD
#############################################################################

ifeq ($(PLATFORM),openbsd)

  BASE_CFLAGS += -Wall -fno-strict-aliasing -Wimplicit -Wstrict-prototypes \
                -I/usr/X11R6/include -I/usr/local/include \
                -fvisibility=hidden

  DEBUG_CFLAGS=$(BASE_CFLAGS) -g

  ifeq ($(ARCH),x86_64)
    RELEASE_CFLAGS=$(BASE_CFLAGS) -DNDEBUG -O3 -ffast-math -funroll-loops \
      -fomit-frame-pointer -fexpensive-optimizations
  else
  ifeq ($(ARCH),x86)
    RELEASE_CFLAGS=$(BASE_CFLAGS) -DNDEBUG -O3 -mtune=pentiumpro \
      -march=pentium -fomit-frame-pointer -pipe -ffast-math \
      -funroll-loops -fstrength-reduce
  endif
  endif

  SHLIBEXT = so
  SHLIBCFLAGS = -fPIC
  SHLIBLDFLAGS = -shared $(LDFLAGS)

  # don't need -ldl (FreeBSD)
  LDFLAGS=-lm

  ifeq ($(USE_SDL),1)
    BASE_CFLAGS += -I/usr/local/include/SDL2
    CLIENT_LDFLAGS = -L/usr/X11R6/lib -L/usr/local/lib -lSDL2
  else
    CLIENT_LDFLAGS = -L/usr/X11R6/lib -L/usr/lib -lX11
  endif

  CLIENT_LDFLAGS += -lm -lGL -L/usr/local/lib

  ifeq ($(USE_CODEC_VORBIS),1)
    CLIENT_LDFLAGS += -lvorbisfile -lvorbis -logg
  endif

else # ifeq openbsd

#############################################################################
# SETUP AND BUILD -- NETBSD
#############################################################################

ifeq ($(PLATFORM),netbsd)

  LDFLAGS = -lm

  SHLIBEXT = so
  SHLIBCFLAGS = -fPIC -fvisibility=hidden
  SHLIBLDFLAGS = -shared $(LDFLAGS)

  BASE_CFLAGS += -Wall -fno-strict-aliasing -Wimplicit -Wstrict-prototypes
  DEBUG_CFLAGS = $(BASE_CFLAGS) -g

  BUILD_CLIENT = 0

else # ifeq netbsd
#############################################################################
# SETUP AND BUILD -- JS
#############################################################################

ifeq ($(PLATFORM),js)
  EMSDK=$(MOUNT_DIR)/xquakejs/lib/emsdk
  NODE_JS=$(EMSDK)/node/12.9.1_64bit/bin/node
  BINARYEN_ROOT=$(EMSDK)/upstream
  EMSCRIPTEN=$(EMSDK)/upstream/emscripten
define EM_CONFIG
"LLVM_ROOT = '$(EMSDK)/upstream/bin';NODE_JS = '$(NODE_JS)';BINARYEN_ROOT = '$(BINARYEN_ROOT)';EMSCRIPTEN_ROOT = '$(EMSCRIPTEN)'"
endef
ifndef EMSCRIPTEN_CACHE
  EMSCRIPTEN_CACHE=$(HOME)/.emscripten_cache
endif

  CC=$(EMSCRIPTEN)/emcc
  RANLIB=$(EMSCRIPTEN)/emranlib
  ARCH=js
  BINEXT=.js

  DEBUG=0
  EMCC_DEBUG=0

  HAVE_VM_COMPILED=true
  BUILD_CLIENT=1
  BUILD_SERVER=0
  BUILD_GAME_QVM=1
  BUILD_GAME_SO=0
  BUILD_STANDALONE=0
  BUILD_RENDERER_OPENGL=0
  BUILD_RENDERER_JS=0
  BUILD_RENDERER_OPENGL2=1
  BUILD_RENDERER_OPENGLES=0

  USE_Q3KEY=1
  USE_IPV6=0
  USE_SDL=1
  USE_VULKAN=0
  USE_CURL=0
  USE_CURL_DLOPEN=0
  USE_CODEC_VORBIS=1
  USE_CODEC_OPUS=1
  USE_FREETYPE=0
  USE_MUMBLE=0
  USE_VOIP=0
  SDL_LOADSO_DLOPEN=0
  USE_OPENAL_DLOPEN=0
  USE_RENDERER_DLOPEN=0
  USE_LOCAL_HEADERS=0
  GL_EXT_direct_state_access=1
  GL_ARB_ES2_compatibility=1
  GL_GLEXT_PROTOTYPES=1

  BASE_CFLAGS = \
	  -Wall -fno-strict-aliasing -Wimplicit -Wstrict-prototypes \
		-DGL_GLEXT_PROTOTYPES=1 -DGL_ARB_ES2_compatibility=1 -DGL_EXT_direct_state_access=1 \
		-DUSE_Q3KEY -DUSE_MD5 \
    -I$(EMSCRIPTEN_CACHE)/wasm/include/SDL2 \
		-I$(EMSCRIPTEN_CACHE)/wasm/include \
		-I$(EMSCRIPTEN_CACHE)/wasm-obj/include/SDL2 \
		-I$(EMSCRIPTEN_CACHE)/wasm-obj/include \
		-I$(EMSCRIPTEN_CACHE)/wasm-lto/include \
		-I$(EMSCRIPTEN_CACHE)/wasm-lto/include/SDL2 \
		-I$(EMSCRIPTEN_CACHE)/wasm-lto-pic/include \
		-I$(EMSCRIPTEN_CACHE)/wasm-lto-pic/include/SDL2

# debug optimize flags: --closure 0 --minify 0 -g -g4 || -O1 --closure 0 --minify 0 -g -g3
  DEBUG_CFLAGS=$(BASE_CFLAGS) \
    -O1 -g3 \
		-s WASM=1 \
		-s MODULARIZE=0 \
    -s SAFE_HEAP=0 \
    -s DEMANGLE_SUPPORT=1 \
    -s ASSERTIONS=1 \
    -s AGGRESSIVE_VARIABLE_ELIMINATION=0 \
    -frtti \
    -fPIC

  RELEASE_CFLAGS=$(BASE_CFLAGS) \
    -O3 -Oz \
    -s WASM=1 \
		-s MODULARIZE=0 \
    -s SAFE_HEAP=0 \
    -s DEMANGLE_SUPPORT=1 \
    -s ASSERTIONS=0 \
    -s AGGRESSIVE_VARIABLE_ELIMINATION=0 \
    -flto \
    -fPIC

ifneq ($(USE_CODEC_OPUS),0)
  RELEASE_CFLAGS += \
		-DUSE_CODEC_OPUS=1 \
    -DOPUS_BUILD -DHAVE_LRINTF -DFLOATING_POINT -DFLOAT_APPROX -DUSE_ALLOCA \
		-I$(OPUSDIR)/include \
		-I$(OPUSDIR)/celt \
		-I$(OPUSDIR)/silk \
    -I$(OPUSDIR)/silk/float \
		-I$(OPUSFILEDIR)/include 
endif

ifneq ($(USE_CODEC_VORBIS),0)
  RELEASE_CFLAGS += \
	  -DUSE_CODEC_VORBIS=1 \
    -I$(OGGDIR)/ \
    -I$(VORBISDIR)/
endif

  SHLIBCFLAGS = \
		-DEMSCRIPTEN \
	  -fvisibility=hidden \
		-O1 -g3 \
		-s STRICT=1 \
		-s AUTO_JS_LIBRARIES=0 \
		-s ERROR_ON_UNDEFINED_SYMBOLS=0 \
		-s SIDE_MODULE=1 \
		-s RELOCATABLE=0 \
		-s LINKABLE=1 \
		-s EXPORT_ALL=1 \
		-s EXPORTED_FUNCTIONS="['_GetRefAPI']" \
		-s ALLOW_TABLE_GROWTH=1 \
		-s ALLOW_MEMORY_GROWTH=1 \
		-s GL_UNSAFE_OPTS=0 \
		-s LEGACY_GL_EMULATION=0 \
		-s WEBGL2_BACKWARDS_COMPATIBILITY_EMULATION=1 \
		-s MIN_WEBGL_VERSION=1 \
		-s MAX_WEBGL_VERSION=3 \
    -s USE_WEBGL2=1 \
    -s FULL_ES2=1 \
    -s FULL_ES3=1 \
		-s USE_SDL=2 \
		-s EXPORT_NAME=\"quake3e_opengl2_js\" \
		-s WASM=0 \
		-s MODULARIZE=0 \
    -s SAFE_HEAP=1 \
    -s DEMANGLE_SUPPORT=1 \
    -s ASSERTIONS=1 \
    -s AGGRESSIVE_VARIABLE_ELIMINATION=0 \
    -frtti \
    -fPIC

ifeq ($(USE_RENDERER_DLOPEN),1)
  CLIENT_LDFLAGS += \
		-s EXPORT_ALL=1 \
		-s DECLARE_ASM_MODULE_EXPORTS=1 \
		-s LINKABLE=1 \
		-s INCLUDE_FULL_LIBRARY=1
endif

  SHLIBEXT=js

#  --llvm-lto 3
#   -s USE_WEBGL2=1
#   -s MIN_WEBGL_VERSION=2
#   -s MAX_WEBGL_VERSION=2
#   -s USE_SDL_IMAGE=2 \
#   -s SDL2_IMAGE_FORMATS='["bmp","png","xpm"]' \
# --em-config $(EM_CONFIG) \
# --cache $(EMSCRIPTEN_CACHE) \

  CLIENT_LDFLAGS += \
		-lbrowser.js \
		-lasync.js \
		-lidbfs.js \
		-lsdl.js \
		-lwebgl.js \
		-lwebgl2.js \
		--js-library $(QUAKEJS)/sys_common.js \
		--js-library $(QUAKEJS)/sys_browser.js \
		--js-library $(QUAKEJS)/sys_net.js \
		--js-library $(QUAKEJS)/sys_files.js \
		--js-library $(QUAKEJS)/sys_input.js \
		--js-library $(QUAKEJS)/sys_main.js \
		--js-library $(CMDIR)/vm_js.js \
		--pre-js $(QUAKEJS)/sys_polyfill.js \
		--post-js $(QUAKEJS)/sys_overrides.js \
		-s RELOCATABLE=0 \
		-s STRICT=1 \
		-s AUTO_JS_LIBRARIES=0 \
		-s DISABLE_EXCEPTION_CATCHING=0 \
    -s DISABLE_DEPRECATED_FIND_EVENT_TARGET_BEHAVIOR=1 \
    -s ERROR_ON_UNDEFINED_SYMBOLS=1 \
    -s INVOKE_RUN=1 \
    -s NO_EXIT_RUNTIME=1 \
    -s EXIT_RUNTIME=1 \
    -s EXTRA_EXPORTED_RUNTIME_METHODS="['SYS', 'SYSC', 'SYSF', 'SYSN', 'SYSM', 'ccall', 'callMain', 'addFunction', 'stackAlloc', 'stackSave', 'stackRestore', 'dynCall']" \
    -s EXPORTED_FUNCTIONS="['_main', '_malloc', '_free', '_atof', '_strncpy', '_memset', '_memcpy', '_fopen', '_fseek', '_Com_WriteConfigToFile', '_IN_PushInit', '_IN_PushEvent', '_CL_UpdateSound', '_CL_UpdateShader', '_CL_GetClientState', '_Com_Printf', '_CL_Outside_NextDownload', '_NET_SendLoopPacket', '_SOCKS_Frame_Proxy', '_Com_Frame_Proxy', '_Com_Outside_Error', '_Z_Malloc', '_Z_Free', '_S_Malloc', '_Cvar_Set', '_Cvar_SetValue', '_Cvar_Get', '_Cvar_VariableString', '_Cvar_VariableIntegerValue', '_Cbuf_ExecuteText', '_Cbuf_Execute', '_Cbuf_AddText', '_Field_CharEvent']" \
		-s MAIN_MODULE=0 \
    -s ALLOW_TABLE_GROWTH=1 \
    -s INITIAL_MEMORY=50MB \
    -s ALLOW_MEMORY_GROWTH=1 \
		-s GL_UNSAFE_OPTS=0 \
    -s LEGACY_GL_EMULATION=0 \
    -s WEBGL2_BACKWARDS_COMPATIBILITY_EMULATION=1 \
		-s MIN_WEBGL_VERSION=1 \
		-s MAX_WEBGL_VERSION=3 \
    -s USE_WEBGL2=1 \
    -s FULL_ES2=1 \
    -s FULL_ES3=1 \
    -s USE_SDL=2 \
		-s USE_SDL_MIXER=2 \
		-s USE_VORBIS=1 \
		-s USE_ZLIB=1 \
		-s USE_OGG=1 \
		-s USE_PTHREADS=0 \
    -s FORCE_FILESYSTEM=1 \
    -s EXPORT_NAME=\"quake3e\"
		
else # ifeq js

#############################################################################
# SETUP AND BUILD -- GENERIC
#############################################################################

  DEBUG_CFLAGS = $(BASE_CFLAGS) -ggdb -O0
  RELEASE_CFLAGS = $(BASE_CFLAGS) -DNDEBUG -O2

  SHLIBEXT = so
  SHLIBCFLAGS = -fPIC -fvisibility=hidden
  SHLIBLDFLAGS = -shared

endif #Linux
endif #mingw32
endif #darwin
endif #FreeBSD
endif #OpenBSD
endif #NetBSD
endif #js

TARGET_CLIENT = $(CNAME)$(ARCHEXT)$(BINEXT)

TARGET_REND1 = $(RENDERER_PREFIX)_opengl_$(SHLIBNAME)
TARGET_REND2 = $(RENDERER_PREFIX)_opengl2_$(SHLIBNAME)
TARGET_RENDJS = $(RENDERER_PREFIX)_js_$(SHLIBNAME)
TARGET_RENDV = $(RENDERER_PREFIX)_vulkan_$(SHLIBNAME)

TARGET_SERVER = $(DNAME)$(ARCHEXT)$(BINEXT)

TARGETS =

ifneq ($(BUILD_SERVER),0)
  TARGETS += $(B)/$(TARGET_SERVER)
endif

ifneq ($(BUILD_CLIENT),0)
  TARGETS += $(B)/$(TARGET_CLIENT)
endif

ifneq ($(USE_RENDERER_DLOPEN),0)
ifneq ($(PLATFORM),js)
  TARGETS += $(B)/$(TARGET_REND1)
endif
  TARGETS += $(B)/$(TARGET_REND2)
#    TARGETS += $(B)/$(TARGET_RENDJS)
#    TARGETS += $(B)/$(TARGET_RENDV)
endif

ifneq ($(HAVE_VM_COMPILED),true)
  BASE_CFLAGS += -DNO_VM_COMPILED
endif

ifeq ($(BUILD_STANDALONE),1)
  BASE_CFLAGS += -DSTANDALONE
endif

ifeq ($(USE_Q3KEY),1)
  BASE_CFLAGS += -DUSE_Q3KEY -DUSE_MD5
endif

ifeq ($(NOFPU),1)
  BASE_CFLAGS += -DNOFPU
endif

ifneq ($(USE_RENDERER_DLOPEN),0)
  BASE_CFLAGS += -DUSE_RENDERER_DLOPEN
  BASE_CFLAGS += -DRENDERER_PREFIX=\\\"$(RENDERER_PREFIX)\\\"
endif

ifeq ($(USE_CCACHE),1)
  CC := ccache $(CC)
endif

ifneq ($(USE_RENDERER_DLOPEN),0)
    RENDCFLAGS=$(SHLIBCFLAGS)
else
    RENDCFLAGS=$(NOTSHLIBCFLAGS)
endif

define DO_CC
$(echo_cmd) "CC $<"
$(Q)$(CC) $(NOTSHLIBCFLAGS) $(CFLAGS) -o $@ -c $<
endef

define DO_REND_CC
$(echo_cmd) "REND_CC $<"
$(Q)$(CC) $(RENDCFLAGS) $(CFLAGS) -o $@ -c $<
endef

define DO_REF_STR
$(echo_cmd) "REF_STR $<"
$(Q)rm -f $@
$(Q)echo "const char *fallbackShader_$(notdir $(basename $<)) =" >> $@
$(Q)cat $< | sed -e 's/^/\"/;s/$$/\\n\"/' | tr -d '\r' >> $@
$(Q)echo ";" >> $@
endef

define DO_BOT_CC
$(echo_cmd) "BOT_CC $<"
$(Q)$(CC) $(NOTSHLIBCFLAGS) $(CFLAGS) $(BOTCFLAGS) -DBOTLIB -o $@ -c $<
endef

ifeq ($(GENERATE_DEPENDENCIES),1)
  DO_QVM_DEP=cat $(@:%.o=%.d) | sed -e 's/\.o/\.asm/g' >> $(@:%.o=%.d)
endif

define DO_SHLIB_CC
$(echo_cmd) "SHLIB_CC $<"
$(Q)$(CC) $(CFLAGS) $(SHLIBCFLAGS) -o $@ -c $<
$(Q)$(DO_QVM_DEP)
endef

define DO_SHLIB_CC_MISSIONPACK
$(echo_cmd) "SHLIB_CC_MISSIONPACK $<"
$(Q)$(CC) -DMISSIONPACK $(CFLAGS) $(SHLIBCFLAGS) -o $@ -c $<
$(Q)$(DO_QVM_DEP)
endef

define DO_AS
$(echo_cmd) "AS $<"
$(Q)$(CC) $(CFLAGS) -DELF -x assembler-with-cpp -o $@ -c $<
endef

define DO_DED_CC
$(echo_cmd) "DED_CC $<"
$(Q)$(CC) $(NOTSHLIBCFLAGS) -DDEDICATED $(CFLAGS) -o $@ -c $<
endef

define DO_WINDRES
$(echo_cmd) "WINDRES $<"
$(Q)$(WINDRES) -i $< -o $@
endef

ifndef SHLIBNAME
  SHLIBNAME=$(ARCH).$(SHLIBEXT)
endif

#############################################################################
# MAIN TARGETS
#############################################################################

default: release
all: debug release

debug:
	@$(MAKE) targets B=$(BD) CFLAGS="$(CFLAGS) $(DEBUG_CFLAGS)" V=$(V)

release:
	@$(MAKE) targets B=$(BR) CFLAGS="$(CFLAGS) $(RELEASE_CFLAGS)" V=$(V)

define ADD_COPY_TARGET
TARGETS += $2
$2: $1
	$(echo_cmd) "CP $$<"
	@cp $1 $2
endef

# These functions allow us to generate rules for copying a list of files
# into the base directory of the build; this is useful for bundling libs,
# README files or whatever else
define GENERATE_COPY_TARGETS
$(foreach FILE,$1, \
  $(eval $(call ADD_COPY_TARGET, \
    $(FILE), \
    $(addprefix $(B)/,$(notdir $(FILE))))))
endef

ifneq ($(BUILD_CLIENT),0)
  $(call GENERATE_COPY_TARGETS,$(CLIENT_EXTRA_FILES))
endif

# Create the build directories and tools, print out
# an informational message, then start building
targets: makedirs tools
	@echo ""
	@echo "Building quake3 in $(B):"
	@echo ""
	@echo "  VERSION: $(VERSION)"
	@echo "  PLATFORM: $(PLATFORM)"
	@echo "  ARCH: $(ARCH)"
	@echo "  COMPILE_PLATFORM: $(COMPILE_PLATFORM)"
	@echo "  COMPILE_ARCH: $(COMPILE_ARCH)"
ifdef MINGW
	@echo "  WINDRES: $(WINDRES)"
endif
	@echo "  CC: $(CC)"
	@echo ""
	@echo "  CFLAGS:"
	@for i in $(CFLAGS); \
	do \
		echo "    $$i"; \
	done
	@echo ""
	@echo "  Output:"
	@for i in $(TARGETS); \
	do \
		echo "    $$i"; \
	done
	@echo ""
ifneq ($(TARGETS),)
	@$(MAKE) $(TARGETS) V=$(V)
endif

makedirs:
	@if [ ! -d $(BUILD_DIR) ];then $(MKDIR) $(BUILD_DIR);fi
	@if [ ! -d $(B) ];then $(MKDIR) $(B);fi
	@if [ ! -d $(B)/client ];then $(MKDIR) $(B)/client;fi
	@if [ ! -d $(B)/client/ogg ];then $(MKDIR) $(B)/client/ogg;fi
	@if [ ! -d $(B)/client/vorbis ];then $(MKDIR) $(B)/client/vorbis;fi
	@if [ ! -d $(B)/client/opus ];then $(MKDIR) $(B)/client/opus;fi
	@if [ ! -d $(B)/rend1 ];then $(MKDIR) $(B)/rend1;fi
	@if [ ! -d $(B)/rend2 ];then $(MKDIR) $(B)/rend2;fi
	@if [ ! -d $(B)/rend2/glsl ];then $(MKDIR) $(B)/rend2/glsl;fi
	@if [ ! -d $(B)/rendjs ];then $(MKDIR) $(B)/rendjs;fi
	@if [ ! -d $(B)/rendjs/glsl ];then $(MKDIR) $(B)/rendjs/glsl;fi
	@if [ ! -d $(B)/rendv ];then $(MKDIR) $(B)/rendv;fi
	@if [ ! -d $(B)/ded ];then $(MKDIR) $(B)/ded;fi

#############################################################################
# CLIENT/SERVER
#############################################################################

Q3REND1OBJ = \
  $(B)/rend1/tr_animation.o \
  $(B)/rend1/tr_arb.o \
  $(B)/rend1/tr_backend.o \
  $(B)/rend1/tr_bsp.o \
  $(B)/rend1/tr_cmds.o \
  $(B)/rend1/tr_curve.o \
  $(B)/rend1/tr_flares.o \
  $(B)/rend1/tr_font.o \
  $(B)/rend1/tr_image.o \
  $(B)/rend1/tr_image_png.o \
  $(B)/rend1/tr_image_jpg.o \
  $(B)/rend1/tr_image_bmp.o \
  $(B)/rend1/tr_image_tga.o \
  $(B)/rend1/tr_image_pcx.o \
  $(B)/rend1/tr_init.o \
  $(B)/rend1/tr_light.o \
  $(B)/rend1/tr_main.o \
  $(B)/rend1/tr_marks.o \
  $(B)/rend1/tr_mesh.o \
  $(B)/rend1/tr_model.o \
  $(B)/rend1/tr_model_iqm.o \
  $(B)/rend1/tr_noise.o \
  $(B)/rend1/tr_scene.o \
  $(B)/rend1/tr_shade.o \
  $(B)/rend1/tr_shade_calc.o \
  $(B)/rend1/tr_shader.o \
  $(B)/rend1/tr_shadows.o \
  $(B)/rend1/tr_sky.o \
  $(B)/rend1/tr_surface.o \
  $(B)/rend1/tr_vbo.o \
  $(B)/rend1/tr_world.o

Q3REND2OBJ = \
  $(B)/rend2/tr_animation.o \
  $(B)/rend2/tr_backend.o \
  $(B)/rend2/tr_bsp.o \
  $(B)/rend2/tr_cmds.o \
  $(B)/rend2/tr_curve.o \
  $(B)/rend2/tr_dsa.o \
  $(B)/rend2/tr_extramath.o \
  $(B)/rend2/tr_extensions.o \
  $(B)/rend2/tr_fbo.o \
  $(B)/rend2/tr_flares.o \
  $(B)/rend2/tr_font.o \
  $(B)/rend2/tr_glsl.o \
  $(B)/rend2/tr_image.o \
  $(B)/rend2/tr_image_bmp.o \
  $(B)/rend2/tr_image_jpg.o \
  $(B)/rend2/tr_image_pcx.o \
  $(B)/rend2/tr_image_png.o \
  $(B)/rend2/tr_image_tga.o \
  $(B)/rend2/tr_image_dds.o \
  $(B)/rend2/tr_init.o \
  $(B)/rend2/tr_light.o \
  $(B)/rend2/tr_main.o \
  $(B)/rend2/tr_marks.o \
  $(B)/rend2/tr_mesh.o \
  $(B)/rend2/tr_model.o \
  $(B)/rend2/tr_model_iqm.o \
  $(B)/rend2/tr_noise.o \
  $(B)/rend2/tr_postprocess.o \
  $(B)/rend2/tr_scene.o \
  $(B)/rend2/tr_shade.o \
  $(B)/rend2/tr_shade_calc.o \
  $(B)/rend2/tr_shader.o \
  $(B)/rend2/tr_shadows.o \
  $(B)/rend2/tr_sky.o \
  $(B)/rend2/tr_surface.o \
  $(B)/rend2/tr_vbo.o \
  $(B)/rend2/tr_world.o

Q3R2STRINGOBJ = \
  $(B)/rend2/glsl/bokeh_fp.o \
  $(B)/rend2/glsl/bokeh_vp.o \
  $(B)/rend2/glsl/calclevels4x_fp.o \
  $(B)/rend2/glsl/calclevels4x_vp.o \
  $(B)/rend2/glsl/depthblur_fp.o \
  $(B)/rend2/glsl/depthblur_vp.o \
  $(B)/rend2/glsl/dlight_fp.o \
  $(B)/rend2/glsl/dlight_vp.o \
  $(B)/rend2/glsl/down4x_fp.o \
  $(B)/rend2/glsl/down4x_vp.o \
  $(B)/rend2/glsl/fogpass_fp.o \
  $(B)/rend2/glsl/fogpass_vp.o \
  $(B)/rend2/glsl/generic_fp.o \
  $(B)/rend2/glsl/generic_vp.o \
  $(B)/rend2/glsl/lightall_fp.o \
  $(B)/rend2/glsl/lightall_vp.o \
  $(B)/rend2/glsl/pshadow_fp.o \
  $(B)/rend2/glsl/pshadow_vp.o \
  $(B)/rend2/glsl/shadowfill_fp.o \
  $(B)/rend2/glsl/shadowfill_vp.o \
  $(B)/rend2/glsl/shadowmask_fp.o \
  $(B)/rend2/glsl/shadowmask_vp.o \
  $(B)/rend2/glsl/ssao_fp.o \
  $(B)/rend2/glsl/ssao_vp.o \
  $(B)/rend2/glsl/texturecolor_fp.o \
  $(B)/rend2/glsl/texturecolor_vp.o \
  $(B)/rend2/glsl/tonemap_fp.o \
  $(B)/rend2/glsl/tonemap_vp.o

Q3RENDJSOBJ = \
  $(B)/rendjs/tr_animation.o \
  $(B)/rendjs/tr_backend.o \
  $(B)/rendjs/tr_bsp.o \
  $(B)/rendjs/tr_cmds.o \
  $(B)/rendjs/tr_curve.o \
  $(B)/rendjs/tr_dsa.o \
  $(B)/rendjs/tr_extramath.o \
  $(B)/rendjs/tr_extensions.o \
  $(B)/rendjs/tr_fbo.o \
  $(B)/rendjs/tr_flares.o \
  $(B)/rendjs/tr_font.o \
  $(B)/rendjs/tr_glsl.o \
  $(B)/rendjs/tr_image.o \
  $(B)/rendjs/tr_image_bmp.o \
  $(B)/rendjs/tr_image_jpg.o \
  $(B)/rendjs/tr_image_pcx.o \
  $(B)/rendjs/tr_image_png.o \
  $(B)/rendjs/tr_image_tga.o \
  $(B)/rendjs/tr_image_dds.o \
  $(B)/rendjs/tr_init.o \
  $(B)/rendjs/tr_light.o \
  $(B)/rendjs/tr_main.o \
  $(B)/rendjs/tr_marks.o \
  $(B)/rendjs/tr_mesh.o \
  $(B)/rendjs/tr_model.o \
  $(B)/rendjs/tr_model_iqm.o \
  $(B)/rendjs/tr_noise.o \
  $(B)/rendjs/tr_postprocess.o \
  $(B)/rendjs/tr_scene.o \
  $(B)/rendjs/tr_shade.o \
  $(B)/rendjs/tr_shade_calc.o \
  $(B)/rendjs/tr_shader.o \
  $(B)/rendjs/tr_shadows.o \
  $(B)/rendjs/tr_sky.o \
  $(B)/rendjs/tr_surface.o \
  $(B)/rendjs/tr_vbo.o \
  $(B)/rendjs/tr_world.o

Q3RJSSTRINGOBJ = \
  $(B)/rendjs/glsl/bokeh_fp.o \
  $(B)/rendjs/glsl/bokeh_vp.o \
  $(B)/rendjs/glsl/calclevels4x_fp.o \
  $(B)/rendjs/glsl/calclevels4x_vp.o \
  $(B)/rendjs/glsl/depthblur_fp.o \
  $(B)/rendjs/glsl/depthblur_vp.o \
  $(B)/rendjs/glsl/dlight_fp.o \
  $(B)/rendjs/glsl/dlight_vp.o \
  $(B)/rendjs/glsl/down4x_fp.o \
  $(B)/rendjs/glsl/down4x_vp.o \
  $(B)/rendjs/glsl/fogpass_fp.o \
  $(B)/rendjs/glsl/fogpass_vp.o \
  $(B)/rendjs/glsl/generic_fp.o \
  $(B)/rendjs/glsl/generic_vp.o \
  $(B)/rendjs/glsl/lightall_fp.o \
  $(B)/rendjs/glsl/lightall_vp.o \
  $(B)/rendjs/glsl/pshadow_fp.o \
  $(B)/rendjs/glsl/pshadow_vp.o \
  $(B)/rendjs/glsl/shadowfill_fp.o \
  $(B)/rendjs/glsl/shadowfill_vp.o \
  $(B)/rendjs/glsl/shadowmask_fp.o \
  $(B)/rendjs/glsl/shadowmask_vp.o \
  $(B)/rendjs/glsl/ssao_fp.o \
  $(B)/rendjs/glsl/ssao_vp.o \
  $(B)/rendjs/glsl/texturecolor_fp.o \
  $(B)/rendjs/glsl/texturecolor_vp.o \
  $(B)/rendjs/glsl/tonemap_fp.o \
  $(B)/rendjs/glsl/tonemap_vp.o

ifneq ($(USE_RENDERER_DLOPEN), 0)
  Q3REND1OBJ += \
    $(B)/rend1/q_shared.o \
    $(B)/rend1/puff.o \
    $(B)/rend1/q_math.o
  Q3REND2OBJ += \
    $(B)/rend2/q_shared.o \
    $(B)/rend2/puff.o \
    $(B)/rend2/q_math.o
endif

Q3RENDVOBJ = \
  $(B)/rendv/tr_animation.o \
  $(B)/rendv/tr_backend.o \
  $(B)/rendv/tr_bsp.o \
  $(B)/rendv/tr_cmds.o \
  $(B)/rendv/tr_curve.o \
  $(B)/rendv/tr_font.o \
  $(B)/rendv/tr_image.o \
  $(B)/rendv/tr_image_png.o \
  $(B)/rendv/tr_image_jpg.o \
  $(B)/rendv/tr_image_bmp.o \
  $(B)/rendv/tr_image_tga.o \
  $(B)/rendv/tr_image_pcx.o \
  $(B)/rendv/tr_init.o \
  $(B)/rendv/tr_light.o \
  $(B)/rendv/tr_main.o \
  $(B)/rendv/tr_marks.o \
  $(B)/rendv/tr_mesh.o \
  $(B)/rendv/tr_model.o \
  $(B)/rendv/tr_model_iqm.o \
  $(B)/rendv/tr_noise.o \
  $(B)/rendv/tr_scene.o \
  $(B)/rendv/tr_shade.o \
  $(B)/rendv/tr_shade_calc.o \
  $(B)/rendv/tr_shader.o \
  $(B)/rendv/tr_shadows.o \
  $(B)/rendv/tr_sky.o \
  $(B)/rendv/tr_surface.o \
  $(B)/rendv/tr_world.o \
  $(B)/rendv/vk.o \
  $(B)/rendv/vk_flares.o \
  $(B)/rendv/vk_vbo.o \
  \
  $(B)/rendv/dot_frag.o \
  $(B)/rendv/dot_vert.o \
  $(B)/rendv/fog_frag.o \
  $(B)/rendv/fog_vert.o \
  $(B)/rendv/gamma_frag.o \
  $(B)/rendv/gamma_vert.o \
  $(B)/rendv/light_fog_vert.o \
  $(B)/rendv/light_vert.o \
  $(B)/rendv/light_fog_frag.o \
  $(B)/rendv/light_frag.o \
  $(B)/rendv/light1_fog_frag.o \
  $(B)/rendv/light1_frag.o \
  $(B)/rendv/mt_fog_vert.o \
  $(B)/rendv/mt_vert.o \
  $(B)/rendv/mt_fog_frag.o \
  $(B)/rendv/mt_frag.o \
  $(B)/rendv/st_fog_vert.o \
  $(B)/rendv/st_vert.o \
  $(B)/rendv/st_enviro_fog_vert.o \
  $(B)/rendv/st_enviro_vert.o \
  $(B)/rendv/color_frag.o \
  $(B)/rendv/color_vert.o \
  $(B)/rendv/st_fog_frag.o \
  $(B)/rendv/st_df_frag.o \
  $(B)/rendv/st_frag.o

ifneq ($(USE_RENDERER_DLOPEN), 0)
  Q3RENDVOBJ += \
    $(B)/rendv/q_shared.o \
    $(B)/rendv/puff.o \
    $(B)/rendv/q_math.o
endif

JPGOBJ = \
  $(B)/client/jaricom.o \
  $(B)/client/jcapimin.o \
  $(B)/client/jcapistd.o \
  $(B)/client/jcarith.o \
  $(B)/client/jccoefct.o  \
  $(B)/client/jccolor.o \
  $(B)/client/jcdctmgr.o \
  $(B)/client/jchuff.o   \
  $(B)/client/jcinit.o \
  $(B)/client/jcmainct.o \
  $(B)/client/jcmarker.o \
  $(B)/client/jcmaster.o \
  $(B)/client/jcomapi.o \
  $(B)/client/jcparam.o \
  $(B)/client/jcprepct.o \
  $(B)/client/jcsample.o \
  $(B)/client/jctrans.o \
  $(B)/client/jdapimin.o \
  $(B)/client/jdapistd.o \
  $(B)/client/jdarith.o \
  $(B)/client/jdatadst.o \
  $(B)/client/jdatasrc.o \
  $(B)/client/jdcoefct.o \
  $(B)/client/jdcolor.o \
  $(B)/client/jddctmgr.o \
  $(B)/client/jdhuff.o \
  $(B)/client/jdinput.o \
  $(B)/client/jdmainct.o \
  $(B)/client/jdmarker.o \
  $(B)/client/jdmaster.o \
  $(B)/client/jdmerge.o \
  $(B)/client/jdpostct.o \
  $(B)/client/jdsample.o \
  $(B)/client/jdtrans.o \
  $(B)/client/jerror.o \
  $(B)/client/jfdctflt.o \
  $(B)/client/jfdctfst.o \
  $(B)/client/jfdctint.o \
  $(B)/client/jidctflt.o \
  $(B)/client/jidctfst.o \
  $(B)/client/jidctint.o \
  $(B)/client/jmemmgr.o \
  $(B)/client/jmemnobs.o \
  $(B)/client/jquant1.o \
  $(B)/client/jquant2.o \
  $(B)/client/jutils.o

Q3OBJ = \
  $(B)/client/cl_cgame.o \
  $(B)/client/cl_cin.o \
	$(B)/client/cl_cin_roq.o \
	$(B)/client/cl_cin_ogm.o \
  $(B)/client/cl_console.o \
  $(B)/client/cl_input.o \
  $(B)/client/cl_keys.o \
  $(B)/client/cl_main.o \
  $(B)/client/cl_net_chan.o \
  $(B)/client/cl_parse.o \
  $(B)/client/cl_scrn.o \
  $(B)/client/cl_ui.o \
  $(B)/client/cl_avi.o \
  $(B)/client/cl_jpeg.o \
  \
  $(B)/client/cm_load.o \
  $(B)/client/cm_patch.o \
  $(B)/client/cm_polylib.o \
  $(B)/client/cm_test.o \
  $(B)/client/cm_trace.o \
  \
  $(B)/client/cmd.o \
  $(B)/client/common.o \
  $(B)/client/cvar.o \
  $(B)/client/files.o \
  $(B)/client/history.o \
  $(B)/client/keys.o \
  $(B)/client/md4.o \
  $(B)/client/md5.o \
  $(B)/client/msg.o \
  $(B)/client/net_chan.o \
  $(B)/client/net_ip.o \
	$(B)/client/qrcodegen.o \
  $(B)/client/huffman.o \
  $(B)/client/huffman_static.o \
  \
  $(B)/client/snd_adpcm.o \
  $(B)/client/snd_dma.o \
  $(B)/client/snd_mem.o \
  $(B)/client/snd_mix.o \
  $(B)/client/snd_wavelet.o \
  \
  $(B)/client/snd_main.o \
  $(B)/client/snd_codec.o \
  $(B)/client/snd_codec_wav.o \
	$(B)/client/snd_codec_ogg.o \
  \
  $(B)/client/sv_bot.o \
  $(B)/client/sv_ccmds.o \
  $(B)/client/sv_client.o \
  $(B)/client/sv_filter.o \
	$(B)/client/sv_demo.o \
	$(B)/client/sv_demo_cl.o \
  $(B)/client/sv_demo_ext.o \
	$(B)/client/sv_demo_mv.o \
  $(B)/client/sv_game.o \
  $(B)/client/sv_init.o \
  $(B)/client/sv_main.o \
  $(B)/client/sv_net_chan.o \
  $(B)/client/sv_snapshot.o \
  $(B)/client/sv_world.o \
  \
  $(B)/client/q_math.o \
  $(B)/client/q_shared.o \
  \
  $(B)/client/unzip.o \
  $(B)/client/puff.o \
  $(B)/client/vm.o \
  $(B)/client/vm_interpreted.o \
  \
  $(B)/client/be_aas_bspq3.o \
  $(B)/client/be_aas_cluster.o \
  $(B)/client/be_aas_debug.o \
  $(B)/client/be_aas_entity.o \
  $(B)/client/be_aas_file.o \
  $(B)/client/be_aas_main.o \
  $(B)/client/be_aas_move.o \
  $(B)/client/be_aas_optimize.o \
  $(B)/client/be_aas_reach.o \
  $(B)/client/be_aas_route.o \
  $(B)/client/be_aas_routealt.o \
  $(B)/client/be_aas_sample.o \
  $(B)/client/be_ai_char.o \
  $(B)/client/be_ai_chat.o \
  $(B)/client/be_ai_gen.o \
  $(B)/client/be_ai_goal.o \
  $(B)/client/be_ai_move.o \
  $(B)/client/be_ai_weap.o \
  $(B)/client/be_ai_weight.o \
  $(B)/client/be_ea.o \
  $(B)/client/be_interface.o \
  $(B)/client/l_crc.o \
  $(B)/client/l_libvar.o \
  $(B)/client/l_log.o \
  $(B)/client/l_memory.o \
  $(B)/client/l_precomp.o \
  $(B)/client/l_script.o \
  $(B)/client/l_struct.o

ifneq ($(USE_LOCAL_HEADERS),0)
ifneq ($(USE_CODEC_VORBIS),0)
Q3OBJ += \
  $(B)/client/ogg/bitwise.o \
  $(B)/client/ogg/framing.o \
  \
  $(B)/client/vorbis/analysis.o \
  $(B)/client/vorbis/barkmel.o \
  $(B)/client/vorbis/bitrate.o \
  $(B)/client/vorbis/block.o \
  $(B)/client/vorbis/codebook.o \
  $(B)/client/vorbis/floor0.o \
  $(B)/client/vorbis/floor1.o \
  $(B)/client/vorbis/info.o \
  $(B)/client/vorbis/lookup.o \
  $(B)/client/vorbis/lpc.o \
  $(B)/client/vorbis/lsp.o \
  $(B)/client/vorbis/mapping0.o \
  $(B)/client/vorbis/mdct.o \
  $(B)/client/vorbis/misc.o \
  $(B)/client/vorbis/psy.o \
  $(B)/client/vorbis/registry.o \
  $(B)/client/vorbis/res0.o \
  $(B)/client/vorbis/sharedbook.o \
  $(B)/client/vorbis/smallft.o \
  $(B)/client/vorbis/synthesis.o \
  $(B)/client/vorbis/vorbisenc.o \
  $(B)/client/vorbis/vorbisfile.o \
  $(B)/client/vorbis/window.o
endif
endif

ifneq ($(DEBUG),1)
ifneq ($(USE_CODEC_OPUS),0)
Q3OBJ += \
	$(B)/client/snd_codec_opus.o \
	$(B)/client/opus/analysis.o \
	$(B)/client/opus/mlp.o \
	$(B)/client/opus/mlp_data.o \
	$(B)/client/opus/opus.o \
	$(B)/client/opus/opus_decoder.o \
	$(B)/client/opus/opus_encoder.o \
	$(B)/client/opus/opus_multistream.o \
	$(B)/client/opus/opus_multistream_encoder.o \
	$(B)/client/opus/opus_multistream_decoder.o \
	$(B)/client/opus/repacketizer.o \
	\
	$(B)/client/opus/bands.o \
	$(B)/client/opus/celt.o \
	$(B)/client/opus/cwrs.o \
	$(B)/client/opus/entcode.o \
	$(B)/client/opus/entdec.o \
	$(B)/client/opus/entenc.o \
	$(B)/client/opus/kiss_fft.o \
	$(B)/client/opus/laplace.o \
	$(B)/client/opus/mathops.o \
	$(B)/client/opus/mdct.o \
	$(B)/client/opus/modes.o \
	$(B)/client/opus/pitch.o \
	$(B)/client/opus/celt_encoder.o \
	$(B)/client/opus/celt_decoder.o \
	$(B)/client/opus/celt_lpc.o \
	$(B)/client/opus/quant_bands.o \
	$(B)/client/opus/rate.o \
	$(B)/client/opus/vq.o \
	\
	$(B)/client/opus/CNG.o \
	$(B)/client/opus/code_signs.o \
	$(B)/client/opus/init_decoder.o \
	$(B)/client/opus/decode_core.o \
	$(B)/client/opus/decode_frame.o \
	$(B)/client/opus/decode_parameters.o \
	$(B)/client/opus/decode_indices.o \
	$(B)/client/opus/decode_pulses.o \
	$(B)/client/opus/decoder_set_fs.o \
	$(B)/client/opus/dec_API.o \
	$(B)/client/opus/enc_API.o \
	$(B)/client/opus/encode_indices.o \
	$(B)/client/opus/encode_pulses.o \
	$(B)/client/opus/gain_quant.o \
	$(B)/client/opus/interpolate.o \
	$(B)/client/opus/LP_variable_cutoff.o \
	$(B)/client/opus/NLSF_decode.o \
	$(B)/client/opus/NSQ.o \
	$(B)/client/opus/NSQ_del_dec.o \
	$(B)/client/opus/PLC.o \
	$(B)/client/opus/shell_coder.o \
	$(B)/client/opus/tables_gain.o \
	$(B)/client/opus/tables_LTP.o \
	$(B)/client/opus/tables_NLSF_CB_NB_MB.o \
	$(B)/client/opus/tables_NLSF_CB_WB.o \
	$(B)/client/opus/tables_other.o \
	$(B)/client/opus/tables_pitch_lag.o \
	$(B)/client/opus/tables_pulses_per_block.o \
	$(B)/client/opus/VAD.o \
	$(B)/client/opus/control_audio_bandwidth.o \
	$(B)/client/opus/quant_LTP_gains.o \
	$(B)/client/opus/VQ_WMat_EC.o \
	$(B)/client/opus/HP_variable_cutoff.o \
	$(B)/client/opus/NLSF_encode.o \
	$(B)/client/opus/NLSF_VQ.o \
	$(B)/client/opus/NLSF_unpack.o \
	$(B)/client/opus/NLSF_del_dec_quant.o \
	$(B)/client/opus/process_NLSFs.o \
	$(B)/client/opus/stereo_LR_to_MS.o \
	$(B)/client/opus/stereo_MS_to_LR.o \
	$(B)/client/opus/check_control_input.o \
	$(B)/client/opus/control_SNR.o \
	$(B)/client/opus/init_encoder.o \
	$(B)/client/opus/control_codec.o \
	$(B)/client/opus/A2NLSF.o \
	$(B)/client/opus/ana_filt_bank_1.o \
	$(B)/client/opus/biquad_alt.o \
	$(B)/client/opus/bwexpander_32.o \
	$(B)/client/opus/bwexpander.o \
	$(B)/client/opus/debug.o \
	$(B)/client/opus/decode_pitch.o \
	$(B)/client/opus/inner_prod_aligned.o \
	$(B)/client/opus/lin2log.o \
	$(B)/client/opus/log2lin.o \
	$(B)/client/opus/LPC_analysis_filter.o \
	$(B)/client/opus/LPC_fit.o \
	$(B)/client/opus/LPC_inv_pred_gain.o \
	$(B)/client/opus/table_LSF_cos.o \
	$(B)/client/opus/NLSF2A.o \
	$(B)/client/opus/NLSF_stabilize.o \
	$(B)/client/opus/NLSF_VQ_weights_laroia.o \
	$(B)/client/opus/pitch_est_tables.o \
	$(B)/client/opus/resampler.o \
	$(B)/client/opus/resampler_down2_3.o \
	$(B)/client/opus/resampler_down2.o \
	$(B)/client/opus/resampler_private_AR2.o \
	$(B)/client/opus/resampler_private_down_FIR.o \
	$(B)/client/opus/resampler_private_IIR_FIR.o \
	$(B)/client/opus/resampler_private_up2_HQ.o \
	$(B)/client/opus/resampler_rom.o \
	$(B)/client/opus/sigm_Q15.o \
	$(B)/client/opus/sort.o \
	$(B)/client/opus/sum_sqr_shift.o \
	$(B)/client/opus/stereo_decode_pred.o \
	$(B)/client/opus/stereo_encode_pred.o \
	$(B)/client/opus/stereo_find_predictor.o \
	$(B)/client/opus/stereo_quant_pred.o \
	\
	$(B)/client/opus/apply_sine_window_FLP.o \
	$(B)/client/opus/corrMatrix_FLP.o \
	$(B)/client/opus/encode_frame_FLP.o \
	$(B)/client/opus/find_LPC_FLP.o \
	$(B)/client/opus/find_LTP_FLP.o \
	$(B)/client/opus/find_pitch_lags_FLP.o \
	$(B)/client/opus/find_pred_coefs_FLP.o \
	$(B)/client/opus/LPC_analysis_filter_FLP.o \
	$(B)/client/opus/LTP_analysis_filter_FLP.o \
	$(B)/client/opus/LTP_scale_ctrl_FLP.o \
	$(B)/client/opus/noise_shape_analysis_FLP.o \
	$(B)/client/opus/process_gains_FLP.o \
	$(B)/client/opus/regularize_correlations_FLP.o \
	$(B)/client/opus/residual_energy_FLP.o \
	$(B)/client/opus/warped_autocorrelation_FLP.o \
	$(B)/client/opus/wrappers_FLP.o \
	$(B)/client/opus/autocorrelation_FLP.o \
	$(B)/client/opus/burg_modified_FLP.o \
	$(B)/client/opus/bwexpander_FLP.o \
	$(B)/client/opus/energy_FLP.o \
	$(B)/client/opus/inner_product_FLP.o \
	$(B)/client/opus/k2a_FLP.o \
	$(B)/client/opus/LPC_inv_pred_gain_FLP.o \
	$(B)/client/opus/pitch_analysis_core_FLP.o \
	$(B)/client/opus/scale_copy_vector_FLP.o \
	$(B)/client/opus/scale_vector_FLP.o \
	$(B)/client/opus/schur_FLP.o \
	$(B)/client/opus/sort_FLP.o \
	\
  $(B)/client/http.o \
  $(B)/client/info.o \
  $(B)/client/internal.o \
  $(B)/client/opusfile.o \
  $(B)/client/stream.o \
  $(B)/client/wincerts.o
endif
endif

  Q3OBJ += $(JPGOBJ)

ifeq ($(USE_RENDERER_DLOPEN),0)
ifeq ($(USE_VULKAN),1)
  Q3OBJ += $(Q3RENDVOBJ)
else
ifeq ($(BUILD_RENDERER_JS),1)
  Q3OBJ += $(Q3RENDJSOBJ) $(Q3RJSSTRINGOBJ)
else
ifeq ($(BUILD_RENDERER_OPENGL2),1)
  Q3OBJ += $(Q3REND2OBJ) $(Q3R2STRINGOBJ)
else
  Q3OBJ += $(Q3REND1OBJ)
endif

endif # build js
endif # use vulcan
endif # no dlopen

ifeq ($(ARCH),x86)
ifndef MINGW
  Q3OBJ += \
    $(B)/client/snd_mix_mmx.o \
    $(B)/client/snd_mix_sse.o
endif
endif

ifeq ($(HAVE_VM_COMPILED),true)
  ifeq ($(ARCH),x86)
    Q3OBJ += $(B)/client/vm_x86.o
  endif
  ifeq ($(ARCH),x86_64)
    Q3OBJ += $(B)/client/vm_x86.o
  endif
endif

ifeq ($(USE_CURL),1)
  Q3OBJ += $(B)/client/cl_curl.o
endif

ifdef MINGW

  Q3OBJ += \
    $(B)/client/win_main.o \
    $(B)/client/win_shared.o \
    $(B)/client/win_syscon.o \
    $(B)/client/win_resource.o

ifeq ($(USE_SDL),1)
ifneq ($(PLATFORM),js)
    Q3OBJ += \
        $(B)/client/sdl_glimp.o \
        $(B)/client/sdl_gamma.o \
        $(B)/client/sdl_input.o \
        $(B)/client/sdl_snd.o
endif
else # !USE_SDL
    Q3OBJ += \
        $(B)/client/win_gamma.o \
        $(B)/client/win_glimp.o \
        $(B)/client/win_input.o \
        $(B)/client/win_minimize.o \
        $(B)/client/win_qgl.o \
        $(B)/client/win_snd.o \
        $(B)/client/win_wndproc.o
ifeq ($(USE_VULKAN_API),1)
    Q3OBJ += \
        $(B)/client/win_qvk.o
endif
endif # !USE_SDL

else # !MINGW
ifeq ($(PLATFORM),js)
Q3OBJ += \
	$(B)/client/sdl_glimp.o \
	$(B)/client/sdl_gamma.o \
	$(B)/client/sdl_snd.o \
	$(B)/client/sys_main.o \
	$(B)/client/sys_input.o

else
  Q3OBJ += \
    $(B)/client/unix_main.o \
    $(B)/client/unix_shared.o \
    $(B)/client/linux_signals.o
endif

ifeq ($(USE_SDL),1)
ifneq ($(PLATFORM),js)
    Q3OBJ += \
        $(B)/client/sdl_glimp.o \
        $(B)/client/sdl_gamma.o \
        $(B)/client/sdl_input.o \
        $(B)/client/sdl_snd.o
endif
else # !USE_SDL
    Q3OBJ += \
        $(B)/client/linux_glimp.o \
        $(B)/client/linux_qgl.o \
        $(B)/client/linux_snd.o \
        $(B)/client/x11_dga.o \
        $(B)/client/x11_randr.o \
        $(B)/client/x11_vidmode.o
ifeq ($(USE_VULKAN_API),1)
    Q3OBJ += \
        $(B)/client/linux_qvk.o
endif
endif # !USE_SDL

endif # !MINGW

# client binary

$(B)/$(TARGET_CLIENT): $(Q3OBJ)
	$(echo_cmd) "LD $@"
	$(Q)$(CC) -v -o $@ $(Q3OBJ) $(CLIENT_LDFLAGS) $(CFLAGS) \
		$(LDFLAGS)

# modular renderers

$(B)/$(TARGET_REND1): $(Q3REND1OBJ)
	$(echo_cmd) "LD $@"
	$(Q)$(CC) $(SHLIBCFLAGS) $(SHLIBLDFLAGS) -o $@ $(Q3REND1OBJ)

$(B)/$(TARGET_REND2): $(Q3REND2OBJ) $(Q3R2STRINGOBJ)
	$(echo_cmd) "LD $@"
	$(Q)$(CC) $(SHLIBCFLAGS) $(SHLIBLDFLAGS) -o $@ $(Q3REND2OBJ) $(Q3R2STRINGOBJ)

$(B)/$(TARGET_RENDJS): $(Q3RENDJSOBJ) $(Q3R2STRINGOBJ)
	$(echo_cmd) "LD $@"
	$(Q)$(CC) $(SHLIBCFLAGS) $(SHLIBLDFLAGS) -o $@ $(Q3RENDJSOBJ) $(Q3RJSSTRINGOBJ)

$(B)/$(TARGET_RENDV): $(Q3RENDVOBJ)
	$(echo_cmd) "LD $@"
	$(Q)$(CC) $(SHLIBCFLAGS) $(SHLIBLDFLAGS) -o $@ $(Q3RENDVOBJ)

#############################################################################
# DEDICATED SERVER
#############################################################################

Q3DOBJ = \
  $(B)/ded/sv_bot.o \
  $(B)/ded/sv_client.o \
  $(B)/ded/sv_ccmds.o \
  $(B)/ded/sv_filter.o \
	$(B)/ded/sv_demo.o \
	$(B)/ded/sv_demo_cl.o \
  $(B)/ded/sv_demo_ext.o \
	$(B)/ded/sv_demo_mv.o \
  $(B)/ded/sv_game.o \
  $(B)/ded/sv_init.o \
  $(B)/ded/sv_main.o \
  $(B)/ded/sv_net_chan.o \
  $(B)/ded/sv_snapshot.o \
  $(B)/ded/sv_world.o \
  \
  $(B)/ded/cm_load.o \
  $(B)/ded/cm_patch.o \
  $(B)/ded/cm_polylib.o \
  $(B)/ded/cm_test.o \
  $(B)/ded/cm_trace.o \
  $(B)/ded/cmd.o \
  $(B)/ded/common.o \
  $(B)/ded/cvar.o \
  $(B)/ded/files.o \
  $(B)/ded/history.o \
  $(B)/ded/keys.o \
  $(B)/ded/md4.o \
  $(B)/ded/md5.o \
  $(B)/ded/msg.o \
  $(B)/ded/net_chan.o \
  $(B)/ded/net_ip.o \
  $(B)/ded/huffman.o \
  $(B)/ded/huffman_static.o \
  \
  $(B)/ded/q_math.o \
  $(B)/ded/q_shared.o \
  \
  $(B)/ded/unzip.o \
  $(B)/ded/vm.o \
	$(B)/ded/vm_interpreted.o \
  \
  $(B)/ded/be_aas_bspq3.o \
  $(B)/ded/be_aas_cluster.o \
  $(B)/ded/be_aas_debug.o \
  $(B)/ded/be_aas_entity.o \
  $(B)/ded/be_aas_file.o \
  $(B)/ded/be_aas_main.o \
  $(B)/ded/be_aas_move.o \
  $(B)/ded/be_aas_optimize.o \
  $(B)/ded/be_aas_reach.o \
  $(B)/ded/be_aas_route.o \
  $(B)/ded/be_aas_routealt.o \
  $(B)/ded/be_aas_sample.o \
  $(B)/ded/be_ai_char.o \
  $(B)/ded/be_ai_chat.o \
  $(B)/ded/be_ai_gen.o \
  $(B)/ded/be_ai_goal.o \
  $(B)/ded/be_ai_move.o \
  $(B)/ded/be_ai_weap.o \
  $(B)/ded/be_ai_weight.o \
  $(B)/ded/be_ea.o \
  $(B)/ded/be_interface.o \
  $(B)/ded/l_crc.o \
  $(B)/ded/l_libvar.o \
  $(B)/ded/l_log.o \
  $(B)/ded/l_memory.o \
  $(B)/ded/l_precomp.o \
  $(B)/ded/l_script.o \
  $(B)/ded/l_struct.o
	
ifeq ($(USE_CURL),1)
  Q3DOBJ += $(B)/ded/cl_curl.o
endif

ifdef MINGW
  Q3DOBJ += \
  $(B)/ded/win_main.o \
  $(B)/client/win_resource.o \
  $(B)/ded/win_shared.o \
  $(B)/ded/win_syscon.o
else
  Q3DOBJ += \
  $(B)/ded/linux_signals.o \
  $(B)/ded/unix_main.o \
  $(B)/ded/unix_shared.o
endif

ifeq ($(HAVE_VM_COMPILED),true)
  ifeq ($(ARCH),x86)
    Q3DOBJ += $(B)/ded/vm_x86.o
  endif
  ifeq ($(ARCH),x86_64)
    Q3DOBJ += $(B)/ded/vm_x86.o
  endif
endif

$(B)/$(TARGET_SERVER): $(Q3DOBJ)
	$(echo_cmd) "LD $@"
	$(Q)$(CC) -o $@ $(Q3DOBJ) $(LDFLAGS)

#############################################################################
## CLIENT/SERVER RULES
#############################################################################

$(B)/client/%.o: $(ADIR)/%.s
	$(DO_AS)

$(B)/client/%.o: $(CDIR)/%.c
	$(DO_CC)

$(B)/client/%.o: $(SDIR)/%.c
	$(DO_CC)

$(B)/client/%.o: $(CMDIR)/%.c
	$(DO_CC)

$(B)/client/%.o: $(BLIBDIR)/%.c
	$(DO_BOT_CC)

$(B)/client/%.o: $(JPDIR)/%.c
	$(DO_CC)

$(B)/client/ogg/%.o: $(OGGDIR)/%.c
	$(DO_CC)

$(B)/client/vorbis/%.o: $(VORBISDIR)/%.c
	$(DO_CC)

$(B)/client/opus/%.o: $(OPUSDIR)/src/%.c
	$(DO_CC)

$(B)/client/opus/%.o: $(OPUSDIR)/celt/%.c
	$(DO_CC)

$(B)/client/opus/%.o: $(OPUSDIR)/silk/%.c
	$(DO_CC)

$(B)/client/opus/%.o: $(OPUSDIR)/silk/float/%.c
	$(DO_CC)

$(B)/client/%.o: $(OPUSFILEDIR)/src/%.c
	$(DO_CC)

$(B)/client/%.o: $(SDLDIR)/%.c
	$(DO_CC)

$(B)/rend1/%.o: $(R1DIR)/%.c
	$(DO_REND_CC)

$(B)/rend1/%.o: $(RCDIR)/%.c
	$(DO_REND_CC)

$(B)/rend1/%.o: $(CMDIR)/%.c
	$(DO_REND_CC)

$(B)/rend2/glsl/%.c: $(R2DIR)/glsl/%.glsl
	$(DO_REF_STR)

$(B)/rend2/glsl/%.o: $(B)/renderer2/glsl/%.c
	$(DO_REND_CC)

$(B)/rend2/%.o: $(RCDIR)/%.c
	$(DO_REND_CC)

$(B)/rend2/%.o: $(R2DIR)/%.c
	$(DO_REND_CC)

$(B)/rend2/%.o: $(CMDIR)/%.c
	$(DO_REND_CC)

$(B)/rendjs/glsl/%.c: $(RJSDIR)/glsl/%.glsl
	$(DO_REF_STR)

$(B)/rendjs/glsl/%.o: $(B)/rendererjs/glsl/%.c
	$(DO_REND_CC)

$(B)/rendjs/%.o: $(RCDIR)/%.c
	$(DO_REND_CC)

$(B)/rendjs/%.o: $(RJSDIR)/%.c
	$(DO_REND_CC)

$(B)/rendv/%.o: $(RVDIR)/%.c
	$(DO_REND_CC)

$(B)/rendv/%.o: $(RCDIR)/%.c
	$(DO_REND_CC)

$(B)/rendv/%.o: $(RVSDIR)/%.c
	$(DO_REND_CC)

$(B)/rendv/%.o: $(CMDIR)/%.c
	$(DO_REND_CC)

$(B)/client/%.o: $(UDIR)/%.c
	$(DO_CC)

$(B)/client/%.o: $(W32DIR)/%.c
	$(DO_CC)

$(B)/client/%.o: $(W32DIR)/%.rc
	$(DO_WINDRES)

$(B)/client/%.o: $(QUAKEJS)/%.c
	$(DO_CC)

$(B)/ded/%.o: $(ADIR)/%.s
	$(DO_AS)

$(B)/ded/cl_curl.o: $(CDIR)/cl_curl.c
	$(DO_DED_CC)

$(B)/ded/%.o: $(SDIR)/%.c
	$(DO_DED_CC)

$(B)/ded/%.o: $(CMDIR)/%.c
	$(DO_DED_CC)

$(B)/ded/%.o: $(BLIBDIR)/%.c
	$(DO_BOT_CC)

$(B)/ded/%.o: $(UDIR)/%.c
	$(DO_DED_CC)

$(B)/ded/%.o: $(W32DIR)/%.c
	$(DO_DED_CC)

$(B)/ded/%.o: $(W32DIR)/%.rc
	$(DO_WINDRES)

#############################################################################
# MISC
#############################################################################

install: release
	@for i in $(TARGETS); do \
		if [ -f $(BR)$$i ]; then \
			$(INSTALL) -D -m 0755 "$(BR)/$$i" "$(DESTDIR)$$i"; \
			$(STRIP) "$(DESTDIR)$$i"; \
		fi \
	done

copyfiles: release
	@if [ ! -d $(COPYDIR)/baseq3 ]; then echo "You need to set COPYDIR to where your Quake3 data is!"; fi
	-$(MKDIR) -p -m 0755 $(COPYDIR)/baseq3
	-$(MKDIR) -p -m 0755 $(COPYDIR)/missionpack

ifneq ($(BUILD_CLIENT),0)
	$(INSTALL) -s -m 0755 $(BR)/$(TARGET_CLIENT) $(COPYDIR)/$(TARGET_CLIENT)
endif

ifneq ($(BUILD_SERVER),0)
	@if [ -f $(BR)/$(TARGET_SERVER) ]; then \
		$(INSTALL) -s -m 0755 $(BR)/$(TARGET_SERVER) $(COPYDIR)/$(TARGET_SERVER); \
	fi
endif

clean: clean-debug clean-release
	@$(MAKE) -C $(LOKISETUPDIR) clean

clean2:
	@echo "CLEAN $(B)"
	@if [ -d $(B) ];then (find $(B) -name '*.d' -exec rm {} \;)fi
	@rm -f $(Q3OBJ) $(Q3DOBJ)
	@rm -f $(TARGETS)

clean-debug:
	@rm -rf $(BD)

clean-release:
	@echo $(BR)
	@rm -rf $(BR)

distclean: clean
	@rm -rf $(BUILD_DIR)

installer: release
	@$(MAKE) VERSION=$(VERSION) -C $(LOKISETUPDIR) V=$(V)

dist:
	rm -rf quake3-$(SVN_VERSION)
	svn export . quake3-$(SVN_VERSION)
	tar --owner=root --group=root --force-local -cjf quake3-$(SVN_VERSION).tar.bz2 quake3-$(SVN_VERSION)
	rm -rf quake3-$(SVN_VERSION)

dist2:
	rm -rf quake3-1.32e-src
	svn export . quake3-1.32e-src
	zip -9 -r quake3-1.32e-src.zip quake3-1.32e-src/*
	rm -rf quake3-1.32e-src

#############################################################################
# DEPENDENCIES
#############################################################################

D_FILES=$(shell find . -name '*.d')

#ifneq ($(strip $(D_FILES)),)
 # include $(D_FILES)
#endif

.PHONY: all clean clean2 clean-debug clean-release copyfiles \
	debug default dist distclean installer makedirs release \
	targets tools toolsclean
