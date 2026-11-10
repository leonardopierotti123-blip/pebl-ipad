# PEBL for iPad (iOS/iPadOS) build.
#
# Generates an Xcode project; SDL2 and its satellite libraries are fetched
# and built statically.  Typical use (on a Mac with Xcode):
#
#   cmake -S ios -B build-ios -G Xcode \
#         -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
#         -DCMAKE_OSX_ARCHITECTURES=arm64 \
#         -DPEBL_DEVELOPMENT_TEAM=<your Apple team id>
#   open build-ios/PEBL.xcodeproj     # or: cmake --build build-ios --config Release
#
# See ios/README.md for signing and installation (including from Windows).

cmake_minimum_required(VERSION 3.24)

if(NOT CMAKE_SYSTEM_NAME)
    set(CMAKE_SYSTEM_NAME iOS)
endif()
if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET 14.0)
endif()

project(PEBL VERSION 2.4.0 LANGUAGES C CXX OBJC OBJCXX)

set(PEBL_VERSION_STRING "2.4")
set(PEBL_BUNDLE_ID "net.sourceforge.pebl.ipad" CACHE STRING "Bundle identifier of the iPad app")
set(PEBL_DEVELOPMENT_TEAM "" CACHE STRING "Apple development team id used for signing (empty: unsigned)")
set(PEBL_BUILD_NUMBER "1" CACHE STRING "CFBundleVersion")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

get_filename_component(PEBL_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
set(SRC "${PEBL_ROOT}/src")

#-------------------------------------------------------------------------------
# Third-party libraries (static)
#-------------------------------------------------------------------------------
include(FetchContent)
set(FETCHCONTENT_QUIET OFF)

# Vendored FreeType/HarfBuzz declare cmake_minimum_required() < 3.5, which
# CMake 4 rejects unless a policy floor is given.
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)

# Download dependencies directly instead of through per-dependency Xcode
# sub-builds (much faster with the Xcode generator).
if(POLICY CMP0168)
    cmake_policy(SET CMP0168 NEW)
endif()

# SDL2
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TEST OFF CACHE BOOL "" FORCE)
set(SDL2_DISABLE_INSTALL ON CACHE BOOL "" FORCE)
FetchContent_Declare(SDL2
    GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
    GIT_TAG release-2.30.10
    GIT_SHALLOW TRUE)
FetchContent_MakeAvailable(SDL2)

# SDL2_image: PNG/JPG/BMP/GIF/... via the built-in stb backend, no external deps.
set(SDL2IMAGE_INSTALL OFF CACHE BOOL "" FORCE)
set(SDL2IMAGE_SAMPLES OFF CACHE BOOL "" FORCE)
set(SDL2IMAGE_VENDORED OFF CACHE BOOL "" FORCE)
set(SDL2IMAGE_BACKEND_STB ON CACHE BOOL "" FORCE)
set(SDL2IMAGE_BACKEND_IMAGEIO OFF CACHE BOOL "" FORCE)
set(SDL2IMAGE_AVIF OFF CACHE BOOL "" FORCE)
set(SDL2IMAGE_JXL OFF CACHE BOOL "" FORCE)
set(SDL2IMAGE_TIF OFF CACHE BOOL "" FORCE)
set(SDL2IMAGE_WEBP OFF CACHE BOOL "" FORCE)
FetchContent_Declare(SDL2_image
    GIT_REPOSITORY https://github.com/libsdl-org/SDL_image.git
    GIT_TAG release-2.8.2
    GIT_SHALLOW TRUE
    GIT_SUBMODULES "")
FetchContent_MakeAvailable(SDL2_image)

# SDL2_ttf with vendored FreeType + HarfBuzz (needed for RTL/complex scripts).
set(SDL2TTF_INSTALL OFF CACHE BOOL "" FORCE)
set(SDL2TTF_SAMPLES OFF CACHE BOOL "" FORCE)
set(SDL2TTF_VENDORED ON CACHE BOOL "" FORCE)
set(SDL2TTF_HARFBUZZ ON CACHE BOOL "" FORCE)
FetchContent_Declare(SDL2_ttf
    GIT_REPOSITORY https://github.com/libsdl-org/SDL_ttf.git
    GIT_TAG release-2.22.0
    GIT_SHALLOW TRUE
    GIT_SUBMODULES external/freetype external/harfbuzz)
FetchContent_MakeAvailable(SDL2_ttf)

# SDL2_mixer: WAV, OGG (stb_vorbis), MP3 (dr_mp3), FLAC (dr_flac), MIDI (timidity);
# only codecs that need no external library.
set(SDL2MIXER_INSTALL OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_SAMPLES OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_VENDORED OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_OPUS OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_MOD OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_MIDI_FLUIDSYNTH OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_WAVPACK OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_GME OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_VORBIS STB CACHE STRING "" FORCE)
set(SDL2MIXER_FLAC_LIBFLAC OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_FLAC_DRFLAC ON CACHE BOOL "" FORCE)
set(SDL2MIXER_MP3_MPG123 OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_MP3_DRMP3 ON CACHE BOOL "" FORCE)
set(SDL2MIXER_MIDI_NATIVE OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_MIDI_TIMIDITY ON CACHE BOOL "" FORCE)
FetchContent_Declare(SDL2_mixer
    GIT_REPOSITORY https://github.com/libsdl-org/SDL_mixer.git
    GIT_TAG release-2.8.0
    GIT_SHALLOW TRUE
    GIT_SUBMODULES "")
FetchContent_MakeAvailable(SDL2_mixer)

# SDL2_net
set(SDL2NET_INSTALL OFF CACHE BOOL "" FORCE)
set(SDL2NET_SAMPLES OFF CACHE BOOL "" FORCE)
FetchContent_Declare(SDL2_net
    GIT_REPOSITORY https://github.com/libsdl-org/SDL_net.git
    GIT_TAG release-2.2.0
    GIT_SHALLOW TRUE)
FetchContent_MakeAvailable(SDL2_net)

# SDL2_gfx ships with PEBL (libs/SDL2_gfx-1.0.4).
set(GFX "${PEBL_ROOT}/libs/SDL2_gfx-1.0.4")
add_library(SDL2_gfx STATIC
    ${GFX}/SDL2_gfxPrimitives.c
    ${GFX}/SDL2_rotozoom.c
    ${GFX}/SDL2_framerate.c
    ${GFX}/SDL2_imageFilter.c)
target_include_directories(SDL2_gfx PUBLIC ${GFX})
target_link_libraries(SDL2_gfx PUBLIC SDL2::SDL2-static)

#-------------------------------------------------------------------------------
# PEBL sources (same set as the WebAssembly build in the Makefile, which also
# uses the iterative evaluator; minus serial/parallel ports and eye tracker)
#-------------------------------------------------------------------------------
set(PEBL_SOURCES
    ${SRC}/apps/PEBL.cpp

    ${SRC}/base/Evaluator-es.cpp
    ${SRC}/base/FunctionMap.cpp
    ${SRC}/base/grammar.tab.cpp
    ${SRC}/base/PEBLObject.cpp
    ${SRC}/base/Loader.cpp
    ${SRC}/base/PComplexData.cpp
    ${SRC}/base/PList.cpp
    ${SRC}/base/PNode.cpp
    ${SRC}/base/VariableMap.cpp
    ${SRC}/base/Variant.cpp
    ${SRC}/base/lex.yy.c
    ${SRC}/devices/PEventLoop-es.cpp

    ${SRC}/devices/PDevice.cpp
    ${SRC}/devices/PEventQueue.cpp
    ${SRC}/devices/PEvent.cpp
    ${SRC}/devices/PKeyboard.cpp
    ${SRC}/devices/PTimer.cpp
    ${SRC}/devices/DeviceState.cpp
    ${SRC}/devices/PStream.cpp
    ${SRC}/devices/PAudioOut.cpp
    ${SRC}/devices/PNetwork.cpp
    ${SRC}/devices/PJoystick.cpp

    ${SRC}/libs/PEBLMath.cpp
    ${SRC}/libs/PEBLStream.cpp
    ${SRC}/libs/PEBLObjects.cpp
    ${SRC}/libs/PEBLEnvironment.cpp
    ${SRC}/libs/PEBLList.cpp
    ${SRC}/libs/PEBLString.cpp
    ${SRC}/libs/PEBLLSL.cpp

    ${SRC}/objects/PEnvironment.cpp
    ${SRC}/objects/PWidget.cpp
    ${SRC}/objects/PWindow.cpp
    ${SRC}/objects/PImageBox.cpp
    ${SRC}/objects/PCanvas.cpp
    ${SRC}/objects/PColor.cpp
    ${SRC}/objects/PDrawObject.cpp
    ${SRC}/objects/PFont.cpp
    ${SRC}/objects/PTextObject.cpp
    ${SRC}/objects/PLabel.cpp
    ${SRC}/objects/PTextBox.cpp
    ${SRC}/objects/PMovie.cpp
    ${SRC}/objects/PCustomObject.cpp

    ${SRC}/utility/PEBLUtility.cpp
    ${SRC}/utility/PError.cpp
    ${SRC}/utility/BinReloc.cpp
    ${SRC}/utility/PEBLPath.cpp
    ${SRC}/utility/PEBLHTTP.cpp
    ${SRC}/utility/PEBLHTTP_ios.mm
    ${SRC}/utility/md5.cpp
    ${SRC}/utility/FontCache.cpp
    ${SRC}/utility/FormatParser.cpp
    ${SRC}/utility/PLabStreamingLayer.cpp
    ${SRC}/utility/re.c

    ${SRC}/platforms/sdl/PlatformEnvironment.cpp
    ${SRC}/platforms/sdl/PlatformWidget.cpp
    ${SRC}/platforms/sdl/PlatformWindow.cpp
    ${SRC}/platforms/sdl/PlatformImageBox.cpp
    ${SRC}/platforms/sdl/PlatformKeyboard.cpp
    ${SRC}/platforms/sdl/PlatformFont.cpp
    ${SRC}/platforms/sdl/PlatformLabel.cpp
    ${SRC}/platforms/sdl/PlatformTextBox.cpp
    ${SRC}/platforms/sdl/PlatformTimer.cpp
    ${SRC}/platforms/sdl/PlatformDrawObject.cpp
    ${SRC}/platforms/sdl/PlatformCanvas.cpp
    ${SRC}/platforms/sdl/SDLUtility.cpp
    ${SRC}/platforms/sdl/PlatformEventQueue.cpp
    ${SRC}/platforms/sdl/PlatformAudioOut.cpp
    ${SRC}/platforms/sdl/PlatformNetwork.cpp
    ${SRC}/platforms/sdl/PlatformJoystick.cpp
    ${SRC}/platforms/sdl/PlatformAudioIn.cpp

    ${SRC}/platforms/ios/PEBLiOS.mm
    ${SRC}/platforms/ios/PEBLiOSRunLoop.cpp
)

# The flex scanner includes C++ headers (as in the Makefile).
set_source_files_properties(${SRC}/base/lex.yy.c PROPERTIES LANGUAGE CXX)

add_executable(PEBL MACOSX_BUNDLE ${PEBL_SOURCES})

target_compile_definitions(PEBL PRIVATE
    PEBL_IOS
    PEBL_UNIX
    PEBL_ITERATIVE_EVAL
    PEBL_MIXER
    PEBL_NETWORK
    PEBL_AUDIOIN
    PEBL_HTTP
    HTTP_LIB=4
    PEBL_VERSION="${PEBL_VERSION_STRING}"
    PREFIX=/
    EXECNAME=pebl2
    PEBLNAME=pebl2
    PEBLDIRNAME="pebl2"
)

target_compile_options(PEBL PRIVATE
    $<$<COMPILE_LANGUAGE:CXX,OBJCXX>:-Wno-write-strings>
    -Wno-deprecated-declarations
    -Wno-register
    $<$<COMPILE_LANGUAGE:OBJC,OBJCXX>:-fobjc-arc>
)

target_include_directories(PEBL PRIVATE ${SRC}/utility ${GFX})

target_link_libraries(PEBL PRIVATE
    SDL2::SDL2main
    SDL2::SDL2-static
    SDL2_image::SDL2_image-static
    SDL2_ttf::SDL2_ttf-static
    SDL2_mixer::SDL2_mixer-static
    SDL2_net::SDL2_net-static
    SDL2_gfx
    "-framework Foundation"
    "-framework UIKit"
    "-framework AVFoundation"
    "-framework AudioToolbox"
    "-framework CoreAudio"
    "-framework CoreGraphics"
    "-framework CoreHaptics"
    "-framework CoreMotion"
    "-framework GameController"
    "-framework Metal"
    "-framework QuartzCore"
    "-framework OpenGLES"
)

#-------------------------------------------------------------------------------
# App bundle
#-------------------------------------------------------------------------------
set_target_properties(PEBL PROPERTIES
    OUTPUT_NAME "PEBL"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
    MACOSX_BUNDLE_GUI_IDENTIFIER "${PEBL_BUNDLE_ID}"
    MACOSX_BUNDLE_BUNDLE_NAME "PEBL"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PEBL_VERSION_STRING}"
    MACOSX_BUNDLE_BUNDLE_VERSION "${PEBL_BUILD_NUMBER}"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${PEBL_BUNDLE_ID}"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "2"          # iPad
    XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "${CMAKE_OSX_DEPLOYMENT_TARGET}"
    XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC "YES"
    XCODE_ATTRIBUTE_ENABLE_BITCODE "NO"
    XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT "dwarf-with-dsym"
    XCODE_ATTRIBUTE_ASSETCATALOG_COMPILER_APPICON_NAME "AppIcon"
)

target_sources(PEBL PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/Assets.xcassets")
set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/Assets.xcassets"
    PROPERTIES MACOSX_PACKAGE_LOCATION Resources)

if(PEBL_DEVELOPMENT_TEAM)
    set_target_properties(PEBL PROPERTIES
        XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${PEBL_DEVELOPMENT_TEAM}"
        XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Automatic"
        XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "Apple Development")
else()
    # Unsigned build (CI); sign later with Xcode, Sideloadly, AltStore, ...
    set_target_properties(PEBL PROPERTIES
        XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
        XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO"
        XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "")
endif()

# Copy the read-only PEBL resources into the bundle: the standard library,
# media (fonts, images, sounds, settings), the battery and the touch launcher.
# The battery is copied again to Documents on first launch (see PEBLiOS.mm),
# where scripts can write their data/ folders.
add_custom_command(TARGET PEBL POST_BUILD
    COMMAND rsync -a --delete
            --exclude "*.zip" --exclude "data/" --exclude ".DS_Store"
            "${PEBL_ROOT}/battery/" "$<TARGET_BUNDLE_CONTENT_DIR:PEBL>/battery/"
    COMMAND rsync -a --delete --exclude ".DS_Store"
            "${PEBL_ROOT}/media/" "$<TARGET_BUNDLE_CONTENT_DIR:PEBL>/media/"
    COMMAND rsync -a --delete --exclude ".DS_Store"
            "${PEBL_ROOT}/pebl-lib/" "$<TARGET_BUNDLE_CONTENT_DIR:PEBL>/pebl-lib/"
    COMMAND ${CMAKE_COMMAND} -E copy
            "${CMAKE_CURRENT_SOURCE_DIR}/resources/ios-launcher.pbl"
            "$<TARGET_BUNDLE_CONTENT_DIR:PEBL>/ios-launcher.pbl"
    COMMENT "Copying PEBL battery, media and libraries into the app bundle")
