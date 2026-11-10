# MuseScore 4 Real-Time Collaboration

**Team:** Fahad, David, Jed, Bennett, Michael

## Prerequisites

* **Node.js** installed on your machine.
* A valid `serviceAccountKey.json` file (Firebase credentials).

## Server Setup

1. Open a terminal in the project directory and navigate to the server folder:

   ```bash
   cd server
   ```

2. Install the required dependencies:

   ```bash
   npm install
   ```

3. **Crucial:** Ensure the `serviceAccountKey.json` file is placed directly inside the `server` folder.
4. Start the WebSocket server:

   ```bash
   node server.js
   ```

   *You should see the message: `WebSocket server running on port 8080`*

## Testing the Server (Command Line)

To verify the server works without MuseScore, open a **second** terminal window and run:

```bash
npx wscat -c ws://localhost:8080
```

*(If it asks you to install wscat, type `y` for yes).*

Once connected, paste the following JSON string and press Enter to send a test message:

```json
{"type":"ChatMessage","message":"hi"}
```

## Testing with MuseScore 4

1. Copy the plugin's `.qml` file into your local MuseScore plugins directory:
   * **Windows:** `C:\Users\<YourUsername>\Documents\MuseScore4\Plugins`
   * **Mac:** `~/Documents/MuseScore4/Plugins`
2. With the Node server still running, open a score in MuseScore 4.
3. Click the plugin from the **Plugins** dropdown menu in the top left.
4. Check your Node server terminal. If the test was successful, you should instantly see: `message: 'Hello from MuseScore 4 Plugin!'` along with the score properties.
