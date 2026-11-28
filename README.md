# MuseScore 4 Real-Time Collaboration

**Team:** Fahad, David, Jed, Bennett, Michael

## Prerequisites

- **Node.js** installed on your machine.
- A valid `serviceAccountKey.json` file (Firebase credentials).

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

   _You should see the message: `WebSocket server running on port 8080`_

## Installing Plugin

1. Take the file labled `MS4RTC.qml` and place it in the MuseScore plugins folder

   _To find it, open MuseScore, click **Edit → Preferences → Folders**, and check or change the **Plugins** path._

2. Open MuseScore,**Plugins → Plugin Manager**, and enable **MuseScore 4 Real-Time Collab**.
3. Open a score, and click the plugin from the **Plugins** dropdown in the top left
4. A new window will open, Click **Host** to host a session or enter a room code and click **Join** to join a session

   _If hosting, the room code will appear in the bottom left_

## Running the Plugin Test (Command Line)

1. Before testing, make sure the server is running and a room is actively being hosted
2. Open a **second** terminal, navigate to the `server` folder, and run:

   ```bash
   node test-client.js <ROOM-CODE>
   ```

_You should see messages in the terminal confirming connection and then running tests_
