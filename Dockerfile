# syntax=docker/dockerfile:1
###############################################################################
# VaN3Twin (DriveX-devs) — Imagen Docker
#
# Base    : Ubuntu 22.04 (Jammy) — versión oficialmente soportada por VaN3Twin
# Arch    : multi-arquitectura (arm64 nativo en Apple Silicon / amd64 en Intel)
# Autor   : Guía de instalación VaN3Twin en Docker (macOS Tahoe)
#
# La imagen replica el procedimiento oficial del README:
#   1) dependencias del sistema (apt)          [capas 1-2]
#   2) gRPC v1.60.0 desde código fuente        [capa 3]
#   3) usuario no-root (exigido por el script) [capa 4]
#   4) clonado del repo + sandbox_builder.sh   [capas 5-6]
#   5) ./ns3 configure + ./ns3 build           [capa 7]
###############################################################################

FROM ubuntu:22.04

# --- Argumentos de construcción -------------------------------------------
# GRPC_VERSION: versión de gRPC que instala sandbox_builder.sh oficialmente
# VAN3TWIN_REF: rama/tag del repo a clonar (master por defecto)
ARG DEBIAN_FRONTEND=noninteractive
ARG GRPC_VERSION=v1.60.0
ARG VAN3TWIN_REF=master
# Repo a clonar: por defecto el upstream de DriveX; para la imagen docente con
# la integración SUMO-GEO incluida, pasar el fork:
#   --build-arg VAN3TWIN_REPO=https://github.com/Pbarbecho/VaN3TwinGEO.git
ARG VAN3TWIN_REPO=https://github.com/DriveX-devs/VaN3Twin.git
# Bindings Python de ns-3 (necesarios para PyViz). DESACTIVADOS por defecto:
# verificado (ago-2026, arm64) que los bindings pregenerados NO compilan con
# los parches de VaN3Twin (fallan propagation, tap-bridge y módulos del
# núcleo) -> PyViz no disponible en este fork; usar NetAnim + Wireshark.
# Si upstream lo arreglara, reintentar con (existe fallback automático):
#   docker compose build --build-arg NS3_PYTHON_FLAG=--enable-python-bindings
ARG NS3_PYTHON_FLAG=--disable-python

ENV TZ=Etc/UTC \
    LANG=C.UTF-8

# ---------------------------------------------------------------------------
# Capa 1 — Toolchain y dependencias de ns-3 / VaN3Twin
#
# Lista derivada de sandbox_builder.sh (opción install-dependencies), con
# tres diferencias deliberadas:
#   * SIN libc6-dev-i386  -> no existe en arm64 (Apple Silicon)
#   * libopencv-dev (apt) -> sustituye la compilación de OpenCV desde fuente;
#     src/automotive/CMakeLists.txt solo requiere find_package(OpenCV),
#     y el paquete de Ubuntu 22.04 (OpenCV 4.5.4) lo satisface.
#     Ahorra ~40 min de compilación y ~2 GB de imagen.
#   * libgl1-mesa-dri + mesa-utils -> driver software de Mesa (swrast/
#     llvmpipe) para que sumo-gui pueda renderizar OpenGL DENTRO del
#     contenedor con LIBGL_ALWAYS_SOFTWARE=1 (sin este paquete: "libGL
#     error: failed to load driver: swrast" y GLXBadContext con XQuartz).
#     mesa-utils aporta glxinfo/glxgears para diagnosticar.
#   * xvfb + x11vnc + fluxbox -> servidor X virtual con GLX por software,
#     acceso VNC y un gestor de ventanas ligero (sin él, las ventanas de
#     sumo-gui aparecen sin bordes, inmóviles y sobre fondo negro):
#     ruta de GUI por defecto, que NO depende de XQuartz/iglx; los arranca
#     automáticamente el `command` del docker-compose.yml.
#   * nodejs -> lo exige el módulo vehicle-visualizer (lanza "node server.js").
#   * python3-gi/gir1.2-*/pygraphviz/graphviz/ipython3 -> dependencias GTK
#     de PyViz (el visualizador interactivo de ns-3); solo se usan si se
#     habilitan los bindings Python (NS3_PYTHON_FLAG, capa 7).
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential g++ gcc gdb valgrind \
        cmake ninja-build ccache \
        git mercurial unzip wget curl ca-certificates \
        pkg-config autoconf automake libtool \
        python3 python3-dev python3-pip python3-setuptools \
        lsb-release sudo nano \
        libboost-all-dev \
        libgsl-dev gsl-bin libgsl27 libgslcblas0 \
        sqlite3 libsqlite3-dev \
        libxml2 libxml2-dev \
        libssl-dev \
        libgtk-3-dev \
        qtbase5-dev qtchooser qt5-qmake qtbase5-dev-tools \
        libgl1-mesa-dri mesa-utils \
        xvfb x11vnc fluxbox \
        nodejs \
        python3-gi python3-gi-cairo gir1.2-gtk-3.0 gir1.2-goocanvas-2.0 \
        python3-pygraphviz graphviz ipython3 \
        libopencv-dev \
        libprotobuf-dev protobuf-compiler \
        libssh-dev \
        tcpdump iproute2 \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Capa 2 — SUMO 1.12.0 desde los repos de Ubuntu 22.04
#
# NO se usa el PPA ppa:sumo/stable porque:
#   a) los PPA de Launchpad normalmente NO publican binarios arm64
#      (fallaría en Apple Silicon), y
#   b) el README advierte que versiones nuevas de SUMO pueden romper
#      la compatibilidad con TraCI. SUMO 1.12.0 está dentro del rango
#      probado por los autores (v1.6.0 – v1.18.0).
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        sumo sumo-tools \
    && rm -rf /var/lib/apt/lists/*

ENV SUMO_HOME=/usr/share/sumo

# ---------------------------------------------------------------------------
# Capa 3 — gRPC v1.60.0 desde código fuente
#
# Obligatorio: src/carla/CMakeLists.txt hace find_package(gRPC CONFIG REQUIRED)
# y el paquete apt de Ubuntu 22.04 NO incluye los ficheros de configuración
# CMake de gRPC. Se replica el procedimiento exacto de sandbox_builder.sh.
# El "rm -rf" final dentro del MISMO RUN evita que ~6 GB de fuentes queden
# en la capa de la imagen.
# ---------------------------------------------------------------------------
RUN git clone -b ${GRPC_VERSION} --depth 1 https://github.com/grpc/grpc /opt/grpc \
    && cd /opt/grpc \
    && git submodule update --init --depth 1 \
    && mkdir -p cmake/build && cd cmake/build \
    && cmake -DgRPC_INSTALL=ON \
             -DgRPC_BUILD_TESTS=OFF \
             -DCMAKE_BUILD_TYPE=Release \
             -DCMAKE_INSTALL_PREFIX=/usr/local \
             ../.. \
    && make -j"$(nproc)" \
    && make install \
    && ldconfig \
    && rm -rf /opt/grpc

# ---------------------------------------------------------------------------
# Capa 3b — Visor NetAnim (Qt5), instalado en /usr/local/bin/NetAnim
#
# NetAnim reproduce el XML que genera AnimationInterface (animación de
# paquetes entre nodos). No existe como paquete de Ubuntu, así que se
# compila aquí (Qt5 ya está en la capa 1) y queda listo en el PATH:
#   docker compose exec van3twin NetAnim   (con el visor VNC abierto)
# ---------------------------------------------------------------------------
# NetAnim moderno (3.109+) se construye con CMake (el antiguo NetAnim.pro
# de qmake ya no existe). Se intenta la etiqueta estable 3.110 y, si el
# nombre de la etiqueta cambiara, se usa master. libqt5svg5-dev se instala
# aquí (y no en la capa 1) para no invalidar la caché de las capas previas.
RUN apt-get update && apt-get install -y --no-install-recommends libqt5svg5-dev \
    && rm -rf /var/lib/apt/lists/* \
    && ( git clone --depth 1 -b netanim-3.110 https://gitlab.com/nsnam/netanim.git /opt/netanim-src \
         || git clone --depth 1 https://gitlab.com/nsnam/netanim.git /opt/netanim-src ) \
    && cmake -S /opt/netanim-src -B /opt/netanim-src/build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /opt/netanim-src/build -j"$(nproc)" \
    && BIN=$(find /opt/netanim-src/build -type f \( -name netanim -o -name NetAnim \) | head -1) \
    && test -n "$BIN" \
    && install -m 0755 "$BIN" /usr/local/bin/NetAnim \
    && ln -sf /usr/local/bin/NetAnim /usr/local/bin/netanim \
    && rm -rf /opt/netanim-src

# ---------------------------------------------------------------------------
# Capa 3c — Soporte de bindings Python para PyViz
#
# pybindgen: puro Python (lo usan las versiones de ns-3 hasta la 3.36).
# cppyy: lo usan ns-3.37+; solo se instala si existe wheel BINARIO para
# esta arquitectura (en arm64 no lo hay y compilarlo desde fuente tomaría
# horas; en ese caso se omite y actúa el fallback de la capa 7).
# ---------------------------------------------------------------------------
RUN pip3 install --no-cache-dir pybindgen \
    && (pip3 install --no-cache-dir --only-binary=:all: cppyy \
        || echo ">> cppyy sin wheel binario para $(uname -m): se omite")

# ---------------------------------------------------------------------------
# Capa 4 — Usuario no-root
#
# sandbox_builder.sh se niega a ejecutarse como root ("Please do NOT run
# this script as root"). Se crea el usuario 'vanet' con sudo sin contraseña
# para poder instalar paquetes adicionales desde dentro del contenedor.
# ---------------------------------------------------------------------------
RUN useradd -m -s /bin/bash vanet \
    && echo 'vanet ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/vanet \
    && chmod 0440 /etc/sudoers.d/vanet

USER vanet
WORKDIR /home/vanet

# ---------------------------------------------------------------------------
# Capa 5 — Clonado de VaN3Twin
# ---------------------------------------------------------------------------
RUN git clone --branch ${VAN3TWIN_REF} ${VAN3TWIN_REPO}

WORKDIR /home/vanet/VaN3Twin

# ---------------------------------------------------------------------------
# Capa 6 — Construcción del "sandbox" ns-3
#
# sandbox_builder.sh (SIN el argumento install-dependencies, porque las
# dependencias ya se instalaron en las capas 1-3):
#   * clona ns-3-dev del fork 5G-LENA (CTTC) + módulo nr (rama nr-v2x-dev)
#   * hace checkout de la etiqueta ns-3-dev-v2x-v0.2
#   * copia los módulos de VaN3Twin dentro de ns-3-dev/src/
#   * aplica parches (modelos de propagación, SignalInfo, Sionna, etc.)
#   * detecta Ubuntu 22.04 vía lsb_release (por eso se instaló lsb-release)
#
# El "echo" alimenta el "read -p 'Press ENTER...'" interactivo del script.
# ---------------------------------------------------------------------------
RUN echo "" | ./sandbox_builder.sh

# ---------------------------------------------------------------------------
# Capa 6b — Ejemplo v2v-simple-cam-exchange-80211p con animación NetAnim
#
# Aplica los 3 cambios documentados en el manual (sección Visualización):
#   1) include de ns3/netanim-module.h
#   2) AnimationInterface justo antes de Simulator::Run()
#   3) enlace con ${libnetanim} en el CMakeLists de los ejemplos
# Así la imagen genera v2v-cam-exchange-anim.xml de fábrica, sin ediciones
# manuales. Los grep finales validan que los parches se aplicaron (si
# upstream cambia el fichero, la build falla aquí y no en el enlace).
# ---------------------------------------------------------------------------
RUN cd ns-3-dev/src/automotive/examples \
    && sed -i 's|#include "ns3/wave-mac-helper.h"|#include "ns3/wave-mac-helper.h"\n#include "ns3/netanim-module.h"|' \
        v2v-simple-cam-exchange-80211p.cc \
    && sed -i 's|^  Simulator::Run ();|  AnimationInterface anim ("v2v-cam-exchange-anim.xml");\n  anim.SetMaxPktsPerTraceFile (500000);\n\n  Simulator::Run ();|' \
        v2v-simple-cam-exchange-80211p.cc \
    && sed -i '/NAME v2v-simple-cam-exchange-80211p/,/^)/ s|        ${libtraci}|        ${libtraci}\n        ${libnetanim}|' \
        CMakeLists.txt \
    && grep -q "netanim-module.h" v2v-simple-cam-exchange-80211p.cc \
    && grep -q "AnimationInterface" v2v-simple-cam-exchange-80211p.cc \
    && grep -q "libnetanim" CMakeLists.txt

# ---------------------------------------------------------------------------
# Capa 7 — Configuración y compilación de ns-3 + VaN3Twin
#
#   --build-profile=optimized : acelera el tiempo de simulación (README)
#   --enable-examples         : compila los ejemplos v2v-*/v2i-* (esenciales)
#   --enable-tests            : habilita la suite de tests de ns-3
#   --disable-python          : sin bindings Python (innecesarios, más rápido)
#   --disable-werror          : OBLIGATORIO en Ubuntu >= 22.04 según el README
#
# Esta es la capa más larga: 45-120 min según CPU/RAM asignadas a Docker.
# ---------------------------------------------------------------------------
WORKDIR /home/vanet/VaN3Twin/ns-3-dev

# Intento 1: con bindings Python (PyViz). Si configure o build fallan por
# los bindings (no probados por DriveX en este fork), fallback automático
# SIN Python para garantizar una imagen funcional. Comprobar el resultado:
#   ./ns3 show config | grep -i python
#
# REBUILD_NS3: cache-bust selectivo. Cambiar su valor fuerza a reejecutar
# SOLO esta capa (reintento de bindings) conservando la caché de las capas
# pesadas anteriores (gRPC, SUMO, NetAnim...):
#   docker compose build --build-arg REBUILD_NS3=$(date +%s)
ARG REBUILD_NS3=0
RUN echo "cache-bust: ${REBUILD_NS3}" \
    && ( ./ns3 configure --build-profile=optimized --enable-examples \
          --enable-tests ${NS3_PYTHON_FLAG} --disable-werror \
      && ./ns3 build ) \
    || ( echo ">> Bindings Python no disponibles: recompilando sin PyViz" \
         && ./ns3 clean \
         && ./ns3 configure --build-profile=optimized --enable-examples \
                --enable-tests --disable-python --disable-werror \
         && ./ns3 build )

# ---------------------------------------------------------------------------
# Valores por defecto de ejecución (el docker-compose los puede sobreescribir)
# ---------------------------------------------------------------------------
# Por defecto la GUI apunta al X virtual interno (VNC) con OpenGL por
# software; el compose puede sobreescribirlo para la alternativa XQuartz.
ENV DISPLAY=:99 \
    LIBGL_ALWAYS_SOFTWARE=1

CMD ["/bin/bash"]
