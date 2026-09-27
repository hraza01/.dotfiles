// Generate native Qt dock state locally; no machine-specific state is shipped.
#include <QApplication>
#include <QDockWidget>
#include <QMainWindow>
#include <QTextStream>
#include <QToolBar>

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    QMainWindow window;
    window.resize(1280, 800);
    window.setCentralWidget(new QWidget);
    auto dock = [&](const char *name, Qt::DockWidgetArea area) {
        auto *widget = new QDockWidget(&window);
        widget->setObjectName(name);
        widget->setWidget(new QWidget);
        window.addDockWidget(area, widget);
        return widget;
    };
    auto *places = dock("placesDock", Qt::RightDockWidgetArea);
    auto *info = dock("infoDock", Qt::RightDockWidgetArea);
    auto *folders = dock("foldersDock", Qt::LeftDockWidgetArea);
    auto *terminal = dock("terminalDock", Qt::BottomDockWidgetArea);
    auto *toolbar = window.addToolBar("Navigation");
    toolbar->setObjectName("mainToolBar");
    const auto original = QTextStream(stdin).readAll().trimmed().toLatin1();
    if (!original.isEmpty() && !window.restoreState(QByteArray::fromBase64(original)))
        return 2;
    window.addDockWidget(Qt::RightDockWidgetArea, places);
    window.splitDockWidget(places, info, Qt::Vertical);
    places->show();
    info->show();
    folders->hide();
    terminal->hide();
    toolbar->show();
    window.show();
    app.processEvents();
    // Offscreen QPA may constrain the initial show to its small virtual screen.
    window.resize(1280, 900);
    app.processEvents();
    window.resizeDocks({places, info}, {280, 280}, Qt::Horizontal);
    window.resizeDocks({places, info}, {380, 340}, Qt::Vertical);
    app.processEvents();
    if (window.dockWidgetArea(places) != Qt::RightDockWidgetArea
        || window.dockWidgetArea(info) != Qt::RightDockWidgetArea
        || info->y() <= places->y())
        return 3;
    QTextStream(stdout) << window.saveState().toBase64() << Qt::endl;
}
