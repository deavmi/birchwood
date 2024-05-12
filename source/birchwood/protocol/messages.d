/** 
 * Message definition and tooling
 */
module birchwood.protocol.messages;

import dlog;

import std.string;
import std.conv : to, ConvException;
import birchwood.protocol.constants : ReplyType;

import birchwood.client.exceptions;
import birchwood.config.conninfo : ChecksMode;
import birchwood.logging;

// TODO: Before release we should remove this import
import std.stdio : writeln;

/* TODO: We could move these all to `package.d` */

/**
* Encoding/decoding primitives
*/

/** 
 * Encodes the provided message into a CRLF
 * terminated byte array
 *
 * Params:
 *   messageIn = the message to encode
 * Returns: the encoded message
 */
public ubyte[] encodeMessage(string messageIn)
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
                DEBUG("<<< Unsupported response code (Error below) >>>");
                DEBUG(e);
            }
        }

        /* Parse the parameters into key-value pairs (if any) and trailing text (if any) */
        parameterParse();
    }

    /** 
     * Encodes this `Message` into a CRLF delimited
     * byte array
     *
     * If `ChecksMode` is set to `EASY` (default) then
     * any invalid characters will be stripped prior
     * to encoding
     *
     * Params:
     *    mode = the `ChecksMode` to use
     *
     * Throws: 
     *  `BirchwoodException` if `ChecksMode` is set to
     *  `HARDCORE` and invalid characters are present
     * Returns: the encoded format
     */
    public string encode(ChecksMode mode)
    {
        string fullLine;

        /** 
         * Copy over the values (they might be updated and we
         * want to leave the originals intact)
         */
        string fFrom = from, fCommand = command, fParams = params;
        
        /** 
         * If in `HARDCORE` mode then and illegal characters
         * are present, throw an exception
         */
        if(mode == ChecksMode.HARDCORE && (
                                            hic(fFrom) ||
                                            hic(fCommand) ||
                                            hic(fParams)
                                          ))
        {
            throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS, "Invalid characters present");
        }
        /** 
         * If in `EASY` mode and illegal characters have
         * been found, then fix them up
         */
        else
        {
            // Strip illegal characters from all
            fFrom = sic(fFrom);
            fCommand = sic(fCommand);
            fParams = sic(fParams);
        }
        
        /* Combine */
        fullLine = fFrom~" "~fCommand~" "~fParams;

        

        return fullLine;
    }

    // TODO: comemnt
    private alias sic = stripIllegalCharacters;
    // TODO: comemnt
    private alias hic = hasIllegalCharacters;

    /** 
     * Checks whether the provided input string contains
     * any invalid characters
     *
     * Params:
     *   input = the string to check
     * Returns: `true` if so, `false` otherwise
     */
    // TODO: Add unittest
    public static bool hasIllegalCharacters(string input)
    {
        foreach(char character; input)
        {
            if(character == '\n' || character == '\r')
            {
                return true;
            }
        }

        return false;
    }

    /** 
     * Provided an input string this will strip any illegal
     * characters present within it
     *
     * Params:
     *   input = the string to filter
     * Returns: the filtered string
     */
    // TODO: Add unittest
    public static string stripIllegalCharacters(string input)
    {
        string stripped;
        foreach(char character; input)
        {
            if(character == '\n' || character == '\r')
            {
                continue;
            }

            stripped ~= character;
        }

        return stripped;
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

                // DEBUG("from: "~from);

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
                // DEBUG("command: "~command);

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
                // DEBUG("params: "~params);
            }
            else
            {
                //TODO: handle
                DEBUG("Malformed message start after :");
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
     * Retrieves the trailing text in the paramaters
     * (if any)
     *
     * Returns: the trailing text
     */
    public string getTrailing()
    {
        return ppTrailing;
    }

    /** 
     * Returns the parameters excluding the trailing text
     * which are seperated by spaces but only those
     * which are key-value pairs
     *
     * Returns: the key-value pair parameters
     */
    public string[string] getKVPairs()
    {
        return ppKVPairs;
    }

    /** 
     * Returns the parameters excluding the trailing text
     * which are seperated by spaces
     *
     * Returns: the parameters
     */
    public string[] getPairs()
    {
        return ppPairs;
    }

    private string ppTrailing;
    private string[string] ppKVPairs;
    private string[] ppPairs;


    version(unittest)
    {
        import std.stdio;
    }

    unittest
    {
        string testInput = "A:=1 A=2 :Hello this is text";
        writeln("Input: ", testInput);
        
        bool hasTrailer;
        string[] splitted = splitting(testInput, hasTrailer);
        writeln("Input (split): ", splitted);

        

        assert(cmp(splitted[0], "A:=1") == 0);
        assert(cmp(splitted[1], "A=2") == 0);

        /* Trailer test */
        assert(hasTrailer);
        assert(cmp(splitted[2], "Hello this is text") == 0);
    }

    unittest
    {
        string testInput = ":Hello this is text";
        bool hasTrailer;
        string[] splitted = splitting(testInput, hasTrailer);

        /* Trailer test */
        assert(hasTrailer);
        assert(cmp(splitted[0], "Hello this is text") == 0);
    }

    /** 
     * Imagine: `A:=1 A=2 :Hello` 
     *
     * Params:
     *   input = 
     * Returns: 
     */
    private static string[] splitting(string input, ref bool hasTrailer)
    {
        string[] splits;

        bool trailingMode;
        string buildUp;
        for(ulong idx = 0; idx < input.length; idx++)
        {
            /* Get current character */
            char curCHar = input[idx];


            if(trailingMode)
            {
                buildUp ~= curCHar;
                continue;
            }

            if(buildUp.length == 0)
            {
                if(curCHar == ':')
                {
                    trailingMode = true;
                    continue;
                }
            }
            

            if(curCHar ==  ' ')
            {
                /* Flush */
                splits ~= buildUp;
                buildUp = "";
            }
            else
            {
                buildUp ~= curCHar;
            }
        }

        if(buildUp.length)
        {
            splits ~= buildUp;
        }

        hasTrailer = trailingMode;

        return splits;
    }

    /** 
     * NOTE: This needs more work with trailing support
     * we must make sure we only look for lastInex of `:`
     * where it is first cyaracter after space but NOT within
     * an active parameter
     */
    private void parameterParse()
    {
        /* Only parse if there are params */
        if(params.length)
        {
            /* Trailing text */
            string trailing;

            /* Split the `<params>` */
            bool hasTrailer;
            string[] paramsSplit = splitting(params, hasTrailer);

            // logger.debug_("ParamsSPlit direct:", paramsSplit);
            
            

            /* Extract the trailer as the last item in the array (if it exists) */
            if(hasTrailer)
            {
                trailing = paramsSplit[paramsSplit.length-1];

                /* Remove it from the parameters */
                paramsSplit = paramsSplit[0..$-1];

                // logger.debug_("GOt railer ", trailing);
            }

            ppPairs = paramsSplit;


            /* Generate the key-value pairs */
            foreach(string pair; paramsSplit)
            {
                /* Only do this if we have an `=` in the current pair */
                if(indexOf(pair, "=") > -1)
                {
                    string key = split(pair, "=")[0];
                    string value = split(pair, "=")[1];
                    ppKVPairs[key] = value;
                }
            }

            /* Save the trailing */
            ppTrailing = trailing;

            // logger.debug_("ppTrailing: ", ppTrailing);
        }
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

version(unittest)
{
    // Contains illegal characters
    string badString1 = "doos"~"bruh"~"lek"~cast(string)[10]~"ker";
    string badString2 = "doos"~"bruh"~"lek"~cast(string)[13]~"ker";
}

/**
 * Tests the detection of illegal characters in messages
 */
unittest
{
    assert(Message.hasIllegalCharacters(badString1) == true);
    assert(Message.hasIllegalCharacters(badString2) == true);
}

/**
 * Tests if a message containing bad characters,
 * once stripped, is then valid.
 *
 * Essentially, tests the stripper.
 */
unittest
{
    assert(Message.hasIllegalCharacters(Message.stripIllegalCharacters(badString1)) == false);
    assert(Message.hasIllegalCharacters(Message.stripIllegalCharacters(badString2)) == false);
}

/**
 * Tests the ability, at the `Message`-level, to detect
 * illegal characters and automatically strip them when
 * in `ChecksMode.EASY`
 */
unittest
{
    Message message = new Message(badString1, "fine", "fine");

    try
    {
        string encoded = message.encode(ChecksMode.EASY);
        assert(Message.hasIllegalCharacters(encoded) == false);
    }
    catch(BirchwoodException e)
    {
        assert(false);
    }
}

/**
 * Tests the ability, at the `Message`-level, to detect
 * illegal characters and throw an exception when in
 * `ChecksMode.HARDCORE`
 */
unittest
{
    Message message = new Message(badString1, "fine", "fine");

    try
    {
        message.encode(ChecksMode.HARDCORE);
        assert(false);
    }
    catch(BirchwoodException e)
    {
        assert(e.getType() == ErrorType.ILLEGAL_CHARACTERS);
    }
}