const { WebSocketServer } = require("ws");
const { randomInt, randomUUID } = require("crypto");
const { initializeApp, cert } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const serviceAccount = require("./serviceAccountKey.json");

const app = initializeApp({
    credential: cert(serviceAccount),
});

const db = getFirestore(app); // Initialize Firestore database
const wss = new WebSocketServer({ port: 8080 }); //set port for server to listen on
console.log("WebSocket server running on port 8080");

const CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

function sendJSON(ws, message) {
    if (ws.readyState === 1) {
        ws.send(JSON.stringify(message));
    }
}

function hostIsOnline(code) {
    return [...wss.clients].some(
        (client) => client.sessionCode === code && client.isHost && client.readyState === 1,
    );
}

// HOST: Create a 4-character session in Firebase
async function hostSession(ws) {
    if (ws.sessionCode) {
        throw new Error("You are already in a session.");
    }

    for (let attempt = 0; attempt < 20; attempt++) {
        let code = "";

        for (let i = 0; i < 4; i++) {
            code += CHARS[randomInt(CHARS.length)];
        }

        const ref = db.collection("sessions").doc(code);

        try {
            await ref.create({
                hostId: ws.clientId,
                participants: [ws.clientId],
                status: "active",
                createdAt: FieldValue.serverTimestamp(),
                updatedAt: FieldValue.serverTimestamp(),
            });
        } catch (error) {
            // Firestore ALREADY_EXISTS: generate another code.
            if (error.code === 6 || error.code === "already-exists") {
                continue;
            }
            throw error;
        }

        if (ws.readyState !== 1) {
            await ref.update({
                status: "closed",
                participants: [],
                updatedAt: FieldValue.serverTimestamp(),
            });
            return;
        }

        ws.sessionCode = code;
        ws.isHost = true;

        sendJSON(ws, {
            type: "SessionCreated",
            sessionCode: code,
        });

        console.log("Session created:", code);
        return;
    }

    throw new Error("Could not generate a unique session code.");
}

// JOIN: Find the session in Firebase and add the user
async function joinSession(ws, rawCode) {
    if (ws.sessionCode) {
        throw new Error("You are already in a session.");
    }

    const code = typeof rawCode === "string" ? rawCode.trim().toUpperCase() : "";

    if (!/^[A-Z0-9]{4}$/.test(code)) {
        throw new Error("Enter a valid 4-character code.");
    }

    if (!hostIsOnline(code)) {
        throw new Error("Session not found or host is offline.");
    }

    const ref = db.collection("sessions").doc(code);

    await db.runTransaction(async (transaction) => {
        const doc = await transaction.get(ref);

        if (!doc.exists || doc.get("status") !== "active") {
            throw new Error("Session not found or closed.");
        }

        transaction.update(ref, {
            participants: FieldValue.arrayUnion(ws.clientId),
            updatedAt: FieldValue.serverTimestamp(),
        });
    });

    if (ws.readyState !== 1 || !hostIsOnline(code)) {
        await ref.update({
            participants: FieldValue.arrayRemove(ws.clientId),
            updatedAt: FieldValue.serverTimestamp(),
        });

        if (ws.readyState === 1) {
            throw new Error("Session host disconnected.");
        }
        return;
    }

    ws.sessionCode = code;
    ws.isHost = false;

    sendJSON(ws, {
        type: "SessionJoined",
        sessionCode: code,
    });

    for (const client of wss.clients) {
        if (client !== ws && client.sessionCode === code) {
            sendJSON(client, { type: "PeerJoined" });
        }
    }

    // Request host score for new client
    const host = [...wss.clients].find(client =>
        client.isHost && client.sessionCode === code && client.readyState === 1
    );
    if (host) {
        sendJSON(host, {
            type: "RequestScoreSnapshot",
            targetClientId: ws.clientId
        });
    }

    console.log("Client joined:", code);
}

// DISCONNECT: Update Firebase when someone leaves
async function leaveSession(ws) {
    const code = ws.sessionCode;
    if (!code) return;

    ws.sessionCode = null;
    const ref = db.collection("sessions").doc(code);

    if (ws.isHost) {
        // Close the room for everybody.
        for (const client of wss.clients) {
            if (client.sessionCode === code) {
                client.sessionCode = null;
                client.isHost = false;
                sendJSON(client, { type: "SessionClosed" });
            }
        }

        await ref.update({
            status: "closed",
            participants: [],
            updatedAt: FieldValue.serverTimestamp(),
        });
    } else {
        // Remove only the departing participant.
        await ref.update({
            participants: FieldValue.arrayRemove(ws.clientId),
            updatedAt: FieldValue.serverTimestamp(),
        });

        for (const client of wss.clients) {
            if (client.sessionCode === code) {
                sendJSON(client, { type: "PeerLeft" });
            }
        }
    }
}

wss.on("connection", async function connection(ws) {
    // Handle new client connection
    ws.clientId = randomUUID();
    ws.sessionCode = null;
    ws.isHost = false;
    ws.sessionRequestPending = false;

    ws.on("close", () => {
        leaveSession(ws).catch((error) => {
            console.error("Session cleanup failed:", error);
        });
    });
    ws.on("error", console.error);

    ws.on("message", async function message(data) {
        //handle incoming messages from clients
        try {
            const parsedData = JSON.parse(data.toString()); //parse incoming data as JSON
            parsedData.timeStamp = new Date().toISOString(); //add timestamp to parsed data
            const textData = JSON.stringify(parsedData); //convert parsed data back to string for broadcasting
            if (
                (parsedData.type === "ScoreOperation" ||
                    parsedData.type === "ChatMessage" ||
                    parsedData.type === "CursorPosition") &&
                !ws.sessionCode
            ) {
                sendJSON(ws, {
                    type: "Error",
                    message: "You must host or join a session first.",
                });
                return;
            }
            switch (
            parsedData.type //handle different message types
            ) {
                case "HostSession":
                case "JoinSession":
                    if (ws.sessionRequestPending) {
                        sendJSON(ws, {
                            type: "Error",
                            message: "Session request already in progress.",
                        });
                        break;
                    }

                    ws.sessionRequestPending = true;

                    try {
                        if (parsedData.type === "HostSession") {
                            await hostSession(ws);
                        } else {
                            await joinSession(ws, parsedData.sessionCode);
                        }
                    } finally {
                        ws.sessionRequestPending = false;
                    }
                    break;
                case "ScoreSnapshot": {
                    // Verify sender is host
                    if (!ws.isHost || !ws.sessionCode) {
                        sendJSON(ws, { type: "Error", message: "Only the session host can send score snapshots." });
                        break;
                    }
                    if (typeof parsedData.targetClientId !== "string" ||
                        !parsedData.snapshot || typeof parsedData.snapshot !== "object" ||
                        Array.isArray(parsedData.snapshot) ||
                        !Number.isInteger(parsedData.staffCount) || parsedData.staffCount < 1) {
                        sendJSON(ws, { type: "Error", message: "Invalid score snapshot." });
                        break;
                    }
                    const joiner = [...wss.clients].find(client =>
                        client.clientId === parsedData.targetClientId &&
                        client !== ws && client.sessionCode === ws.sessionCode &&
                        client.readyState === 1
                    );
                    if (!joiner) {
                        sendJSON(ws, { type: "Error", message: "Joining client is no longer in the session." });
                        break;
                    }
                    sendJSON(joiner, {
                        type: "ScoreSnapshot",
                        snapshot: parsedData.snapshot,
                        staffCount: parsedData.staffCount,
                        scoreSettings: parsedData.scoreSettings
                    });
                    console.log("Host score snapshot forwarded to joining client in session:", ws.sessionCode);
                    break;
                }
                case "ScoreOperation": // score operation handler
                    console.log("score operation received:", parsedData);
                    wss.clients.forEach(function each(client) {
                        //go through each connected client
                        if (
                            client !== ws &&
                            client.readyState === 1 &&
                            ws.sessionCode &&
                            client.sessionCode === ws.sessionCode
                        ) {
                            //if not this client and client is ready to receive
                            client.send(textData); //transmit the data
                        }
                    });
                    break; //stop loop when done with score op
                case "CursorPosition":
                    console.log("Cursor position received:", parsedData);
                    if (
                        parsedData.position !== null &&
                        (typeof parsedData.position !== "object" ||
                            !Number.isInteger(parsedData.position.tick) ||
                            !Number.isInteger(parsedData.position.staff) ||
                            parsedData.position.tick < 0 ||
                            parsedData.position.staff < 0)
                    ) {
                        sendJSON(ws, { type: "Error", message: "Invalid cursor position." });
                        break;
                    }
                    parsedData.clientId = ws.clientId;
                    parsedData.sessionCode = ws.sessionCode;
                    wss.clients.forEach(function each(client) {
                        if (client !== ws && client.readyState === 1 && client.sessionCode === ws.sessionCode) {
                            sendJSON(client, parsedData);
                        }
                    });
                    break;
                case "ChatMessage": //chat message handler
                    console.log("chat message received:", parsedData);
                    wss.clients.forEach(function each(client) {
                        //go through each connected client
                        if (
                            client !== ws &&
                            client.readyState === 1 &&
                            ws.sessionCode &&
                            client.sessionCode === ws.sessionCode
                        ) {
                            //if not this client and client is ready to receive
                            client.send(textData);
                        }
                    });
                    break; //stop loop when done
                default:
                    console.log("Unknown message type received:", parsedData.type);
                    ws.send(JSON.stringify({ type: "Error", message: "Unknown message type" })); //if wrong data received
            }
        } catch (error) {
            console.error("Message processing error:", error);

            sendJSON(ws, {
                type: "Error",
                message: error.message || "Request failed.",
            });
        }
    });
    ws.send(
        JSON.stringify({
            type: "Connected",
            message: "Successfully connected to MuseScore RTC server",
            timeStamp: new Date().toISOString(),
        }),
    ); //message sent to client(s) to confirm connection

    try {
        const docRef = await db.collection("server_status").add({
            //notift users when new client joins
            event: "New Client Connected",
            timestamp: FieldValue.serverTimestamp(), //log the time when the new client connected in the db
        });

        console.log("Firestore test successfully written with ID:", docRef.id); //output successful firestore write id
    } catch (error) {
        console.error("Error occurred while writing to Firestore:", error.message);
    }
});



