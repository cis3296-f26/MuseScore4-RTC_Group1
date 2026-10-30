# Test 

## Paste below from /server
node server.js

## Open /server in a new terminal and paste below

```
node -e '
const ws = new WebSocket("ws://localhost:8080");

ws.onopen = () => {
    console.log("Client connected!");
};

ws.onmessage = (event) => {
    console.log("Server response:", event.data);
    ws.close();
};

ws.onerror = console.error;
'
```

## Example output
WebSocket server running on port 8080
Firestore test successfully written with ID: UUID