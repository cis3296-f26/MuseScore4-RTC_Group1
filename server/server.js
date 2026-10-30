const { WebSocketServer } = require("ws");
const { initializeApp, cert} = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const serviceAccount = require("./serviceAccountKey.json");

const app = initializeApp({
    credential: cert(serviceAccount)
});

const db = getFirestore(app);
const wss = new WebSocketServer({ port: 8080 });
console.log("WebSocket server running on port 8080");

wss.on("connection", async function connection(ws) {
    ws.on("error", console.error);

    try{
        const docRef = await db.collection("server_status").add({
            event: "New Client Connected",
            timestamp: FieldValue.serverTimestamp()
        });
        console.log("Firestore test successfully written with ID: ", docRef.id);
    } catch (error) {
        console.error("Error occurred while writing to Firestore:", error.message);
    }

    ws.on("message", async function message(data) {
        try {
            const textData = data.toString();
            const parsedData = JSON.parse(textData);

            switch (parsedData.type) {
                case "ScoreOperation":
                    console.log("score operation received:", parsedData);
                    wss.clients.forEach(function each(client) {
                        if (client !== ws && client.readyState === 1) {
                            client.send(textData);
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
                    ws.send(JSON.stringify({type: "error", error: "Unknown message type"}));
            }
        } catch (error) {
            console.error("Error occurred while parsing JSON:", error.message);
            ws.send(JSON.stringify({type: "error", error: "Invalid JSON format"}));
        }
    });

    ws.send("something");
});