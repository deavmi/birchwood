module birchwood.messages;

import dlog;

import std.string;
import std.conv : to, ConvException;

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

/* Reply object */
    public enum ReplyType : ulong
    {
        /* Error replies */
        ERR_NOSUCHNICK = 401,
        ERR_NOSUCHSERVER = 402,
        ERR_NOSUCHCHANNEL = 403,
        ERR_CANNOTSENDTOCHAN = 404,
        ERR_TOOMANYCHANNELS = 405,
        ERR_WASNOSUCHNICK = 406,
        ERR_TOOMANYTARGETS = 407,
        ERR_NOORIGIN = 409,
        ERR_NORECIPIENT = 411,
        ERR_NOTEXTTOSEND = 412,
        ERR_NOTOPLEVEL = 413,
        ERR_WILDTOPLEVEL  = 414,
        ERR_UNKNOWNCOMMAND = 421,
        ERR_NOMOTD = 422,
        ERR_NOADMININFO = 423,
        ERR_FILEERROR = 424,
        ERR_NONICKNAMEGIVEN = 431,
        ERR_ERRONEUSNICKNAME = 432,
        ERR_NICKNAMEINUSE = 433,
        ERR_NICKCOLLISION = 436,
        ERR_USERNOTINCHANNEL = 441,
        ERR_NOTONCHANNEL = 442,
        ERR_USERONCHANNEL = 443,
        ERR_NOLOGIN = 444,
        ERR_SUMMONDISABLED = 445,
        ERR_USERSDISABLED = 446,
        ERR_NOTREGISTERED = 451,
        ERR_NEEDMOREPARAMS = 461,
        ERR_ALREADYREGISTRED = 462,
        ERR_NOPERMFORHOST = 463,
        ERR_PASSWDMISMATCH = 464,
        ERR_YOUREBANNEDCREEP = 465,
        ERR_KEYSET = 467,
        ERR_CHANNELISFULL = 471,
        ERR_UNKNOWNMODE = 472,
        ERR_INVITEONLYCHAN = 473,
        ERR_BANNEDFROMCHAN = 474,
        ERR_BADCHANNELKEY = 475,
        ERR_NOPRIVILEGES = 481,
        ERR_CHANOPRIVSNEEDED = 482,
        ERR_CANTKILLSERVER = 483,
        ERR_NOOPERHOST = 491,
        ERR_UMODEUNKNOWNFLAG = 501,
        ERR_USERSDONTMATCH = 502,

        /* Command responses */
        RPL_NONE = 300,
        RPL_USERHOST = 302,
        RPL_ISON = 303,
        RPL_AWAY = 301,
        RPL_UNAWAY = 305,
        RPL_NOWAWAY = 306,
        RPL_WHOISUSER = 311,
        RPL_WHOISSERVER = 312,
        RPL_WHOISOPERATOR = 313,
        RPL_WHOISIDLE = 317,
        RPL_ENDOFWHOIS = 318,
        RPL_WHOISCHANNELS = 319,
        RPL_WHOWASUSER = 314,
        RPL_ENDOFWHOWAS = 369,
        RPL_LISTSTART = 321,
        RPL_LIST = 322,
        RPL_LISTEND = 323,
        RPL_CHANNELMODEIS = 324,
        RPL_NOTOPIC = 331,
        RPL_TOPIC = 332,
        RPL_INVITING = 341,
        RPL_SUMMONING = 342,
        RPL_VERSION = 351,
        RPL_WHOREPLY = 352,
        RPL_ENDOFWHO = 315,
        RPL_NAMREPLY = 353,
        RPL_ENDOFNAMES = 366,
        RPL_LINKS = 364,
        RPL_ENDOFLINKS = 365,
        RPL_BANLIST = 367,
        RPL_ENDOFBANLIST = 368,
        RPL_INFO = 371,
        RPL_ENDOFINFO = 374,
        RPL_MOTDSTART = 375,
        RPL_MOTD = 372,
        RPL_ENDOFMOTD = 376,
        RPL_YOUREOPER = 381,
        RPL_REHASHING = 382,
        RPL_TIME = 391,
        RPL_USERSSTART = 392,
        RPL_USERS = 393,
        RPL_ENDOFUSERS = 394,
        RPL_NOUSERS = 395,
        RPL_TRACELINK = 200,
        RPL_TRACECONNECTING = 201,
        RPL_TRACEHANDSHAKE = 202,
        RPL_TRACEUNKNOWN = 203,
        RPL_TRACEOPERATOR = 204,
        RPL_TRACEUSER = 205,
        RPL_TRACESERVER = 206,
        RPL_TRACENEWTYPE = 208,
        RPL_TRACELOG = 261,
        RPL_STATSLINKINFO = 211,
        RPL_STATSCOMMANDS = 212,
        RPL_STATSCLINE = 213,
        RPL_STATSNLINE = 214,
        RPL_STATSILINE = 215,
        RPL_STATSKLINE = 216,
        RPL_STATSYLINE = 218,
        RPL_ENDOFSTATS = 219,
        RPL_STATSLLINE = 241,
        RPL_STATSUPTIME = 242,
        RPL_STATSOLINE = 243,
        RPL_STATSHLINE = 244,
        RPL_UMODEIS = 221,
        RPL_LUSERCLIENT = 251,
        RPL_LUSEROP = 252,
        RPL_LUSERUNKNOWN = 253,
        RPL_LUSERCHANNELS = 254,
        RPL_LUSERME = 255,
        RPL_ADMINME = 256,
        RPL_ADMINLOC1 = 257,
        RPL_ADMINLOC2 = 258,
        RPL_ADMINEMAIL = 259,

        /* Reserved Numerics (See section 6.3 in RFC 1459) */
        RPL_TRACECLASS = 209,
        RPL_SERVICEINFO = 231,
        RPL_SERVICE = 233,
        RPL_SERVLISTEND = 235,
        RPL_WHOISCHANOP = 316,
        RPL_CLOSING = 362,
        RPL_INFOSTART = 372,
        ERR_YOUWILLBEBANNED = 466,
        ERR_NOSERVICEHOST = 492,
        RPL_STATSQLINE = 217,
        RPL_ENDOFSERVICES = 232,
        RPL_SERVLIST = 234,
        RPL_KILLDONE = 361,
        RPL_CLOSEEND = 363,
        RPL_MYPORTIS = 384,
        ERR_BADCHANMASK = 476,


        BIRCHWOOD_UNKNOWN_RESP_CODE = 0
}

/**
 * Message types
 */
public class Message
{
    public string from;
    public string command;
    public string params;

    /* Whether this numeric reply is an error type */
    public bool isError = false;
    /* Whether this is a response message */
    public bool isResponse = false;

    /* The numeric reply */
    public ReplyType replyType = ReplyType.BIRCHWOOD_UNKNOWN_RESP_CODE;

    this(string from, string command, string params)
    {
        this.from = from;
        this.command = command;
        this.params = params;

        /* Check if this is a command reply */
        if(isNumeric(command))
        {
            isResponse = true;
            
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
        return null;
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

    /* TODO: Rename to `getParams()` */
    public string getParams()
    {
        return params;
    }

    public string getCommand()
    {
        return command;
    }
}