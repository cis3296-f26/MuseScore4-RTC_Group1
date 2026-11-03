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
        console.log("Received message from server: " + msg);
    }

    FileIO {
        id: outfile
        source: tempPath() + "/MuseScoreScript.log"
        onError: console.log(msg)
    }  

    onRun: {
        console.log("Run " + root.title);

        // Open the native built-in websocket and capture the dynamic socket ID (sid)
        api.websocket.open(8080, function(sid) {
            console.log("Connected to Node Backend. Socket ID: " + sid);
            
            root.nodeSocketID = sid;

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