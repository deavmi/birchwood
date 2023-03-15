module birchwood.protocol.formatting;

import std.string;

// Reset character; resets all formatting
enum reset = '\x0F';

// Toggle characters
enum bold_code = '\x02';
enum italic_code = '\x1D';
enum underline_code = '\x1F';
enum strikethrough_code = '\x1E';
enum monospace_code = '\x11';
enum reverse_colors_code = '\x16'; // NOT UNIVERSALLY SUPPORTED

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
string set_fg(string color) {return [generate_color_control_char(color)] ~ color;}

// Generate a string that sets the foreground and background color
string set_fg_bg(string color) {return [generate_color_control_char(color)] ~ color ~ "," ~ color;}

// Generate a string that resets the foreground and background colors
pragma(inline)
string reset_fg_bg() {return "\x03";}

// Format strings with functions
pragma(inline)
string bold(string text) {return bold_code~text~bold_code;}

pragma(inline)
string italics(string text) {return italic_code~text~italic_code;}

pragma(inline)
string underline(string text) {return underline_code~text~underline_code;}

pragma(inline)
string strikethrough(string text) {return strikethrough_code~text~strikethrough_code;}

pragma(inline)
string monospace(string text) {return monospace_code~text~monospace_code;}