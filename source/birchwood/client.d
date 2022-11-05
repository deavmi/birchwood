module birchwood.client;

import std.socket : Socket, SocketException, Address, parseAddress, SocketType, ProtocolType, SocketOSException;
import std.socket : SocketFlags;
import std.conv : to;
import std.container.slist : SList;
import core.sync.mutex : Mutex;
import core.thread : Thread, dur;
import std.string;
import eventy;
import birchwood.messages : Message, encodeMessage, decodeMessage, ReplyType;

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

    /* The quit message */
    public const string quitMessage;

    /* TODO: before publishing change this bulk size */
    private this(Address addrInfo, string nickname, ulong bulkReadSize = 20, string quitMessage = "birchwood client disconnecting...")
    {
        this.addrInfo = addrInfo;
        this.nickname = nickname;
        this.bulkReadSize = bulkReadSize;
        this.quitMessage = quitMessage;
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

public final class Client : Thread
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
        super(&loop);
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
        logger.log("Channel("~channel~"): "~msgBody);
    }
    public void onDirectMessage(Message fullMessage, string nickname, string msgBody)
    {
        /* Default implementation */
        logger.log("DirectMessage("~nickname~"): "~msgBody);
    }
    public void onGenericCommand(Message message)
    {
        /* Default implementation */
        logger.log("Generic("~message.getCommand()~"): "~message.getParams());
    }
    public void onCommandReply(Message commandReply)
    {
        /* Default implementation */
        logger.log("Response("~to!(string)(commandReply.replyType)~"): "~commandReply.toString());
    }




    /* TODO: Decide on object to return */
    // public string


    /**
    * User operations (request-response type)
    */
    public void joinChannel(string channel)
    {
        /* Join the channel */
        sendMessage("JOIN "~channel);
    }
    public void directMessage(string[] recipients)
    {
        //TODO: Implement
    }
    public void channelMessage(string channel)
    {
        //TODO: Implement
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
                else if(ircMessage.isResponse)
                {
                    /* Call the command reply handler */
                    onCommandReply(ircMessage);
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

                /* Start socket loop */
                this.start();

                
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

    private void processMessage(ubyte[] message)
    {
        // import std.stdio;
        // logger.log("Message length: "~to!(string)(message.length));
        // logger.log("InterpAsString: "~cast(string)message);

        receiveQ(message);
    }

    /** 
     * TODO: Determine how we want to do this
     *
     * This simply receives messages from the server,
     * parses them and puts them into the receive queue
     */
    private void loop()
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


        import core.thread;
        Thread.sleep(dur!("seconds")(2));
        client.command(new Message("", "NICK", "birchwood"));

        Thread.sleep(dur!("seconds")(2));
        client.command(new Message("", "USER", "doggie doggie irc.frdeenode.net :Tristan B. Kildaire"));
        
        Thread.sleep(dur!("seconds")(4));
        client.command(new Message("", "JOIN", "#birchwoodtesting"));
        
        Thread.sleep(dur!("seconds")(2));
        client.command(new Message("", "NAMES", ""));


        /* TODO: Add a check here to make sure the above worked I guess? */
        /* TODO: Make this end */
        // while(true)
        // {

        // }


    }


}