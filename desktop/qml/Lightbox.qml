import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: lightboxRoot
    color: "#181818"
    z: 2000

    readonly property string fIcon: "Segoe Fluent Icons, Segoe MDL2 Assets"

    property var photosList: []
    property int currentIndex: -1
    property var currentPhoto: (currentIndex >= 0 && currentIndex < photosList.length) ? photosList[currentIndex] : null
    property var currentFaces: []
    property bool showFaces: false
    property int selectedFaceId: -1

    Connections {
        target: gallery
        function onPhotoFacesLoaded(imageId, faces) {
            if (lightboxRoot.currentPhoto && lightboxRoot.currentPhoto.id === imageId) {
                lightboxRoot.currentFaces = faces;
            }
        }
        function onPhotoLocationUpdated(imageId, newLocation) {
            if (lightboxRoot.currentPhoto && lightboxRoot.currentPhoto.id === imageId) {
                var p = Object.assign({}, lightboxRoot.currentPhoto);
                p.location_name = newLocation;
                var list = lightboxRoot.photosList.slice();
                list[lightboxRoot.currentIndex] = p;
                lightboxRoot.photosList = list;
            }
        }
    }

    function show(photos, index) {
        lightboxRoot.photosList = photos;
        lightboxRoot.currentIndex = index;
        lightboxRoot.visible = true;
        lightboxRoot.selectedFaceId = -1;
        loadFaces();
    }

    function hide() {
        lightboxRoot.visible = false;
        lightboxRoot.currentIndex = -1;
        lightboxRoot.currentFaces = [];
        lightboxRoot.selectedFaceId = -1;
        lightboxRoot.showFaces = false;
    }

    function loadFaces() {
        if (currentPhoto) {
            gallery.loadPhotoFaces(currentPhoto.id);
        }
    }

    function prev() {
        if (currentIndex > 0) {
            currentIndex--;
            selectedFaceId = -1;
            loadFaces();
        }
    }

    function next() {
        if (currentIndex < photosList.length - 1) {
            currentIndex++;
            selectedFaceId = -1;
            loadFaces();
        }
    }

    // Keyboard Shortcuts
    focus: visible
    Keys.onEscapePressed: hide()
    Keys.onLeftPressed: prev()
    Keys.onRightPressed: next()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Lightbox Header
        Rectangle {
            Layout.fillWidth: true
            height: 52
            color: root.cBgSurface
            border.color: root.cBorder

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 12

                RowLayout {
                    spacing: 6
                    Layout.maximumWidth: 320

                    Text {
                        text: currentPhoto ? currentPhoto.filename : "Photo"
                        color: root.cTextMain
                        font.family: root.fSans
                        font.bold: true
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        Layout.maximumWidth: 280
                    }

                    // Copy Filename Button
                    Rectangle {
                        width: 24
                        height: 24
                        radius: 4
                        color: copyHdrFnMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.12) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "\uE8C8"
                            font.family: lightboxRoot.fIcon
                            font.pixelSize: 11
                            color: copyHdrFnMouse.containsMouse ? "#ffffff" : root.cTextMuted
                        }

                        MouseArea {
                            id: copyHdrFnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (currentPhoto) {
                                    gallery.copyText(currentPhoto.filename);
                                }
                            }
                        }
                    }
                }

                // Location Badge (Clickable to Edit Location - Fluent Green Accent)
                Rectangle {
                    visible: currentPhoto ? true : false
                    color: locBadgeMouse.containsMouse ? Qt.rgba(16/255, 185/255, 129/255, 0.22) : Qt.rgba(16/255, 185/255, 129/255, 0.12)
                    border.color: locBadgeMouse.containsMouse ? "#6ccb5f" : Qt.rgba(16/255, 185/255, 129/255, 0.35)
                    radius: 11
                    implicitHeight: 22
                    implicitWidth: locBadgeRow.implicitWidth + 16

                    RowLayout {
                        id: locBadgeRow
                        anchors.centerIn: parent
                        spacing: 5
                        Text {
                            text: "\uE707"
                            font.family: lightboxRoot.fIcon
                            font.pixelSize: 10
                            color: "#6ccb5f"
                        }
                        Text {
                            id: locBadgeText
                            text: (currentPhoto && currentPhoto.location_name) ? currentPhoto.location_name : "Add location"
                            color: (currentPhoto && currentPhoto.location_name) ? "#ffffff" : root.cTextMuted
                            font.family: root.fSans
                            font.pixelSize: 11
                        }
                        Text {
                            text: "\uE70F"
                            font.family: lightboxRoot.fIcon
                            font.pixelSize: 9
                            color: "#6ccb5f"
                            visible: locBadgeMouse.containsMouse
                        }
                    }

                    MouseArea {
                        id: locBadgeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            locInputField.text = (currentPhoto && currentPhoto.location_name) ? currentPhoto.location_name : "";
                            editLocationDialog.visible = true;
                            locInputField.forceActiveFocus();
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // WhatsApp Button
                Button {
                    id: btnWhatsApp
                    flat: true
                    contentItem: RowLayout {
                        spacing: 6
                        Text { text: "\uE8BD"; font.family: lightboxRoot.fIcon; font.pixelSize: 13; color: root.cTextMain }
                        Text {
                            text: "WhatsApp (" + (root.whatsappTarget === "web" ? "Web" : "Desktop") + ")"
                            color: root.cTextMain
                            font.family: root.fSans
                            font.pixelSize: 12
                        }
                    }
                    background: Rectangle {
                        color: btnWhatsApp.hovered ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(255, 255, 255, 0.04)
                        border.color: Qt.rgba(255, 255, 255, 0.12)
                        radius: 4
                    }
                    onClicked: {
                        if (currentPhoto) {
                            gallery.shareViaWhatsApp([currentPhoto.id], root.whatsappTarget);
                        }
                    }
                }

                // Gallery Button
                Button {
                    id: btnGallery
                    flat: true
                    contentItem: RowLayout {
                        spacing: 6
                        Text { text: "\uE8A7"; font.family: lightboxRoot.fIcon; font.pixelSize: 13; color: root.cTextMain }
                        Text { text: "Gallery"; color: root.cTextMain; font.family: root.fSans; font.pixelSize: 12 }
                    }
                    background: Rectangle {
                        color: btnGallery.hovered ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(255, 255, 255, 0.04)
                        border.color: Qt.rgba(255, 255, 255, 0.12)
                        radius: 4
                    }
                    onClicked: {
                        if (currentPhoto) {
                            gallery.openInGallery([currentPhoto.id]);
                        }
                    }
                }

                // Explorer Button
                Button {
                    id: btnExplorer
                    flat: true
                    contentItem: RowLayout {
                        spacing: 6
                        Text { text: "\uEC50"; font.family: lightboxRoot.fIcon; font.pixelSize: 13; color: root.cTextMain }
                        Text { text: "Explorer"; color: root.cTextMain; font.family: root.fSans; font.pixelSize: 12 }
                    }
                    background: Rectangle {
                        color: btnExplorer.hovered ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(255, 255, 255, 0.04)
                        border.color: Qt.rgba(255, 255, 255, 0.12)
                        radius: 4
                    }
                    onClicked: {
                        if (currentPhoto) {
                            gallery.revealInExplorer(currentPhoto.id);
                        }
                    }
                }

                // Remove from Library Button
                Button {
                    id: btnRemove
                    flat: true
                    contentItem: RowLayout {
                        spacing: 5
                        Text {
                            text: "\uE74D"
                            font.family: lightboxRoot.fIcon
                            font.pixelSize: 13
                            color: btnRemove.hovered ? "#ff99a4" : root.cTextMain
                        }
                        Text {
                            text: "Remove"
                            color: btnRemove.hovered ? "#ff99a4" : root.cTextMain
                            font.family: root.fSans
                            font.pixelSize: 12
                        }
                    }
                    background: Rectangle {
                        color: btnRemove.hovered ? Qt.rgba(196/255, 43/255, 28/255, 0.25) : Qt.rgba(255, 255, 255, 0.04)
                        border.color: btnRemove.hovered ? Qt.rgba(255, 153/255, 164/255, 0.40) : Qt.rgba(255, 255, 255, 0.12)
                        radius: 4
                    }
                    onClicked: confirmRemovePhotoDialog.visible = true
                }

                // Toggle Face Boxes Button
                Button {
                    id: btnToggleFaces
                    flat: true
                    contentItem: RowLayout {
                        spacing: 5
                        Text {
                            text: "\uE77B"
                            font.family: lightboxRoot.fIcon
                            font.pixelSize: 13
                            color: showFaces ? root.cTextMain : root.cTextMuted
                        }
                        Text {
                            text: showFaces ? "Hide Faces" : "Show Faces"
                            color: showFaces ? root.cTextMain : root.cTextMuted
                            font.family: root.fSans
                            font.pixelSize: 12
                        }
                    }
                    background: Rectangle {
                        color: showFaces ? Qt.rgba(255, 255, 255, 0.12) : (btnToggleFaces.hovered ? Qt.rgba(255, 255, 255, 0.08) : "transparent")
                        radius: 4
                        border.color: showFaces ? Qt.rgba(255, 255, 255, 0.25) : (btnToggleFaces.hovered ? Qt.rgba(255, 255, 255, 0.12) : "transparent")
                    }
                    onClicked: {
                        showFaces = !showFaces;
                        if (!showFaces) {
                            selectedFaceId = -1;
                        }
                    }
                }

                // Close Button
                Button {
                    id: btnClose
                    flat: true
                    contentItem: Text {
                        text: "\uE711"
                        font.family: lightboxRoot.fIcon
                        font.pixelSize: 13
                        color: btnClose.hovered ? root.cTextMain : root.cTextMuted
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: btnClose.hovered ? Qt.rgba(255, 255, 255, 0.10) : "transparent"
                        radius: 4
                    }
                    onClicked: hide()
                }
            }
        }

        // Viewport Image Area
        Item {
            id: viewport
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Image {
                id: mainImage
                anchors.fill: parent
                anchors.margins: 20
                source: currentPhoto ? ("image://raw/" + currentPhoto.id) : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
            }

            // Face Bounding Boxes Overlay
            Repeater {
                model: (mainImage.paintedWidth > 0 && currentFaces.length > 0 && (showFaces || selectedFaceId !== -1)) ? currentFaces : []
                delegate: Item {
                    id: faceBoxItem
                    readonly property var face: modelData
                    readonly property real scaleX: mainImage.paintedWidth / mainImage.sourceSize.width
                    readonly property real scaleY: mainImage.paintedHeight / mainImage.sourceSize.height
                    readonly property real imgLeft: mainImage.x + (mainImage.width - mainImage.paintedWidth) / 2
                    readonly property real imgTop: mainImage.y + (mainImage.height - mainImage.paintedHeight) / 2

                    readonly property bool isHighlighted: lightboxRoot.selectedFaceId === face.id
                    visible: showFaces || isHighlighted

                    x: imgLeft + face.bbox_x1 * scaleX
                    y: imgTop + face.bbox_y1 * scaleY
                    width: (face.bbox_x2 - face.bbox_x1) * scaleX
                    height: (face.bbox_y2 - face.bbox_y1) * scaleY

                    // Outer dark shadow stroke to guarantee razor-sharp contrast on pure white images
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -1
                        color: "transparent"
                        border.color: Qt.rgba(0, 0, 0, 0.70)
                        border.width: 1
                        radius: 4
                    }

                    // Main bounding box (Vibrant Emerald Green Camera Tracking Style)
                    Rectangle {
                        anchors.fill: parent
                        color: isHighlighted ? Qt.rgba(16/255, 185/255, 129/255, 0.22) : "transparent"
                        border.color: isHighlighted ? "#6ccb5f" : "#10b981"
                        border.width: isHighlighted ? 3 : 2
                        radius: 4

                        // Face Label Tag (High contrast on all photos, avoids top viewport clipping)
                        Rectangle {
                            id: faceTagPill
                            anchors.bottom: (faceBoxItem.y < 28) ? undefined : parent.top
                            anchors.top: (faceBoxItem.y < 28) ? parent.bottom : undefined
                            anchors.bottomMargin: (faceBoxItem.y < 28) ? 0 : 4
                            anchors.topMargin: (faceBoxItem.y < 28) ? 4 : 0
                            anchors.left: parent.left
                            height: 22
                            radius: 4
                            color: isHighlighted ? "#10b981" : Qt.rgba(14/255, 24/255, 18/255, 0.95)
                            border.color: isHighlighted ? "#6ccb5f" : "#10b981"
                            border.width: 1
                            implicitWidth: tagRow.implicitWidth + 14

                            RowLayout {
                                id: tagRow
                                anchors.centerIn: parent
                                spacing: 5

                                Text {
                                    text: "\uE77B"
                                    font.family: lightboxRoot.fIcon
                                    font.pixelSize: 10
                                    color: isHighlighted ? "#ffffff" : "#10b981"
                                }

                                Text {
                                    id: nameLabel
                                    text: face.person_name || "Untagged"
                                    color: "#ffffff"
                                    font.family: root.fSans
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                Text {
                                    text: (face.gender || "") + (face.age ? " ~" + face.age : "")
                                    color: isHighlighted ? Qt.rgba(255, 255, 255, 0.85) : Qt.rgba(16/255, 185/255, 129/255, 0.90)
                                    font.family: root.fSans
                                    font.pixelSize: 10
                                    visible: (face.gender || face.age) ? true : false
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (lightboxRoot.selectedFaceId === face.id) {
                                    lightboxRoot.selectedFaceId = -1;
                                } else {
                                    lightboxRoot.selectedFaceId = face.id;
                                }
                            }
                        }
                    }
                }
            }

            // Prev & Next Overlay Arrow Buttons
            Button {
                id: btnPrevOverlay
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                flat: true
                visible: currentIndex > 0
                contentItem: Text {
                    text: "\uE76B"
                    font.family: lightboxRoot.fIcon
                    font.pixelSize: 16
                    color: "#fff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: btnPrevOverlay.hovered ? Qt.rgba(40/255, 40/255, 40/255, 0.85) : Qt.rgba(0, 0, 0, 0.65)
                    radius: 20
                    implicitWidth: 40
                    implicitHeight: 40
                    border.color: Qt.rgba(255, 255, 255, 0.2)
                }
                onClicked: prev()
            }

            Button {
                id: btnNextOverlay
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                flat: true
                visible: currentIndex < photosList.length - 1
                contentItem: Text {
                    text: "\uE76C"
                    font.family: lightboxRoot.fIcon
                    font.pixelSize: 16
                    color: "#fff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: btnNextOverlay.hovered ? Qt.rgba(40/255, 40/255, 40/255, 0.85) : Qt.rgba(0, 0, 0, 0.65)
                    radius: 20
                    implicitWidth: 40
                    implicitHeight: 40
                    border.color: Qt.rgba(255, 255, 255, 0.2)
                }
                onClicked: next()
            }
        }

        // Lightbox Footer: Detected Face Chips
        Rectangle {
            Layout.fillWidth: true
            height: 56
            color: root.cBgSurface
            border.color: root.cBorder

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 12

                RowLayout {
                    spacing: 6
                    Text {
                        text: "\uE77B"
                        font.family: lightboxRoot.fIcon
                        font.pixelSize: 12
                        color: root.cTextMuted
                    }
                    Text {
                        text: currentFaces.length > 0 ? ("Faces (" + currentFaces.length + "):") : "No faces detected"
                        color: root.cTextMuted
                        font.family: root.fSans
                        font.pixelSize: 12
                    }
                }

                ListView {
                    Layout.fillWidth: true
                    height: 40
                    orientation: ListView.Horizontal
                    spacing: 8
                    clip: true
                    model: currentFaces

                    delegate: Rectangle {
                        id: chipCard
                        readonly property var faceData: modelData
                        readonly property bool isSelectedChip: lightboxRoot.selectedFaceId === faceData.id
                        width: chipRow.implicitWidth + 18
                        height: 32
                        radius: 16
                        color: isSelectedChip ? Qt.rgba(16/255, 185/255, 129/255, 0.22) : ((chipMouse.containsMouse || setAvMouse.containsMouse) ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(255, 255, 255, 0.04))
                        border.color: isSelectedChip ? "#10b981" : ((chipMouse.containsMouse || setAvMouse.containsMouse) ? Qt.rgba(255, 255, 255, 0.20) : Qt.rgba(255, 255, 255, 0.10))
                        border.width: isSelectedChip ? 2 : 1

                        // Base chip click (z: 0)
                        MouseArea {
                            id: chipMouse
                            objectName: "chipMouse"
                            anchors.fill: parent
                            z: 0
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (lightboxRoot.selectedFaceId === faceData.id) {
                                    lightboxRoot.selectedFaceId = -1;
                                } else {
                                    lightboxRoot.selectedFaceId = faceData.id;
                                }
                            }
                        }

                        // Content (z: 1)
                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 8
                            z: 1

                            Rectangle {
                                width: 24
                                height: 24
                                radius: 12
                                clip: true
                                color: "#333"

                                Image {
                                    anchors.fill: parent
                                    source: "image://face/" + faceData.id
                                    fillMode: Image.PreserveAspectCrop
                                }
                            }

                            Text {
                                text: faceData.person_name || "Untagged"
                                color: chipCard.isSelectedChip ? "#10b981" : "#ffffff"
                                font.family: root.fSans
                                font.pixelSize: 12
                                font.bold: chipCard.isSelectedChip
                            }

                            Text {
                                text: (faceData.gender || "") + (faceData.age ? " ~" + faceData.age : "")
                                color: chipCard.isSelectedChip ? Qt.rgba(16/255, 185/255, 129/255, 0.85) : Qt.rgba(255, 255, 255, 0.60)
                                font.family: root.fSans
                                font.pixelSize: 10
                                visible: faceData.gender || faceData.age
                            }

                            // Quick Set as Default Picture Button
                            Rectangle {
                                visible: faceData.person_id && (chipCard.isSelectedChip || chipMouse.containsMouse || setAvMouse.containsMouse)
                                width: 22
                                height: 22
                                radius: 11
                                color: setAvMouse.containsMouse ? "#10b981" : Qt.rgba(255, 255, 255, 0.16)
                                border.color: setAvMouse.containsMouse ? "#ffffff" : "transparent"
                                border.width: 1
                                scale: setAvMouse.containsMouse ? 1.15 : 1.0
                                Behavior on scale { NumberAnimation { duration: 100 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "\uE722"
                                    font.family: lightboxRoot.fIcon
                                    font.pixelSize: 10
                                    color: "#ffffff"
                                }

                                MouseArea {
                                    id: setAvMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        gallery.setPersonAvatar(faceData.person_id, faceData.id);
                                    }
                                }

                                ToolTip.visible: setAvMouse.containsMouse
                                ToolTip.delay: 350
                                ToolTip.text: "Set as default picture"
                            }
                        }
                    }
                }
            }
        }
    }

    // Remove Confirmation Modal
    Rectangle {
        id: confirmRemovePhotoDialog
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
            width: Math.min(420, parent.width - 40)
            height: 180
            radius: 8
            color: "#2c2c2c"
            border.color: Qt.rgba(255, 255, 255, 0.08)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12

                RowLayout {
                    spacing: 8
                    Text {
                        text: "\uE74D"
                        font.family: lightboxRoot.fIcon
                        font.pixelSize: 16
                        color: "#c42b1c"
                    }
                    Text {
                        text: "Remove Photo from Library?"
                        color: "#ffffff"
                        font.family: root.fSans
                        font.bold: true
                        font.pixelSize: 14
                    }
                }

                Text {
                    text: "This photo and its detected faces will be removed from your catalog.\n\nYour original file on disk will NOT be deleted."
                    color: Qt.rgba(255, 255, 255, 0.70)
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
                        id: btnCancelModal
                        flat: true
                        contentItem: Text {
                            text: "Cancel"
                            color: root.cTextMain
                            font.family: root.fSans
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: btnCancelModal.hovered ? Qt.rgba(255, 255, 255, 0.10) : Qt.rgba(255, 255, 255, 0.06)
                            border.color: Qt.rgba(255, 255, 255, 0.12)
                            radius: 4
                            implicitWidth: 70
                            implicitHeight: 30
                        }
                        onClicked: confirmRemovePhotoDialog.visible = false
                    }

                    Button {
                        id: btnConfirmDeleteModal
                        flat: true
                        contentItem: Text {
                            text: "Remove from Library"
                            color: "#ffffff"
                            font.family: root.fSans
                            font.bold: true
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: btnConfirmDeleteModal.hovered ? "#d83b01" : "#c42b1c"
                            radius: 4
                            implicitWidth: 140
                            implicitHeight: 30
                        }
                        onClicked: {
                            confirmRemovePhotoDialog.visible = false;
                            if (currentPhoto) {
                                var pid = currentPhoto.id;
                                gallery.removePhotosFromLibrary([pid]);
                                var curIdx = currentIndex;
                                var pList = photosList.slice();
                                pList.splice(curIdx, 1);
                                if (pList.length === 0) {
                                    hide();
                                } else {
                                    photosList = pList;
                                    currentIndex = Math.min(curIdx, pList.length - 1);
                                    selectedFaceId = -1;
                                    loadFaces();
                                }
                                root.refreshPhotos();
                            }
                        }
                    }
                }
            }
        }
    }

    // Edit Location Dialog
    Rectangle {
        id: editLocationDialog
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.65)
        visible: false
        z: 3500

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(420, parent.width - 40)
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
                        text: "\uE707"
                        font.family: lightboxRoot.fIcon
                        font.pixelSize: 16
                        color: root.cAccent
                    }
                    Text {
                        text: "Edit Photo Location"
                        color: "#ffffff"
                        font.family: root.fSans
                        font.bold: true
                        font.pixelSize: 14
                    }
                }

                Text {
                    text: "Enter a location label for this photo (e.g. City, Landmark, or Trip name):"
                    color: root.cTextMuted
                    font.family: root.fSans
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                TextField {
                    id: locInputField
                    Layout.fillWidth: true
                    height: 34
                    color: "#ffffff"
                    font.family: root.fSans
                    font.pixelSize: 12
                    placeholderText: "e.g. Paris, France or Beach House"
                    selectByMouse: true
                    background: Rectangle {
                        color: Qt.rgba(255, 255, 255, 0.06)
                        border.color: locInputField.activeFocus ? root.cAccent : Qt.rgba(255, 255, 255, 0.18)
                        radius: 4
                    }
                    Keys.onReturnPressed: editLocationDialog.saveLocation()
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: 10

                    Button {
                        id: btnCancelLoc
                        flat: true
                        contentItem: Text {
                            text: "Cancel"
                            color: root.cTextMain
                            font.family: root.fSans
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: btnCancelLoc.hovered ? Qt.rgba(255, 255, 255, 0.10) : Qt.rgba(255, 255, 255, 0.06)
                            border.color: Qt.rgba(255, 255, 255, 0.12)
                            radius: 4
                            implicitWidth: 70
                            implicitHeight: 30
                        }
                        onClicked: editLocationDialog.visible = false
                    }

                    Button {
                        id: btnSaveLoc
                        flat: true
                        contentItem: Text {
                            text: "Save Location"
                            color: "#ffffff"
                            font.family: root.fSans
                            font.bold: true
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: btnSaveLoc.hovered ? "#0091ff" : "#0078d4"
                            radius: 4
                            implicitWidth: 100
                            implicitHeight: 30
                        }
                        onClicked: editLocationDialog.saveLocation()
                    }
                }
            }
        }

        function saveLocation() {
            editLocationDialog.visible = false;
            if (currentPhoto) {
                gallery.updatePhotoLocation(currentPhoto.id, locInputField.text.trim());
            }
        }
    }
}
