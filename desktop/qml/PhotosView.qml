import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: photosRoot

    readonly property string fIcon: "Segoe Fluent Icons, Segoe MDL2 Assets"

    property var photosModel: []
    property int currentPage: 1
    property int totalPages: 1
    property int filteredTotal: 0
    property bool isLoading: false
    property int lastSelectedIndex: -1

    // Responsive Column Calculation
    readonly property int targetWidth: 200
    readonly property int columnsCount: Math.max(2, Math.floor(grid.width / targetWidth))
    readonly property real tileWidth: grid.width / columnsCount

    Connections {
        target: gallery
        function onPhotosLoaded(items, total, page, total_pages) {
            photosRoot.isLoading = false;
            photosRoot.currentPage = page;
            photosRoot.totalPages = total_pages;
            photosRoot.filteredTotal = total;

            if (page === 1) {
                photosRoot.photosModel = items;
            } else {
                var current = photosRoot.photosModel.slice();
                for (var i = 0; i < items.length; i++) {
                    current.push(items[i]);
                }
                photosRoot.photosModel = current;
            }
        }
        function onPhotoLocationUpdated(imageId, newLocation) {
            for (var i = 0; i < photosRoot.photosModel.length; i++) {
                if (photosRoot.photosModel[i].id === imageId) {
                    var list = photosRoot.photosModel.slice();
                    var item = Object.assign({}, list[i]);
                    item.location_name = newLocation;
                    list[i] = item;
                    photosRoot.photosModel = list;
                    break;
                }
            }
        }
    }

    Component.onCompleted: refresh()

    function refresh() {
        photosRoot.currentPage = 1;
        photosRoot.photosModel = [];
        photosRoot.isLoading = true;
        loadCurrentPage(1);
    }

    function loadCurrentPage(page) {
        var personIds = "";
        if (root.selectedPeopleFilters && root.selectedPeopleFilters.length > 0) {
            personIds = root.selectedPeopleFilters.map(function(p){
                return (typeof p === "object" && p !== null) ? p.id : p;
            }).join(",");
        }
        gallery.loadPhotos(
            page,
            120,
            root.activeFolder || "",
            personIds,
            root.personFilterMode || "together",
            root.searchQuery || ""
        );
    }

    function selectAllVisible() {
        var allIds = [];
        for (var i = 0; i < photosModel.length; i++) {
            allIds.push(photosModel[i].id);
        }
        root.selectedPhotoIds = allIds;
        root.photoSelectMode = true;
    }

    function deselectAll() {
        root.selectedPhotoIds = [];
        root.photoSelectMode = false;
    }

    function toggleSelectAll() {
        if (root.selectedPhotoIds.length >= photosModel.length && photosModel.length > 0) {
            deselectAll();
        } else {
            selectAllVisible();
        }
    }

    // Responsive Photo Grid
    GridView {
        id: grid
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.topMargin: 16
        anchors.bottomMargin: 16
        anchors.rightMargin: 8
        cellWidth: photosRoot.tileWidth
        cellHeight: photosRoot.tileWidth
        clip: true
        model: photosRoot.photosModel
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
            id: vbar
            policy: ScrollBar.AsNeeded
            hoverEnabled: true
            active: true
            width: (hovered || pressed) ? 12 : 8
            Behavior on width { NumberAnimation { duration: 120 } }

            contentItem: Rectangle {
                implicitWidth: 8
                implicitHeight: 48
                radius: width / 2
                color: vbar.pressed 
                    ? Qt.rgba(255, 255, 255, 0.65) 
                    : (vbar.hovered ? Qt.rgba(255, 255, 255, 0.45) : Qt.rgba(255, 255, 255, 0.22))
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            background: Rectangle {
                implicitWidth: (vbar.hovered || vbar.pressed) ? 12 : 8
                color: (vbar.hovered || vbar.pressed) ? Qt.rgba(255, 255, 255, 0.05) : "transparent"
                radius: width / 2
            }
        }

        // Infinite Scroll Check: Loads next page when nearing bottom (mouse wheel, dragging scrollbar, keys)
        onContentYChanged: {
            if (!photosRoot.isLoading && contentHeight > height && photosRoot.currentPage < photosRoot.totalPages) {
                if (contentY + height >= contentHeight - 600) {
                    photosRoot.isLoading = true;
                    photosRoot.loadCurrentPage(photosRoot.currentPage + 1);
                }
            }
        }

        delegate: Item {
            width: grid.cellWidth
            height: grid.cellHeight

            readonly property var item: modelData
            readonly property bool isSelected: root.selectedPhotoIds.indexOf(item.id) !== -1

            Rectangle {
                id: card
                anchors.fill: parent
                anchors.margins: 4
                radius: 6
                color: root.cBgCard
                clip: true
                border.width: isSelected ? 2 : 1
                border.color: isSelected ? "#ffffff" : (mouseArea.containsMouse ? Qt.rgba(255, 255, 255, 0.25) : root.cBorder)

                // Thumbnail Image
                Image {
                    anchors.fill: parent
                    source: "image://thumb/" + item.id
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                }

                // Selection Highlight Tint (Subtle Neutral Windows 11 Overlay)
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(255, 255, 255, 0.12)
                    visible: isSelected
                }

                // Multi-select Checkmark (Top-Left)
                Rectangle {
                    id: checkmark
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 8
                    width: 22
                    height: 22
                    radius: 11
                    color: isSelected ? "#0078d4" : Qt.rgba(0, 0, 0, 0.5)
                    border.color: "#ffffff"
                    border.width: 1.5
                    visible: isSelected || root.photoSelectMode || mouseArea.containsMouse
                    z: 10

                    Text {
                        anchors.centerIn: parent
                        text: "\uE73E"
                        font.family: photosRoot.fIcon
                        color: "#ffffff"
                        font.bold: true
                        font.pixelSize: 11
                        visible: isSelected
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: (mouse) => {
                            mouse.accepted = true;
                            toggleSelect(index, item.id, mouse.modifiers & Qt.ShiftModifier);
                        }
                    }
                }

                // Face Counter Badge (Top-Right)
                Rectangle {
                    visible: item.face_count > 0
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    height: 20
                    radius: 10
                    color: Qt.rgba(0, 0, 0, 0.65)
                    border.color: Qt.rgba(255, 255, 255, 0.15)
                    border.width: 1
                    implicitWidth: faceBadgeRow.implicitWidth + 14

                    RowLayout {
                        id: faceBadgeRow
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            text: "\uE77B"
                            font.family: photosRoot.fIcon
                            font.pixelSize: 10
                            color: "#ffffff"
                        }
                        Text {
                            id: faceBadgeText
                            text: item.face_count
                            color: "#ffffff"
                            font.family: root.fSans
                            font.bold: true
                            font.pixelSize: 11
                        }
                    }
                }

                // Location Badge (Bottom-Left above filename - Fluent Green Accent)
                Rectangle {
                    visible: item.location_name ? true : false
                    anchors.left: parent.left
                    anchors.bottom: filenameBar.top
                    anchors.margins: 6
                    height: 18
                    radius: 9
                    color: Qt.rgba(10/255, 26/255, 18/255, 0.80)
                    border.color: Qt.rgba(16/255, 185/255, 129/255, 0.45)
                    border.width: 1
                    implicitWidth: Math.min(150, locRow.implicitWidth + 14)

                    RowLayout {
                        id: locRow
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            text: "\uE707"
                            font.family: photosRoot.fIcon
                            font.pixelSize: 10
                            color: "#6ccb5f"
                        }
                        Text {
                            id: locText
                            text: item.location_name ? item.location_name.split(",")[0] : ""
                            color: "#ffffff"
                            font.family: root.fSans
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }
                }

                // Filename Label (Overlay on hover with quick copy button)
                Rectangle {
                    id: filenameBar
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 24
                    color: Qt.rgba(24/255, 24/255, 24/255, 0.90)
                    visible: mouseArea.containsMouse || copyFnMouse.containsMouse
                    z: 5

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 6
                        spacing: 4

                        Text {
                            text: item.filename
                            color: "#ffffff"
                            font.family: root.fSans
                            font.pixelSize: 11
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                            verticalAlignment: Text.AlignVCenter
                        }

                        // Quick Copy Filename Button
                        Rectangle {
                            width: 20
                            height: 20
                            radius: 3
                            color: copyFnMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.20) : "transparent"
                            scale: copyFnMouse.containsMouse ? 1.15 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100 } }

                            Text {
                                anchors.centerIn: parent
                                text: "\uE8C8"
                                font.family: photosRoot.fIcon
                                font.pixelSize: 10
                                color: copyFnMouse.containsMouse ? "#ffffff" : Qt.rgba(255, 255, 255, 0.70)
                            }

                            MouseArea {
                                id: copyFnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: gallery.copyText(item.filename)
                            }

                            ToolTip.visible: copyFnMouse.containsMouse
                            ToolTip.delay: 350
                            ToolTip.text: "Copy filename"
                        }
                    }
                }

                // Interactive Mouse & Native Drag Area (z: 0)
                MouseArea {
                    id: mouseArea
                    anchors.fill: parent
                    z: 0
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    // Native Drag & Drop Trigger
                    drag.target: null
                    property real startX: 0
                    property real startY: 0
                    property bool isDragging: false

                    onPressed: (mouse) => {
                        startX = mouse.x;
                        startY = mouse.y;
                        isDragging = false;
                    }

                    onPositionChanged: (mouse) => {
                        if (!isDragging && (mouse.buttons & Qt.LeftButton)) {
                            var dx = Math.abs(mouse.x - startX);
                            var dy = Math.abs(mouse.y - startY);
                            if (dx > 10 || dy > 10) {
                                isDragging = true;
                                // Trigger native Win32 OLE drag-and-drop to external applications!
                                var dragIds = [];
                                if (root.selectedPhotoIds.length > 0 && isSelected) {
                                    dragIds = root.selectedPhotoIds;
                                } else {
                                    dragIds = [item.id];
                                }
                                gallery.startNativeDrag(dragIds);
                            }
                        }
                    }

                    onReleased: {
                        isDragging = false;
                    }

                    onClicked: (mouse) => {
                        if (root.photoSelectMode) {
                            toggleSelect(index, item.id, mouse.modifiers & Qt.ShiftModifier);
                        } else {
                            lightbox.show(photosModel, index);
                        }
                    }
                }
            }
        }
    }

    function toggleSelect(index, photoId, isShift) {
        root.photoSelectMode = true;
        var currentSelected = root.selectedPhotoIds.slice();

        if (isShift && photosRoot.lastSelectedIndex !== -1 && photosRoot.lastSelectedIndex !== index) {
            var start = Math.min(photosRoot.lastSelectedIndex, index);
            var end = Math.max(photosRoot.lastSelectedIndex, index);
            for (var i = start; i <= end; i++) {
                var pid = photosModel[i].id;
                if (currentSelected.indexOf(pid) === -1) {
                    currentSelected.push(pid);
                }
            }
        } else {
            var idx = currentSelected.indexOf(photoId);
            if (idx !== -1) {
                currentSelected.splice(idx, 1);
            } else {
                currentSelected.push(photoId);
            }
            photosRoot.lastSelectedIndex = index;
        }

        root.selectedPhotoIds = currentSelected;
        if (currentSelected.length === 0) {
            root.photoSelectMode = false;
        }
    }

    // Empty State
    Rectangle {
        anchors.centerIn: parent
        width: 440
        height: 240
        color: "transparent"
        visible: photosRoot.photosModel.length === 0 && !photosRoot.isLoading

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 12

            Text {
                text: "\uEB9F"
                font.family: photosRoot.fIcon
                font.pixelSize: 48
                color: root.cTextDim
                Layout.alignment: Qt.AlignHCenter
            }
            Text {
                text: "No Photos Found"
                color: root.cTextMain
                font.family: root.fSans
                font.bold: true
                font.pixelSize: 15
                Layout.alignment: Qt.AlignHCenter
            }
            Text {
                text: root.selectedPeopleFilters.length > 1 && root.personFilterMode === "together"
                    ? "No photos found with all selected people in the same frame.\nTry switching to 'Either (OR)' mode below."
                    : (root.selectedPeopleFilters.length > 0 && root.personFilterMode === "only"
                        ? "No solo photos found where this person is alone in the frame.\nTry switching to 'All with Them' mode to see photos with other people."
                        : (root.selectedPeopleFilters.length > 0 || root.activeFolder !== ""
                            ? "No photos matching the current filter combination."
                            : "No photos found in database. Click '+ Add Folder' above to scan."))
                color: root.cTextMuted
                font.family: root.fSans
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }

            // Quick Switch to All with Them if solo 'only' mode returned 0 photos
            Button {
                visible: root.selectedPeopleFilters.length > 0 && root.personFilterMode === "only"
                flat: true
                Layout.alignment: Qt.AlignHCenter
                contentItem: Text { text: "Show All Photos with Them (Include Group Photos)"; color: "#ffffff"; font.family: root.fSans; font.bold: true; font.pixelSize: 12 }
                background: Rectangle { color: Qt.rgba(255, 255, 255, 0.1); border.color: Qt.rgba(255, 255, 255, 0.18); radius: 6 }
                onClicked: root.personFilterMode = "together"
            }

            // Quick Switch to Either (OR) if multi-person together failed
            Button {
                visible: root.selectedPeopleFilters.length > 1 && root.personFilterMode === "together"
                flat: true
                Layout.alignment: Qt.AlignHCenter
                contentItem: Text { text: "Switch to 'Either (OR)' Mode"; color: "#ffffff"; font.family: root.fSans; font.bold: true; font.pixelSize: 12 }
                background: Rectangle { color: Qt.rgba(255, 255, 255, 0.1); border.color: Qt.rgba(255, 255, 255, 0.18); radius: 6 }
                onClicked: root.personFilterMode = "either"
            }

            // Quick Clear Filters
            Button {
                visible: root.selectedPeopleFilters.length > 0 || root.activeFolder !== "" || root.searchQuery !== ""
                flat: true
                Layout.alignment: Qt.AlignHCenter
                contentItem: Text { text: "Clear All Active Filters"; color: root.cTextMuted; font.family: root.fSans; font.pixelSize: 12 }
                background: Rectangle { color: Qt.rgba(255, 255, 255, 0.05); border.color: root.cBorder; radius: 6 }
                onClicked: root.clearAllFilters()
            }
        }
    }

    // Live Scrubbing Pill (Tracks scrollbar thumb when dragging to move faster - Windows 11 Neutral Style)
    Rectangle {
        id: scrubPill
        visible: vbar.pressed && photosRoot.photosModel.length > 0
        height: 28
        width: pillContent.implicitWidth + 22
        radius: 14
        color: Qt.rgba(36/255, 36/255, 36/255, 0.96)
        border.color: Qt.rgba(255, 255, 255, 0.18)
        border.width: 1
        anchors.right: parent.right
        anchors.rightMargin: 18
        y: Math.max(12, Math.min(grid.height - 40, (vbar.position + vbar.visualSize / 2) * grid.height - height / 2))
        z: 100

        RowLayout {
            id: pillContent
            anchors.centerIn: parent
            spacing: 6

            Text {
                text: "\uEB9F"
                font.family: photosRoot.fIcon
                font.pixelSize: 11
                color: root.cTextMuted
            }

            Text {
                text: {
                    var approxRow = Math.max(0, Math.floor(grid.contentY / grid.cellHeight));
                    var approxIdx = Math.min(photosRoot.photosModel.length, (approxRow + 1) * photosRoot.columnsCount);
                    var total = photosRoot.filteredTotal > 0 ? photosRoot.filteredTotal : photosRoot.photosModel.length;
                    var dateStr = "";
                    if (photosRoot.photosModel[approxIdx - 1] && photosRoot.photosModel[approxIdx - 1].date_taken) {
                        dateStr = " • " + photosRoot.photosModel[approxIdx - 1].date_taken.substring(0, 7);
                    }
                    return approxIdx + " of " + total + dateStr;
                }
                color: "#ffffff"
                font.family: root.fSans
                font.bold: true
                font.pixelSize: 11
            }
        }
    }

    // Floating "Back to Top" Quick Jump Button (Windows 11 Neutral Style)
    Rectangle {
        id: btnScrollTop
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 24
        width: 38
        height: 38
        radius: 19
        color: btnScrollTopMouse.containsMouse ? Qt.rgba(52/255, 52/255, 52/255, 0.95) : Qt.rgba(36/255, 36/255, 36/255, 0.90)
        border.color: Qt.rgba(255, 255, 255, 0.16)
        border.width: 1
        visible: grid.contentY > 800
        z: 90
        scale: btnScrollTopMouse.containsMouse ? 1.06 : 1.0
        Behavior on scale { NumberAnimation { duration: 120 } }
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: "\uE70E" // ChevronUp
            font.family: photosRoot.fIcon
            font.pixelSize: 13
            color: "#ffffff"
        }

        MouseArea {
            id: btnScrollTopMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                grid.contentY = 0;
            }
        }

        ToolTip.visible: btnScrollTopMouse.containsMouse
        ToolTip.text: "Back to Top"
        ToolTip.delay: 300
    }
}
