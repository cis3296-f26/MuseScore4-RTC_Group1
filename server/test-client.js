const WebSocket = require("ws");
const ws = new WebSocket("ws://localhost:8080");

ws.on('open', function open() {
    console.log("Connected to server. Begining test");

    const test_Payload = {
        type: "ScoreOperation",
        operation: "NoteCountChanged",
        previousCount: 0,
        currentCount: 1,
        note: {
            pitch: 60,
            startTick: 960,
            duration: 480
        }
    };

    ws.send(JSON.stringify(test_Payload));

    setTimeout(() => {
        ws.close()
    }, 1000);
});