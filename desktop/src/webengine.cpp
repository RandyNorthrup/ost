// QtWebEngine must be set up before the QGuiApplication exists (it
// shares an OpenGL context with Qt Quick); cxx-qt-lib has no binding for
// it, so this one call is plain C++.
#include <QtWebEngineQuick/qtwebenginequickglobal.h>

extern "C" void ost_webengine_initialize()
{
    QtWebEngineQuick::initialize();
}
