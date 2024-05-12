/**
 * Internal logging facilities
 */
module birchwood.logging;

import gogga;
import gogga.extras;
import dlog.basic : Level, FileHandler;
import std.stdio : stdout;

/** 
 * Globally available logger
 */
package __gshared GoggaLogger logger;

/**
 * Initializes a logger instance
 * globally
 */
__gshared static this()
{
    logger = new GoggaLogger();

    GoggaMode mode;

    // TODO: Add flag support
    version(DBG_VERBOSE_LOGGING)
    {
        mode = GoggaMode.RUSTACEAN;
    }
    else
    {
        mode = GoggaMode.SIMPLE;
    }

    logger.mode(mode);

    Level level = Level.DEBUG;

    // TODO: Add flag support
    // version(DBG_DEBUG_LOGGING)
    // {
    //     level = Level.DEBUG;
    // }
    // else
    // {
    //     level = Level.INFO;
    // }
   

    logger.setLevel(level);
    logger.addHandler(new FileHandler(stdout));
}

// Bring in helper methods
mixin LoggingFuncs!(logger);