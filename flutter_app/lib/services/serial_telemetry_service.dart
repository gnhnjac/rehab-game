export 'serial_unsupported.dart'
    if (dart.library.html) 'serial_web.dart'
    if (dart.library.io) 'serial_desktop.dart';
