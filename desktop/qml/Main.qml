import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: root
    visible: true
    width: 1380
    height: 890
    minimumWidth: 960
    minimumHeight: 640
    title: "Suvi Gallery - Private AI Photo & Face Organizer (100% Offline)"
    color: root.cBgMain

    // Windows 11 System Typography
    readonly property string fSans: "Segoe UI Variable Text, Segoe UI, sans-serif"
    readonly property string fSansDisplay: "Segoe UI Variable Display, Segoe UI, sans-serif"
    readonly property string fIcon: "Segoe Fluent Icons, Segoe MDL2 Assets"

    // Windows 11 Dark Neutral Palette (Exact native Windows 11 Photos App look)
    readonly property color cBgMain: "#1f1f1f"          // Windows 11 Dark canvas
    readonly property color cBgSurface: "#282828"       // Windows 11 CommandBar / Navigation
    readonly property color cBgCard: "#2b2b2b"          // Windows 11 Card surface
    readonly property color cBgCardHover: "#353535"     // Card hover
    readonly property color cBorder: Qt.rgba(255, 255, 255, 0.08)      // Subtle neutral border
    readonly property color cBorderHover: Qt.rgba(255, 255, 255, 0.18) // Hover border
    readonly property color cTextMain: "#ffffff"        // Primary text
    readonly property color cTextMuted: Qt.rgba(255, 255, 255, 0.70)   // Secondary text
    readonly property color cTextDim: Qt.rgba(255, 255, 255, 0.45)     // Tertiary text
    readonly property color cAccent: "#60cdff"          // Windows 11 Fluent Blue (soft, modern)
    readonly property color cAccentHover: "#7be0ff"
    readonly property color cDanger: "#ff99a4"          // Windows 11 soft red for warnings
    readonly property color cSuccess: "#6ccb5f"         // Subtle Fluent green

    // App State
    property string currentTab: "photos"
    property string activeFolder: ""
    property var selectedPeopleFilters: [] // [{ id, name }]
    property string personFilterMode: "together" // "together", "only", "either"
    property string searchQuery: ""

    onActiveFolderChanged: {
        if (root.currentTab === "photos" && photosView) photosView.refresh();
    }
    onSelectedPeopleFiltersChanged: {
        syncPeopleCombo();
        if (root.currentTab === "photos" && photosView) photosView.refresh();
    }
    onPersonFilterModeChanged: {
        if (root.currentTab === "photos" && photosView) photosView.refresh();
    }
    onSearchQueryChanged: {
        if (root.currentTab === "photos" && photosView) photosView.refresh();
    }

    // Multi-Selection State for Photos
    property bool photoSelectMode: false
    property var selectedPhotoIds: []
    property string whatsappTarget: "desktop" // "desktop" | "web"

    // Live AI HUD State
    property int totalImages: 0
    property int processedImages: 0
    property int totalFaces: 0
    property int totalPeople: 0
    property real speedFps: 0.0
    property bool isRunning: false
    property bool isScanning: false

    // Connect to Python GalleryBridge signals
    Connections {
        target: gallery

        function onStatusChanged(status) {
            root.totalImages = status.total_images || 0;
            root.processedImages = status.processed_images || 0;
            root.totalFaces = status.total_faces || 0;
            root.totalPeople = status.total_people || 0;
            root.speedFps = status.speed_fps || 0.0;
            root.isRunning = status.is_running || false;
            root.isScanning = status.is_scanning || false;
        }

        function onToastNotification(message, type) {
            toast.show(message, type);
        }
    }

    Component.onCompleted: {
        root.whatsappTarget = gallery.getWhatsAppMode();
        gallery.loadFolders();
        gallery.loadPeople();
    }

    // Top Header (Windows 11 Fluent CommandBar)
    header: Rectangle {
        height: 56
        color: root.cBgSurface
        border.color: root.cBorder
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 16

            // Brand
            RowLayout {
                spacing: 10
                Rectangle {
                    width: 32
                    height: 32
                    radius: 6
                    color: Qt.rgba(255, 255, 255, 0.08)
                    border.color: root.cBorder
                    Text {
                        anchors.centerIn: parent
                        text: "\uEB9F"
                        font.family: root.fIcon
                        font.pixelSize: 16
                        color: "#ffffff"
                    }
                }
                Text {
                    text: "Suvi Gallery"
                    color: root.cTextMain
                    font.family: root.fSans
                    font.bold: true
                    font.pixelSize: 15
                }
                Rectangle {
                    color: Qt.rgba(255, 255, 255, 0.06)
                    border.color: Qt.rgba(255, 255, 255, 0.12)
                    radius: 10
                    implicitWidth: offlineText.implicitWidth + 14
                    implicitHeight: 20
                    Text {
                        id: offlineText
                        anchors.centerIn: parent
                        text: "OFFLINE"
                        color: root.cTextMuted
                        font.family: root.fSans
                        font.pixelSize: 10
                        font.bold: true
                    }
                }
            }

            // Navigation Tabs (Clean Windows 11 Fluent Tabs)
            RowLayout {
                spacing: 4
                Layout.leftMargin: 10

                // Photos Tab Button
                Button {
                    id: btnTabPhotos
                    flat: true
                    contentItem: RowLayout {
                        spacing: 7
                        Text {
                            text: "\uEB9F"
                            font.family: root.fIcon
                            font.pixelSize: 14
                            color: root.currentTab === "photos" ? "#ffffff" : root.cTextMuted
                        }
                        Text {
                            text: "Photos (" + root.totalImages + ")"
                            color: root.currentTab === "photos" ? "#ffffff" : root.cTextMuted
                            font.family: root.fSans
                            font.bold: root.currentTab === "photos"
                            font.pixelSize: 13
                        }
                    }
                    background: Rectangle {
                        color: root.currentTab === "photos" ? Qt.rgba(255, 255, 255, 0.08) : (btnTabPhotos.hovered ? Qt.rgba(255, 255, 255, 0.04) : "transparent")
                        radius: 6
                        border.color: root.currentTab === "photos" ? Qt.rgba(255, 255, 255, 0.12) : "transparent"
                    }
                    onClicked: root.switchTab("photos")
                }

                // Folders Tab Button
                Button {
                    id: btnTabFolders
                    flat: true
                    contentItem: RowLayout {
                        spacing: 7
                        Text {
                            text: "\uED25"
                            font.family: root.fIcon
                            font.pixelSize: 14
                            color: root.currentTab === "folders" ? "#ffffff" : root.cTextMuted
                        }
                        Text {
                            text: "Folders"
                            color: root.currentTab === "folders" ? "#ffffff" : root.cTextMuted
                            font.family: root.fSans
                            font.bold: root.currentTab === "folders"
                            font.pixelSize: 13
                        }
                    }
                    background: Rectangle {
                        color: root.currentTab === "folders" ? Qt.rgba(255, 255, 255, 0.08) : (btnTabFolders.hovered ? Qt.rgba(255, 255, 255, 0.04) : "transparent")
                        radius: 6
                        border.color: root.currentTab === "folders" ? Qt.rgba(255, 255, 255, 0.12) : "transparent"
                    }
                    onClicked: root.switchTab("folders")
                }

                // People Tab Button
                Button {
                    id: btnTabPeople
                    flat: true
                    contentItem: RowLayout {
                        spacing: 7
                        Text {
                            text: "\uE716"
                            font.family: root.fIcon
                            font.pixelSize: 14
                            color: root.currentTab === "people" ? "#ffffff" : root.cTextMuted
                        }
                        Text {
                            text: "People (" + root.totalPeople + ")"
                            color: root.currentTab === "people" ? "#ffffff" : root.cTextMuted
                            font.family: root.fSans
                            font.bold: root.currentTab === "people"
                            font.pixelSize: 13
                        }
                    }
                    background: Rectangle {
                        color: root.currentTab === "people" ? Qt.rgba(255, 255, 255, 0.08) : (btnTabPeople.hovered ? Qt.rgba(255, 255, 255, 0.04) : "transparent")
                        radius: 6
                        border.color: root.currentTab === "people" ? Qt.rgba(255, 255, 255, 0.12) : "transparent"
                    }
                    onClicked: root.switchTab("people")
                }
            }

            // Search Bar (Windows 11 Subtle Neutral Style)
            Rectangle {
                Layout.fillWidth: true
                Layout.maximumWidth: 440
                height: 36
                color: Qt.rgba(255, 255, 255, 0.06)
                radius: 6
                border.color: searchInput.activeFocus ? Qt.rgba(255, 255, 255, 0.3) : root.cBorder

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    spacing: 8

                    Text {
                        text: "\uE721"
                        font.family: root.fIcon
                        font.pixelSize: 13
                        color: root.cTextMuted
                    }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        color: root.cTextMain
                        font.family: root.fSans
                        font.pixelSize: 13
                        clip: true
                        selectByMouse: true

                        Text {
                            anchors.fill: parent
                            text: "Search people, scenes, objects..."
                            color: root.cTextDim
                            font.family: root.fSans
                            font.pixelSize: 13
                            visible: !searchInput.text && !searchInput.activeFocus
                        }

                        onTextChanged: searchDebounce.restart()
                    }

                    Text {
                        text: "\uE711"
                        font.family: root.fIcon
                        color: root.cTextMuted
                        font.pixelSize: 10
                        visible: searchInput.text.length > 0
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                searchInput.text = "";
                                root.searchQuery = "";
                                photosView.refresh();
                            }
                        }
                    }
                }

                Timer {
                    id: searchDebounce
                    interval: 300
                    onTriggered: {
                        root.searchQuery = searchInput.text.trim();
                        photosView.refresh();
                    }
                }
            }

            // Add Folder Button (Fluent Neutral CommandBar Button)
            Button {
                id: btnAddFolder
                flat: true
                contentItem: RowLayout {
                    spacing: 7
                    Text { text: "\uE8F4"; font.family: root.fIcon; font.pixelSize: 14; color: "#ffffff" }
                    Text { text: "Add Folder"; color: "#ffffff"; font.family: root.fSans; font.bold: true; font.pixelSize: 12 }
                }
                background: Rectangle {
                    color: btnAddFolder.hovered ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.08)
                    border.color: Qt.rgba(255, 255, 255, 0.14)
                    radius: 6
                }
                onClicked: gallery.pickFolder()
            }
        }
    }

    // Main Column Layout
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Sub-Bar: Folder filter & Action Trigger & AI Progress HUD
        Rectangle {
            id: subBar
            Layout.fillWidth: true
            height: 48
            color: root.cBgSurface
            border.color: root.cBorder
            border.width: 1

            // 1. SELECTION MODE ACTIVE TOOLBAR (Windows 11 Fluent CommandBar)
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 12
                visible: root.currentTab === "photos" && (root.photoSelectMode || root.selectedPhotoIds.length > 0)

                // Close / Cancel Selection
                Button {
                    id: btnCancelSel
                    flat: true
                    contentItem: Text {
                        text: "\uE711"
                        font.family: root.fIcon
                        color: btnCancelSel.hovered ? "#ffffff" : root.cTextMuted
                        font.pixelSize: 12
                        font.bold: true
                    }
                    background: Rectangle {
                        color: btnCancelSel.hovered ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(255, 255, 255, 0.04)
                        radius: 6
                        border.color: root.cBorder
                    }
                    onClicked: {
                        root.photoSelectMode = false;
                        root.selectedPhotoIds = [];
                    }
                }

                // Selected Count Badge (Neutral Fluent Pill)
                Rectangle {
                    color: Qt.rgba(255, 255, 255, 0.08)
                    border.color: Qt.rgba(255, 255, 255, 0.14)
                    radius: 6
                    implicitHeight: 28
                    implicitWidth: selCountBadgeText.implicitWidth + 20

                    Text {
                        id: selCountBadgeText
                        anchors.centerIn: parent
                        text: root.selectedPhotoIds.length > 0
                            ? (root.selectedPhotoIds.length + " selected")
                            : "Click photos to select"
                        color: "#ffffff"
                        font.family: root.fSans
                        font.bold: true
                        font.pixelSize: 12
                    }
                }

                // Select All / Deselect All Toggle Button
                Button {
                    id: btnToggleSelectAll
                    flat: true
                    contentItem: RowLayout {
                        spacing: 6
                        Text {
                            text: (photosView && root.selectedPhotoIds.length >= photosView.photosModel.length && photosView.photosModel.length > 0) ? "\uE73E" : "\uE762"
                            font.family: root.fIcon
                            font.pixelSize: 13
                            color: "#ffffff"
                        }
                        Text {
                            text: (photosView && root.selectedPhotoIds.length >= photosView.photosModel.length && photosView.photosModel.length > 0) ? "Deselect All" : "Select All"
                            color: "#ffffff"
                            font.family: root.fSans
                            font.pixelSize: 12
                        }
                    }
                    background: Rectangle {
                        color: btnToggleSelectAll.hovered ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(255, 255, 255, 0.04)
                        radius: 6
                        border.color: root.cBorder
                    }
                    onClicked: photosView.toggleSelectAll()
                }

                Item { Layout.fillWidth: true } // Spacer

                // Share Menu Button with unified Popup
                Button {
                    id: btnShareMenuTrigger
                    visible: root.selectedPhotoIds.length > 0
                    flat: true
                    contentItem: RowLayout {
                        spacing: 6
                        Text { text: "\uE72D"; font.family: root.fIcon; font.pixelSize: 13; color: "#ffffff" }
                        Text { text: "Share"; color: "#ffffff"; font.family: root.fSans; font.bold: true; font.pixelSize: 12 }
                        Text { text: "\uE70D"; font.family: root.fIcon; color: root.cTextMuted; font.pixelSize: 9 }
                    }
                    background: Rectangle {
                        color: btnShareMenuTrigger.hovered ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.07)
                        border.color: Qt.rgba(255, 255, 255, 0.14)
                        radius: 6
                    }
                    onClicked: shareMenuPopup.open()

                    Popup {
                        id: shareMenuPopup
                        y: parent.height + 6
                        x: parent.width - width
                        width: 220
                        padding: 6
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                        background: Rectangle {
                            color: "#2c2c2c"
                            radius: 8
                            border.color: Qt.rgba(255, 255, 255, 0.12)
                            border.width: 1
                        }

                        contentItem: ColumnLayout {
                            spacing: 4

                            // WhatsApp (Desktop)
                            Rectangle {
                                Layout.fillWidth: true
                                height: 36
                                radius: 6
                                color: itemWaDesktopMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.08) : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 9
                                    Text { text: "\uE8BD"; font.family: root.fIcon; font.pixelSize: 14; color: root.cTextMuted }
                                    Text { text: "WhatsApp (Desktop)"; color: "#ffffff"; font.family: root.fSans; font.pixelSize: 12 }
                                }

                                MouseArea {
                                    id: itemWaDesktopMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        shareMenuPopup.close();
                                        gallery.shareViaWhatsApp(root.selectedPhotoIds, "desktop");
                                    }
                                }
                            }

                            // WhatsApp (Web)
                            Rectangle {
                                Layout.fillWidth: true
                                height: 36
                                radius: 6
                                color: itemWaWebMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.08) : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 9
                                    Text { text: "\uE774"; font.family: root.fIcon; font.pixelSize: 14; color: root.cTextMuted }
                                    Text { text: "WhatsApp (Web)"; color: "#ffffff"; font.family: root.fSans; font.pixelSize: 12 }
                                }

                                MouseArea {
                                    id: itemWaWebMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        shareMenuPopup.close();
                                        gallery.shareViaWhatsApp(root.selectedPhotoIds, "web");
                                    }
                                }
                            }

                            // Divider
                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Qt.rgba(255, 255, 255, 0.08)
                            }

                            // Open in Windows Gallery
                            Rectangle {
                                Layout.fillWidth: true
                                height: 36
                                radius: 6
                                color: itemGalleryMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.08) : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 9
                                    Text { text: "\uE8A7"; font.family: root.fIcon; font.pixelSize: 14; color: root.cTextMuted }
                                    Text { text: "Open in Gallery"; color: "#ffffff"; font.family: root.fSans; font.pixelSize: 12 }
                                }

                                MouseArea {
                                    id: itemGalleryMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        shareMenuPopup.close();
                                        gallery.openInGallery(root.selectedPhotoIds);
                                    }
                                }
                            }
                        }
                    }
                }

                // Copy Options Dropdown Button (Windows 11 Fluent CommandBar Button)
                Button {
                    id: btnCopyMenu
                    visible: root.selectedPhotoIds.length > 0
                    flat: true
                    contentItem: RowLayout {
                        spacing: 6
                        Text { text: "\uE8C8"; font.family: root.fIcon; font.pixelSize: 13; color: "#ffffff" }
                        Text { text: "Copy ▾"; color: "#ffffff"; font.family: root.fSans; font.bold: true; font.pixelSize: 12 }
                    }
                    background: Rectangle {
                        color: (btnCopyMenu.hovered || copyMenuPopup.opened) ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.06)
                        border.color: root.cBorder
                        radius: 6
                    }
                    onClicked: copyMenuPopup.open()

                    Popup {
                        id: copyMenuPopup
                        y: btnCopyMenu.height + 4
                        width: 200
                        padding: 6
                        background: Rectangle {
                            color: "#2c2c2c"
                            border.color: Qt.rgba(255, 255, 255, 0.12)
                            radius: 8
                        }

                        ColumnLayout {
                            width: parent.width
                            spacing: 2

                            // Copy File Names
                            Rectangle {
                                Layout.fillWidth: true
                                height: 34
                                radius: 6
                                color: itemCopyNamesMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.08) : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 9
                                    Text { text: "\uE8C8"; font.family: root.fIcon; font.pixelSize: 13; color: root.cTextMuted }
                                    Text { text: "Copy File Names"; color: "#ffffff"; font.family: root.fSans; font.pixelSize: 12 }
                                }

                                MouseArea {
                                    id: itemCopyNamesMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        copyMenuPopup.close();
                                        gallery.copyFileNames(root.selectedPhotoIds);
                                    }
                                }
                            }

                            // Copy Full File Paths
                            Rectangle {
                                Layout.fillWidth: true
                                height: 34
                                radius: 6
                                color: itemCopyPathsMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.08) : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 9
                                    Text { text: "\uEC50"; font.family: root.fIcon; font.pixelSize: 13; color: root.cTextMuted }
                                    Text { text: "Copy Full Paths"; color: "#ffffff"; font.family: root.fSans; font.pixelSize: 12 }
                                }

                                MouseArea {
                                    id: itemCopyPathsMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        copyMenuPopup.close();
                                        gallery.copyFilePaths(root.selectedPhotoIds);
                                    }
                                }
                            }

                            // Divider
                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Qt.rgba(255, 255, 255, 0.08)
                            }

                            // Copy Photos (Files)
                            Rectangle {
                                Layout.fillWidth: true
                                height: 34
                                radius: 6
                                color: itemCopyFilesMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.08) : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 9
                                    Text { text: "\uEB9F"; font.family: root.fIcon; font.pixelSize: 13; color: root.cTextMuted }
                                    Text { text: "Copy Photos (Files)"; color: "#ffffff"; font.family: root.fSans; font.pixelSize: 12 }
                                }

                                MouseArea {
                                    id: itemCopyFilesMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        copyMenuPopup.close();
                                        gallery.copyToClipboard(root.selectedPhotoIds);
                                    }
                                }
                            }
                        }
                    }
                }

                // Compact Remove Button (Windows 11 Fluent Delete Button)
                Button {
                    id: btnRemoveSelected
                    visible: root.selectedPhotoIds.length > 0
                    flat: true
                    contentItem: RowLayout {
                        spacing: 6
                        Text {
                            text: "\uE74D"
                            font.family: root.fIcon
                            font.pixelSize: 13
                            color: btnRemoveSelected.hovered ? "#ff99a4" : "#ffffff"
                        }
                        Text {
                            text: "Delete"
                            color: btnRemoveSelected.hovered ? "#ff99a4" : "#ffffff"
                            font.family: root.fSans
                            font.bold: true
                            font.pixelSize: 12
                        }
                    }
                    background: Rectangle {
                        color: btnRemoveSelected.hovered ? Qt.rgba(239/255, 68/255, 68/255, 0.15) : Qt.rgba(255, 255, 255, 0.06)
                        border.color: btnRemoveSelected.hovered ? Qt.rgba(239/255, 68/255, 68/255, 0.4) : root.cBorder
                        radius: 6
                    }
                    onClicked: confirmRemoveSelectedDialog.visible = true
                }
            }
            // 2. NORMAL BROWSE TOOLBAR (When not in multi-select mode)
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 14
                visible: !(root.currentTab === "photos" && (root.photoSelectMode || root.selectedPhotoIds.length > 0))

                // Folder Dropdown Filter
                ComboBox {
                    id: folderCombo
                    Layout.preferredWidth: Math.min(260, root.width * 0.24)
                    model: ["All Folders (All Photos)"]
                    property var folderPaths: []
                    font.family: root.fSans

                    Connections {
                        target: gallery
                        function onFoldersLoaded(folders) {
                            var items = ["All Folders (All Photos)"];
                            var paths = [];
                            for (var i = 0; i < folders.length; i++) {
                                items.push(folders[i].name + " (" + folders[i].photo_count + ")");
                                paths.push(folders[i].directory);
                            }
                            folderCombo.folderPaths = paths;
                            folderCombo.model = items;
                        }
                    }

                    onActivated: (index) => {
                        if (index === 0) {
                            root.activeFolder = "";
                        } else {
                            root.selectedPeopleFilters = [];
                            root.activeFolder = folderCombo.folderPaths[index - 1] || "";
                        }
                    }
                }

                // People Dropdown Filter (Visible on Photos tab)
                ComboBox {
                    id: peopleCombo
                    visible: root.currentTab === "photos"
                    Layout.preferredWidth: Math.min(260, root.width * 0.24)
                    model: ["All People (No Filter)"]
                    property var peopleList: []
                    font.family: root.fSans

                    Connections {
                        target: gallery
                        function onPeopleLoaded(people) {
                            var items = ["All People (No Filter)"];
                            var plist = [];
                            for (var i = 0; i < people.length; i++) {
                                var pName = people[i].name || ("Person #" + people[i].id);
                                items.push(pName + " (" + people[i].photo_count + ")");
                                plist.push({ id: people[i].id, name: pName, avatar_face_id: people[i].avatar_face_id });
                            }
                            peopleCombo.peopleList = plist;
                            peopleCombo.model = items;
                            root.syncPeopleCombo();
                        }
                    }

                    onActivated: (index) => {
                        if (index === 0) {
                            root.selectedPeopleFilters = [];
                            root.personFilterMode = "together";
                        } else {
                            var p = peopleCombo.peopleList[index - 1];
                            if (p) {
                                root.activeFolder = "";
                                folderCombo.currentIndex = 0;
                                root.selectedPeopleFilters = [{ id: p.id, name: p.name, avatar_face_id: p.avatar_face_id }];
                                root.personFilterMode = "together";
                            }
                        }
                    }
                }

                // Clean Select Mode Trigger Button
                Button {
                    id: btnStartSelect
                    flat: true
                    visible: root.currentTab === "photos"
                    contentItem: RowLayout {
                        spacing: 6
                        Text { text: "\uE762"; font.family: root.fIcon; font.pixelSize: 13; color: "#ffffff" }
                        Text { text: "Select"; color: "#ffffff"; font.family: root.fSans; font.bold: true; font.pixelSize: 12 }
                    }
                    background: Rectangle {
                        color: btnStartSelect.hovered ? Qt.rgba(255, 255, 255, 0.1) : Qt.rgba(255, 255, 255, 0.05)
                        border.color: root.cBorder
                        radius: 6
                    }
                    onClicked: root.photoSelectMode = true
                }

                Item { Layout.fillWidth: true } // Spacer

                // Live AI Indexing HUD (Clean Windows 11 Status Indicator)
                RowLayout {
                    spacing: 10
                    visible: root.totalImages > 0

                    Rectangle {
                        width: 7
                        height: 7
                        radius: 3.5
                        color: root.isRunning ? root.cAccent : (root.isScanning ? "#ffd54f" : Qt.rgba(255, 255, 255, 0.7))
                        SequentialAnimation on opacity {
                            running: root.isRunning || root.isScanning
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.3; to: 1.0; duration: 600 }
                            NumberAnimation { from: 1.0; to: 0.3; duration: 600 }
                        }
                    }

                    Text {
                        text: root.isRunning ? "AI Indexing..." : (root.isScanning ? "Scanning..." : "Ready")
                        color: root.cTextMuted
                        font.family: root.fSans
                        font.pixelSize: 12
                    }

                    Text {
                        text: root.processedImages + " / " + root.totalImages + " indexed"
                        color: root.cTextDim
                        font.family: root.fSans
                        font.pixelSize: 12
                    }

                    Text {
                        text: root.speedFps > 0 ? (root.speedFps.toFixed(1) + " fps") : ""
                        color: root.cTextDim
                        font.family: root.fSans
                        font.pixelSize: 12
                        visible: root.speedFps > 0
                    }
                }
            }
        }

        // Active Filter Banner (Neutral Windows 11 Fluent Chips)
        Rectangle {
            id: filterBanner
            Layout.fillWidth: true
            height: 44
            color: Qt.rgba(36/255, 36/255, 36/255, 0.98)
            border.color: root.cBorder
            border.width: 1
            visible: root.activeFolder !== "" || root.selectedPeopleFilters.length > 0

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 12

                Text { text: "Active Filter:"; color: root.cTextDim; font.family: root.fSans; font.pixelSize: 12; font.bold: true }

                // Folder Chip
                Rectangle {
                    visible: root.activeFolder !== ""
                    color: Qt.rgba(255, 255, 255, 0.08)
                    border.color: Qt.rgba(255, 255, 255, 0.14)
                    radius: 6
                    implicitHeight: 28
                    implicitWidth: folderChipRow.implicitWidth + 24

                    RowLayout {
                        id: folderChipRow
                        anchors.centerIn: parent
                        spacing: 7
                        Text { text: "\uED25"; font.family: root.fIcon; font.pixelSize: 12; color: root.cTextMuted }
                        Text { text: root.activeFolder; color: "#ffffff"; font.family: root.fSans; font.pixelSize: 12 }
                        Text {
                            text: "\uE711"
                            font.family: root.fIcon
                            color: root.cTextMuted
                            font.pixelSize: 10
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.activeFolder = "";
                                    folderCombo.currentIndex = 0;
                                    photosView.refresh();
                                }
                            }
                        }
                    }
                }

                // People Chips
                Repeater {
                    model: root.selectedPeopleFilters
                    delegate: Rectangle {
                        color: Qt.rgba(255, 255, 255, 0.08)
                        border.color: Qt.rgba(255, 255, 255, 0.14)
                        radius: 6
                        implicitHeight: 28
                        implicitWidth: pChipRow.implicitWidth + 20

                        RowLayout {
                            id: pChipRow
                            anchors.centerIn: parent
                            spacing: 8

                            Rectangle {
                                width: 20
                                height: 20
                                radius: 10
                                clip: true
                                color: "#333"
                                visible: modelData.avatar_face_id ? true : false

                                Image {
                                    anchors.fill: parent
                                    source: modelData.avatar_face_id ? ("image://face/" + modelData.avatar_face_id) : ""
                                    fillMode: Image.PreserveAspectCrop
                                }
                            }

                            Text {
                                visible: !modelData.avatar_face_id
                                text: "\uE77B"
                                font.family: root.fIcon
                                font.pixelSize: 12
                                color: root.cTextMuted
                            }

                            Text {
                                id: pChipText
                                text: (modelData.name || ("Person #" + modelData.id)) + (root.selectedPeopleFilters.length === 1 && photosView && photosView.filteredTotal >= 0 ? " (" + photosView.filteredTotal + " photos)" : "")
                                color: "#ffffff"
                                font.family: root.fSans
                                font.bold: true
                                font.pixelSize: 12
                            }

                            Text {
                                text: "\uE711"
                                font.family: root.fIcon
                                color: root.cTextMuted
                                font.pixelSize: 10
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var cur = root.selectedPeopleFilters.slice();
                                        cur.splice(index, 1);
                                        root.selectedPeopleFilters = cur;
                                    }
                                }
                            }
                        }
                    }
                }

                // Single Person Mode Switcher (Visible when exactly 1 person selected)
                RowLayout {
                    visible: root.selectedPeopleFilters.length === 1
                    spacing: 6

                    Text { text: "Option:"; color: root.cTextDim; font.family: root.fSans; font.pixelSize: 12 }

                    Button {
                        id: btnAllWithThem
                        flat: true
                        contentItem: RowLayout {
                            spacing: 5
                            Text {
                                text: "\uE716"
                                font.family: root.fIcon
                                font.pixelSize: 12
                                color: root.personFilterMode !== "only" ? "#ffffff" : root.cTextMuted
                            }
                            Text {
                                text: "All with Them"
                                color: root.personFilterMode !== "only" ? "#ffffff" : root.cTextMuted
                                font.family: root.fSans
                                font.bold: root.personFilterMode !== "only"
                                font.pixelSize: 11
                            }
                        }
                        background: Rectangle {
                            color: root.personFilterMode !== "only" ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.04)
                            radius: 6
                            border.color: root.personFilterMode !== "only" ? Qt.rgba(255, 255, 255, 0.22) : root.cBorder
                        }
                        onClicked: { root.personFilterMode = "together"; }
                    }

                    Button {
                        id: btnOnlyThem
                        flat: true
                        contentItem: RowLayout {
                            spacing: 5
                            Text {
                                text: "\uE735"
                                font.family: root.fIcon
                                font.pixelSize: 12
                                color: root.personFilterMode === "only" ? "#ffffff" : root.cTextMuted
                            }
                            Text {
                                text: "Only Them"
                                color: root.personFilterMode === "only" ? "#ffffff" : root.cTextMuted
                                font.family: root.fSans
                                font.bold: root.personFilterMode === "only"
                                font.pixelSize: 11
                            }
                        }
                        background: Rectangle {
                            color: root.personFilterMode === "only" ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.04)
                            radius: 6
                            border.color: root.personFilterMode === "only" ? Qt.rgba(255, 255, 255, 0.22) : root.cBorder
                        }
                        onClicked: {
                            root.personFilterMode = (root.personFilterMode === "only" ? "together" : "only");
                        }
                    }
                }

                // Multi-People Relational Mode Switcher (Visible when 2+ people selected)
                RowLayout {
                    visible: root.selectedPeopleFilters.length >= 2
                    spacing: 4

                    Text { text: "Mode:"; color: root.cTextDim; font.family: root.fSans; font.pixelSize: 12 }

                    Button {
                        flat: true
                        contentItem: Text {
                            text: "Together (AND)"
                            color: root.personFilterMode === "together" ? "#ffffff" : root.cTextMuted
                            font.family: root.fSans
                            font.bold: root.personFilterMode === "together"
                            font.pixelSize: 11
                        }
                        background: Rectangle {
                            color: root.personFilterMode === "together" ? Qt.rgba(255, 255, 255, 0.12) : "transparent"
                            radius: 4
                            border.color: root.personFilterMode === "together" ? Qt.rgba(255, 255, 255, 0.22) : root.cBorder
                        }
                        onClicked: { root.personFilterMode = "together"; }
                    }

                    Button {
                        flat: true
                        contentItem: Text {
                            text: "Either (OR)"
                            color: root.personFilterMode === "either" ? "#ffffff" : root.cTextMuted
                            font.family: root.fSans
                            font.bold: root.personFilterMode === "either"
                            font.pixelSize: 11
                        }
                        background: Rectangle {
                            color: root.personFilterMode === "either" ? Qt.rgba(255, 255, 255, 0.12) : "transparent"
                            radius: 4
                            border.color: root.personFilterMode === "either" ? Qt.rgba(255, 255, 255, 0.22) : root.cBorder
                        }
                        onClicked: { root.personFilterMode = "either"; }
                    }

                    Button {
                        flat: true
                        contentItem: Text {
                            text: "Strictly ONLY Them"
                            color: root.personFilterMode === "only" ? "#ffffff" : root.cTextMuted
                            font.family: root.fSans
                            font.bold: root.personFilterMode === "only"
                            font.pixelSize: 11
                        }
                        background: Rectangle {
                            color: root.personFilterMode === "only" ? Qt.rgba(255, 255, 255, 0.12) : "transparent"
                            radius: 4
                            border.color: root.personFilterMode === "only" ? Qt.rgba(255, 255, 255, 0.22) : root.cBorder
                        }
                        onClicked: { root.personFilterMode = "only"; }
                    }
                }

                Item { Layout.fillWidth: true }

                Button {
                    flat: true
                    contentItem: RowLayout {
                        spacing: 5
                        Text { text: "Clear All"; color: root.cTextMuted; font.family: root.fSans; font.pixelSize: 12 }
                        Text { text: "\uE711"; font.family: root.fIcon; color: root.cTextMuted; font.pixelSize: 10 }
                    }
                    onClicked: root.clearAllFilters()
                }
            }
        }

        // Main Stack Views
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            PhotosView {
                id: photosView
                anchors.fill: parent
                visible: root.currentTab === "photos"
            }

            FoldersView {
                id: foldersView
                anchors.fill: parent
                visible: root.currentTab === "folders"
            }

            PeopleView {
                id: peopleView
                anchors.fill: parent
                visible: root.currentTab === "people"
            }
        }
    }

    // Remove Selected Photos Confirmation Modal
    Rectangle {
        id: confirmRemoveSelectedDialog
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
            width: Math.min(440, parent.width - 40)
            height: 190
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
                        font.family: root.fIcon
                        font.pixelSize: 16
                        color: "#ff99a4"
                    }
                    Text {
                        text: "Remove Selected Photos from Library?"
                        color: "#ffffff"
                        font.family: root.fSans
                        font.bold: true
                        font.pixelSize: 15
                    }
                }

                Text {
                    text: "Remove " + root.selectedPhotoIds.length + " selected photo(s) from your catalog?\n\nYour original files on disk will NOT be deleted."
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
                        onClicked: confirmRemoveSelectedDialog.visible = false
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
                            confirmRemoveSelectedDialog.visible = false;
                            var ids = root.selectedPhotoIds.slice();
                            gallery.removePhotosFromLibrary(ids);
                            root.selectedPhotoIds = [];
                            root.photoSelectMode = false;
                            photosView.refresh();
                        }
                    }
                }
            }
        }
    }

    // Lightbox Inspector Modal
    Lightbox {
        id: lightbox
        anchors.fill: parent
        visible: false
    }

    // Toast Notification Component
    Rectangle {
        id: toast
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 24
        height: 44
        width: Math.min(460, toastMsg.implicitWidth + 60)
        radius: 8
        color: "#2c2c2c"
        border.color: Qt.rgba(255, 255, 255, 0.14)
        border.width: 1
        opacity: 0
        z: 9999

        property string message: ""

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 10
            Text {
                id: toastIcon
                text: "\uE73E"
                font.family: root.fIcon
                font.pixelSize: 14
                color: "#60cdff"
            }
            Text {
                id: toastMsg
                text: toast.message
                color: root.cTextMain
                font.family: root.fSans
                font.pixelSize: 12
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        function show(msg, type) {
            toast.message = msg;
            if (type === "warning") {
                toastIcon.text = "\uE7BA";
                toastIcon.color = "#ffd54f";
                toast.border.color = Qt.rgba(255, 213, 79, 0.4);
            } else if (type === "info") {
                toastIcon.text = "\uE946";
                toastIcon.color = "#60cdff";
                toast.border.color = Qt.rgba(96, 205, 255, 0.4);
            } else {
                toastIcon.text = "\uE73E";
                toastIcon.color = "#60cdff";
                toast.border.color = Qt.rgba(255, 255, 255, 0.16);
            }
            toastAnim.restart();
        }

        SequentialAnimation {
            id: toastAnim
            NumberAnimation { target: toast; property: "opacity"; to: 1.0; duration: 200 }
            PauseAnimation { duration: 4000 }
            NumberAnimation { target: toast; property: "opacity"; to: 0.0; duration: 300 }
        }
    }

    // Tab Switching Helper
    function switchTab(tab) {
        root.currentTab = tab;
        if (tab === "folders") {
            gallery.loadFolders();
        } else if (tab === "people") {
            gallery.loadPeople();
        } else if (tab === "photos") {
            photosView.refresh();
        }
    }

    function refreshPhotos() {
        if (photosView) photosView.refresh();
    }

    function clearAllFilters() {
        root.activeFolder = "";
        root.selectedPeopleFilters = [];
        root.personFilterMode = "together";
        root.searchQuery = "";
        searchInput.text = "";
        folderCombo.currentIndex = 0;
        syncPeopleCombo();
        photosView.refresh();
    }

    function syncPeopleCombo() {
        if (typeof peopleCombo === "undefined" || !peopleCombo || !peopleCombo.peopleList) return;
        if (root.selectedPeopleFilters.length === 1) {
            var targetId = root.selectedPeopleFilters[0].id;
            for (var i = 0; i < peopleCombo.peopleList.length; i++) {
                if (peopleCombo.peopleList[i].id === targetId) {
                    peopleCombo.currentIndex = i + 1;
                    return;
                }
            }
            peopleCombo.currentIndex = 0;
        } else if (root.selectedPeopleFilters.length === 0) {
            peopleCombo.currentIndex = 0;
        } else {
            peopleCombo.currentIndex = -1;
        }
    }
}
