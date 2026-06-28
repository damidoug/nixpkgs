{
  config,
  uthash,
  lib,
  stdenv,
  ninja,
  nv-codec-headers-12,
  fetchFromGitHub,
  fetchurl,
  addDriverRunpath,
  autoAddDriverRunpath,
  cudaSupport ? config.cudaSupport,
  cmake,
  fdk_aac,
  ffmpeg,
  jansson,
  libjack2,
  libxkbcommon,
  libpthread-stubs,
  libxdmcp,
  qtbase,
  qtsvg,
  speex,
  libv4l,
  x264,
  curl,
  wayland,
  libx11,
  pkg-config,
  libvlc,
  libGL,
  mbedtls,
  wrapGAppsHook3,
  scriptingSupport ? true,
  luajit,
  swig,
  python3,
  python311,
  alsaSupport ? stdenv.hostPlatform.isLinux,
  alsa-lib,
  pulseaudioSupport ? config.pulseaudio or stdenv.hostPlatform.isLinux,
  libpulseaudio,
  browserSupport ? stdenv.hostPlatform.isLinux,
  cef-binary,
  pciutils,
  pipewireSupport ? stdenv.hostPlatform.isLinux,
  withFdk ? true,
  pipewire,
  libdrm,
  librist,
  cjson,
  libva,
  srt,
  qtwayland,
  wrapQtAppsHook,
  nlohmann_json,
  websocketpp,
  asio,
  decklinkSupport ? false,
  blackmagic-desktop-video,
  freetype,
  libdatachannel,
  libvpl,
  qrcodegencpp,
  rnnoise,
  simde,
  nix-update-script,
  kdePackages,
  swift,
}:

let
  inherit (lib) optional optionals;

  selectSystem =
    attrs:
    attrs.${stdenv.hostPlatform.system} or (throw "Unsupported system ${stdenv.hostPlatform.system}");

  cef = cef-binary.overrideAttrs (
    oldAttrs:
    let
      version = "6533";
      revision = "6";
    in
    {
      inherit version;

      src = fetchurl {
        url = "https://cdn-fastly.obsproject.com/downloads/cef_binary_${version}_linux_${
          selectSystem {
            aarch64-linux = "aarch64";
            x86_64-linux = "x86_64";
          }
        }_v${revision}.tar.xz";
        hash = selectSystem {
          aarch64-linux = "sha256-ZCUURp6qKaXIh4kQhNLnP33C10Bfffp3JrLbwkswmZk=";
          x86_64-linux = "sha256-eWMzVRmhnM3FIz9zNMWrAjAm4vPpoMxBcAfAnYZggUY=";
        };
      };
    }
  );
in
stdenv.mkDerivation (finalAttrs: {
  pname = "obs-studio";
  version = "32.1.2";

  src = fetchFromGitHub {
    owner = "obsproject";
    repo = "obs-studio";
    rev = finalAttrs.version;
    hash = "sha256-9i7wLHpKqbcYzPlzSMF4xEpsTINQnVDPtneLJaSM+/I=";
    fetchSubmodules = true;
  };

  separateDebugInfo = true;

  patches = [
    ./fix-nix-plugin-path.patch
  ];

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    wrapQtAppsHook
    kdePackages.extra-cmake-modules
  ]
  ++ optionals stdenv.hostPlatform.isLinux [
    addDriverRunpath
    wrapGAppsHook3
  ]
  ++ optional stdenv.hostPlatform.isDarwin swift
  ++ optional scriptingSupport swig
  ++ optional cudaSupport autoAddDriverRunpath;

  buildInputs = [
    curl
    ffmpeg
    jansson
    libjack2
    qtbase
    qtsvg
    speex
    x264
    mbedtls
    librist
    cjson
    srt
    nlohmann_json
    websocketpp
    asio
    libdatachannel
    qrcodegencpp
    uthash
  ]
  ++ optionals stdenv.hostPlatform.isDarwin [
    freetype
    rnnoise
  ]
  ++ optionals stdenv.hostPlatform.isLinux [
    libv4l
    libvlc
    libxkbcommon
    libpthread-stubs
    libxdmcp
    wayland
    pciutils
    libva
    qtwayland
    libvpl
    nv-codec-headers-12
  ]
  ++ optionals scriptingSupport [
    luajit
    (if stdenv.hostPlatform.isDarwin then python311 else python3)
  ]
  ++ optional alsaSupport alsa-lib
  ++ optional pulseaudioSupport libpulseaudio
  ++ optionals pipewireSupport [
    pipewire
    libdrm
  ]
  ++ optional browserSupport cef
  ++ optional withFdk fdk_aac;

  propagatedBuildInputs = [ simde ];

  # Copied from the obs-linuxbrowser
  postUnpack = lib.optionalString browserSupport ''
    ln -s ${cef} cef
  '';

  postPatch =
    ''
      cp ${./CMakeUserPresets.json} ./CMakeUserPresets.json
    ''
    + lib.optionalString stdenv.hostPlatform.isDarwin ''
      # Remove Xcode generator requirement and xcrun-based SDK checks
      sed -i '/^if(NOT XCODE)/,/^endif()/d' cmake/macos/compilerconfig.cmake
      sed -i '/^check_sdk_requirements()/d' cmake/macos/compilerconfig.cmake
      # Remove download of pre-built obs-deps (Nix provides all deps via buildInputs)
      sed -i '/^include(buildspec)/d' cmake/macos/defaults.cmake
      # Remove -py3-stable-abi swig flag (not supported in nixpkgs swig)
      sed -i 's/-py3-stable-abi//' shared/obs-scripting/cmake/python.cmake
      sed -i 's/-py3-stable-abi//' shared/obs-scripting/obspython/CMakeLists.txt
      # Swift module name cannot contain hyphens (Xcode handles this automatically)
      sed -i '/^add_library(libobs-metal SHARED)/a set_target_properties(libobs-metal PROPERTIES Swift_MODULE_NAME libobs_metal)' libobs-metal/CMakeLists.txt
      # Explicitly pass bridging header to swiftc (Xcode uses SWIFT_OBJC_BRIDGING_HEADER attribute instead)
      echo 'target_compile_options(libobs-metal PRIVATE "$<$<COMPILE_LANGUAGE:Swift>:-import-objc-header;''${CMAKE_CURRENT_SOURCE_DIR}/libobs-metal-Bridging-Header.h>")' >> libobs-metal/CMakeLists.txt
      # Enable Swift language for Ninja (Xcode enables it implicitly)
      substituteInPlace CMakeLists.txt \
        --replace-fail \
        'project(obs-studio VERSION ''${OBS_VERSION_CANONICAL})' \
        'project(obs-studio VERSION ''${OBS_VERSION_CANONICAL})
if(APPLE)
  enable_language(Swift)
endif()'
    '';

  cmakeFlags = [
    "--preset"
    "nixpkgs-${if stdenv.hostPlatform.isDarwin then "darwin" else "linux"}"
    "-DOBS_VERSION_OVERRIDE=${finalAttrs.version}"
    "-Wno-dev" # kill dev warnings that are useless for packaging
    "-DENABLE_JACK=ON"
    "-DENABLE_WEBRTC=ON"
    (lib.cmakeBool "ENABLE_QSV11" stdenv.hostPlatform.isx86_64)
    (lib.cmakeBool "ENABLE_LIBFDK" withFdk)
    (lib.cmakeBool "ENABLE_SCRIPTING" scriptingSupport)
    (lib.cmakeBool "ENABLE_ALSA" alsaSupport)
    (lib.cmakeBool "ENABLE_PULSEAUDIO" pulseaudioSupport)
    (lib.cmakeBool "ENABLE_PIPEWIRE" pipewireSupport)
    (lib.cmakeBool "ENABLE_AJA" false) # TODO: fix linking against libajantv2
    (lib.cmakeBool "ENABLE_BROWSER" browserSupport)
    (lib.cmakeBool "ENABLE_VLC" stdenv.hostPlatform.isLinux)
    (lib.cmakeBool "ENABLE_VIRTUALCAM" false)
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    "-DCMAKE_Swift_COMPILER=swiftc"
  ]
  ++ lib.optional browserSupport "-DCEF_ROOT_DIR=../../cef";

  env.NIX_CFLAGS_COMPILE = toString (
    [
      "-Wno-error=deprecated-declarations"
      "-Wno-error=sign-compare" # https://github.com/obsproject/obs-studio/issues/10200
    ]
    ++ lib.optional stdenv.hostPlatform.isLinux "-Wno-error=stringop-overflow="
  );

  dontWrapGApps = stdenv.hostPlatform.isLinux;
  preFixup =
    let
      wrapperLibraries = [
        libx11
        libvlc
        libGL
      ]
      ++ optionals decklinkSupport [ blackmagic-desktop-video ];
    in
    lib.optionalString stdenv.hostPlatform.isLinux ''
      qtWrapperArgs+=(
        --prefix LD_LIBRARY_PATH : "$out/lib:${lib.makeLibraryPath wrapperLibraries}"
        ''${gappsWrapperArgs[@]}
      )
    ''
    + lib.optionalString browserSupport ''
      # Remove cef components before patchelf, otherwise it will fail
      rm $out/lib/obs-plugins/libcef.so
      rm $out/lib/obs-plugins/libEGL.so
      rm $out/lib/obs-plugins/libGLESv2.so
      rm $out/lib/obs-plugins/libvk_swiftshader.so
      rm $out/lib/obs-plugins/libvulkan.so.1
      rm $out/lib/obs-plugins/chrome-sandbox
    '';

  postFixup = lib.concatStrings [
    (lib.optionalString (stdenv.hostPlatform.isLinux && !cudaSupport) ''
      addDriverRunpath $out/lib/lib*.so
      addDriverRunpath $out/lib/obs-plugins/*.so
    '')

    (lib.optionalString browserSupport ''
      # Link cef components again after patchelfing other libs
      ln -sf ${cef}/${cef.buildType}/* $out/lib/obs-plugins/
    '')
  ];

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Free and open source software for video recording and live streaming";
    longDescription = ''
      This project is a rewrite of what was formerly known as "Open Broadcaster
      Software", software originally designed for recording and streaming live
      video content, efficiently
    '';
    homepage = "https://obsproject.com";
    maintainers = with lib.maintainers; [
      damidoug
      jb55
      materus
      fpletz
    ];
    license = with lib.licenses; [ gpl2Plus ] ++ optional withFdk fraunhofer-fdk;
    platforms = [
      "x86_64-linux"
      "i686-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    mainProgram = "obs";
  };
})
