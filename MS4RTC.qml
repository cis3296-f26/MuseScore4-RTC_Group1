import MuseScore 3.0
import QtQuick 2.0
import QtWebSockets 1.0
import FileIO 3.0

MuseScore {
	title: "MuseScore 4 Real-Time Collab"
	description: "This plugin allows for collaboration in MuseScore 4.";
	requiresScore: true;
	version: "4.0";
	menuPath: "Plugins.Notes.RTC";

	FileIO {
			id: outfile
            source: tempPath() + "/MuseScoreScript.log"
            onError: console.log(msg)
    }  

    onRun:{
        var cursor = curScore.startCmd()
        var rc = outfile.write("Hello World!\n");
            if (rc){ 
                  console.log("Log file has been  written to "+ outfile.source);
            } else {
                  console.log("Something went wrong. File cannot be written");
            }
        quit();
    } 

}
