#!/usr/bin/env bash

rm -rf $HOME/.local/share/kpackage/generic/com.adiwave.plasma.modernclock/
plasmapkg2 -i com.adiwave.plasma.modernclock/
plasmoidviewer --applet com.adiwave.plasma.modernclock
