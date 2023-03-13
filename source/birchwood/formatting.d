module birchwood.formatting

import std.string;

// Toggle characters
enum bold = '\x02';
enum italic = '\x1D';
enum underline = '\x1F';
enum strikethrough = '\x1E';
enum monospace = '\x11';

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

// Generates a string that changes the foreground color
string set_foreground(string color) {
    char[1] control_char;
    if (color.length == 6) {
        control_char[0] = hex_color_code;
    } else if (color.length == 2) {
        control_char[0] = ascii_color_code;
    } else {
        throw new StringException("Invalid color code (must be either two ASCII digits or a hexadecimal code of the form RRGGBB)");
    }
    return control_char.idup ~ color;
}