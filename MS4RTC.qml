import MuseScore 3.0
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import FileIO 3.0

MuseScore {
    title: "MuseScore 4 Real-Time Collab"
    description: "This plugin allows for collaboration in MuseScore 4."
    requiresScore: true
    version: "4.0"
    pluginType: "dialog"
    width: 400
    height: 300
    menuPath: "Plugins.Notes.RTC"
    property int nodeSocketID: -1
    property int lastNoteCount: -1
    property var lastScoreSnapshot: ({})
    property int lastTick: -1
    property int lastPitch: -1
    property bool isRemoteUpdate: false
    property var lastSelectedNotes: []
    id: root
    



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
                    
                }
            }
            Button {
                text: "Join"
		id: joinButton
		Layout.alignment: Qt.AlignHCenter
                onClicked: {
                    
                }
            }
	    TextArea {
                id: joinCode
		Layout.fillWidth: true
                Layout.fillHeight: true
                wrapMode: Text.Wrap
                font.pixelSize: 14
                color: "white"
                background: Rectangle { color: "black"; radius: 5 }
                onTextChanged: {
                    cursorPosition = length
		    joinButton.text = "Join " + joinCode.text
                }
            }
            
        }
    }
    function onMessageFromServer(msg) {
        var parsedMsg = JSON.parse(msg);
        if(parsedMsg.type === "ScoreOperation"){
            if (parsedMsg.operation === "NoteSelectionChanged"){
                return; // Prevent local cursor from snapping to the note when a remote user selects it
            }

            if (parsedMsg.operation === "NoteCountChanged" && parsedMsg.notes){
                isRemoteUpdate = true;
                
                curScore.startCmd();

                for (var i = 0; i <parsedMsg.notes.length; i++){
                    var noteData = parsedMsg.notes[i]
                    var cursor = curScore.newCursor();
                    cursor.track = 0
                    cursor.rewindToTick(noteData.startTick)

                    if (noteData.duration > 0){
                        cursor.setDuration(noteData.duration, 1920)
                    }else{
                        cursor.setDuration(1,4);
                    }
                    cursor.addNote(noteData.pitch);
                }

                curScore.endCmd();
                root.lastNoteCount = root.countNotes();
                isRemoteUpdate = false;
            }
            if (parsedMsg.operation === "NotesDeleted" && parsedMsg.notes){
                isRemoteUpdate = true;
                curScore.startCmd();

                for (var j = 0; j<parsedMsg.notes.length; j++){
                    var ghostNote = parsedMsg.notes[j];
                    var delCursor = curScore.newCursor();
                    delCursor.track = 0;
                    delCursor.rewindToTick(ghostNote.startTick);

                    if (delCursor.element && delCursor.element.type === Element.CHORD){
                        for (var k = 0; k < delCursor.element.notes.length; k++){
                            if (delCursor.element.notes[k].pitch === ghostNote.pitch){
                                removeElement(delCursor.element.notes[k]);
                                break;
                            }
                        }
                    }
                }
                curScore.endCmd();
                root.lastNoteCount = root.countNotes();
                isRemoteUpdate = false;
            }
        }
    }

    FileIO {
        id: outfile
        source: tempPath() + "/MuseScoreScript.log"
        onError: console.log(msg)
    }  

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

    // Read notes from all staves and voices. Each track has four voices.
    // This is a detection only snapshot, it does not modify the score.
    function takeScoreSnapshot() {
        var snapshot = {};
        if (!curScore) return snapshot;

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
                    pitches.sort(function(a, b) { return a - b; });

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
        console.log("Detected " + operation + ": " + JSON.stringify({previous: previous, current: current}));
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

    function getSelectedNoteData(){
        if (!curScore || !curScore.selection || curScore.selection.elements.length === 0) {return null;}

        var el = curScore.selection.elements[0];
        var realTick = -1;

        if (el.type === Element.NOTE){
            var chord = el.parent;
            if (chord && chord.parent){
                realTick = chord.parent.tick;
            }
            return{
                pitch: el.pitch,
                startTick: realTick,
                duration: chord && chord.duration ? chord.duration.ticks : -1
            };
        }

        if (el.type === Element.CHORD && el.notes.length > 0){
            var seg = el.parent;
            return{
                pitch: el.notes[0].pitch,
                startTick: realTick,
                duration: el.duration ? el.duration.ticks : -1
            };
        }
        
        return null;
    }

    Timer {
        id: scoreTimer
        interval: 1000
        repeat: true
        running: false

        onTriggered: {
            if (!curScore || root.isRemoteUpdate) return;

            // Compare real score contents, not just the selected note.
            var currentSnapshot = root.takeScoreSnapshot();
            root.compareScoreSnapshots(root.lastScoreSnapshot, currentSnapshot);
            root.lastScoreSnapshot = currentSnapshot;

            // Retain the original note count change detection.
            var currentCount = root.countNotes();
            var notesArray = root.getSelectedNoteData();

            if (root.lastNoteCount === -1) {
                root.lastNoteCount = currentCount;
                return;
            }

            if (notesArray && notesArray.length > 0) root.lastSelectedNotes = notesArray;

            if (currentCount > root.lastNoteCount) {
                console.log("Notes added");

                if (root.nodeSocketID !== -1 && notesArray && notesArray.length > 0) {
                    api.websocket.send(
                        root.nodeSocketID,
                        JSON.stringify({
                            type: "ScoreOperation",
                            operation: "NoteCountChanged",
                            previousCount: root.lastNoteCount,
                            currentCount: currentCount,
                            notes: notesArray
                        })
                    );
                }
                root.lastNoteCount = currentCount;
                if (notesArray && notesArray.length > 0) {
                    root.lastPitch = notesArray[0].pitch;
                    root.lastTick = notesArray[0].startTick;
                }
            }
            else if (currentCount < root.lastNoteCount){
                console.log("Notes Deleted");
                if (root.nodeSocketID !== -1 && root.lastSelectedNotes && root.lastSelectedNotes.length > 0){
                    api.websocket.send(
                        root.nodeSocketID,
                        JSON.stringify({
                            type: "ScoreOperation",
                            operation: "NotesDeleted",
                            notes: root.lastSelectedNotes
                        })
                    );
                }
                root.lastNoteCount = currentCount;
            }
            else if (notesArray && notesArray.length > 0 && 
            (notesArray[0].pitch !== root.lastPitch || notesArray[0].startTick !== root.lastTick)){
                if (root.nodeSocketID !== -1){
                    api.websocket.send(
                        root.nodeSocketID,
                        JSON.stringify({
                            type: "ScoreOperation",
                            operation: "NoteSelectionChanged",
                            notes: notesArray
                        })
                    );
                }
                root.lastPitch = notesArray[0].pitch;
                root.lastTick = notesArray[0].startTick;
            }
        }
    }

    onRun: {
        console.log("Run " + root.title);

        // Open the native built in websocket and capture the dynamic socket ID (sid)
        api.websocket.open(8080, function(sid) {
            console.log("Connected to Node Backend. Socket ID: " + sid);
            
            root.nodeSocketID = sid;

            root.lastNoteCount = root.countNotes();
            root.lastScoreSnapshot = root.takeScoreSnapshot();
            scoreTimer.start();

            api.websocket.onMessage(root.nodeSocketID, root.onMessageFromServer);

            if (curScore) {
                var props = [];
                for (var prop in curScore) {
                    props.push(prop + ":" + typeof curScore[prop]);
                }
                var scoreTitle = curScore.scoreName ? curScore.scoreName : "Untitled";
                api.websocket.send(root.nodeSocketID, JSON.stringify({ 
                    type: "ChatMessage", 
                    message: "Score Loaded: " + scoreTitle + " with properties: " + props.length
                }));
            }
        });
    }
}