const WebSocket = require("ws");

const sessionCode = process.argv[2];
if (!sessionCode) {
  console.error("Usage: node test-client.js <ROOM-CODE>");
  process.exit(1);
}
const ws = new WebSocket("ws://localhost:8080");

ws.on("open", () => {
  console.log(`Connected. Joining session ${sessionCode.toUpperCase()}...`);
  ws.send(JSON.stringify({ type: "JoinSession", sessionCode: sessionCode.toUpperCase() }));
});

ws.on("message,", (data) => {
  const msg = JSON.parse(data.toString());

  if (msg.type === "Error") {
  }
});

/*
ws.on("open", function open() {
  console.log("Connected to server. \nBegining Addition Test...");


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
    console.log("Beginning change test...");

    const cha_Payload = {
      type: "ScoreOperation",
      operation: "PitchChanged",
      previous: {
        track: 0,
        tick: 480,
        pitches: [72],
        duration: 480,
      },
      current: {
        track: 0,
        tick: 480,
        pitches: [74],
        duration: 480,
      },
    };

    ws.send(JSON.stringify(cha_Payload));

    setTimeout(() => {
      console.log("Beginning Duration Test...");

      const dur_payload = {
        type: "ScoreOperation",
        operation: "DurationChanged",
        previous: {
          track: 0,
          tick: 480,
          pitches: [74],
          duration: 480,
        },
        current: {
          track: 0,
          tick: 480,
          pitches: [74],
          duration: 960,
        },
      };
      ws.send(JSON.stringify(dur_payload));

      setTimeout(() => {
        console.log("Beggining Deletion Test...");

        const del_payload = {
          type: "ScoreOperation",
          operation: "ChordRemoved",
          previous: {
            track: 0,
            tick: 480,
            pitches: [74],
            duration: 960,
          },
          current: null,
        };
        ws.send(JSON.stringify(del_payload));

        setTimeout(() => {
          console.log("Testing Complete");
          ws.close();
        }, 1000);
      }, 1000);
    }, 1000);
  }, 3000);
}); */
