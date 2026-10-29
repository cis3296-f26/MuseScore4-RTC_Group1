import {WebSocketServer} from "ws";

const wss = new WebSocketServer({ port: 8080 });

wss.on("connection", function connection(ws) {
    ws.on("error", console.error);

    ws.on("message", function message(data) {
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
                case "Chat Message":
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
            console.log("received type:",parsedData.type);
        } catch (error) {
            console.error("Error occurred while parsing JSON:", error.message);
            ws.send(JSON.stringify({type: "error", error: "Invalid JSON format"}));
        }
    });

    ws.send("something");
});