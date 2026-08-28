import QtQuick

// A contained manifest plugin stays referenced from bar.layout so the shell keeps every
// entry point loaded and services that read their settings from the bar keep working. The
// real bar widget is rendered by HostedWidget; this owned placeholder occupies no space.
Item {
  visible: false
  implicitWidth: 0
  implicitHeight: 0
}
