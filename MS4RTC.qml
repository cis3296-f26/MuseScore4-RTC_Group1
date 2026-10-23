import MuseScore 4.0
import QtQuick 2.0
import QtWebsockets

MuseScore {
	description: "This plugin allows for collaboration in MuseScore 4.";
	requiresScore: true;
	version: "4";
	menuPath: "Plugins.Notes.RTC";


	onRun: {
		console.log("Hello world!");
	}
}