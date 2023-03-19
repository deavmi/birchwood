/**
 * Message formatting utilities
 */
module birchwood.protocol.formatting;

import birchwood.client.exceptions;

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
public enum SimpleColor: string
{
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
char generate_color_control_char(string color)
{
    if (color.length == 6)
    {
        return hex_color_code;
    }
    else if (color.length == 2)
    {
        return ascii_color_code;
    }
    else
    {
        throw new BirchwoodException(ErrorType.INVALID_FORMATTING, "Invalid color code (must be either two ASCII digits or a hexadecimal code of the form RRGGBB)");
    }
}

// Generates a string that changes the foreground color
string set_foreground(string color)
{
    char[1] control_char;

    if(color.length == 6)
    {
        control_char[0] = hex_color_code;
    }
    else if(color.length == 2)
    {
        control_char[0] = ascii_color_code;
    }
    else
    {
        throw new BirchwoodException(ErrorType.INVALID_FORMATTING, "Invalid color code (must be either two ASCII digits or a hexadecimal code of the form RRGGBB)");
    }

    return control_char.idup~color;
}


// TODO: Investigate how we want to aloow people to use the below

/** 
 * Generate a string that sets the foreground and background color
 *
 * Params:
 *   fg = foreground color in hex code or ASCII color code
 *   bg = background color
 *
 * Returns: the control sequence to set the style
 */
public string setForegroundBackground(string fg, string bg)
{
    char[1] control_char;

    if(fg.length != bg.length)
    {
        throw new BirchwoodException(ErrorType.INVALID_FORMATTING, "Invalid color code (cannot mix hex and ASCII)");
    }

    if(fg.length == 6)
    {
        control_char[0] = hex_color_code;
    }
    else if(fg.length == 2)
    {
        control_char[0] = ascii_color_code;
    }
    else
    {
        throw new BirchwoodException(ErrorType.INVALID_FORMATTING, "Invalid color code (must be either two ASCII digits or a hexadecimal code of the form RRGGBB)");
    }

    return control_char.idup~fg~","~bg;
}

/** 
 * Generates a string that changes the foreground color (except enum)
 *
 * Params:
 *   color = the foreground color
 *
 * Returns: the control sequence
 */
pragma(inline)
public string setForeground(SimpleColor color)
{
    return ascii_color_code~color;
}


/** 
 * Generate a string that sets the foreground and background color (except enum)
 *
 * Params:
 *   fg = the foreground color
 *   bg = the background color
 *
 * Returns: thecolor control sequence
 */
pragma(inline)
public string setForegroundBackground(SimpleColor fg, SimpleColor bg)
{
    return ascii_color_code~fg~","~bg;
}

/** 
 * Generate a string that resets the foreground
 * and background colors
 *
 * Returns: The control string
 */
pragma(inline)
public string resetForegroundBackground()
{
    return [ascii_color_code].idup;
}

// TODO: consider removing praghma(inline), not a bad thing to have though
// TOOD: investigate idup, makes sense me thinks but take a look at
// Format strings with functions (TODO: remove comment)

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