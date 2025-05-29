var Janus = null; // Will be set by janus.js
var janus = null;
var streaming = null;
var videoElement = null;
var currentStreamId = null;

function initDashboard() {
    videoElement = document.getElementById("droneVideo");
    if (!videoElement) {
        console.error("Video element not found");
        return;
    }

    Janus.init({
        debug: "info", // Set to "all" for verbose logging
        callback: function() {
            janus = new Janus({
                server: "ws://172.31.46.18:8188", // Update to your Janus WebSocket URL
                success: function() {
                    console.log("Janus connection established");
                    janus.attach({
                        plugin: "janus.plugin.streaming",
                        success: function(pluginHandle) {
                            streaming = pluginHandle;
                            console.log("Streaming plugin attached");
                            listStreams();
                        },
                        error: function(error) {
                            console.error("Error attaching plugin:", error);
                            alert("Failed to attach to Streaming plugin: " + error);
                        },
                        onmessage: function(msg, jsep) {
                            console.log("Message received:", msg);
                            if (msg.streaming === "list") {
                                updateStreamList(msg.list || []);
                            } else if (msg.streaming === "event" && msg.result && msg.result.status === "preparing") {
                                if (jsep) {
                                    streaming.createAnswer({
                                        jsep: jsep,
                                        media: { audio: false, video: true },
                                        success: function(jsep) {
                                            streaming.send({ message: { request: "start" }, jsep: jsep });
                                            console.log("WebRTC answer sent");
                                        },
                                        error: function(error) {
                                            console.error("WebRTC error:", error);
                                            alert("WebRTC error: " + error);
                                        }
                                    });
                                }
                            } else if (msg.streaming === "event" && msg.result && (msg.result.status === "recording_started" || msg.result.status === "recording_stopped")) {
                                console.log(`Recording ${msg.result.status} for mountpoint ${msg.result.id}`);
                                listStreams(); // Refresh list to update recording status
                            } else if (msg.error) {
                                console.error("Plugin error:", msg.error);
                                alert("Plugin error: " + msg.error);
                            }
                        },
                        onremotestream: function(stream) {
                            console.log("Received remote stream");
                            Janus.attachMediaStream(videoElement, stream);
                            videoElement.play().catch(function(e) {
                                console.error("Video playback error:", e);
                            });
                        },
                        oncleanup: function() {
                            console.log("WebRTC connection closed");
                            videoElement.srcObject = null;
                            currentStreamId = null;
                        }
                    });
                },
                error: function(error) {
                    console.error("Janus connection error:", error);
                    alert("Failed to connect to Janus: " + error);
                }
            });
        }
    });
}

function listStreams() {
    if (!streaming) {
        console.error("Plugin not attached");
        return;
    }
    streaming.send({
        message: { request: "listMessages" },
        success: function(result) {
            console.log("List response:", result);
        },
        error: function(error) {
            console.error("List request failed:", error);
            alert("Failed to list streams: " + error);
        }
    });
}

function updateStreamList(streams) {
    var streamList = document.getElementById("streamList");
    if (!streamList) {
        console.error("Stream list element not found");
        return;
    }
    streamList.innerHTML = "";
    if (streams.length === 0) {
        streamList.innerHTML = "<li>No streams available</li>";
        return;
    }
    streams.forEach(function(stream) {
        if (stream.type !== "rtp") return; // Only display RTP streams
        var li = document.createElement("li");
        var sourcePort = stream.source_port || "Unknown";
        var sourceIp = stream.source_ip || "Unknown";
        var description = stream.description || `Stream ${stream.id}`;
        li.innerHTML = `
            ID: ${stream.id}, 
            Description: ${description}, 
            Source: ${sourceIp}:${sourcePort}, 
            Recording: ${stream.is_recording ? "Yes" : "No"}
            <button onclick="watchStream(${stream.id})">Watch</button>
            <button onclick="toggleRecording(${stream.id}, '${stream.is_recording ? "stop" : "start"}')">
                ${stream.is_recording ? "Stop" : "Start"} Recording
            </button>
        `;
        streamList.appendChild(li);
    });
}

function watchStream(id) {
    if (currentStreamId === id) {
        console.log("Already watching stream", id);
        return;
    }
    if (currentStreamId !== null) {
        // Stop current stream
        streaming.send({ message: { request: "stop" } });
        videoElement.srcObject = null;
    }
    streaming.send({
        message: { request: "watch", id: id },
        success: function(result) {
            console.log("Watch response:", result);
            currentStreamId = id;
        },
        error: function(error) {
            console.error("Watch request failed:", error);
            alert("Failed to watch stream: " + error);
        }
    });
}

function toggleRecording(id, action) {
    streaming.send({
        message: { request: "recording", id: id, action: action },
        success: function(result) {
            console.log("Record response:", result);
            listStreams(); // Refresh list
        },
        error: function(error) {
            console.error("Record request failed:", error);
            alert("Failed to toggle recording: " + error);
        }
    });
}

// Initialize on page load
window.onload = function() {
    if (typeof Janus === "undefined") {
        console.error("janus.js not loaded");
        alert("janus.js is required but not loaded");
        return;
    }
    initDashboard();
};