/**
 * Message formatting utilities
 */
module birchwood.protocol.formatting;

import birchwood.client.exceptions;

/** 
 * Control codes
 */
public enum ControlCode: char
{
    /** 
     * Reset styling
     */
    Reset = '\x0F',

    /** 
     * Bold text styling
     */
    Bolden = '\x02',

    /** 
     * Italic text styling
     */
    Italic = '\x1D',

    /** 
     * Underlined text styling
     */
    Underline = '\x1F',

    /** 
     * Strikethough text styling
     */
    Strikethrough = '\x1E',

    /** 
     * Monospace text styling
     */
    Monospace = '\x11',

    /** 
     * Reverse colors (NOTE: not universally supported)
     */
    ReverseColors = '\x16',

    /** 
     * ASCII color encoding scheme
     */
    AsciiColor = '\x03',

    /** 
     * Hex color encoding scheme
     */
    HexColor = '\x04'
}


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

/** 
 * Return the hex control character if color is a hexadecimal color code,
 * the ASCII control character if color is two ASCII digits, and throw an
 * exception if it's neither.
 *
 * This function might be useless now that set_fg and set_fg_bg have been
 * changed, but I'll keep it in case it's needed later.
 *
 * Params:
 *   color = the color to check for
 *
 * Returns: the color control type
 */
private char generateColorControlChar(string color)
{
    if(color.length == 6)
    {
        return ControlCode.HexColor;
    }
    else if(color.length == 2)
    {
        return ControlCode.AsciiColor;
    }
    else
    {
        throw new BirchwoodException(ErrorType.INVALID_FORMATTING, "Invalid color code (must be either two ASCII digits or a hexadecimal code of the form RRGGBB)");
    }
}

/** 
 * Generates a string that changes the foreground color
 *
 * Params:
 *   color = the foreground color
 *
 * Returns:  the color control sequence
 */
public string setForeground(string color)
{
    char[1] control_char;

    if(color.length == 6)
    {
        control_char[0] = ControlCode.HexColor;
    }
    else if(color.length == 2)
    {
        control_char[0] = ControlCode.AsciiColor;
    }
    else
    {
        throw new BirchwoodException(ErrorType.INVALID_FORMATTING, "Invalid color code (must be either two ASCII digits or a hexadecimal code of the form RRGGBB)");
    }

    return cast(string)control_char~color;
}

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
        control_char[0] = ControlCode.HexColor;
    }
    else if(fg.length == 2)
    {
        control_char[0] = ControlCode.AsciiColor;
    }
    else
    {
        throw new BirchwoodException(ErrorType.INVALID_FORMATTING, "Invalid color code (must be either two ASCII digits or a hexadecimal code of the form RRGGBB)");
    }

    return cast(string)control_char~fg~","~bg;
}

/** 
 * Generates a string that changes the foreground color (except enum)
 *
 * Params:
 *   color = the foreground color
 *
 * Returns: the control sequence
 */
public string setForeground(SimpleColor color)
{
    return ControlCode.AsciiColor~color;
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
public string setForegroundBackground(SimpleColor fg, SimpleColor bg)
{
    return ControlCode.AsciiColor~fg~","~bg;
}

/** 
 * Generate a string that resets the foreground
 * and background colors
 *
 * Returns: The control string
 */
public string resetForegroundBackground()
{
    return [ControlCode.AsciiColor];
}

// Format strings with functions (TODO: remove comment)

/** 
 * Formats the provided text as bold
 *
 * Params:
 *   text = the text to bolden
 *
 * Returns: the boldened text 
 */
public string bold(string text)
{
    return ControlCode.Bolden~text~ControlCode.Bolden;
}

/** 
 * Formats the provided text in italics
 *
 * Params:
 *   text = the text to italicize
 *
 * Returns: the italicized text
 */
public string italics(string text)
{
    return ControlCode.Italic~text~ControlCode.Italic;
}

/** 
 * Formats the text as underlined
 *
 * Params:
 *   text = the text to underline
 *
 * Returns: the underlined text
 */
public string underline(string text)
{
    return ControlCode.Underline~text~ControlCode.Underline;
}

/** 
 * Formats the text as strikethroughed
 *
 * Params:
 *   text = the text to strikethrough
 *
 * Returns: the strikethroughed text
 */
public string strikethrough(string text)
{
    return ControlCode.Strikethrough~text~ControlCode.Strikethrough;
}

/** 
 * Formats the text as monospaced
 *
 * Params:
 *   text = the text to monospace
 *
 * Returns: the monospaced text
 */
public string monospace(string text)
{
    return ControlCode.Monospace~text~ControlCode.Monospace;
}