# MuseScore 4 RTC Protocol

## Status

This document describes the current WebSocket protocol implemented by the
MuseScore 4 RTC server. The server currently relays score operations and chat
messages to all other connected clients.

## Transport

- Protocol: WebSocket
- Default endpoint: `ws://localhost:8080`
- Encoding: UTF-8 JSON text messages

## Message Format

Every client message must be a JSON object with a `type` field. The server
currently recognizes these message types:

| Type | Sender | Purpose |:

| `ScoreOperation` | Client | Relays a change to the musical score |
| `ChatMessage` | Client | Relays a chat message |

The recommended message structure is:

```json
{
	"type": "ScoreOperation",
	"version": 1,
	"sessionID": "session-123",
	"senderID": "user-456",
	"messageID": "message-789",
	"timeStamp": "2026-11-03T12:00:00Z",
	"payload": {}
}
```

The server currently uses only `type`. The other fields are passed through to
other clients but are not validated or interpreted by the server.

### Common fields

| Field | Type | Required by current server | Description |

| `type` | string | Yes | Message type |
| `version` | number | No | Version of the message format |
| `sessionID` | string | No | Collaboration session identifier |
| `senderID` | string | No | Identifier of the sending user |
| `messageID` | string | No | Unique identifier for this message |
| `timeStamp` | string | No | Recommended ISO 8601 timestamp |
| `payload` | object | No | Type-specific data |

## Server Messages

### Connected

The server sends this message immediately after a client connects.

```json
{
	"type": "Connected",
	"message": "Successfully connected to MuseScore RTC server"
}
```

### Relayed messages

For `ScoreOperation` and `ChatMessage`, the server forwards the original JSON
message unchanged to every other connected client. The sender does not receive
its own message back.

## Client Messages

### ScoreOperation

Use this message to send a score edit to other clients.

```json
{
	"type": "ScoreOperation",
	"sessionID": "session-123",
	"senderID": "user-456",
	"messageID": "operation-001",
	"timeStamp": "2026-11-03T12:00:00Z",
	"payload": {
		"operation": "replace-with-score-operation-data"
	}
}
```

The exact contents of `payload` are not currently defined or validated by the
server. The client implementation must define how score operations are
represented and applied.

### ChatMessage

Use this message to send chat content to other clients.

```json
{
	"type": "ChatMessage",
	"sessionID": "session-123",
	"senderID": "user-456",
	"messageID": "chat-001",
	"timeStamp": "2026-11-03T12:01:00Z",
	"payload": {
		"text": "Hello from the score session"
	}
}
```

The server does not currently validate the chat payload.

## Errors

### Invalid JSON

If the client sends text that is not valid JSON, the server responds only to
that client:

```json
{
	"type": "error",
	"error": "Invalid JSON format"
}
```

### Unknown message type

If the JSON is valid but `type` is not recognized, the server responds only to
that client:

```json
{
	"type": "error",
	"error": "Unknown message type"
}
```

## Connection Behavior

1. The client opens a WebSocket connection to the server.
2. The server sends a `Connected` message.
3. The client sends `ScoreOperation` or `ChatMessage` messages.
4. The server relays recognized messages to all other connected clients.
5. The client may close the connection at any time.

The current server has no explicit join, leave, room, presence, or reconnect
messages. All connected clients receive relayed messages, regardless of
`sessionID`.

## Current Limitations and Future Work

- Validate `version`, `sessionID`, `senderID`, `messageID`, and `payload`.
- Broadcast messages only to clients in the same session.
- Define the score operation format and conflict-resolution strategy.
- Add authentication and authorization.
- Add explicit disconnect and reconnection behavior.
- Use a structured error code, such as `INVALID_MESSAGE`, instead of only an
	error string.

## Testing Requirements

The server should be tested for:

- Sending the initial `Connected` message.
- Relaying `ScoreOperation` to other clients.
- Relaying `ChatMessage` to other clients.
- Not echoing a message to its sender.
- Rejecting invalid JSON.
- Rejecting unknown message types.
- Handling a client disconnecting without crashing the server.
