import QtQuick

Item {
    id: frame
    property color fillColor: "#210e15"
    property color lineColor: "#5df4fe"
    property real cut: 18
    property real lineWidth: 1.5
    property bool cornerAccent: false
    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const inset = frame.lineWidth / 2;
            const c = Math.min(frame.cut, width / 3, height / 3);
            ctx.beginPath();
            ctx.moveTo(c + inset, inset);
            ctx.lineTo(width - inset, inset);
            ctx.lineTo(width - inset, height - c - inset);
            ctx.lineTo(width - c - inset, height - inset);
            ctx.lineTo(inset, height - inset);
            ctx.lineTo(inset, c + inset);
            ctx.closePath();
            ctx.fillStyle = frame.fillColor;
            ctx.fill();
            ctx.lineWidth = frame.lineWidth;
            ctx.lineJoin = "miter";
            ctx.strokeStyle = frame.lineColor;
            ctx.stroke();
            if (frame.cornerAccent && width > 40 && height > 40) {
                ctx.beginPath();
                ctx.moveTo(width - c - 7, height - 5);
                ctx.lineTo(width - 5, height - c - 7);
                ctx.lineWidth = 2;
                ctx.strokeStyle = "#fb3048";
                ctx.stroke();
            }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }
    onFillColorChanged: canvas.requestPaint()
    onLineColorChanged: canvas.requestPaint()
    onCutChanged: canvas.requestPaint()
    onLineWidthChanged: canvas.requestPaint()
    onCornerAccentChanged: canvas.requestPaint()
}
