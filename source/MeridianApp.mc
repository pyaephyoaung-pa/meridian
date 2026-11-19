import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class MeridianApp extends Application.AppBase {

    // Created only when the face is shown, not in every app context
    private var _view as MeridianView?;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new MeridianView();
        _view = view;
        return [ view, new MeridianDelegate() ];
    }

    function onSettingsChanged() as Void {
        var view = _view;
        if (view != null) {
            view.loadSettings();
        }
        WatchUi.requestUpdate();
    }

    // Font Scale changed in the watch's settings (API 5.1+; the view also
    // re-checks it once a minute for older firmware)
    function onDeviceSettingChanged(aSymbol as Symbol, aValue as Object) as Void {
        var view = _view;
        if (aSymbol == :fontScale && view != null) {
            view.refreshFontScale();
            WatchUi.requestUpdate();
        }
    }
}
