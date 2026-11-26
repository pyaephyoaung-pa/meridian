import Toybox.Complications;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Press and hold a subdial to open the native glance/widget of the metric
// it shows (chosen in settings).
// onPress is the touch-and-hold event; a running watch face gets no plain
// taps (WatchFaceDelegate.onTap only fires in watch face config mode).
class MeridianDelegate extends WatchUi.WatchFaceDelegate {

    function initialize() {
        WatchFaceDelegate.initialize();
    }

    function onPress(evt as WatchUi.ClickEvent) as Boolean {
        var xy = evt.getCoordinates();
        var k = System.getDeviceSettings().screenWidth / Meridian.SIZE;
        // Hit area: the gauge plus a small margin (subdials are far apart, no overlap)
        var hit = (Meridian.SUB_R + 8) * k;

        var type = null as Complications.Type?;
        for (var i = 0; i < 3; i++) {
            if (inside(xy, (Meridian.SLOT_X[i] as Float) * k, (Meridian.SLOT_Y[i] as Float) * k, hit)) {
                type = Meridian.COMPLICATIONS[Meridian.slotMetric(i)] as Complications.Type?;
                break;
            }
        }

        // Not on a register, a metric without a glance (distance), or the
        // watch doesn't offer that metric's glance
        if (type == null) {
            return false;
        }
        try {
            Complications.exitTo(new Complications.Id(type));
            return true;
        } catch (e) {
            return false;
        }
    }

    private function inside(xy as [Number, Number], cx as Numeric, cy as Numeric, r as Numeric) as Boolean {
        var dx = xy[0] - cx;
        var dy = xy[1] - cy;
        return dx * dx + dy * dy <= r * r;
    }
}
