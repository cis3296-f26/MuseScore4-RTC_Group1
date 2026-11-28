import MuseScore 3.0
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import FileIO 3.0

MuseScore {
    id: root
    title: "MuseScore 4 Real-Time Collab"
    description: "This plugin allows for collaboration in MuseScore 4."
    requiresScore: true
    version: "4.0"
    pluginType: "dialog"
    width: 400
    height: 300
    menuPath: "Plugins.Notes.RTC"
    property int nodeSocketID: -1
    property string activeSessionCode: ""
    property int lastNoteCount: -1
    property var lastScoreSnapshot: ({})
    property int lastTick: -1
    property int lastPitch: -1
    property bool isRemoteUpdate: false
    property string lastCursorPositionKey: ""

    property var tickSizes: [1920, 960, 480, 240, 120, 60, 30]
    property var denoms: [1, 2, 4, 8, 16, 32, 64]
    /*
    tickSizes and denoms key: 1920/1: Whole Note/Rest. 960/2: Half Note/Rest.
    480/4: Quarter Note/Rest. 240/8: Eighth Note/Rest. 120/16: 16th Note/Rest.
    60/32: 32nd Note/Rest. 30/64: 64th Note/Rest
    */
    //GUI for determining hosting/joining score
    Dialog {
        id: mainDialog
        width: 400
        height: 300
        visible: true

        background: Rectangle {
            color: "#323c4d"
            radius: 0
        }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            Label {
                text: "Host or Join a Score"
                font.family: "Corbel"
                color: "white"
                font.pixelSize: 32
                Layout.alignment: Qt.AlignHCenter
            }

            Button {
                text: "Host"
                Layout.alignment: Qt.AlignHCenter
                onClicked: {
                    if (root.nodeSocketID === -1) {
                        sessionStatus.text = "Not connected to server.";
                        return;
                    }

                    api.websocket.send(root.nodeSocketID, JSON.stringify({
                        type: "HostSession"
                    }));
                }
            }
            Button {
                id: joinButton
                text: "Join"
                Layout.alignment: Qt.AlignHCenter
                onClicked: {
                    if (root.nodeSocketID === -1) {
                        sessionStatus.text = "Not connected to server.";
                        return;
                    }

                    var code = joinCode.text.trim().toUpperCase();

                    if (!/^[A-Z0-9]{4}$/.test(code)) {
                        sessionStatus.text = "Enter a valid 4-character code.";
                        return;
                    }

                    api.websocket.send(root.nodeSocketID, JSON.stringify({
                        type: "JoinSession",
                        sessionCode: code
                    }));
                }
            }
            TextArea {
                id: joinCode
                Layout.fillWidth: true
                Layout.fillHeight: true
                wrapMode: Text.Wrap
                font.pixelSize: 14
                color: "white"
                background: Rectangle {
                    color: "black"
                    radius: 5
                }
                onTextChanged: {
                    cursorPosition = length;
                    joinButton.text = "Join " + joinCode.text;
                }
            }
            Label {
                id: remoteCursorStatus
                text: "Other collaborator: no selection reported"
                color: "#a9d8ff"
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            Label {
                id: sessionStatus
                text: "Connecting to server..."
                color: "white"
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }
    }
    function onMessageFromServer(msg) {
        var parsedMsg = JSON.parse(msg);
        if (parsedMsg.type === "Connected") {
            sessionStatus.text = "Connected to server.";
            return;
        }

        if (parsedMsg.type === "SessionCreated" || parsedMsg.type === "SessionJoined") {
            root.activeSessionCode = parsedMsg.sessionCode;

            if (parsedMsg.type === "SessionCreated") {
                sessionStatus.text = "Hosting: " + parsedMsg.sessionCode;
            } else {
                sessionStatus.text = "Joined: " + parsedMsg.sessionCode;
            }

            root.lastScoreSnapshot = root.takeScoreSnapshot();
            root.lastCursorPositionKey = "";
            root.pollCursorPosition();
            scoreTimer.start();
            return;
        }

        if (parsedMsg.type === "Error") {
            sessionStatus.text = parsedMsg.message || "An error occurred.";
            return;
        }

        if (parsedMsg.type === "SessionClosed") {
            root.activeSessionCode = "";
            scoreTimer.stop();
            remoteCursorStatus.text = "Other collaborator: no selection reported";
            root.lastCursorPositionKey = "";
            sessionStatus.text = "Session closed.";
            return;
        }

        if (parsedMsg.type === "PeerJoined") {
            sessionStatus.text = "Another user joined.";
            return;
        }

        if (parsedMsg.type === "PeerLeft") {
            sessionStatus.text = "Another user left.";
            remoteCursorStatus.text = "Other collaborator: no selection reported";
            return;
        }
        if (parsedMsg.type === "CursorPosition") {
            var pos = parsedMsg.position;
            if (!pos) {
                remoteCursorStatus.text = "Other collaborator: selection cleared";
            } else {
                remoteCursorStatus.text = "Other collaborator: staff " + (pos.staff + 1) + ", tick " + pos.tick + (pos.pitch !== undefined ? ", MIDI pitch " + pos.pitch : "");
            }
            return;
        }
        if (parsedMsg.type === "ScoreOperation") {
            if (parsedMsg.operation === "NoteSelectionChanged") {
                return; // Prevent local cursor from snapping to the note when a remote user selects it
            }

            isRemoteUpdate = true;
            curScore.startCmd();

            var cursor = curScore.newCursor();

            if (parsedMsg.operation === "ChordAdded" && parsedMsg.current) {
                var chordData = parsedMsg.current;

                cursor.track = (chordData.track !== undefined) ? chordData.track : 0;
                cursor.rewindToTick(chordData.tick);

                var failSafe = 0;
                while (cursor.tick < chordData.tick) {
                    var gap = chordData.tick - cursor.tick;
                    var restAdded = false;
                    var prevTick = cursor.tick;

                    for (var i = 0; i < root.tickSizes.length; i++) {
                        if (gap >= root.tickSizes[i]) {
                            cursor.setDuration(1, root.denoms[i]);
                            cursor.addRest();
                            restAdded = true;
                            break;
                        }
                    }
                    if (!restAdded || cursor.tick <= prevTick)
                        break;

                    failSafe++;
                }

                if (chordData.duration > 0) {
                    cursor.setDuration(chordData.duration, 1920);
                } else {
                    cursor.setDuration(1, 4);
                }

                for (var i = 0; i < chordData.pitches.length; i++) {
                    cursor.addNote(chordData.pitches[i]);
                }
                
            } else if ((parsedMsg.operation === "PitchChanged" || parsedMsg.operation === "DurationChanged") && parsedMsg.current){
                var newChord = parsedMsg.current;
                cursor.track = (newChord.track !== undefined) ? newChord.track : 0;
                cursor.rewindToTick(newChord.tick);
                
                if (newChord.duration > 0){
                    cursor.setDuration(newChord.duration, 1920);
                } else{
                    cursor.setDuration(1, 4);
                }
                
                for (var i = 0; i < newChord.pitches.length; i++){
                    cursor.addNote(newChord.pitches[i], i > 0);
                }
                
            } else if (parsedMsg.operation === "ChordRemoved" && parsedMsg.previous) {
                var oldChord = parsedMsg.previous;
                cursor.track = (oldChord.track !== undefined) ? oldChord.track : 0;
                cursor.rewindToTick(oldChord.tick);

                if (oldChord.duration > 0) {
                    cursor.setDuration(oldChord.duration, 1920);
                } else {
                    cursor.setDuration(1, 4);
                }
                cursor.addRest();
            }
            /*
            else if(parsedMsg.operation === "NoteCountChanged" && parsedMsg.note){
                var noteData = parsedMsg.note;

                cursor.track = (noteData.track !== undefined) ? noteData.track : 0;
                cursor.rewindToTick(noteData.startTick);
                if (noteData.duration > 0){
                    cursor.setDuration(noteData.duration, 1920)
                }
                else{
                    cursor.setDuration(1, 4);
                }

                cursor.addNote(noteData.pitch);
                root.lastPitch = noteData.pitch;
                root.lastTick = noteData.startTick;
            }
            */

            curScore.endCmd();

            //root.lastNoteCount = root.countNotes();
            root.lastScoreSnapshot = root.takeScoreSnapshot();
            isRemoteUpdate = false;
        }
    }

    FileIO {
        id: outfile
        source: tempPath() + "/MuseScoreScript.log"
        onError: console.log(msg)
    }
    /*
    function countNotes() {
        if (!curScore) return 0;

        var count = 0;
        var cursor = curScore.newCursor();

        cursor.rewind(0);

        while (cursor.segment) {
            if (cursor.element && cursor.element.type === Element.CHORD) {
                count += cursor.element.notes.length;
            }
            cursor.next();
        }

        return count;
    }
    */
    // Read notes from all staves and voices. Each track has four voices.
    // This is a detection only snapshot, it does not modify the score.
    function takeScoreSnapshot() {
        var snapshot = {};
        if (!curScore)
            return snapshot;

        var totalTracks = curScore.nstaves * 4;
        for (var track = 0; track < totalTracks; track++) {
            var cursor = curScore.newCursor();
            cursor.track = track;
            cursor.rewind(0);

            while (cursor.segment) {
                var element = cursor.element;
                if (element && element.type === Element.CHORD) {
                    var pitches = [];
                    for (var i = 0; i < element.notes.length; i++) {
                        pitches.push(element.notes[i].pitch);
                    }
                    pitches.sort(function (a, b) {
                        return a - b;
                    });

                    var duration = element.duration ? element.duration.ticks : -1;
                    var key = track + ":" + cursor.tick;
                    snapshot[key] = {
                        track: track,
                        tick: cursor.tick,
                        pitches: pitches,
                        duration: duration
                    };
                }
                cursor.next();
            }
        }
        return snapshot;
    }

    function sendDetectedChange(operation, previous, current) {
        console.log("Detected " + operation + ": " + JSON.stringify({
            previous: previous,
            current: current
        }));
        if (root.nodeSocketID !== -1) {
            api.websocket.send(root.nodeSocketID, JSON.stringify({
                type: "ScoreOperation",
                operation: operation,
                previous: previous || null,
                current: current || null
            }));
        }
    }

    function compareScoreSnapshots(previous, current) {
        var key;
        for (key in current) {
            if (!previous.hasOwnProperty(key)) {
                root.sendDetectedChange("ChordAdded", null, current[key]);
            } else {
                var oldChord = previous[key];
                var newChord = current[key];
                if (JSON.stringify(oldChord.pitches) !== JSON.stringify(newChord.pitches)) {
                    root.sendDetectedChange("PitchChanged", oldChord, newChord);
                }
                if (oldChord.duration !== newChord.duration) {
                    root.sendDetectedChange("DurationChanged", oldChord, newChord);
                }
            }
        }
        for (key in previous) {
            if (!current.hasOwnProperty(key)) {
                root.sendDetectedChange("ChordRemoved", previous[key], null);
            }
        }
    }

    function getSelectedNoteData() {
        if (!curScore || !curScore.selection || curScore.selection.elements.length === 0) {
            return null;
        }

        var el = curScore.selection.elements[0];
        var realTick = -1;

        if (el.type === Element.NOTE) {
            var chord = el.parent;
            if (chord && chord.parent) {
                realTick = chord.parent.tick;
            }
            return {
                pitch: el.pitch,
                startTick: realTick,
                duration: chord && chord.duration ? chord.duration.ticks : -1
            };
        }

        if (el.type === Element.CHORD && el.notes.length > 0) {
            var seg = el.parent;
            return {
                pitch: el.notes[0].pitch,
                startTick: realTick,
                duration: el.duration ? el.duration.ticks : -1
            };
        }

        return null;
    }

    // Read the visible GUI selection, not a separate traversal cursor.
    function getCursorPosition() {
        if (!curScore || !curScore.selection)
            return null;
        var selection = curScore.selection;
        if (selection.isRange && selection.startSegment) {
            return {
                kind: "range",
                tick: selection.startSegment.tick,
                staff: selection.startStaff
            };
        }
        if (!selection.elements || selection.elements.length === 0)
            return null;
        var el = selection.elements[0];
        if (!el)
            return null;
        var position = {
            kind: "element",
            tick: -1,
            staff: (el.track !== undefined && el.track >= 0) ? Math.floor(el.track / 4) : -1
        };
        var parent = el;
        for (var depth = 0; depth < 5 && parent; depth++) {
            if (parent.type === Element.SEGMENT && parent.tick !== undefined) {
                position.tick = parent.tick;
                break;
            }
            parent = parent.parent;
        }
        if (position.tick < 0 || position.staff < 0)
            return null;
        if (el.type === Element.NOTE)
            position.pitch = el.pitch;
        return position;
    }

    function pollCursorPosition() {
        if (!root.activeSessionCode || root.nodeSocketID === -1)
            return;
        var position = root.getCursorPosition();
        var signature = JSON.stringify(position);
        if (signature === root.lastCursorPositionKey)
            return;
        root.lastCursorPositionKey = signature;
        console.log("Cursor position: " + signature);
        api.websocket.send(root.nodeSocketID, JSON.stringify({
            type: "CursorPosition",
            position: position
        }));
    }

    Timer {
        id: scoreTimer
        interval: 1000
        repeat: true
        running: false

        onTriggered: {
            if (!curScore || root.isRemoteUpdate)
                return;

            root.pollCursorPosition();

            // Compare real score contents, not just the selected note.
            var currentSnapshot = root.takeScoreSnapshot();
            root.compareScoreSnapshots(root.lastScoreSnapshot, currentSnapshot);
            root.lastScoreSnapshot = currentSnapshot;

            // Retain the original note count change detection.

            var noteData = root.getSelectedNoteData();
            /* Redundant Code. Keeping just in case
            var currentCount = root.countNotes();
            if (currentCount !== root.lastNoteCount) {
                if (root.nodeSocketID !== -1) {
                    api.websocket.send(root.nodeSocketID, JSON.stringify({
                        type: "ScoreOperation",
                        operation: "NoteCountChanged",
                        previousCount: root.lastNoteCount,
                        currentCount: currentCount,
                        note: noteData
                    }));
                }
                root.lastNoteCount = currentCount;
                if (noteData) {
                    root.lastPitch = noteData.pitch;
                    root.lastTick = noteData.startTick;
                }

            }
            */
            if (noteData && (noteData.pitch !== root.lastPitch || noteData.startTick !== root.lastTick)) {
                if (root.nodeSocketID !== -1) {
                    api.websocket.send(root.nodeSocketID, JSON.stringify({
                        type: "ScoreOperation",
                        operation: "NoteSelectionChanged",
                        note: noteData
                    }));
                }
                root.lastPitch = noteData.pitch;
                root.lastTick = noteData.startTick;
            }
        }
    }

    onRun: {
        console.log("Run " + root.title);

        // Open the native built in websocket and capture the dynamic socket ID (sid)
        api.websocket.open(8080, function (sid) {
            console.log("Connected to Node Backend. Socket ID: " + sid);

            root.nodeSocketID = sid;

            //root.lastNoteCount = root.countNotes();
            root.lastScoreSnapshot = root.takeScoreSnapshot();

            api.websocket.onMessage(root.nodeSocketID, root.onMessageFromServer);
        });
    }
}
