module birchwood.messages;

import dlog;

import std.string;

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
 * Message types
 */
public class Message
{
    public string from;
    public string command;
    public string message;

    this(string from, string command, string message)
    {
        this.from = from;
        this.command = command;
        this.message = message;
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

                logger.log("from: "~from);

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
                logger.log("command: "~command);

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
                logger.log("params: "~params);
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
        return "(from: "~from~", command: "~command~", message: `"~message~"`)";
    }

    public string getMessage()
    {
        return message;
    }
}