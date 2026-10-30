# Test 

## Paste below from /server
node server.js

## Open /server in a new terminal and paste below

```
node -e '
const ws = new WebSocket("ws://localhost:8080");

ws.onopen = () => {
    console.log("Connected!");
};

ws.onmessage = (event) => {
    console.log("Received:", event.data);
    ws.close();
};

ws.onerror = console.error;
'
```

## Example output
WebSocket server running on port 8080
Firestore test successfully written with ID: wB1iXsossPfw2nGtw6g