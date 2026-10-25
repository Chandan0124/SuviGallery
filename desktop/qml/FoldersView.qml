import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: foldersRoot

    readonly property string fIcon: "Segoe Fluent Icons, Segoe MDL2 Assets"

    property var foldersModel: []
    property var targetRemoveFolder: null

    Connections {
        target: gallery
        function onFoldersLoaded(folders) {
            foldersRoot.foldersModel = folders;
        }
    }

    Component.onCompleted: gallery.loadFolders()

    readonly property int targetWidth: 260
    readonly property int columnsCount: Math.max(1, Math.floor(grid.width / targetWidth))
    readonly property real tileWidth: grid.width / columnsCount

    GridView {
        id: grid
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.topMargin: 20
        anchors.bottomMargin: 20
        anchors.rightMargin: 8
        cellWidth: foldersRoot.tileWidth
        cellHeight: 220
        clip: true
        model: foldersRoot.foldersModel
        focus: true

        // Keyboard Fast Navigation
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_PageDown) {
                grid.contentY = Math.min(grid.contentHeight - grid.height, grid.contentY + grid.height * 0.85);
                event.accepted = true;
            } else if (event.key === Qt.Key_PageUp) {
                grid.contentY = Math.max(0, grid.contentY - grid.height * 0.85);
                event.accepted = true;
            } else if (event.key === Qt.Key_Home) {
                grid.contentY = 0;
                event.accepted = true;
            } else if (event.key === Qt.Key_End) {
                grid.contentY = Math.max(0, grid.contentHeight - grid.height);
                event.accepted = true;
            }
        }

        // Native Windows 11 Fluent Vertical ScrollBar
        ScrollBar.vertical: ScrollBar {
            id: vbarFolders
            policy: ScrollBar.AsNeeded
            hoverEnabled: true
            active: true
            width: (hovered || pressed) ? 12 : 8
            Behavior on width { NumberAnimation { duration: 120 } }

            contentItem: Rectangle {
                implicitWidth: 8
                implicitHeight: 48
                radius: width / 2
                color: vbarFolders.pressed 
                    ? Qt.rgba(255, 255, 255, 0.65) 
                    : (vbarFolders.hovered ? Qt.rgba(255, 255, 255, 0.45) : Qt.rgba(255, 255, 255, 0.22))
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            background: Rectangle {
                implicitWidth: (vbarFolders.hovered || vbarFolders.pressed) ? 12 : 8
                color: (vbarFolders.hovered || vbarFolders.pressed) ? Qt.rgba(255, 255, 255, 0.05) : "transparent"
                radius: width / 2
            }
        }

        delegate: Item {
            width: grid.cellWidth
            height: grid.cellHeight

            readonly property var folder: modelData

            Rectangle {
                anchors.fill: parent
                anchors.margins: 6
                radius: 8
                color: root.cBgCard
                border.color: mouseArea.containsMouse ? Qt.rgba(255, 255, 255, 0.25) : root.cBorder
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Folder Cover
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: "#202020"
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: folder.cover_image_id ? ("image://thumb/" + folder.cover_image_id) : ""
                            fillMode: Image.PreserveAspectCrop
                            visible: folder.cover_image_id > 0
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "\uED25"
                            font.family: foldersRoot.fIcon
                            font.pixelSize: 44
                            color: root.cTextDim
                            visible: !folder.cover_image_id
                        }
                    }

                    // Folder Metadata
                    Rectangle {
                        Layout.fillWidth: true
                        height: 64
                        color: root.cBgCard

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 3

                            RowLayout {
                                spacing: 6
                                Layout.fillWidth: true
                                Text {
                                    text: "\uED25"
                                    font.family: foldersRoot.fIcon
                                    font.pixelSize: 13
                                    color: root.cTextMuted
                                }
                                Text {
                                    text: folder.name
                                    color: "#ffffff"
                                    font.family: root.fSans
                                    font.bold: true
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            Text {
                                text: folder.directory
                                color: root.cTextDim
                                font.family: root.fSans
                                font.pixelSize: 10
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }

                            RowLayout {
                                spacing: 14
                                RowLayout {
                                    spacing: 4
                                    Text {
                                        text: "\uEB9F"
                                        font.family: foldersRoot.fIcon
                                        font.pixelSize: 11
                                        color: root.cTextMuted
                                    }
                                    Text {
                                        text: folder.photo_count + " photos"
                                        color: root.cTextMuted
                                        font.family: root.fSans
                                        font.pixelSize: 11
                                    }
                                }
                                RowLayout {
                                    spacing: 4
                                    Text {
                                        text: "\uE77B"
                                        font.family: foldersRoot.fIcon
                                        font.pixelSize: 11
                                        color: root.cTextMuted
                                    }
                                    Text {
                                        text: folder.face_count + " faces"
                                        color: root.cTextMuted
                                        font.family: root.fSans
                                        font.pixelSize: 11
                                    }
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    id: mouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.selectedPeopleFilters = [];
                        root.activeFolder = folder.directory;
                        root.switchTab("photos");
                    }
                }

                // Remove Folder Button (Top-Right)
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 10
                    width: 28
                    height: 28
                    radius: 6
                    color: btnRemoveFolderMouse.containsMouse ? Qt.rgba(239/255, 68/255, 68/255, 0.2) : Qt.rgba(0, 0, 0, 0.5)
                    border.color: btnRemoveFolderMouse.containsMouse ? Qt.rgba(239/255, 68/255, 68/255, 0.5) : Qt.rgba(255, 255, 255, 0.15)
                    z: 10

                    Text {
                        anchors.centerIn: parent
                        text: "\uE74D"
                        font.family: foldersRoot.fIcon
                        font.pixelSize: 13
                        color: btnRemoveFolderMouse.containsMouse ? "#ff99a4" : "#ffffff"
                    }

                    MouseArea {
                        id: btnRemoveFolderMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            foldersRoot.targetRemoveFolder = folder;
                            confirmRemoveFolderDialog.visible = true;
                        }
                    }
                }
            }
        }
    }

    // Remove Folder Confirmation Modal (Windows 11 Fluent Style)
    Rectangle {
        id: confirmRemoveFolderDialog
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.65)
        visible: false
        z: 3000

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(460, parent.width - 40)
            height: 200
            radius: 8
            color: "#2c2c2c"
            border.color: Qt.rgba(255, 255, 255, 0.12)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12

                RowLayout {
                    spacing: 8
                    Text {
                        text: "\uE74D"
                        font.family: foldersRoot.fIcon
                        font.pixelSize: 16
                        color: "#ff99a4"
                    }
                    Text {
                        text: "Remove Folder from Library?"
                        color: "#ffffff"
                        font.family: root.fSans
                        font.bold: true
                        font.pixelSize: 15
                    }
                }

                Text {
                    text: foldersRoot.targetRemoveFolder
                        ? ("Remove '" + foldersRoot.targetRemoveFolder.name + "' (" + foldersRoot.targetRemoveFolder.photo_count + " photos) from your library catalog?\n\nAll indexed photos and faces in this folder will be removed.\nYour original files on disk will NOT be deleted.")
                        : ""
                    color: root.cTextMuted
                    font.family: root.fSans
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: 10

                    Button {
                        flat: true
                        contentItem: Text { text: "Cancel"; color: "#ffffff"; font.family: root.fSans; font.pixelSize: 12 }
                        background: Rectangle { color: Qt.rgba(255, 255, 255, 0.06); border.color: root.cBorder; radius: 6 }
                        onClicked: confirmRemoveFolderDialog.visible = false
                    }

                    Button {
                        flat: true
                        contentItem: Text {
                            text: "Remove from Library"
                            color: "#ffffff"
                            font.family: root.fSans
                            font.bold: true
                            font.pixelSize: 12
                        }
                        background: Rectangle {
                            color: "#c42b1c"
                            radius: 6
                        }
                        onClicked: {
                            confirmRemoveFolderDialog.visible = false;
                            if (foldersRoot.targetRemoveFolder) {
                                var dir = foldersRoot.targetRemoveFolder.directory;
                                gallery.removeFolderFromLibrary(dir);
                                if (root.activeFolder === dir) {
                                    root.activeFolder = "";
                                }
                                root.refreshPhotos();
                            }
                        }
                    }
                }
            }
        }
    }

    // Empty State
    Rectangle {
        anchors.centerIn: parent
        width: 320
        height: 200
        color: "transparent"
        visible: foldersRoot.foldersModel.length === 0

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 12

            Text {
                text: "\uED25"
                font.family: foldersRoot.fIcon
                font.pixelSize: 48
                color: root.cTextDim
                Layout.alignment: Qt.AlignHCenter
            }
            Text { text: "No Folders Indexed Yet"; color: root.cTextMain; font.family: root.fSans; font.bold: true; font.pixelSize: 15; Layout.alignment: Qt.AlignHCenter }
            Text { text: "Click 'Add Folder' above to organize your photos."; color: root.cTextMuted; font.family: root.fSans; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
            Button {
                flat: true
                Layout.alignment: Qt.AlignHCenter
                contentItem: Text { text: "Select Folder"; color: "#ffffff"; font.family: root.fSans; font.bold: true; font.pixelSize: 12 }
                background: Rectangle { color: Qt.rgba(255, 255, 255, 0.08); border.color: Qt.rgba(255, 255, 255, 0.15); radius: 6 }
                onClicked: gallery.pickFolder()
            }
        }
    }
}
