import QtQuick 2.15
import QtQuick.Layouts 1.3
import QtQuick.Controls 2.15
import org.kde.plasma.core 3.0
import org.kde.plasma.components 3.0

/*
  Htop-like Plasma 6 widget - Main_merged.qml
  - Merges CPU/memory, process list, sorting, filtering, kill buttons
  - Adds per-process disk I/O rates (read/write) and system network I/O
  - Modular and configurable via root properties (colors, refreshInterval, visibleColumns)

  Notes:
  - Per-process network I/O is not practical from /proc alone; this widget reports
    system-wide network speeds and per-process disk I/O rates (from /proc/<pid>/io).
  - Reading many /proc/*/io entries can be somewhat expensive on systems with many processes.
  - Killing processes requires appropriate permissions (you cannot kill root-owned processes without privilege).
*/

Item {
    id: root
    width: 980
    height: 620

    /********* Customization / configuration (changeable) *********/
    property int refreshIntervalMs: 2000
    property color primaryColor: "#00C853"         // main accent (bars, highlights)
    property color accentColor: "#FFC107"          // secondary accent
    property color backgroundColor: "transparent"
    property color rowAltColor: "#1a1a1a"
    property int fontSize: 12

    // Which columns to show by default
    property var visibleColumns: ({ pid: true, user: true, cpu: true, mem: true, cmd: true, ioReadRate: true, ioWriteRate: true })

    // Filtering & sorting
    property string filterText: ""
    property string sortColumn: "cpu"   // default sort
    property bool sortAsc: false

    /********* Runtime state *********/
    property var processes: []            // array of process objects
    property var _prevIo: ({})            // map pid -> {read, write}
    property var cpuUsages: []
    property int memUsedPercent: 0
    property string networkIface: ""
    property real netDownloadSpeed: 0
    property real netUploadSpeed: 0
    property var _prevCpuStats: []

    /********* Helpers *********/
    function bytesToHuman(b) {
        if (b === undefined || b === null) return "-"
        var n = Math.abs(b)
        if (n < 1024) return b + " B/s"
        if (n < 1024*1024) return (b/1024).toFixed(1) + " KB/s"
        if (n < 1024*1024*1024) return (b/(1024*1024)).toFixed(1) + " MB/s"
        return (b/(1024*1024*1024)).toFixed(2) + " GB/s"
    }

    function numOrZero(v) { var n = parseFloat(v); return isNaN(n) ? 0 : n }

    function toggleSort(col) {
        if (sortColumn === col) sortAsc = !sortAsc
        else { sortColumn = col; sortAsc = false }
    }

    function toggleColumn(col) {
        visibleColumns[col] = !visibleColumns[col]
    }

    /********* Periodic updates *********/
    Timer {
        id: mainTimer
        interval: root.refreshIntervalMs
        running: true
        repeat: true
        onTriggered: root.updateAll()
    }

    Component.onCompleted: {
        // detect a first non-loopback interface
        detectIface.query = "bash -c 'ls /sys/class/net | grep -v lo | head -n1'"
        detectIface.refresh()
        // initial update
        root.updateAll()
    }

    /********* DataSources (runcmd engine) *********/
    PlasmaCore.DataSource { id: detectIface; engine: "runcmd";
        onNewData: {
            var s = newData.trim()
            root.networkIface = s.length ? s : "eth0"
        }
    }

    // Combined ps + per-process io query (single shell command)
    PlasmaCore.DataSource {
        id: psIoQuery
        engine: "runcmd"
        onNewData: {
            var text = newData.trim()
            if (!text) { processes = []; return }
            var lines = text.split(/\n/)
            var arr = []
            var intervalSec = Math.max(0.001, root.refreshIntervalMs/1000.0)
            for (var i=0;i<lines.length;i++){
                var cols = lines[i].split("|")
                if (cols.length < 7) continue
                var pid = cols[0]
                var user = cols[1]
                var cpu = numOrZero(cols[2])
                var mem = numOrZero(cols[3])
                var cmd = cols[4]
                var ioRead = parseFloat(cols[5]) || 0
                var ioWrite = parseFloat(cols[6]) || 0

                // compute rates using previous snapshot
                var prev = root._prevIo[pid]
                var readRate = 0
                var writeRate = 0
                if (prev) {
                    readRate = (ioRead - prev.read) / intervalSec
                    writeRate = (ioWrite - prev.write) / intervalSec
                    if (readRate < 0) readRate = 0
                    if (writeRate < 0) writeRate = 0
                }

                // update prev map
                root._prevIo[pid] = { read: ioRead, write: ioWrite }

                arr.push({ pid: pid, user: user, cpu: cpu, mem: mem, cmd: cmd, ioRead: ioRead, ioWrite: ioWrite, ioReadRate: readRate, ioWriteRate: writeRate })
            }
            processes = arr
        }
    }

    PlasmaCore.DataSource {
        id: systemQuery
        engine: "runcmd"
        onNewData: {
            var lines = newData.split(/\n/)
            var newCpu = []
            var memTotal = 0
            var memAvailable = 0

            function parseCpuLine(line, prev) {
                var parts = line.trim().split(/\s+/)
                var user = parseInt(parts[1]) || 0
                var nice = parseInt(parts[2]) || 0
                var system = parseInt(parts[3]) || 0
                var idle = parseInt(parts[4]) || 0
                var iowait = parseInt(parts[5]) || 0
                var irq = parseInt(parts[6]) || 0
                var softirq = parseInt(parts[7]) || 0
                var steal = parseInt(parts[8]) || 0
                var total = user + nice + system + idle + iowait + irq + softirq + steal
                var active = total - idle - iowait
                if (!prev) return { active: active, total: total, usage: 0 }
                var deltaTotal = total - prev.total
                var deltaActive = active - prev.active
                var usage = 0
                if (deltaTotal > 0) usage = (deltaActive / deltaTotal) * 100
                if (usage < 0 || usage > 100) usage = 0
                return { active: active, total: total, usage: usage }
            }

            for (var i=0;i<lines.length;i++){
                var l = lines[i]
                if (!l) continue
                if (l.indexOf("cpu") === 0) {
                    var m = l.match(/^cpu(\d*)/)
                    var idx = (m && m[1].length) ? parseInt(m[1]) : 0
                    var stat = parseCpuLine(l, root._prevCpuStats[idx])
                    newCpu.push(stat)
                } else if (l.indexOf("MemTotal:") === 0) {
                    memTotal = parseInt(l.split(/\s+/)[1]) || 0
                } else if (l.indexOf("MemAvailable:") === 0) {
                    memAvailable = parseInt(l.split(/\s+/)[1]) || 0
                }
            }
            root._prevCpuStats = newCpu
            var usages = []
            for (var j=1;j<newCpu.length;j++) usages.push(Math.round(newCpu[j].usage))
            cpuUsages = usages
            if (memTotal && memAvailable) memUsedPercent = Math.round(((memTotal - memAvailable) / memTotal) * 100)
        }
    }

    PlasmaCore.DataSource {
        id: netQuery
        engine: "runcmd"
        property real prevRx: 0
        property real prevTx: 0
        onNewData: {
            var lines = newData.trim().split(/\s+/)
            if (lines.length < 2) return
            var rx = parseFloat(lines[0]) || 0
            var tx = parseFloat(lines[1]) || 0
            var intervalSec = Math.max(0.001, root.refreshIntervalMs/1000.0)
            if (netQuery.prevRx > 0) {
                root.netDownloadSpeed = (rx - netQuery.prevRx) / intervalSec
                root.netUploadSpeed = (tx - netQuery.prevTx) / intervalSec
            }
            netQuery.prevRx = rx
            netQuery.prevTx = tx
        }
    }

    PlasmaCore.DataSource { id: killQuery; engine: "runcmd" }

    /********* Update orchestration *********/
    function updateAll() {
        // processes + per-process io
        psIoQuery.query = 'bash -c "ps -eo pid,user,%cpu,%mem,comm --no-headers | while read -r pid user cpu mem cmd; do cmd=\"${cmd//|/_}\"; r=$(awk \"/read_bytes/ {print $2}\" /proc/$pid/io 2>/dev/null || echo 0); w=$(awk \"/write_bytes/ {print $2}\" /proc/$pid/io 2>/dev/null || echo 0); printf \"%s|%s|%s|%s|%s|%s|%s\\n\" \"$pid\" \"$user\" \"$cpu\" \"$mem\" \"$cmd\" \"$r\" \"$w\"; done"'
        psIoQuery.refresh()

        // cpu/mem
        systemQuery.query = "bash -c 'cat /proc/stat /proc/meminfo | head -n 40'"
        systemQuery.refresh()

        // network (system)
        var iface = networkIface.length ? networkIface : 'eth0'
        netQuery.query = 'bash -c "cat /sys/class/net/' + iface + '/statistics/rx_bytes /sys/class/net/' + iface + '/statistics/tx_bytes"'
        netQuery.refresh()
    }

    function killProcess(pid, force) {
        var sig = force ? '-9' : '-15'
        killQuery.query = "bash -c 'kill " + sig + " " + pid + "'"
        killQuery.refresh()
        // refresh after a short delay
        Qt.callLater(function(){ updateAll() })
    }

    function filteredAndSortedProcesses() {
        var arr = processes.slice()
        var f = filterText.trim().toLowerCase()
        if (f.length) {
            arr = arr.filter(function(p){
                return (p.cmd && p.cmd.toLowerCase().indexOf(f) !== -1) || (p.user && p.user.toLowerCase().indexOf(f) !== -1) || (p.pid && String(p.pid).indexOf(f) !== -1)
            })
        }
        arr.sort(function(a,b){
            var va = a[sortColumn]
            var vb = b[sortColumn]
            // handle absent columns gracefully
            if (va === undefined) va = ''
            if (vb === undefined) vb = ''
            // numeric sort for known numeric columns
            var numericCols = { pid:1, cpu:1, mem:1, ioRead:1, ioWrite:1, ioReadRate:1, ioWriteRate:1 }
            if (numericCols[sortColumn]) {
                va = parseFloat(va) || 0
                vb = parseFloat(vb) || 0
            } else {
                va = String(va).toLowerCase()
                vb = String(vb).toLowerCase()
            }
            if (va < vb) return sortAsc ? -1 : 1
            if (va > vb) return sortAsc ? 1 : -1
            return 0
        })
        return arr
    }

    /********* UI *********/
    Rectangle {
        anchors.fill: parent
        color: backgroundColor

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            // Top controls: search, refresh interval, column toggles
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                TextField {
                    id: searchField
                    placeholderText: "Filter by name, user or pid..."
                    Layout.preferredWidth: 360
                    font.pixelSize: fontSize
                    onTextChanged: root.filterText = text
                }

                RowLayout {
                    spacing: 8
                    Label { text: "Refresh (ms):" }
                    SpinBox { value: root.refreshIntervalMs; from:500; to:10000; stepSize:500; onValueChanged: { root.refreshIntervalMs = value; mainTimer.interval = value } }
                    CheckBox { checked: mainTimer.running; text: mainTimer.running ? "Running" : "Paused"; onClicked: mainTimer.running = !mainTimer.running }
                }

                // Column toggles
                Flow { Layout.fillWidth: true; spacing: 6; Layout.alignment: Qt.AlignRight
                    Repeater {
                        model: [ {key:'pid', label:'PID'}, {key:'user', label:'USER'},{key:'cpu', label:'CPU'},{key:'mem', label:'MEM'},{key:'cmd', label:'CMD'},{key:'ioReadRate', label:'IO R'},{key:'ioWriteRate', label:'IO W'} ]
                        CheckBox { text: modelData.label; checked: root.visibleColumns[modelData.key] !== false; onClicked: root.toggleColumn(modelData.key) }
                    }
                }
            }

            // System bars (memory, network)
            Rectangle { Layout.fillWidth: true; height: 80; color: 'transparent'
                ColumnLayout { anchors.fill: parent; spacing: 6
                    RowLayout { spacing: 10; Layout.fillWidth: true; anchors.margins: 2
                        Label { text: "Memory"; font.bold: true }
                        ProgressBar { value: memUsedPercent/100.0; Layout.fillWidth: true }
                        Label { text: memUsedPercent + "%" }
                        Label { text: "Net: " + (netDownloadSpeed ? (netDownloadSpeed/1024).toFixed(1) + " KB/s" : "-") + " / " + (netUploadSpeed ? (netUploadSpeed/1024).toFixed(1) + " KB/s" : "-") }
                    }

                    RowLayout { spacing: 8; Layout.fillWidth: true
                        Label { text: "CPU per core"; font.bold: true }
                        Repeater {
                            model: cpuUsages.length
                            ProgressBar { value: cpuUsages[index]/100.0; Layout.preferredWidth: 100; Layout.minimumWidth: 40 }
                        }
                    }
                }
            }

            // Table header
            RowLayout { Layout.fillWidth: true; spacing: 6; height: 30
                Rectangle { width: visibleColumns.pid ? 80 : 0; height: parent.height; color: 'transparent' ; Text { text: visibleColumns.pid ? 'PID' : ''; anchors.centerIn: parent }; MouseArea { anchors.fill: parent; onClicked: if (visibleColumns.pid) toggleSort('pid') } }
                Rectangle { width: visibleColumns.user ? 120 : 0; height: parent.height; color: 'transparent' ; Text { text: visibleColumns.user ? 'USER' : ''; anchors.centerIn: parent }; MouseArea { anchors.fill: parent; onClicked: if (visibleColumns.user) toggleSort('user') } }
                Rectangle { width: visibleColumns.cpu ? 80 : 0; height: parent.height; color: 'transparent' ; Text { text: visibleColumns.cpu ? 'CPU %' : ''; anchors.centerIn: parent }; MouseArea { anchors.fill: parent; onClicked: if (visibleColumns.cpu) toggleSort('cpu') } }
                Rectangle { width: visibleColumns.mem ? 80 : 0; height: parent.height; color: 'transparent' ; Text { text: visibleColumns.mem ? 'MEM %' : ''; anchors.centerIn: parent }; MouseArea { anchors.fill: parent; onClicked: if (visibleColumns.mem) toggleSort('mem') } }
                Rectangle { Layout.fillWidth: true; height: parent.height; color: 'transparent' ; Text { text: visibleColumns.cmd ? 'COMMAND' : ''; anchors.centerIn: parent }; MouseArea { anchors.fill: parent; onClicked: if (visibleColumns.cmd) toggleSort('cmd') } }
                Rectangle { width: visibleColumns.ioReadRate || visibleColumns.ioWriteRate ? 160 : 0; height: parent.height; color: 'transparent'; Text { text: (visibleColumns.ioReadRate||visibleColumns.ioWriteRate) ? 'Disk I/O (R/W)' : ''; anchors.centerIn: parent } }
                Rectangle { width: 120; height: parent.height; color: 'transparent' ; Text { text: 'ACTIONS'; anchors.centerIn: parent } }
            }

            // Process list
            ScrollView { Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                Column { id: listCol; width: parent.width; spacing: 2; padding: 2
                    Repeater {
                        model: filteredAndSortedProcesses()
                        Rectangle {
                            width: parent.width
                            height: 32
                            color: index % 2 === 0 ? 'transparent' : root.rowAltColor
                            RowLayout { anchors.fill: parent; anchors.margins: 6; spacing: 8
                                // PID
                                Label { visible: root.visibleColumns.pid; width: 80; text: model.pid }
                                Label { visible: root.visibleColumns.user; width: 120; text: model.user }
                                Label { visible: root.visibleColumns.cpu; width: 80; horizontalAlignment: Text.AlignRight; text: model.cpu.toFixed(1) }
                                Label { visible: root.visibleColumns.mem; width: 80; horizontalAlignment: Text.AlignRight; text: model.mem.toFixed(1) }
                                Label { visible: root.visibleColumns.cmd; Layout.fillWidth: true; elide: Text.ElideRight; text: model.cmd }
                                ColumnLayout { width: (root.visibleColumns.ioReadRate||root.visibleColumns.ioWriteRate) ? 160 : 0; spacing:2; visible: root.visibleColumns.ioReadRate||root.visibleColumns.ioWriteRate
                                    RowLayout { spacing:6
                                        Label { visible: root.visibleColumns.ioReadRate; text: bytesToHuman(model.ioReadRate); font.pixelSize: fontSize-1 }
                                        Label { visible: root.visibleColumns.ioWriteRate; text: bytesToHuman(model.ioWriteRate); font.pixelSize: fontSize-1 }
                                    }
                                }
                                RowLayout { width: 120; spacing: 6
                                    Button { text: 'Kill'; onClicked: root.killProcess(model.pid, false) }
                                    Button { text: 'SIGKILL'; onClicked: root.killProcess(model.pid, true) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Small note: you can customize colors and visibleColumns at runtime by editing root properties.
}
