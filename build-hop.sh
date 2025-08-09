#!/usr/bin/env bash

rm -rf $HOME/.local/share/kpackage/generic/com.adiwave.plasma.htop/
plasmapkg2 -i com.adiwave.plasma.htop/
plasmoidviewer --applet com.adiwave.plasma.htop
