module birchwood.messages;

import dlog;

import std.string;
import std.conv : to, ConvException;
import birchwood.constants : ReplyType;

// TODO: Before release we should remove this import
import std.stdio : writeln;

/* TODO: We could move these all to `package.d` */

/* Static is redundant as module is always static , gshared needed */
/* Apparebky works without gshared, that is kinda sus ngl */
__gshared Logger logger;
/**
* source/birchwood/messages.d(10,8): Error: variable `birchwood.messages.logger` is a thread-local class and cannot have a static initializer. Use `static this()` to initialize instead.
*
* It is complaining that it wopuld static init per thread, static this() for module is required but that would
* do a module init per thread, so __gshared static this() is needed, we want one global init - a single logger
* variable and also class init
*/

__gshared static this()
{
    logger = new DefaultLogger();
}

/**
* Encoding/decoding primitives
*/
public static ubyte[] encodeMessage(string messageIn)
{
    ubyte[] messageOut = cast(ubyte[])messageIn;
    messageOut~=[cast(ubyte)13, cast(ubyte)10];
    return messageOut;
}

public static string decodeMessage(ubyte[] messageIn)
{
    /* TODO: We could do a chekc to ESNURE it is well encoded */

    return cast(string)messageIn[0..messageIn.length-2];
    // return  null;
}

/** 
 * Checks if the provided message is valid (i.e.)
 * does not contain any CR or LF characters in it
 *
 * Params:
 *   message = the message to test
 * Returns: <code>true</code> if the message is valid,
 * <code>false</code> false otherwise
 */
 //TODO: Should we add an emptiness check here
public static bool isValidText(string message)
{
    foreach(char character; message)
    {
        if(character == 13 || character == 10)
        {
            return false;
        }
    }

    return true;
}

/**
 * Message types
 */
public final class Message
{
    /* Message contents */
    private string from;
    private string command;
    private string params;

    /* The numeric reply (as per Section 6 of RFC 1459) */
    private bool isNumericResponse = false;
    private ReplyType replyType = ReplyType.BIRCHWOOD_UNKNOWN_RESP_CODE;
    private bool isError = false;

    /** 
     * Constructs a new Message
     *
     * Params:
     *   from = the from parameter
     *   command = the command
     *   params = any optional parameters to the command
     */
    this(string from, string command, string params = "")
    {
        this.from = from;
        this.command = command;
        this.params = params;

        /* Check if this is a command reply */
        if(isNumeric(command))
        {
            isNumericResponse = true;
            
            //FIXME: SOmething is tripping it u, elts' see
            try
            {
                /* Grab the code */
                replyType = to!(ReplyType)(to!(ulong)(command));
                // TODO: Add validity check on range of values here, if bad throw exception
                // TODO: Add check for "6.3 Reserved numerics" or handling of SOME sorts atleast

                /* Error codes are in range of [401, 502] */
                if(replyType >= 401 && replyType <= 502)
                {
                    // TODO: Call error handler
                    isError = true;
                }
                /* Command replies are in range of [259, 395] */
                else if(replyType >= 259 && replyType <= 395)
                {
                    // TODO: Call command-reply handler
                    isError = false;
                }
            }
            catch(ConvException e)
            {
                logger.log("<<< Unsupported response code (Error below) >>>");
                logger.log(e);
            }
        }
    }

    /* TODO: Implement encoder function */
    public string encode()
    {
        string fullLine = from~" "~command~" "~params;
        return fullLine;
    }

    public static Message parseReceivedMessage(string message)
    {
        /* TODO: testing */

        /* From */
        string from;

        /* Command */
        string command;

        /* Params */
        string params;



        /* Check if there is a PREFIX (according to RFC 1459) */
        if(message[0] == ':')
        {
            /* prefix ends after first space (we fetch servername, host/user) */
            //TODO: make sure not -1
            long firstSpace = indexOf(message, ' ');

            /* TODO: double check the condition */
            if(firstSpace > 0)
            {
                from = message[1..firstSpace];

                // logger.log("from: "~from);

                /* TODO: Find next space (what follows `from` is  `' ' { ' ' }`) */
                ulong i = firstSpace;
                for(; i < message.length; i++)
                {
                    if(message[i] != ' ')
                    {
                        break;
                    }
                }

                // writeln("Yo");

                string rem = message[i..message.length];
                // writeln("Rem: "~rem);
                long idx  = indexOf(rem, " "); //TOOD: -1 check

                /* Extract the command */
                command = rem[0..idx];
                // logger.log("command: "~command);

                /* Params are everything till the end */
                i = idx;
                for(; i < rem.length; i++)
                {
                    if(rem[i] != ' ')
                    {
                        break;
                    }
                }
                params = rem[i..rem.length];
                // logger.log("params: "~params);
            }
            else
            {
                //TODO: handle
                logger.log("Malformed message start after :");
                assert(false);
            }

            
        }
        /* In this case it is only `<command> <params>` */
        else
        {

            long firstSpace = indexOf(message, " "); //TODO: Not find check
            
            command = message[0..firstSpace];

            ulong pos = firstSpace;
            for(; pos < message.length; pos++)
            {
                if(message[pos] != ' ')
                {
                    break;
                }
            }

            params = message[pos..message.length];

        }

        return new Message(from, command, params);
    }

    public override string toString()
    {
        return "(from: "~from~", command: "~command~", message: `"~params~"`)";
    }

    /** 
     * Returns the sender of the message
     *
     * Returns: The `from` field
     */
    public string getFrom()
    {
        return from;
    }
    
    /** 
     * Returns the command name
     *
     * Returns: The command itself
     */
    public string getCommand()
    {
        return command;
    }

    /** 
     * Returns the optional paremeters (if any)
     *
     * Returns: The parameters
     */
    public string getParams()
    {
        return params;
    }

    /** 
     * Returns whether or not this message was
     * a numeric response
     *
     * Returns: `true` if numeric response
     * `false` otherwise
     */
    public bool isResponseMessage()
    {
        return isNumericResponse;
    }

    /** 
     * Returns whether or not this message is
     * an error kind-of numeric response
     *
     * Returns: `true` if numeric response
     * is an error, `false` otherwise
     */
    public bool isResponseError()
    {
        return isError;
    }

    /** 
     * Returns the type of reply (if this message
     * was a numeric response)
     *
     * Returns: the ReplyType
     */
    public ReplyType getReplyType()
    {
        return replyType;
    }
}