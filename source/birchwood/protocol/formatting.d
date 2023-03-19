/**
 * Message formatting utilities
 */
module birchwood.protocol.formatting;

// FIXME: Remove below import and start using BirchwoodException
import std.string;

// Reset character; resets all formatting
enum reset_code = '\x0F';

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

/** 
 * Simple color codes
 */
public enum SimpleColor: string {
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
// This function might be useless now that set_fg and set_fg_bg have been changed, but I'll keep it in case it's needed later.
char generate_color_control_char(string color) {
    if (color.length == 6) {
        return hex_color_code;
    } else if (color.length == 2) {
        return ascii_color_code;
    } else {
        throw new StringException("Invalid color code (must be either two ASCII digits or a hexadecimal code of the form RRGGBB)");
    }
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

// Generate a string that sets the foreground and background color
string set_foreground_background(string fg, string bg) {
    char[1] control_char;
    if (fg.length != bg.length) {
        throw new StringException("Invalid color code (cannot mix hex and ASCII)");
    }
    if (fg.length == 6) {
        control_char[0] = hex_color_code;
    } else if (fg.length == 2) {
        control_char[0] = ascii_color_code;
    } else {
        throw new StringException("Invalid color code (must be either two ASCII digits or a hexadecimal code of the form RRGGBB)");
    }
    return control_char.idup ~ fg ~ "," ~ bg;
}

// Generates a string that changes the foreground color (except enum)
pragma(inline)
string set_foreground(SimpleColor color) {
    return ascii_color_code ~ color;
}

// Generate a string that sets the foreground and background color (except enum)
pragma(inline)
string set_foreground_background(SimpleColor fg, SimpleColor bg) {
    return ascii_color_code ~ fg ~ "," ~ bg;
}

/** 
 * Generate a string that resets the foreground
 * and background colors
 *
 * Returns: The control string
 */
pragma(inline)
string reset_fg_bg()
{
    return [ascii_color_code].idup;
}




// Format strings with functions

/** 
 * Formats the provided text as bold
 *
 * Params:
 *   text = the text to bolden
 *
 * Returns: the boldened text 
 */
pragma(inline)
public string bold(string text)
{
    return bold_code~text~bold_code;
}

/** 
 * Formats the provided text in italics
 *
 * Params:
 *   text = the text to italicize
 *
 * Returns: the italicized text
 */
pragma(inline)
public string italics(string text)
{
    return italic_code~text~italic_code;
}

/** 
 * Formats the text as underlined
 *
 * Params:
 *   text = the text to underline
 *
 * Returns: the underlined text
 */
pragma(inline)
public string underline(string text)
{
    return underline_code~text~underline_code;
}

/** 
 * Formats the text as strikethroughed
 *
 * Params:
 *   text = the text to strikethrough
 *
 * Returns: the strikethroughed text
 */
pragma(inline)
public string strikethrough(string text)
{
    return strikethrough_code~text~strikethrough_code;
}

/** 
 * Formats the text as monospaced
 *
 * Params:
 *   text = the text to monospace
 *
 * Returns: the monospaced text
 */
pragma(inline)
public string monospace(string text)
{
    return monospace_code~text~monospace_code;
}