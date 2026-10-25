import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: peopleRoot

    readonly property string fIcon: "Segoe Fluent Icons, Segoe MDL2 Assets"

    property var peopleModel: []
    property var selectedPeopleIds: []
    property bool selectMode: false

    function selectOrOpenPerson(personId, personName, avatarFaceId) {
        if (peopleRoot.selectMode) {
            var cur = peopleRoot.selectedPeopleIds.slice();
            var idx = cur.indexOf(personId);
            if (idx !== -1) cur.splice(idx, 1);
            else cur.push(personId);
            peopleRoot.selectedPeopleIds = cur;
        } else {
            root.activeFolder = "";
            root.selectedPeopleFilters = [{ id: personId, name: personName, avatar_face_id: avatarFaceId || null }];
            root.personFilterMode = "together";
            root.switchTab("photos");
        }
    }

    Connections {
        target: gallery
        function onPeopleLoaded(people) {
            peopleRoot.peopleModel = people;
        }
        function onPersonFacesLoaded(personId, faces) {
            if (avatarPickerModal.personId === personId) {
                avatarPickerModal.facesList = faces;
                avatarPickerModal.isLoading = false;
            }
        }
    }

    Component.onCompleted: gallery.loadPeople()

    readonly property int targetWidth: 200
    readonly property int columnsCount: Math.max(2, Math.floor(grid.width / targetWidth))
    readonly property real tileWidth: grid.width / columnsCount

    function openAvatarPicker(personId, personName, currentFaceId) {
        avatarPickerModal.personId = personId;
        avatarPickerModal.personName = personName;
        avatarPickerModal.currentFaceId = currentFaceId;
        avatarPickerModal.facesList = [];
        avatarPickerModal.isLoading = true;
        avatarPickerModal.visible = true;
        gallery.loadPersonFaces(personId);
    }

    function applyPeopleFilter(mode) {
        var selected = [];
        var pModel = peopleRoot.peopleModel || [];
        for (var i = 0; i < pModel.length; i++) {
            if (peopleRoot.selectedPeopleIds.indexOf(pModel[i].id) !== -1) {
                selected.push({ id: pModel[i].id, name: pModel[i].name, avatar_face_id: pModel[i].avatar_face_id });
            }
        }
        root.activeFolder = "";
        root.selectedPeopleFilters = selected;
        root.personFilterMode = mode;
        peopleRoot.selectedPeopleIds = [];
        peopleRoot.selectMode = false;
        root.switchTab("photos");
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

        // People Toolbar (Windows 11 Fluent CommandBar Style)
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // 1. SELECTION ACTIVE TOOLBAR
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                visible: peopleRoot.selectMode || peopleRoot.selectedPeopleIds.length > 0

                // Close / Cancel Selection
                Button {
                    id: btnCancelPeopleSel
                    flat: true
                    contentItem: Text {
                        text: "\uE711"
                        font.family: peopleRoot.fIcon
                        font.pixelSize: 12
                        color: btnCancelPeopleSel.hovered ? "#ffffff" : root.cTextMuted
                    }
                    background: Rectangle {
                        color: btnCancelPeopleSel.hovered ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(255, 255, 255, 0.04)
                        border.color: root.cBorder
                        radius: 6
                    }
                    onClicked: {
                        peopleRoot.selectedPeopleIds = [];
                        peopleRoot.selectMode = false;
                    }
                }

                // Selected Count Badge
                Rectangle {
                    color: Qt.rgba(255, 255, 255, 0.08)
                    border.color: Qt.rgba(255, 255, 255, 0.14)
                    radius: 6
                    implicitHeight: 30
                    implicitWidth: peopleSelCountText.implicitWidth + 20

                    Text {
                        id: peopleSelCountText
                        anchors.centerIn: parent
                        text: peopleRoot.selectedPeopleIds.length > 0
                            ? (peopleRoot.selectedPeopleIds.length + " selected")
                            : "Click people to select"
                        color: "#ffffff"
                        font.family: root.fSans
                        font.bold: true
                        font.pixelSize: 12
                    }
                }

                // Select All / Deselect All Toggle
                Button {
                    id: btnToggleSelectAllPeople
                    flat: true
                    contentItem: RowLayout {
                        spacing: 6
                        Text {
                            text: (peopleRoot.peopleModel && peopleRoot.selectedPeopleIds.length >= peopleRoot.peopleModel.length && peopleRoot.peopleModel.length > 0) ? "\uE73E" : "\uE762"
                            font.family: peopleRoot.fIcon
                            font.pixelSize: 12
                            color: "#ffffff"
                        }
                        Text {
                            text: (peopleRoot.peopleModel && peopleRoot.selectedPeopleIds.length >= peopleRoot.peopleModel.length && peopleRoot.peopleModel.length > 0) ? "Deselect All" : "Select All"
                            color: "#ffffff"
                            font.family: root.fSans
                            font.pixelSize: 12
                        }
                    }
                    background: Rectangle {
                        color: btnToggleSelectAllPeople.hovered ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(255, 255, 255, 0.04)
                        border.color: root.cBorder
                        radius: 6
                    }
                    onClicked: {
                        var pModel = peopleRoot.peopleModel || [];
                        if (peopleRoot.selectedPeopleIds.length >= pModel.length) {
                            peopleRoot.selectedPeopleIds = [];
                        } else {
                            var all = [];
                            for (var i = 0; i < pModel.length; i++) {
                                all.push(pModel[i].id);
                            }
                            peopleRoot.selectedPeopleIds = all;
                        }
                    }
                }

                // View Photos (1 person selected)
                Button {
                    id: btnViewSinglePersonPhotos
                    visible: peopleRoot.selectedPeopleIds.length === 1
                    flat: true
                    contentItem: RowLayout {
                        spacing: 6
                        Text { text: "\uEB9F"; font.family: peopleRoot.fIcon; font.pixelSize: 12; color: "#ffffff" }
                        Text { text: "View Photos"; color: "#ffffff"; font.family: root.fSans; font.bold: true; font.pixelSize: 12 }
                    }
                    background: Rectangle {
                        color: btnViewSinglePersonPhotos.hovered ? Qt.rgba(255, 255, 255, 0.14) : Qt.rgba(255, 255, 255, 0.08)
                        border.color: Qt.rgba(255, 255, 255, 0.18)
                        radius: 6
                    }
                    onClicked: peopleRoot.applyPeopleFilter("together")
                }

                // View Photos Together (AND) (2+ people selected)
                Button {
                    id: btnTogetherFilter
                    visible: peopleRoot.selectedPeopleIds.length >= 2
                    flat: true
                    contentItem: RowLayout {
                        spacing: 6
                        Text { text: "\uE716"; font.family: peopleRoot.fIcon; font.pixelSize: 12; color: "#ffffff" }
                        Text { text: "Together (AND)"; color: "#ffffff"; font.family: root.fSans; font.bold: true; font.pixelSize: 12 }
                    }
                    background: Rectangle {
                        color: btnTogetherFilter.hovered ? Qt.rgba(255, 255, 255, 0.14) : Qt.rgba(255, 255, 255, 0.08)
                        border.color: Qt.rgba(255, 255, 255, 0.18)
                        radius: 6
                    }
                    onClicked: peopleRoot.applyPeopleFilter("together")
                }

                // View Either Photos (OR) (2+ people selected)
                Button {
                    id: btnEitherFilter
                    visible: peopleRoot.selectedPeopleIds.length >= 2
                    flat: true
                    contentItem: RowLayout {
                        spacing: 6
                        Text { text: "\uE8D4"; font.family: peopleRoot.fIcon; font.pixelSize: 12; color: "#ffffff" }
                        Text { text: "Either (OR)"; color: "#ffffff"; font.family: root.fSans; font.pixelSize: 12 }
                    }
                    background: Rectangle {
                        color: btnEitherFilter.hovered ? Qt.rgba(255, 255, 255, 0.10) : Qt.rgba(255, 255, 255, 0.05)
                        border.color: root.cBorder
                        radius: 6
                    }
                    onClicked: peopleRoot.applyPeopleFilter("either")
                }

                // Combine into One Person (2+ people selected)
                Button {
                    id: btnCombinePeople
                    visible: peopleRoot.selectedPeopleIds.length >= 2
                    flat: true
                    contentItem: RowLayout {
                        spacing: 6
                        Text { text: "\uE7FD"; font.family: peopleRoot.fIcon; font.pixelSize: 12; color: "#ffffff" }
                        Text { text: "Combine"; color: "#ffffff"; font.family: root.fSans; font.pixelSize: 12 }
                    }
                    background: Rectangle {
                        color: btnCombinePeople.hovered ? Qt.rgba(255, 255, 255, 0.10) : Qt.rgba(255, 255, 255, 0.05)
                        border.color: root.cBorder
                        radius: 6
                    }
                    onClicked: combineDialog.open()
                }

                Item { Layout.fillWidth: true }

                // Done Selecting Button
                Button {
                    id: btnDonePeopleSel
                    flat: true
                    contentItem: Text {
                        text: "Done"
                        color: "#ffffff"
                        font.family: root.fSans
                        font.bold: true
                        font.pixelSize: 12
                    }
                    background: Rectangle {
                        color: btnDonePeopleSel.hovered ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.06)
                        border.color: root.cBorder
                        radius: 6
                    }
                    onClicked: {
                        peopleRoot.selectedPeopleIds = [];
                        peopleRoot.selectMode = false;
                    }
                }
            }

            // 2. NORMAL BROWSE TOOLBAR (When selection is not active)
            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                visible: !(peopleRoot.selectMode || peopleRoot.selectedPeopleIds.length > 0)

                Button {
                    id: btnSelectMultiple
                    flat: true
                    contentItem: RowLayout {
                        spacing: 6
                        Text {
                            text: "\uE762"
                            font.family: peopleRoot.fIcon
                            font.pixelSize: 13
                            color: "#ffffff"
                        }
                        Text {
                            text: "Select Multiple"
                            color: "#ffffff"
                            font.family: root.fSans
                            font.bold: true
                            font.pixelSize: 12
                        }
                    }
                    background: Rectangle {
                        color: btnSelectMultiple.hovered ? Qt.rgba(255, 255, 255, 0.09) : Qt.rgba(255, 255, 255, 0.05)
                        border.color: Qt.rgba(255, 255, 255, 0.14)
                        radius: 6
                    }
                    onClicked: peopleRoot.selectMode = true
                }

                Text {
                    text: "Click name to rename. Click avatar to filter photos. Check 2+ people to find photos together."
                    color: root.cTextDim
                    font.family: root.fSans
                    font.pixelSize: 12
                    Layout.fillWidth: true
                }

                Button {
                    id: btnRecluster
                    flat: true
                    contentItem: RowLayout {
                        spacing: 6
                        Text {
                            text: "\uE777"
                            font.family: peopleRoot.fIcon
                            font.pixelSize: 13
                            color: "#ffffff"
                        }
                        Text {
                            text: "Re-cluster Now"
                            color: "#ffffff"
                            font.family: root.fSans
                            font.pixelSize: 12
                        }
                    }
                    background: Rectangle {
                        color: btnRecluster.hovered ? Qt.rgba(255, 255, 255, 0.09) : Qt.rgba(255, 255, 255, 0.05)
                        border.color: root.cBorder
                        radius: 6
                    }
                    onClicked: gallery.runClustering()
                }
            }
        }

        // People Grid
        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            cellWidth: peopleRoot.tileWidth
            cellHeight: 245
            clip: true
            model: peopleRoot.peopleModel
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
                id: vbarPeople
                policy: ScrollBar.AsNeeded
                hoverEnabled: true
                active: true
                width: (hovered || pressed) ? 12 : 8
                Behavior on width { NumberAnimation { duration: 120 } }

                contentItem: Rectangle {
                    implicitWidth: 8
                    implicitHeight: 48
                    radius: width / 2
                    color: vbarPeople.pressed 
                        ? Qt.rgba(255, 255, 255, 0.65) 
                        : (vbarPeople.hovered ? Qt.rgba(255, 255, 255, 0.45) : Qt.rgba(255, 255, 255, 0.22))
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                background: Rectangle {
                    implicitWidth: (vbarPeople.hovered || vbarPeople.pressed) ? 12 : 8
                    color: (vbarPeople.hovered || vbarPeople.pressed) ? Qt.rgba(255, 255, 255, 0.05) : "transparent"
                    radius: width / 2
                }
            }

            delegate: Item {
                width: grid.cellWidth
                height: grid.cellHeight

                readonly property var person: modelData
                readonly property bool isChecked: peopleRoot.selectedPeopleIds.indexOf(person.id) !== -1

                Rectangle {
                    id: cardBg
                    anchors.fill: parent
                    anchors.margins: 8
                    radius: 12
                    color: isChecked ? Qt.rgba(255, 255, 255, 0.08) : ((cardMouse.containsMouse || changeAvMouse.containsMouse) ? Qt.rgba(255, 255, 255, 0.04) : root.cBgCard)
                    border.color: isChecked ? "#ffffff" : ((cardMouse.containsMouse || changeAvMouse.containsMouse) ? Qt.rgba(255, 255, 255, 0.22) : root.cBorder)
                    border.width: isChecked ? 2 : 1

                    // Base card click & hover (behind all interactive controls)
                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        z: 0
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: peopleRoot.selectOrOpenPerson(person.id, person.name, person.avatar_face_id)
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10
                        z: 1

                        // Big Rounded Face Avatar
                        Item {
                            id: avatarContainer
                            width: 136
                            height: 136
                            Layout.alignment: Qt.AlignHCenter
                            scale: (cardMouse.containsMouse || changeAvMouse.containsMouse) ? 1.04 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                            // Circular Background Placeholder
                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: "#202020"
                            }

                            // Face Image (True circular anti-aliased from provider)
                            Image {
                                id: faceImg
                                anchors.fill: parent
                                source: person.avatar_face_id ? ("image://face/" + person.avatar_face_id) : ""
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                                mipmap: true
                                asynchronous: true
                            }

                            // Outer Circular Accent Ring (Windows 11 Subtle Neutral)
                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: "transparent"
                                border.color: isChecked ? "#ffffff" : ((cardMouse.containsMouse || changeAvMouse.containsMouse) ? Qt.rgba(255, 255, 255, 0.3) : Qt.rgba(255, 255, 255, 0.12))
                                border.width: isChecked ? 2.5 : 1.5
                            }

                            // Change Avatar Camera Button
                            Rectangle {
                                id: btnChangeAvatar
                                width: 32
                                height: 32
                                radius: 16
                                anchors.bottom: parent.bottom
                                anchors.right: parent.right
                                anchors.margins: 2
                                color: changeAvMouse.containsMouse ? "#10b981" : Qt.rgba(32/255, 32/255, 32/255, 0.92)
                                border.color: changeAvMouse.containsMouse ? "#ffffff" : Qt.rgba(255, 255, 255, 0.25)
                                border.width: 1.5
                                scale: changeAvMouse.containsMouse ? 1.15 : 1.0
                                Behavior on scale { NumberAnimation { duration: 100 } }
                                visible: cardMouse.containsMouse || changeAvMouse.containsMouse
                                z: 15

                                Text {
                                    anchors.centerIn: parent
                                    text: "\uE722" // Camera glyph
                                    font.family: peopleRoot.fIcon
                                    font.pixelSize: 13
                                    color: "#ffffff"
                                }

                                MouseArea {
                                    id: changeAvMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        peopleRoot.openAvatarPicker(person.id, person.name, person.avatar_face_id);
                                    }
                                }

                                ToolTip.visible: changeAvMouse.containsMouse
                                ToolTip.delay: 350
                                ToolTip.text: "Change default photo"
                            }
                        }

                        // Editable Name Field
                        TextInput {
                            id: nameInput
                            text: person.name
                            color: "#ffffff"
                            font.family: root.fSans
                            font.bold: true
                            font.pixelSize: 13
                            horizontalAlignment: Text.AlignHCenter
                            Layout.fillWidth: true
                            selectByMouse: true
                            z: 2

                            onEditingFinished: {
                                if (text.trim() && text.trim() !== person.name) {
                                    gallery.renamePerson(person.id, text.trim());
                                }
                            }
                        }

                        // Meta: Photo & Face Counts
                        Text {
                            text: person.photo_count + " photos" + (person.face_count > 0 ? " • " + person.face_count + " faces" : "")
                            color: root.cTextMuted
                            font.family: root.fSans
                            font.pixelSize: 11
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    // Multi-select Circular Checkbox (Top-Left)
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.margins: 10
                        width: 22
                        height: 22
                        radius: 11
                        color: isChecked ? "#0078d4" : Qt.rgba(0, 0, 0, 0.5)
                        border.color: "#ffffff"
                        border.width: 1.5
                        visible: peopleRoot.selectMode || isChecked
                        z: 10

                        Text {
                            anchors.centerIn: parent
                            text: "\uE73E"
                            font.family: peopleRoot.fIcon
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 11
                            visible: isChecked
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: {
                                var cur = peopleRoot.selectedPeopleIds.slice();
                                var idx = cur.indexOf(person.id);
                                if (idx !== -1) {
                                    cur.splice(idx, 1);
                                } else {
                                    cur.push(person.id);
                                }
                                peopleRoot.selectedPeopleIds = cur;
                            }
                        }
                    }
                }
            }
        }
    }

    // Combine Dialog
    Dialog {
        id: combineDialog
        title: "Combine Selected People"
        anchors.centerIn: parent
        width: 380
        standardButtons: Dialog.Ok | Dialog.Cancel

        ColumnLayout {
            spacing: 12
            width: parent.width

            Text {
                text: "Combine " + peopleRoot.selectedPeopleIds.length + " face groups into one person:"
                color: root.cTextMain
                font.pixelSize: 13
            }

            TextField {
                id: combineNameInput
                Layout.fillWidth: true
                placeholderText: "Enter person name (e.g. Alex, Mom)"
                color: root.cTextMain
            }
        }

        onAccepted: {
            if (combineNameInput.text.trim()) {
                gallery.combinePeople(peopleRoot.selectedPeopleIds, combineNameInput.text.trim());
                peopleRoot.selectedPeopleIds = [];
                peopleRoot.selectMode = false;
            }
        }
    }

    // Choose Default Picture (Avatar Picker) Dialog
    Rectangle {
        id: avatarPickerModal
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.70)
        visible: false
        z: 4000

        property int personId: -1
        property string personName: ""
        property int currentFaceId: -1
        property var facesList: []
        property bool isLoading: false

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(540, parent.width - 40)
            height: Math.min(480, parent.height - 60)
            radius: 12
            color: "#282828"
            border.color: Qt.rgba(255, 255, 255, 0.12)
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 14

                // Modal Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: Qt.rgba(16/255, 185/255, 129/255, 0.20)
                        border.color: "#10b981"
                        Text {
                            anchors.centerIn: parent
                            text: "\uE722"
                            font.family: peopleRoot.fIcon
                            font.pixelSize: 14
                            color: "#10b981"
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: "Change Default Picture: " + avatarPickerModal.personName
                            color: "#ffffff"
                            font.family: root.fSans
                            font.bold: true
                            font.pixelSize: 15
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: "Click any face photo below to set it as the cover avatar:"
                            color: root.cTextMuted
                            font.family: root.fSans
                            font.pixelSize: 12
                        }
                    }

                    Button {
                        flat: true
                        contentItem: Text {
                            text: "\uE711"
                            font.family: peopleRoot.fIcon
                            font.pixelSize: 12
                            color: root.cTextMuted
                        }
                        background: Rectangle {
                            color: parent.hovered ? Qt.rgba(255, 255, 255, 0.08) : "transparent"
                            radius: 4
                        }
                        onClicked: avatarPickerModal.visible = false
                    }
                }

                // Divider
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(255, 255, 255, 0.08)
                }

                // Loading or Empty State
                Text {
                    visible: avatarPickerModal.isLoading
                    text: "Loading detected faces..."
                    color: root.cTextMuted
                    font.family: root.fSans
                    font.pixelSize: 13
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    visible: !avatarPickerModal.isLoading && avatarPickerModal.facesList.length === 0
                    text: "No other faces found for this person."
                    color: root.cTextMuted
                    font.family: root.fSans
                    font.pixelSize: 13
                    Layout.alignment: Qt.AlignHCenter
                }

                // Faces Grid
                GridView {
                    id: avatarGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    cellWidth: 100
                    cellHeight: 100
                    clip: true
                    model: avatarPickerModal.facesList

                    delegate: Item {
                        width: avatarGrid.cellWidth
                        height: avatarGrid.cellHeight

                        readonly property var faceItem: modelData
                        readonly property bool isCurrent: faceItem.id === avatarPickerModal.currentFaceId

                        Rectangle {
                            id: faceTile
                            anchors.centerIn: parent
                            width: 84
                            height: 84
                            radius: 42
                            color: "#202020"
                            border.color: isCurrent ? "#10b981" : (tileMouse.containsMouse ? "#ffffff" : Qt.rgba(255, 255, 255, 0.15))
                            border.width: isCurrent ? 3 : (tileMouse.containsMouse ? 2 : 1)

                            Image {
                                anchors.fill: parent
                                anchors.margins: isCurrent ? 2 : 0
                                source: "image://face/" + faceItem.id
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                                mipmap: true
                                asynchronous: true
                            }

                            // Current default checkmark badge
                            Rectangle {
                                visible: isCurrent
                                width: 22
                                height: 22
                                radius: 11
                                anchors.bottom: parent.bottom
                                anchors.right: parent.right
                                color: "#10b981"
                                border.color: "#ffffff"
                                border.width: 1.5

                                Text {
                                    anchors.centerIn: parent
                                    text: "\uE73E"
                                    font.family: peopleRoot.fIcon
                                    font.pixelSize: 11
                                    color: "#ffffff"
                                }
                            }

                            MouseArea {
                                id: tileMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    gallery.setPersonAvatar(avatarPickerModal.personId, faceItem.id);
                                    avatarPickerModal.visible = false;
                                }
                            }
                        }
                    }
                }

                // Footer Close Button
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    Button {
                        flat: true
                        contentItem: Text {
                            text: "Close"
                            color: "#ffffff"
                            font.family: root.fSans
                            font.pixelSize: 12
                        }
                        background: Rectangle {
                            color: parent.hovered ? Qt.rgba(255, 255, 255, 0.10) : Qt.rgba(255, 255, 255, 0.05)
                            border.color: root.cBorder
                            radius: 4
                            implicitWidth: 80
                            implicitHeight: 30
                        }
                        onClicked: avatarPickerModal.visible = false
                    }
                }
            }
        }
    }
}
