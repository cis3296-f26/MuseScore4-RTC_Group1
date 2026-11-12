const { WebSocketServer } = require("ws");
const { initializeApp, cert } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const serviceAccount = require("./serviceAccountKey.json");

const app = initializeApp({
    credential: cert(serviceAccount)
});

const db = getFirestore(app); // Initialize Firestore database
const wss = new WebSocketServer({ port: 8080 }); //set port for server to listen on
console.log("WebSocket server running on port 8080");

wss.on("connection", async function connection(ws) { // Handle new client connection
    ws.on("error", console.error);

    ws.on("message", async function message(data) { //handle incoming messages from clients
        try {
            const parsedData = JSON.parse(data.toString()); //parse incoming data as JSON
            parsedData.timeStamp = new Date().toISOString(); //add timestamp to parsed data
            const textData = JSON.stringify(parsedData); //convert parsed data back to string for broadcasting

            switch (parsedData.type) { //handle different message types
                case "ScoreOperation": // score operation handled
                    console.log("score operation received:", parsedData);
                    wss.clients.forEach(function each(client) { //go through each connected client
                        if (client !== ws && client.readyState === 1) { //if not this client and client is ready to receive
                            client.send(textData); //transmit the data
                        }
                    });
                    break; 
                case "ChatMessage": 
                    console.log("chat message received:", parsedData);
                    wss.clients.forEach(function each(client) {
                        if (client !== ws && client.readyState === 1) {
                            client.send(textData);
                        }
                    });
                    break;
                default:
                    console.log("Unknown message type received:", parsedData.type);
                    ws.send(JSON.stringify({ type: "error", error: "Unknown message type" }));
            }
        } catch (error) {
            console.error("Error occurred while parsing JSON:", error.message);
            ws.send(JSON.stringify({ type: "error", error: "Invalid JSON format" }));
        }
    });

    ws.send(JSON.stringify({
        type: "Connected",
        message: "Successfully connected to MuseScore RTC server",
        timeStamp: new Date().toISOString()
    }));

    try {
        const docRef = await db.collection("server_status").add({
            event: "New Client Connected",
            timestamp: FieldValue.serverTimestamp()
        });

        console.log("Firestore test successfully written with ID:", docRef.id);
    } catch (error) {
        console.error("Error occurred while writing to Firestore:", error.message);
    }
});