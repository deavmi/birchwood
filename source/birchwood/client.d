module birchwood.client;

import std.socket : Socket, SocketException, Address, parseAddress, SocketType, ProtocolType, SocketOSException;
import std.socket : SocketFlags;
import std.conv : to;
import std.container.slist : SList;
import core.sync.mutex : Mutex;
import core.thread : Thread, dur;
import std.string;
import eventy;
import birchwood.messages : Message, encodeMessage, decodeMessage;

// TODO: Remove this import
import std.stdio : writeln;
import dlog;

__gshared Logger logger;
__gshared static this()
{
    logger = new DefaultLogger();
}


public class BirchwoodException : Exception
{
    public enum ErrorType
    {
        INVALID_CONN_INFO,
        ALREADY_CONNECTED,
        CONNECT_ERROR
    }

    private ErrorType errType;

    /* Auxillary error information */
    /* TODO: Make these actually Object */
    private string auxInfo;

    this(ErrorType errType)
    {
        super("BirchwoodError("~to!(string)(errType)~")"~(auxInfo.length == 0 ? "" : " "~auxInfo));
        this.errType = errType;
    }

    this(ErrorType errType, string auxInfo)
    {
        this(errType);
        this.auxInfo = auxInfo;
    }

    public ErrorType getType()
    {
        return errType;
    }
}

public struct ConnectionInfo
{
    /* Server address information */
    private Address addrInfo;
    private string nickname;

    /* Misc. */
    /* TODO: Make final/const (find out difference) */
    private ulong bulkReadSize;

    /* Client behaviour (TODO: what is sleep(0), like nothing) */
    private ulong fakeLag = 0;

    /* TODO: before publishing change this bulk size */
    private this(Address addrInfo, string nickname, ulong bulkReadSize = 20)
    {
        this.addrInfo = addrInfo;
        this.nickname = nickname;
        this.bulkReadSize = bulkReadSize;
    }

    public ulong getBulkReadSize()
    {
        return this.bulkReadSize;
    }

    public Address getAddr()
    {
        return addrInfo;
    }

    public static ConnectionInfo newConnection(string hostname, ushort port, string nickname)
    {
        try
        {
            /* Attempt to parse address (may throw SocketException) */
            Address addrInfo = parseAddress(hostname, port);

            /* Username check */
            if(!nickname.length)
            {
                throw new BirchwoodException(BirchwoodException.ErrorType.INVALID_CONN_INFO);
            }



            return ConnectionInfo(addrInfo, nickname);
        }
        catch(SocketException e)
        {
            throw new BirchwoodException(BirchwoodException.ErrorType.INVALID_CONN_INFO);
        }
    }

    /**
    * Tests invalid conneciton information
    *
    * 1. Invalid hostnames
    * 2. Invalid usernames
    */
    unittest
    {
        try
        {
            newConnection("1.", 21, "deavmi");
            assert(false);
        }
        catch(BirchwoodException e)
        {
            assert(e.getType() == BirchwoodException.ErrorType.INVALID_CONN_INFO);
        }

        try
        {
            newConnection("1.1.1.1", 21, "");
            assert(false);
        }
        catch(BirchwoodException e)
        {
            assert(e.getType() == BirchwoodException.ErrorType.INVALID_CONN_INFO);
        }
        
    }
}

public class Client
{
    /* Connection information */
    private ConnectionInfo connInfo;

    /* TODO: We should learn some info in here (or do we put it in connInfo)? */
    private string serverName; //TODO: Make use of


    private Socket socket;

    /* Message queues (and handlers) */
    private SList!(ubyte[]) recvQueue, sendQueue;
    private Mutex recvQueueLock, sendQueueLock;
    private Thread recvHandler, sendHandler;

    /* Event engine */
    private Engine engine;

    this(ConnectionInfo connInfo)
    {
        this.connInfo = connInfo;
    }

    ~this()
    {
        //TODO: Do something here, tare downs
    }

    private final enum EventType : ulong
    {
        GENERIC_EVENT = 1,
        PONG_EVENT
    }


    /* TODO: Move to an events.d class */
    private final class IRCEvent : Event
    {   
        private Message msg;

        this(Message msg)
        {
            super(EventType.GENERIC_EVENT, null);

            this.msg = msg;
        }

        public Message getMessage()
        {
            return msg;
        }

        public override string toString()
        {
            return msg.toString();
        }
    }

    /* TODO: make PongEvent (id 2 buit-in) */
    private final class PongEvent : Event
    {
        private string pingID;

        this(string pingID)
        {
            super(EventType.PONG_EVENT);
            this.pingID = pingID;
        }

        public string getID()
        {
            return pingID;
        }
    }

    /**
    * User overridable handler functions below
    */
    public void onChannelMessage(Message fullMessage, string channel, string msgBody)
    {
        /* Default implementation */
    }
    public void onDirectMessage(Message fullMessage, string nickname, string msgBody)
    {
        /* Default implementation */
    }
    public void onGenericCommand(Message message)
    {
        /* Default implementation */
    }
    public void onCommandReply(Reply commandReply)
    {
        /* Default implementation */
    }

    /* Reply object */
    private enum ReplyType : ulong
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
        ERR_BADCHANMASK = 476
    }

    private struct Reply
    {
        /* Whether this numeric reply is an error type */
        public bool isError = false;

        /* The numeric reply */
        public ReplyType replyType;

        /* Params */
        public string params;
    }


    /* TODO: Decide on object to return */
    // public string


    /**
    * User operations (request-response type)
    */
    public void joinChannel(string channel)
    {
        /* TODO: Expect a reply here with some queuing mechanism */

        /* Join the channel */
        sendMessage("JOIN "~channel);
    }

    // private void makeRequest()

    /** 
     * Issue a generic command
     */
    public void command(Message message)
    {
        /* Encode according to EBNF format */
        // TODO: Validty check
        // TODO: Make `Message.encode()` actually encode instead of empty string
        string stringToSend = message.encode();

        /* Send the message */
        sendMessage(stringToSend);
    }


    /**
    * Initialize the event handlers
    */
    private void initEvents()
    {
        /* TODO: For now we just register one signal type for all messages */

        /* Register all event types */
        engine.addQueue(EventType.GENERIC_EVENT);
        engine.addQueue(EventType.PONG_EVENT);


        /* Base signal with IRC client in it */
        abstract class BaseSignal : Signal
        {
            /* ICR client */
            private Client client;

            this(Client client, ulong[] eventIDs)
            {
                super(eventIDs);
                this.client = client;
            }
        }


        /* Handles all IRC messages besides PING */
        class GenericSignal : BaseSignal
        {
            this(Client client)
            {
                super(client, [EventType.GENERIC_EVENT]);
            }
            
            public override void handler(Event e)
            {
                /* TODO: Insert cast here to our custoim type */
                IRCEvent ircEvent = cast(IRCEvent)e;
                assert(ircEvent); //Should never fail, unless some BOZO regged multiple handles for 1 - wait idk does eventy do that even mmm

                logger.log("IRCEvent(message): "~ircEvent.getMessage().toString());

                /* TODO: We should use a switch statement, imagine how nice */
                Message ircMessage = ircEvent.getMessage();
                string command = ircMessage.getCommand();
                string params = ircMessage.getParams();

                if(cmp(command, "PRIVMSG") == 0)
                {
                    /* Split up into (channel/nick) and (message)*/
                    long firstSpaceIdx = indexOf(command, " "); //TODO: validity check;
                    string chanNick = params[0..firstSpaceIdx];

                    /**
                    * TODO: Implement message fetching here and decide whether isChannel message
                    * or private message
                    */
                    string message;
                }
                // If the command is numeric then it is a reply of some sorts
                else if(isNumeric(command))
                {
                    /* Reply */
                    Reply reply;
                    reply.params = params;
                    
                    /* Grab the code */
                    ReplyType code = to!(ReplyType)(command);
                    // TODO: Add validity check on range of values here, if bad throw exception
                    // TODO: Add check for "6.3 Reserved numerics" or handling of SOME sorts atleast

                    /* Error codes are in range of [401, 502] */
                    if(code >= 401 && code <= 502)
                    {
                        // TODO: Call error handler
                        reply.isError = true;
                    }
                    /* Command replies are in range of [259, 395] */
                    else if(code >= 259 && code <= 395)
                    {
                        // TODO: Call command-reply handler
                        reply.isError = false;
                    }

                    
                    /* Call the command reply handler */
                    onCommandReply(reply);
                }
                /* Generic handler */
                else
                {
                    onGenericCommand(ircMessage);
                }
                
                //TODO: add more commands

            }
        }
        engine.addSignalHandler(new GenericSignal(this));

        /* Handles PING messages */
        class PongSignal : BaseSignal
        {
            this(Client client)
            {
                super(client, [EventType.PONG_EVENT]);
            }

            /* Send a PONG back with the received PING id */
            public override void handler(Event e)
            {
                PongEvent pongEvent = cast(PongEvent)e;
                assert(pongEvent);

                string messageToSend = "PONG "~pongEvent.getID();
                client.sendMessage(messageToSend);
                logger.log("Ponged");
            }
        }
        engine.addSignalHandler(new PongSignal(this));
    }

    /**
    * Connects to the server
    */
    public void connect()
    {
        if(socket is null)
        {
            try
            {
                /* Attempt to connect */
                this.socket = new Socket(connInfo.getAddr().addressFamily(), SocketType.STREAM, ProtocolType.TCP);
                this.socket.connect(connInfo.getAddr());

                /* Initialize queue locks */
                this.recvQueueLock = new Mutex();
                this.sendQueueLock = new Mutex();

                /* Start the event engine */
                this.engine = new Engine();
                this.engine.start();

                /* Regsiter default handler */
                initEvents();

                /* TODO: Clean this up and place elsewhere */
                this.recvHandler = new Thread(&recvHandlerFunc);
                this.recvHandler.start();

                this.sendHandler = new Thread(&sendHandlerFunc);
                this.sendHandler.start();

                
            }
            catch(SocketOSException e)
            {
                throw new BirchwoodException(BirchwoodException.ErrorType.CONNECT_ERROR);
            }
        }
        else
        {
            throw new BirchwoodException(BirchwoodException.ErrorType.ALREADY_CONNECTED);
        }
    }


    ulong j = 0;
    // bool f = true;

    /**
    * We need to create a queue of messages and then have a seperate thread
    * go through them, such as replying to pings etc.
    *
    * We should maybe have two quues, urgent ones (for pings coming in)
    * of which we check first and then everything else into another queue
    */
    private void receiveQ(ubyte[] message)
    {
        /* Lock queue */
        recvQueueLock.lock();

        /* Add to queue */
        recvQueue.insertAfter(recvQueue[], message);

        /* Unlock queue */
        recvQueueLock.unlock();
    }

    /* TODO: Spawn a thread worker that reacts */

    /**
    * This function is run as part of the "reactor"
    * thread and its job is to effectively dequeue
    * messages from the receive queue and call the
    * correct handler function with the message as
    * the event payload.
    *
    * It pays high priority to looking for a PING
    * message first and handling those and then doing
    * a second pass for other messages
    *
    * TODO: Do decode here and triggering of events here
    */
    private void recvHandlerFunc()
    {
        while(true)
        {
            /* Lock the receieve queue */
            recvQueueLock.lock();

            /* Message being analysed */
            Message curMsg;

            /* Search for a PING */
            ubyte[] pingMessage;

            ulong pos = 0;
            foreach(ubyte[] message; recvQueue[])
            {
                if(indexOf(cast(string)message, "PING") > -1)
                {
                    pingMessage = message;
                    recvQueue.linearRemoveElement(message);
                    break;
                }

                



                pos++;
            }


            /**
            * TODO: Plan of action
            *
            * 1. Firstly, we must run `parseReceivedMessage()` on the dequeued
            *    ping message (if any)
            * 2. Then (if there was a PING) trigger said PING handler
            * 3. Normal message handling; `parseReceivedMessage()` on one of the messages
            * (make the dequeue amount configurable possibly)
            * 4. Trigger generic handler
            * 5. We might need to also have a queue for commands ISSUED and command-replies
            *    RECEIVED and then match those first and do something with them (tasky-esque)
            * 6. We can just make a generic reply queue of these things - we have to maybe to this
            * - we can cache or remember stuff when we get 353
            */

            


            /* If we found a PING */
            if(pingMessage.length > 0)
            {
                /* Decode the message and parse it */
                curMsg = Message.parseReceivedMessage(decodeMessage(pingMessage));
                logger.log("Found a ping: "~curMsg.toString());

                // string ogMessage = cast(string)pingMessage;
                // long idxSigStart = indexOf(ogMessage, ":")+1;
                // long idxSigEnd = lastIndexOf(ogMessage, '\r');

                // string pingID = ogMessage[idxSigStart..idxSigEnd];
                string pingID = curMsg.getParams();


                // this.socket.send(encodeMessage("PONG "~pingID));
                // string messageToSend = "PONG "~pingID;

                // sendMessage(messageToSend);

                // logger.log("Ponged");

                /* TODO: Implement */
                Event pongEvent = new PongEvent(pingID);
                engine.push(pongEvent);
            }

            /* Now let's go message by message */
            if(!recvQueue.empty())
            {
                ubyte[] message = recvQueue.front();

                /* Decode message */
                string messageNormal = decodeMessage(message);

                recvQueue.linearRemoveElement(recvQueue.front());

                // writeln("Normal message: "~messageNormal);

                

                /* TODO: Parse message and call correct handler */
                curMsg = Message.parseReceivedMessage(messageNormal);

                Event ircEvent = new IRCEvent(curMsg);
                engine.push(ircEvent);
            }



            /* Unlock the receive queue */
            recvQueueLock.unlock();

            /* TODO: Threading yield here */
            Thread.yield();
        }
    }

    private void sendHandlerFunc()
    {
        /* TODO: Hoist up into ConnInfo */
        ulong fakeLagInBetween = 1;

        while(true)
        {

            /* TODO: handle normal messages (xCount with fakeLagInBetween) */

            /* Lock queue */
            sendQueueLock.lock();

            foreach(ubyte[] message; sendQueue[])
            {
                this.socket.send(message);
                Thread.sleep(dur!("seconds")(fakeLagInBetween));
            }

            /* Empty the send queue */
            sendQueue.clear();

            /* Unlock queue */
            sendQueueLock.unlock();

            /* TODO: Yield */
            Thread.yield();
        }
    }


    /**
    * TODO: Make send queue which is used on another thread to send messages
    *
    * This allows us to intrpoduce fakelag and also prioritse pongs (we should
    * send them via here)
    */
    private void sendMessage(string messageOut)
    {
        /* Encode the mesage */
        ubyte[] encodedMessage = encodeMessage(messageOut);

        /* Lock queue */
        sendQueueLock.lock();

        /* Add to queue */
        sendQueue.insertAfter(sendQueue[], encodedMessage);

        /* Unlock queue */
        sendQueueLock.unlock();
    }

    /* TODO: For commands with an expected reply */
    // private SList!()
    private Object ask()
    {
        return  null;
    }


    bool yes = true;
    bool hasJoined = false;

    private void processMessage(ubyte[] message)
    {
        // import std.stdio;
        // logger.log("Message length: "~to!(string)(message.length));
        // logger.log("InterpAsString: "~cast(string)message);

        receiveQ(message);



        /* FIXME: Move all the below code into a testing method !! */

        
        j++;

        if(j >= 3)
        {
            // import core.thread;
            //  Thread.sleep(dur!("seconds")(10));

            

            
            if(yes)
            {
                // this.socket.send((cast(ubyte[])"CAP LS")~[cast(ubyte)13, cast(ubyte)10]);
                import core.thread;
                Thread.sleep(dur!("seconds")(2));

                this.socket.send((cast(ubyte[])"NICK birchwood")~[cast(ubyte)13, cast(ubyte)10]);

                import core.thread;
                Thread.sleep(dur!("seconds")(2));
                this.socket.send((cast(ubyte[])"USER doggie doggie irc.frdeenode.net :Tristan B. Kildaire")~[cast(ubyte)13, cast(ubyte)10]);

                yes=false;
            }
            else
            {
                if(hasJoined == false)
                {
                     import core.thread;
                Thread.sleep(dur!("seconds")(4));
                    this.socket.send((cast(ubyte[])"join #birchwoodtesting")~[cast(ubyte)13, cast(ubyte)10]);
                    hasJoined = true;

                    import core.thread;
                Thread.sleep(dur!("seconds")(2));

                sendMessage("names");
                }
            }
            

            //  this.socket.send((cast(ubyte[])"PONG irc.freenode.net")~[cast(ubyte)13, cast(ubyte)10]);

            // import core.thread;
            //  Thread.sleep(dur!("seconds")(2));
                // this.socket.send((cast(ubyte[])"join #birchwoodtesting")~[cast(ubyte)13, cast(ubyte)10]);

                // yes=false;
        }
        
    }

    /** 
     * TODO: Determine how we want to do this
     *
     * This simply receives messages from the server,
     * parses them and puts them into the receive queue
     */
    public void loop()
    {
        /* TODO: We could do below but nah for now as we know max 512 bytes */
        /* TODO: Make the read bulk size a configurable parameter */
        /* TODO: Make static array allocation outside, instead of a dynamic one */
        // ulong bulkReadSize = 20;

        /* Fixed allocation of `bulkReadSize` for temporary data */
        ubyte[] currentData;
        currentData.length = connInfo.getBulkReadSize();

        // malloc();

        /* Total built message */
        ubyte[] currentMessage;

        bool hasCR = false;

        /** 
         * Message loop
         */
        while(true)
        {
            /* Receieve at most 512 bytes (as per RFC) */
            ptrdiff_t bytesRead = socket.receive(currentData, SocketFlags.PEEK);

            import std.stdio;
            // writeln(bytesRead);
            // writeln(currentData);

            /* FIXME: CHECK BYTES READ FOR SOCKET ERRORS! */

            /* If we had a CR previously then now we need a LF */
            if(hasCR)
            {
                /* First byte following it should be LF */
                if(currentData[0] == 10)
                {
                    /* Add to the message */
                    currentMessage~=currentData[0];

                    /* TODO: Process mesaage */
                    processMessage(currentMessage);

                    /* Reset state for next message */
                    currentMessage.length = 0;
                    hasCR=false;

                    /* Chop off the LF */
                    ubyte[] scratch;
                    scratch.length = 1;
                    this.socket.receive(scratch);

                    continue;
                }
                else
                {
                    /* TODO: This is an error */
                    assert(false);
                }
            }

            ulong pos;
            for(pos = 0; pos < bytesRead; pos++)
            {
                /* Find first CR */
                if(currentData[pos] == 13)
                {
                    /* If we already have CR then that is an error */
                    if(hasCR)
                    {
                        /* TODO: Handle this */
                        assert(false);
                    }

                    hasCR = true;
                    break;
                }
            }

            /* If we have a CR, then read up to that */
            if(hasCR)
            {
                /* Read up to CR */
                currentMessage~=currentData[0..pos+1];

                /* Dequeue this (TODO: way to dispose without copy over) */
                /* Guaranteed as we peeked this lenght */
                ubyte[] scratch;
                scratch.length = pos+1;
                this.socket.receive(scratch);
                continue;
            }

            /* Add whatever we have read to build-up */
            currentMessage~=currentData[0..bytesRead];

            /* TODO: Dequeue without peek after this */
            ubyte[] scratch;
            scratch.length = bytesRead;
            this.socket.receive(scratch);


            
            /* TODO: Yield here and in other places before continue */

        }
    }

    unittest
    {
        /* FIXME: Get domaina name resolution support */
        // ConnectionInfo connInfo = ConnectionInfo.newConnection("irc.freenode.net", 6667, "testBirchwood");
        //freenode: 149.28.246.185
        //snootnet: 178.62.125.123
        //bonobonet: fd08:8441:e254::5
        ConnectionInfo connInfo = ConnectionInfo.newConnection("149.28.246.185", 6667, "testBirchwood");
        Client client = new Client(connInfo);

        client.connect();

        client.loop();


    }


}