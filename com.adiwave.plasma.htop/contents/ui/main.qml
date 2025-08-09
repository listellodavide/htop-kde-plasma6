import QtQuick 6.5
import QtQuick.Layouts 6.5
import QtQuick.Controls 6.5

import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support

Item {
    width: 200
    height: 100

    Label {
        text: "Hello Plasma 6"
        anchors.centerIn: parent
    }
}
