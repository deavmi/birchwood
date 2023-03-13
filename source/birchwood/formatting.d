module birchwood.formatting;

import std.string;

// Reset character; resets all formatting
enum reset = '\x0F';

// Toggle characters
enum bold = '\x02';
enum italic = '\x1D';
enum underline = '\x1F';
enum strikethrough = '\x1E';
enum monospace = '\x11';
enum reverse_colors = '\x16'; // NOT UNIVERSALLY SUPPORTED

// Color characters
enum ascii_color_code = '\x03';
enum hex_color_code = '\x04';

// Simple color codes
enum simple_colors: string {
    WHITE = "00",
    BLACK = "01",
    BLUE = "02",
    GREEN = "03",
    RED = "04",
    BROWN = "05",
    MAGENTA = "06",
    ORANGE = "07",
    YELLOW = "08",
    LIGHT_GREEN = "09",
    CYAN = "10",
    LIGHT_CYAN = "11",
    LIGHT_BLUE = "12",
    PINK = "13",
    GREY = "14",
    LIGHT_GREY = "15",
    DEFAULT = "99" // NOT UNIVERSALLY SUPPORTED
}

// Return the hex control character if color is a hexadecimal color code, the ASCII control character if color is two ASCII digits, and throw an exception if it's neither
char generate_color_control_char(string color) {
    if (color.length == 6) {
        return hex_color_code;
    } else if (color.length == 2) {
        return ascii_color_code;
    } else {
        throw new StringException("Invalid color code (must be either two ASCII digits or a hexadecimal code of the form RRGGBB)");
    }
}

// Generate a string that sets the foreground color
string set_fg(string color) {return [generate_color_control_char(color)].idup ~ color;}

// Generate a string that sets the foreground and background color
string set_fg_bg(string color) {return [generate_color_control_char(color)].idup ~ color ~ "," ~ color;}

// Generate a string that resets the foreground and background colors
pragma(inline)
string reset_fg_bg() {return "\x03";}