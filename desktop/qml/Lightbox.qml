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

    // AI Photo Studio Properties
    property bool isEditMode: false
    property string activeEditTool: "eraser" // "eraser" | "hair"
    property real brushSize: 36
    property real hairDarkness: 0.70
    property bool isComparingOriginal: false
    property bool hasEditedPreview: false
    property int editTimestamp: 0
    property bool isEditingBusy: false
    property bool autoSnapEdges: true
    property string inpaintMode: "diffusion" // "diffusion" (GTX 1660 Super) | "lama" (Fast CPU)

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
        function onEditPreviewReady(imageId, toolName, ts) {
            if (lightboxRoot.currentPhoto && lightboxRoot.currentPhoto.id === imageId) {
                lightboxRoot.hasEditedPreview = true;
                lightboxRoot.editTimestamp = ts;
                if (maskCanvas) {
                    maskCanvas.clear();
                }
            }
        }
        function onEditSaved(newImgId, newPath) {
            lightboxRoot.exitEditMode();
            root.refreshPhotos();
        }
        function onIsEditingBusy(busy) {
            lightboxRoot.isEditingBusy = busy;
        }
    }

    function enterEditMode() {
        lightboxRoot.isEditMode = true;
        lightboxRoot.showFaces = false;
        lightboxRoot.selectedFaceId = -1;
        lightboxRoot.hasEditedPreview = false;
        lightboxRoot.editTimestamp = 0;
        if (maskCanvas) maskCanvas.clear();
    }

    function exitEditMode() {
        if (currentPhoto) {
            gallery.cancelPhotoEdit(currentPhoto.id);
        }
        lightboxRoot.isEditMode = false;
        lightboxRoot.hasEditedPreview = false;
        lightboxRoot.isComparingOriginal = false;
        if (maskCanvas) maskCanvas.clear();
    }

    function show(photos, index) {
        lightboxRoot.photosList = photos;
        lightboxRoot.currentIndex = index;
        lightboxRoot.visible = true;
        lightboxRoot.selectedFaceId = -1;
        lightboxRoot.isEditMode = false;
        lightboxRoot.hasEditedPreview = false;
        loadFaces();
    }

    function hide() {
        if (lightboxRoot.isEditMode) {
            lightboxRoot.exitEditMode();
        }
        lightboxRoot.visible = false;
        lightboxRoot.currentIndex = -1;
        lightboxRoot.currentFaces = [];
        lightboxRoot.selectedFaceId = -1;
        lightboxRoot.showFaces = false;
        lightboxRoot.hasEditedPreview = false;
    }

    function loadFaces() {
        if (currentPhoto) {
            gallery.loadPhotoFaces(currentPhoto.id);
        }
    }

    function prev() {
        if (lightboxRoot.isEditMode) {
            lightboxRoot.exitEditMode();
        }
        if (currentIndex > 0) {
            currentIndex--;
            selectedFaceId = -1;
            loadFaces();
        }
    }

    function next() {
        if (lightboxRoot.isEditMode) {
            lightboxRoot.exitEditMode();
        }
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

                // AI Photo Studio Edit Button
                Button {
                    id: btnEditStudio
                    flat: true
                    contentItem: RowLayout {
                        spacing: 5
                        Text {
                            text: "\uE70F"
                            font.family: lightboxRoot.fIcon
                            font.pixelSize: 13
                            color: lightboxRoot.isEditMode ? "#10b981" : root.cTextMain
                        }
                        Text {
                            text: lightboxRoot.isEditMode ? "Exit Studio" : "AI Studio"
                            color: lightboxRoot.isEditMode ? "#10b981" : root.cTextMain
                            font.family: root.fSans
                            font.bold: lightboxRoot.isEditMode
                            font.pixelSize: 12
                        }
                    }
                    background: Rectangle {
                        color: lightboxRoot.isEditMode ? Qt.rgba(16/255, 185/255, 129/255, 0.20) : (btnEditStudio.hovered ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(255, 255, 255, 0.04))
                        border.color: lightboxRoot.isEditMode ? "#10b981" : (btnEditStudio.hovered ? Qt.rgba(255, 255, 255, 0.20) : Qt.rgba(255, 255, 255, 0.12))
                        radius: 4
                    }
                    onClicked: {
                        if (lightboxRoot.isEditMode) {
                            lightboxRoot.exitEditMode();
                        } else {
                            lightboxRoot.enterEditMode();
                        }
                    }
                }

                // Toggle Face Boxes Button
                Button {
                    id: btnToggleFaces
                    visible: !lightboxRoot.isEditMode
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
                source: currentPhoto ? (hasEditedPreview && !isComparingOriginal ? ("image://editpreview/" + currentPhoto.id + "?v=" + editTimestamp) : ("image://raw/" + currentPhoto.id)) : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
            }

            // Interactive AI Studio Draw / Masking Canvas
            Item {
                id: drawContainer
                visible: lightboxRoot.isEditMode && mainImage.paintedWidth > 0 && !lightboxRoot.isComparingOriginal
                x: mainImage.x + (mainImage.width - mainImage.paintedWidth) / 2
                y: mainImage.y + (mainImage.height - mainImage.paintedHeight) / 2
                width: mainImage.paintedWidth
                height: mainImage.paintedHeight
                clip: false

                Canvas {
                    id: maskCanvas
                    anchors.fill: parent
                    renderTarget: Canvas.Image
                    renderStrategy: Canvas.Immediate

                    property var strokes: []
                    property var currentStroke: null
                    property int strokeCount: 0

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);

                        for (var i = 0; i < strokes.length; i++) {
                            var s = strokes[i];
                            if (!s.points || s.points.length === 0) continue;

                            ctx.beginPath();
                            ctx.lineCap = "round";
                            ctx.lineJoin = "round";
                            ctx.lineWidth = s.width;
                            ctx.strokeStyle = s.color;

                            var pts = s.points;
                            if (pts.length === 1) {
                                ctx.arc(pts[0].x, pts[0].y, s.width / 2, 0, 2 * Math.PI);
                                ctx.fillStyle = s.color;
                                ctx.fill();
                            } else {
                                ctx.moveTo(pts[0].x, pts[0].y);
                                for (var j = 1; j < pts.length; j++) {
                                    ctx.lineTo(pts[j].x, pts[j].y);
                                }
                                ctx.stroke();
                            }
                        }

                        if (currentStroke && currentStroke.points && currentStroke.points.length > 0) {
                            ctx.beginPath();
                            ctx.lineCap = "round";
                            ctx.lineJoin = "round";
                            ctx.lineWidth = currentStroke.width;
                            ctx.strokeStyle = currentStroke.color;

                            var activePts = currentStroke.points;
                            if (activePts.length === 1) {
                                ctx.arc(activePts[0].x, activePts[0].y, currentStroke.width / 2, 0, 2 * Math.PI);
                                ctx.fillStyle = currentStroke.color;
                                ctx.fill();
                            } else {
                                ctx.moveTo(activePts[0].x, activePts[0].y);
                                for (var k = 1; k < activePts.length; k++) {
                                    ctx.lineTo(activePts[k].x, activePts[k].y);
                                }
                                ctx.stroke();
                            }
                        }
                    }

                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    function clear() {
                        strokes = [];
                        currentStroke = null;
                        strokeCount = 0;
                        requestPaint();
                    }

                    function undo() {
                        if (strokes.length > 0) {
                            strokes.pop();
                            strokeCount = strokes.length;
                            requestPaint();
                        }
                    }
                }

                MouseArea {
                    id: drawMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.CrossCursor
                    enabled: lightboxRoot.isEditMode && !lightboxRoot.isEditingBusy && !lightboxRoot.isComparingOriginal

                    property real cursorX: 0
                    property real cursorY: 0
                    property bool isInside: false

                    onEntered: isInside = true
                    onExited: isInside = false

                    onPositionChanged: function(mouse) {
                        cursorX = mouse.x;
                        cursorY = mouse.y;
                        if (pressed && maskCanvas.currentStroke) {
                            var pts = maskCanvas.currentStroke.points;
                            if (pts.length > 0) {
                                var lastPt = pts[pts.length - 1];
                                var dx = mouse.x - lastPt.x;
                                var dy = mouse.y - lastPt.y;
                                if (dx * dx + dy * dy >= 4) {
                                    pts.push({ x: mouse.x, y: mouse.y });
                                    maskCanvas.requestPaint();
                                }
                            } else {
                                pts.push({ x: mouse.x, y: mouse.y });
                                maskCanvas.requestPaint();
                            }
                        }
                    }

                    onPressed: function(mouse) {
                        cursorX = mouse.x;
                        cursorY = mouse.y;
                        var strokeCol = lightboxRoot.activeEditTool === "eraser" ? "rgba(239, 68, 68, 0.60)" : "rgba(56, 189, 248, 0.60)";
                        maskCanvas.currentStroke = {
                            color: strokeCol,
                            width: lightboxRoot.brushSize,
                            points: [{ x: mouse.x, y: mouse.y }]
                        };
                        maskCanvas.requestPaint();
                    }

                    onReleased: function(mouse) {
                        if (maskCanvas.currentStroke) {
                            maskCanvas.strokes.push(maskCanvas.currentStroke);
                            maskCanvas.currentStroke = null;
                            maskCanvas.strokeCount = maskCanvas.strokes.length;
                            maskCanvas.requestPaint();
                        }
                    }

                    onCanceled: {
                        if (maskCanvas.currentStroke) {
                            maskCanvas.strokes.push(maskCanvas.currentStroke);
                            maskCanvas.currentStroke = null;
                            maskCanvas.strokeCount = maskCanvas.strokes.length;
                            maskCanvas.requestPaint();
                        }
                    }
                }

                // Smooth Brush Circle Cursor Follower
                Rectangle {
                    id: brushCursor
                    width: lightboxRoot.brushSize
                    height: lightboxRoot.brushSize
                    radius: lightboxRoot.brushSize / 2
                    color: "transparent"
                    border.color: lightboxRoot.activeEditTool === "eraser" ? "#ef4444" : "#38bdf8"
                    border.width: 1.5
                    x: drawMouseArea.cursorX - width / 2
                    y: drawMouseArea.cursorY - height / 2
                    visible: drawMouseArea.isInside && drawMouseArea.enabled
                    z: 20
                }
            }

            // Busy Processing Notification Pill
            Rectangle {
                id: busyEditPill
                visible: lightboxRoot.isEditingBusy
                anchors.centerIn: parent
                width: busyRow.implicitWidth + 32
                height: 44
                radius: 22
                color: Qt.rgba(20/255, 20/255, 20/255, 0.92)
                border.color: "#10b981"
                border.width: 1.5
                z: 50

                RowLayout {
                    id: busyRow
                    anchors.centerIn: parent
                    spacing: 10

                    BusyIndicator {
                        running: lightboxRoot.isEditingBusy
                        implicitWidth: 22
                        implicitHeight: 22
                    }

                    Text {
                        text: lightboxRoot.activeEditTool === "eraser" ? (lightboxRoot.autoSnapEdges ? "Detecting object edges & inpainting with LaMa AI..." : "Inpainting background with LaMa AI...") : "Applying Natural Hair Darkening..."
                        color: "#ffffff"
                        font.family: root.fSans
                        font.pixelSize: 12
                        font.bold: true
                    }
                }
            }

            // Face Bounding Boxes Overlay
            Repeater {
                model: (!lightboxRoot.isEditMode && mainImage.paintedWidth > 0 && currentFaces.length > 0 && (showFaces || selectedFaceId !== -1)) ? currentFaces : []
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
                visible: !lightboxRoot.isEditMode && currentIndex > 0
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
                visible: !lightboxRoot.isEditMode && currentIndex < photosList.length - 1
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
            visible: !lightboxRoot.isEditMode

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

        // AI Photo Studio Drawer (Bottom Bar)
        Rectangle {
            id: editStudioDrawer
            Layout.fillWidth: true
            height: 64
            color: "#1c1c1c"
            border.color: Qt.rgba(255, 255, 255, 0.08)
            visible: lightboxRoot.isEditMode

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 14

                // Tool Switcher Tabs
                RowLayout {
                    spacing: 6

                    // Eraser Tool Tab
                    Rectangle {
                        width: 118
                        height: 36
                        radius: 6
                        color: lightboxRoot.activeEditTool === "eraser" ? Qt.rgba(239/255, 68/255, 68/255, 0.18) : (eraserTabMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(255, 255, 255, 0.04))
                        border.color: lightboxRoot.activeEditTool === "eraser" ? "#ef4444" : Qt.rgba(255, 255, 255, 0.12)
                        border.width: lightboxRoot.activeEditTool === "eraser" ? 1.5 : 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "\uE75C"
                                font.family: lightboxRoot.fIcon
                                font.pixelSize: 13
                                color: lightboxRoot.activeEditTool === "eraser" ? "#ef4444" : root.cTextMain
                            }
                            Text {
                                text: "Magic Eraser"
                                color: lightboxRoot.activeEditTool === "eraser" ? "#ffffff" : root.cTextMain
                                font.family: root.fSans
                                font.pixelSize: 12
                                font.bold: lightboxRoot.activeEditTool === "eraser"
                            }
                        }

                        MouseArea {
                            id: eraserTabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: lightboxRoot.activeEditTool = "eraser"
                        }
                    }

                    // Hair Darkener Tool Tab
                    Rectangle {
                        width: 118
                        height: 36
                        radius: 6
                        color: lightboxRoot.activeEditTool === "hair" ? Qt.rgba(56/255, 189/255, 248/255, 0.18) : (hairTabMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(255, 255, 255, 0.04))
                        border.color: lightboxRoot.activeEditTool === "hair" ? "#38bdf8" : Qt.rgba(255, 255, 255, 0.12)
                        border.width: lightboxRoot.activeEditTool === "hair" ? 1.5 : 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "\uE790"
                                font.family: lightboxRoot.fIcon
                                font.pixelSize: 13
                                color: lightboxRoot.activeEditTool === "hair" ? "#38bdf8" : root.cTextMain
                            }
                            Text {
                                text: "Darken Hair"
                                color: lightboxRoot.activeEditTool === "hair" ? "#ffffff" : root.cTextMain
                                font.family: root.fSans
                                font.pixelSize: 12
                                font.bold: lightboxRoot.activeEditTool === "hair"
                            }
                        }

                        MouseArea {
                            id: hairTabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: lightboxRoot.activeEditTool = "hair"
                        }
                    }
                }

                // Vertical Divider
                Rectangle {
                    width: 1
                    height: 28
                    color: Qt.rgba(255, 255, 255, 0.12)
                }

                // Brush Size Control
                RowLayout {
                    spacing: 8
                    Text {
                        text: "Brush: " + Math.round(lightboxRoot.brushSize) + "px"
                        color: root.cTextMuted
                        font.family: root.fSans
                        font.pixelSize: 12
                        Layout.minimumWidth: 76
                    }
                    Slider {
                        id: brushSlider
                        from: 10
                        to: 120
                        value: lightboxRoot.brushSize
                        stepSize: 2
                        Layout.preferredWidth: 100
                        onMoved: lightboxRoot.brushSize = value

                        background: Rectangle {
                            x: brushSlider.leftPadding
                            y: brushSlider.topPadding + brushSlider.availableHeight / 2 - 2
                            width: brushSlider.availableWidth
                            height: 4
                            radius: 2
                            color: Qt.rgba(255, 255, 255, 0.15)
                            Rectangle {
                                width: brushSlider.visualPosition * parent.width
                                height: parent.height
                                color: "#10b981"
                                radius: 2
                            }
                        }

                        handle: Rectangle {
                            x: brushSlider.leftPadding + brushSlider.visualPosition * (brushSlider.availableWidth - width)
                            y: brushSlider.topPadding + brushSlider.availableHeight / 2 - height / 2
                            implicitWidth: 16
                            implicitHeight: 16
                            radius: 8
                            color: "#ffffff"
                            border.color: brushSlider.pressed ? "#059669" : "#10b981"
                            border.width: 2
                        }
                    }
                }

                // Hair Depth Control
                RowLayout {
                    visible: lightboxRoot.activeEditTool === "hair"
                    spacing: 8
                    Text {
                        text: "Depth: " + Math.round(lightboxRoot.hairDarkness * 100) + "%"
                        color: root.cTextMuted
                        font.family: root.fSans
                        font.pixelSize: 12
                        Layout.minimumWidth: 72
                    }
                    Slider {
                        id: hairSlider
                        from: 0.20
                        to: 1.00
                        value: lightboxRoot.hairDarkness
                        stepSize: 0.05
                        Layout.preferredWidth: 90
                        onMoved: lightboxRoot.hairDarkness = value

                        background: Rectangle {
                            x: hairSlider.leftPadding
                            y: hairSlider.topPadding + hairSlider.availableHeight / 2 - 2
                            width: hairSlider.availableWidth
                            height: 4
                            radius: 2
                            color: Qt.rgba(255, 255, 255, 0.15)
                            Rectangle {
                                width: hairSlider.visualPosition * parent.width
                                height: parent.height
                                color: "#38bdf8"
                                radius: 2
                            }
                        }

                        handle: Rectangle {
                            x: hairSlider.leftPadding + hairSlider.visualPosition * (hairSlider.availableWidth - width)
                            y: hairSlider.topPadding + hairSlider.availableHeight / 2 - height / 2
                            implicitWidth: 16
                            implicitHeight: 16
                            radius: 8
                            color: "#ffffff"
                            border.color: hairSlider.pressed ? "#0284c7" : "#38bdf8"
                            border.width: 2
                        }
                    }
                }

                // Auto Edge Snap Toggle Button
                Rectangle {
                    visible: lightboxRoot.activeEditTool === "eraser"
                    width: edgeSnapRow.implicitWidth + 18
                    height: 32
                    radius: 4
                    color: lightboxRoot.autoSnapEdges ? Qt.rgba(16/255, 185/255, 129/255, 0.22) : (edgeSnapMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(255, 255, 255, 0.04))
                    border.color: lightboxRoot.autoSnapEdges ? "#10b981" : Qt.rgba(255, 255, 255, 0.12)
                    border.width: lightboxRoot.autoSnapEdges ? 1.5 : 1

                    RowLayout {
                        id: edgeSnapRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            text: "\uE71E"
                            font.family: lightboxRoot.fIcon
                            font.pixelSize: 13
                            color: lightboxRoot.autoSnapEdges ? "#10b981" : root.cTextMuted
                        }
                        Text {
                            text: "Auto Edge Snap"
                            color: lightboxRoot.autoSnapEdges ? "#ffffff" : root.cTextMuted
                            font.family: root.fSans
                            font.pixelSize: 11
                            font.bold: lightboxRoot.autoSnapEdges
                        }
                    }

                    MouseArea {
                        id: edgeSnapMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: lightboxRoot.autoSnapEdges = !lightboxRoot.autoSnapEdges
                    }

                    ToolTip.visible: edgeSnapMouse.containsMouse
                    ToolTip.text: "Automatically detects and snaps mask to object contours"
                    ToolTip.delay: 300
                }

                // AI Inpainting Engine Mode Selector (GTX 1660 Diffusion vs Fast LaMa)
                Rectangle {
                    visible: lightboxRoot.activeEditTool === "eraser"
                    width: inpaintModeRow.implicitWidth + 18
                    height: 32
                    radius: 4
                    color: lightboxRoot.inpaintMode === "diffusion" ? Qt.rgba(16/255, 185/255, 129/255, 0.22) : (inpaintModeMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(255, 255, 255, 0.04))
                    border.color: lightboxRoot.inpaintMode === "diffusion" ? "#10b981" : Qt.rgba(255, 255, 255, 0.12)
                    border.width: lightboxRoot.inpaintMode === "diffusion" ? 1.5 : 1

                    RowLayout {
                        id: inpaintModeRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            text: lightboxRoot.inpaintMode === "diffusion" ? "\uE945" : "\uE75C"
                            font.family: lightboxRoot.fIcon
                            font.pixelSize: 13
                            color: lightboxRoot.inpaintMode === "diffusion" ? "#10b981" : root.cTextMuted
                        }
                        Text {
                            text: lightboxRoot.inpaintMode === "diffusion" ? "AI Diffusion (GTX 1660)" : "Fast LaMa (CPU)"
                            color: lightboxRoot.inpaintMode === "diffusion" ? "#ffffff" : root.cTextMuted
                            font.family: root.fSans
                            font.pixelSize: 11
                            font.bold: lightboxRoot.inpaintMode === "diffusion"
                        }
                    }

                    MouseArea {
                        id: inpaintModeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (lightboxRoot.inpaintMode === "diffusion") {
                                lightboxRoot.inpaintMode = "lama";
                            } else {
                                lightboxRoot.inpaintMode = "diffusion";
                            }
                        }
                    }

                    ToolTip.visible: inpaintModeMouse.containsMouse
                    ToolTip.text: lightboxRoot.inpaintMode === "diffusion" ? "GPU Generative Diffusion (GTX 1660 Super) - Photorealistic flagship quality" : "Fast on-device pattern inpainter - Instant for small blemishes"
                    ToolTip.delay: 300
                }

                // Vertical Divider
                Rectangle {
                    width: 1
                    height: 28
                    color: Qt.rgba(255, 255, 255, 0.12)
                }

                // Undo & Clear Brush Buttons
                RowLayout {
                    spacing: 6

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 4
                        color: undoMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.05)
                        border.color: Qt.rgba(255, 255, 255, 0.12)

                        Text {
                            anchors.centerIn: parent
                            text: "\uE7A7"
                            font.family: lightboxRoot.fIcon
                            font.pixelSize: 13
                            color: root.cTextMain
                        }

                        MouseArea {
                            id: undoMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: maskCanvas.undo()
                        }

                        ToolTip.visible: undoMouse.containsMouse
                        ToolTip.text: "Undo last stroke"
                        ToolTip.delay: 300
                    }

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 4
                        color: clearMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.05)
                        border.color: Qt.rgba(255, 255, 255, 0.12)

                        Text {
                            anchors.centerIn: parent
                            text: "\uE74D"
                            font.family: lightboxRoot.fIcon
                            font.pixelSize: 13
                            color: clearMouse.containsMouse ? "#ff99a4" : root.cTextMain
                        }

                        MouseArea {
                            id: clearMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: maskCanvas.clear()
                        }

                        ToolTip.visible: clearMouse.containsMouse
                        ToolTip.text: "Clear drawn mask"
                        ToolTip.delay: 300
                    }
                }

                Item { Layout.fillWidth: true }

                // Actions Group: Compare, Apply, Save, Done
                RowLayout {
                    spacing: 8

                    // Hold to Compare
                    Rectangle {
                        visible: lightboxRoot.hasEditedPreview
                        width: compareRow.implicitWidth + 20
                        height: 34
                        radius: 4
                        color: lightboxRoot.isComparingOriginal ? Qt.rgba(56/255, 189/255, 248/255, 0.25) : (compareMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.10) : Qt.rgba(255, 255, 255, 0.05))
                        border.color: lightboxRoot.isComparingOriginal ? "#38bdf8" : Qt.rgba(255, 255, 255, 0.15)

                        RowLayout {
                            id: compareRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "\uE7B5"
                                font.family: lightboxRoot.fIcon
                                font.pixelSize: 12
                                color: lightboxRoot.isComparingOriginal ? "#38bdf8" : root.cTextMain
                            }
                            Text {
                                text: lightboxRoot.isComparingOriginal ? "Showing Original" : "Hold to Compare"
                                color: lightboxRoot.isComparingOriginal ? "#38bdf8" : root.cTextMain
                                font.family: root.fSans
                                font.pixelSize: 11
                            }
                        }

                        MouseArea {
                            id: compareMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: lightboxRoot.isComparingOriginal = true
                            onReleased: lightboxRoot.isComparingOriginal = false
                            onCanceled: lightboxRoot.isComparingOriginal = false
                        }
                    }

                    // Apply Action Button
                    Button {
                        id: btnApplyEdit
                        enabled: !lightboxRoot.isEditingBusy && maskCanvas.strokeCount > 0
                        flat: true
                        contentItem: RowLayout {
                            spacing: 6
                            Text {
                                text: lightboxRoot.isEditingBusy ? "\uE895" : (lightboxRoot.activeEditTool === "eraser" ? "\uE75C" : "\uE790")
                                font.family: lightboxRoot.fIcon
                                font.pixelSize: 13
                                color: "#ffffff"
                            }
                            Text {
                                text: lightboxRoot.isEditingBusy ? "Processing..." : (lightboxRoot.activeEditTool === "eraser" ? "Erase Object" : "Darken Hair")
                                color: "#ffffff"
                                font.family: root.fSans
                                font.bold: true
                                font.pixelSize: 12
                            }
                        }
                        background: Rectangle {
                            color: !btnApplyEdit.enabled ? Qt.rgba(255, 255, 255, 0.08) : (btnApplyEdit.hovered ? "#059669" : "#10b981")
                            radius: 4
                            implicitHeight: 34
                            implicitWidth: 120
                        }
                        onClicked: {
                            if (lightboxRoot.currentPhoto) {
                                var maskData = maskCanvas.toDataURL("image/png");
                                if (lightboxRoot.activeEditTool === "eraser") {
                                    gallery.applyMagicEraser(lightboxRoot.currentPhoto.id, maskData, lightboxRoot.autoSnapEdges, lightboxRoot.inpaintMode, "");
                                } else {
                                    gallery.applyHairDarken(lightboxRoot.currentPhoto.id, maskData, lightboxRoot.hairDarkness);
                                }
                            }
                        }
                    }

                    // Save Non-Destructive Copy Button
                    Button {
                        id: btnSaveEdit
                        visible: lightboxRoot.hasEditedPreview
                        flat: true
                        contentItem: RowLayout {
                            spacing: 6
                            Text {
                                text: "\uE74E"
                                font.family: lightboxRoot.fIcon
                                font.pixelSize: 13
                                color: "#ffffff"
                            }
                            Text {
                                text: "Save as Copy"
                                color: "#ffffff"
                                font.family: root.fSans
                                font.bold: true
                                font.pixelSize: 12
                            }
                        }
                        background: Rectangle {
                            color: btnSaveEdit.hovered ? "#0091ff" : "#0078d4"
                            radius: 4
                            implicitHeight: 34
                            implicitWidth: 120
                        }
                        onClicked: {
                            if (lightboxRoot.currentPhoto) {
                                gallery.saveEditedPhoto(lightboxRoot.currentPhoto.id);
                            }
                        }
                    }

                    // Done / Exit Studio Button
                    Button {
                        id: btnCancelEdit
                        flat: true
                        contentItem: Text {
                            text: "Done"
                            color: root.cTextMain
                            font.family: root.fSans
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: btnCancelEdit.hovered ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.05)
                            border.color: Qt.rgba(255, 255, 255, 0.12)
                            radius: 4
                            implicitHeight: 34
                            implicitWidth: 65
                        }
                        onClicked: lightboxRoot.exitEditMode()
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
