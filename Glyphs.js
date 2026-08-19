.pragma library

// Codepoints, not literals: these are outside the BMP and render as tofu in most editors.
function g(codePoint) {
  return String.fromCodePoint(codePoint)
}

var app = g(0xF03D3)            // package-variant-closed - the always-on box
var container = g(0xF01A7)      // cube-outline - fallback per-container icon

var add = g(0xF0415)            // plus
var rename = g(0xF03EB)         // pencil
var del = g(0xF0A79)            // delete-outline
var close = g(0xF0156)          // close
var search = g(0xF0349)         // magnify
var grip = g(0xF01DD)           // drag-horizontal
var restore = g(0xF099B)        // restore
var manage = g(0xF0493)         // cog
var warn = g(0xF0026)           // alert-circle-outline
var empty = g(0xF0431)          // puzzle-outline - nothing in this container

var left = g(0xF0141)           // chevron-left
var right = g(0xF0142)          // chevron-right
var up = g(0xF0143)             // chevron-up
var down = g(0xF0140)           // chevron-down

// A container shows only its icon, so these have to stay distinct at bar size.
var choices = [
  g(0xF01A7), // cube-outline
  g(0xF03D3), // package-variant-closed
  g(0xF024B), // folder
  g(0xF0570), // view-grid
  g(0xF0431), // puzzle
  g(0xF0493), // cog
  g(0xF1064), // tools
  g(0xF02B4), // controller - gaming
  g(0xF0317), // lan - network
  g(0xF05A9), // wifi
  g(0xF0565), // shield-check - security
  g(0xF033E), // lock
  g(0xF075A), // music
  g(0xF0567), // video
  g(0xF057E), // volume-high
  g(0xF0100), // camera
  g(0xF0379), // monitor
  g(0xF0322), // laptop
  g(0xF018D), // terminal
  g(0xF0174), // code-tags
  g(0xF01BC), // database
  g(0xF015F), // cloud
  g(0xF00E4), // bug
  g(0xF009A), // bell
  g(0xF0B79), // chat
  g(0xF01F0), // mail
  g(0xF0954), // clock
  g(0xF02DC), // home
  g(0xF02D1), // heart
  g(0xF04CE)  // star
]
