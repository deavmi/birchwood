module birchwood.client;

import std.socket : Socket, SocketException, Address, parseAddress, SocketType, ProtocolType, SocketOSException;
import std.socket : SocketFlags;
import std.conv : to;
import std.container.slist : SList;
import core.sync.mutex : Mutex;
import core.thread : Thread, dur;
import std.string;
import eventy;

// TODO: Remove this import
import std.stdio : writeln;

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

    class IRCEvent : Event
        {
            private string message;

            this(ulong typeID, ubyte[] payload)
            {
                super(typeID, payload);

                /* TODFO: actuially parse message here */
                this.message = cast(string)payload;
            }

            public string getMessage()
            {
                return message;
            }
        }

    private void initEvents()
    {
        /* TODO: For now we just register one signal type for all messages */
        ulong signalDefault = 1;
        engine.addQueue(signalDefault);

        


        /* TODO: We also add default signal handler which will just print stuff out */
        class SignalHandler1 : Signal
        {
            this()
            {
                super([1]);
            }
            
            public override void handler(Event e)
            {
                /* TODO: Insert cast here to our custoim type */
                IRCEvent ircEvent = cast(IRCEvent)e;
                assert(ircEvent); //Should never fail, unless some BOZO regged multiple handles for 1 - wait idk does eventy do that even mmm
                import std.stdio;
                writeln("IRCEvent (id): "~to!(string)(ircEvent.id));
                writeln("IRCEvent (payload): "~to!(string)(ircEvent.getMessage));
            }
        }

        Signal j = new SignalHandler1();
        engine.addSignalHandler(j);
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

    private static ubyte[] encodeMessage(string messageIn)
    {
        ubyte[] messageOut = cast(ubyte[])messageIn;
        messageOut~=[cast(ubyte)13, cast(ubyte)10];
        return messageOut;
    }

    private static string decodeMessage(ubyte[] messageIn)
    {
        /* TODO: We could do a chekc to ESNURE it is well encoded */

        return cast(string)messageIn[0..messageIn.length-2];
        // return  null;
    }


    private void defaultHandler(string from, string command, string params)
    {

    }

    // private
    private void function() getHandler()
    {
        /* The chosen handler */
        void function() handlerPtr;


        return handlerPtr;
    }

    /* TODO: Implement me */
    private void parseReceivedMessage(string message)
    {
        /* TODO: testing */
        Event eTest = new IRCEvent(1, cast(ubyte[])message);
        engine.push(eTest);




        /* Command */
        string command;

        /* Check if there is a PREFIX (according to RFC 1459) */
        if(message[0] == ':')
        {
            /* prefix ends after first space (we fetch servername, host/user) */
            //TODO: make sure not -1
            long firstSpace = indexOf(message, ' ');

            /* TODO: double check the condition */
            if(firstSpace > 0)
            {
                string from = message[1..firstSpace];

                writeln("from: "~from);

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
                writeln("command: "~command);
            }
            else
            {
                //TODO: handle
                writeln("Malformed message start after :");
                assert(false);
            }

            
        }
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
    */
    private void recvHandlerFunc()
    {
        while(true)
        {
            /* Lock the receieve queue */
            recvQueueLock.lock();


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



            /* If we found a PING */
            if(pingMessage.length > 0)
            {
                writeln("Found a ping: "~cast(string)pingMessage);
                string ogMessage = cast(string)pingMessage;
                long idxSigStart = indexOf(ogMessage, ":")+1;
                long idxSigEnd = lastIndexOf(ogMessage, '\r');

                string pingID = ogMessage[idxSigStart..idxSigEnd];


                // this.socket.send(encodeMessage("PONG "~pingID));

                string messageToSend = "PONG "~pingID;

                sendMessage(messageToSend);
            }

            /* Now let's go message by message */
            if(!recvQueue.empty())
            {
                ubyte[] message = recvQueue.front();

                /* Decode message */
                string messageNormal = decodeMessage(message);

                recvQueue.linearRemoveElement(recvQueue.front());

                writeln("Normal message: "~messageNormal);

                

                /* TODO: Parse message and call correct handler */
                parseReceivedMessage(messageNormal);
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
            sendQueueLock.lock();

            foreach(ubyte[] message; sendQueue[])
            {
                this.socket.send(message);
                Thread.sleep(dur!("seconds")(fakeLagInBetween));
            }

            sendQueue.clear();

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


    bool yes = true;
    bool hasJoined = false;

    private void processMessage(ubyte[] message)
    {
        // import std.stdio;
        // writeln("Message length: "~to!(string)(message.length));
        // writeln("InterpAsString: "~cast(string)message);

        receiveQ(message);

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
                this.socket.send((cast(ubyte[])"USER doggie doggie irc.freenode.net :Tristan B. Kildaire")~[cast(ubyte)13, cast(ubyte)10]);

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