import Toybox.Complications;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Tap a subdial to open the matching native glance/widget.
class MeridianDelegate extends WatchUi.WatchFaceDelegate {

    function initialize() {
        WatchFaceDelegate.initialize();
    }

    function onPress(evt as WatchUi.ClickEvent) as Boolean {
        var xy = evt.getCoordinates();
        var k = System.getDeviceSettings().screenWidth / Meridian.SIZE;
        // Hit area: the gauge plus a small margin (subdials are far apart, no overlap)
        var hit = (Meridian.SUB_R + 8) * k;

        var type = null;
        if (inside(xy, Meridian.HR_X * k, Meridian.HR_Y * k, hit)) {
            type = Complications.COMPLICATION_TYPE_HEART_RATE;
        } else if (inside(xy, Meridian.BB_X * k, Meridian.BB_Y * k, hit)) {
            type = Complications.COMPLICATION_TYPE_BODY_BATTERY;
        } else if (inside(xy, Meridian.BAT_X * k, Meridian.BAT_Y * k, hit)) {
            type = Complications.COMPLICATION_TYPE_BATTERY;
        }

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
