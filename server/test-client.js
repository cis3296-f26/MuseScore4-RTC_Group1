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
      tick: 480,
      pitches: [72],
      duration: 480,
    },
  };

  ws.send(JSON.stringify(test_Payload));

  setTimeout(() => {
    console.log("Beginning delete test...");

    const del_Payload = {
      type: "ScoreOperation",
      operation: "ChordRemoved",
      previous: {
        track: 0,
        tick: 480,
        pitches: [72],
        duration: 480,
      },
      current: null,
    };

    ws.send(JSON.stringify(del_Payload));

    setTimeout(() => {
      ws.close();
    }, 3000);
  }, 1000);
});
