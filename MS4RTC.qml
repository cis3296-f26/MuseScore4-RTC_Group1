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
    id: root

    function onMessageFromServer(msg) {
        var parsedMsg = JSON.parse(msg);
        outfile.write("Server Update: " + parsedMsg.type + " - " + parsedMsg.message + "\n");
    }

    FileIO {
        id: outfile
        source: tempPath() + "/MuseScoreScript.log"
        onError: console.log(msg)
    }  


    
    property int lastNoteCount: -1

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

    Timer {
        id: scoreTimer
        interval: 1000
        repeat: true
        running: false

        onTriggered: {
            if (!curScore) return;

            var currentCount = root.countNotes();

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
                            currentCount: currentCount
                        })
                    );
                }

                root.lastNoteCount = currentCount;
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