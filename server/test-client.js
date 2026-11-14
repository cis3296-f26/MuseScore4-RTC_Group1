const WebSocket = require("ws");
const ws = new WebSocket("ws://localhost:8080");

ws.on("open", function open() {
  console.log("Connected to server. Begining test");

  const test_Payload = {
    type: "ScoreOperation",
    operation: "ChordAdded",
    previous: null,
    current: {
      track: 0,
      tick: 960,
      pitches: [72],
      duration: 480,
    },
  };

  ws.send(JSON.stringify(test_Payload));

  setTimeout(() => {
    ws.close();
  }, 1000);
});
