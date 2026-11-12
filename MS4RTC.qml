import MuseScore 3.0
import QtQuick 2.0
import FileIO 3.0

MuseScore {
    title: "MuseScore 4 Real-Time Collab"
    description: "This plugin allows for collaboration in MuseScore 4."
    requiresScore: true
    version: "4.0"
    menuPath: "Plugins.Notes.RTC"
    property int nodeSocketID: -1
    property int lastNoteCount: -1
    property int lastTick: -1
    property int lastPitch: -1
    property bool isRemoteUpdate: false
    id: root

    function onMessageFromServer(msg) {
        var parsedMsg = JSON.parse(msg);
        if(parsedMsg.type === "ScoreOperation"){
            if (parsedMsg.operation === "NoteSelectionChanged"){
                return; // Prevent local cursor from snapping to the note when a remote user selects it
            }

            if (parsedMsg.operation === "NoteCountChanged" && parsedMsg.note){
                isRemoteUpdate = true;

                var noteData = parsedMsg.note;
                var cursor = curScore.newCursor();

                cursor.track = 0;

                curScore.startCmd();

                cursor.rewindToTick(noteData.startTick);

                if (noteData.duration > 0){
                    cursor.setDuration(noteData.duration, 1920);
                }else{
                    cursor.setDuration(1,4);
                }

                cursor.addNote(noteData.pitch);

                curScore.endCmd();

                root.lastNoteCount = root.countNotes();
                root.lastPitch = noteData.pitch;
                root.lastTick = noteData.startTick;

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

            var currentCount = root.countNotes();
            var noteData = root.getSelectedNoteData();

            if (root.lastNoteCount === -1) {
                root.lastNoteCount = currentCount;
                return;
            }

            if (currentCount !== root.lastNoteCount) {
                console.log("Score changed!");

                if (root.nodeSocketID !== -1) {
                    api.websocket.send(
                        root.nodeSocketID,
                        JSON.stringify({
                            type: "ScoreOperation",
                            operation: "NoteCountChanged",
                            previousCount: root.lastNoteCount,
                            currentCount: currentCount,
                            note: noteData 
                        })
                    );
                }
                root.lastNoteCount = currentCount;
                if (noteData) {
                    root.lastPitch = noteData.pitch;
                    root.lastTick = noteData.startTick;
                }
            }

            else if (noteData && (noteData.pitch !== root.lastPitch || noteData.startTick !== root.lastTick)){
                if (root.nodeSocketID !== -1){
                    api.websocket.send(
                        root.nodeSocketID,
                        JSON.stringify({
                            type: "ScoreOperation",
                            operation: "NoteSelectionChanged",
                            note: noteData
                        })
                    );
                }
                root.lastPitch = noteData.pitch;
                root.lastTick = noteData.startTick;
            }
        }
    }



    onRun: {
        console.log("Run " + root.title);

        // Open the native built-in websocket and capture the dynamic socket ID (sid)
        api.websocket.open(8080, function(sid) {
            console.log("Connected to Node Backend. Socket ID: " + sid);
            
            root.nodeSocketID = sid;

            root.lastNoteCount = root.countNotes();
            scoreTimer.start();

            api.websocket.onMessage(root.nodeSocketID, root.onMessageFromServer);

            var handshakePayload = JSON.stringify({ 
                type: "ChatMessage", 
                message: "Hello from MuseScore 4 Plugin!" 
            });
            api.websocket.send(root.nodeSocketID, handshakePayload);

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