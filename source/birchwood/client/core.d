module birchwood.client.core;

import std.socket : Socket, SocketException, Address, getAddress, SocketType, ProtocolType, SocketOSException;
import std.socket : SocketFlags;
import std.conv : to;
import std.container.slist : SList;
import core.sync.mutex : Mutex;
import core.thread : Thread, dur;
import std.string;
import eventy;
import birchwood.messages : Message, encodeMessage, decodeMessage, isValidText;
import birchwood.constants : ReplyType;

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
        CONNECT_ERROR,
        EMPTY_PARAMS,
        INVALID_CHANNEL_NAME,
        INVALID_NICK_NAME,
        ILLEGAL_CHARACTERS
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

    /** 
     * Creates a ConnectionInfo struct representing a client configuration which
     * can be provided to the Client class to create a new connection based on its
     * parameters
     *
     * Params:
     *   hostname = hostname of the server
     *   port = server port
     *   nickname = nickname to use
     * Returns: ConnectionInfo for this server
     */
    public static ConnectionInfo newConnection(string hostname, ushort port, string nickname)
    {
        try
        {
            /* Attempt to resolve the address (may throw SocketException) */
            Address[] addrInfo = getAddress(hostname, port);

            /* Username check */
            if(!nickname.length)
            {
                throw new BirchwoodException(BirchwoodException.ErrorType.INVALID_CONN_INFO);
            }

            /* TODO: Add feature to choose which address to use, prefer v4 or v6 type of thing */
            Address chosenAddress = addrInfo[0];

            return ConnectionInfo(chosenAddress, nickname);
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

// TODO: Make abstract and for unit tests make a `DefaultClient`
// ... which logs outputs for the `onX()` handler functions
public class Client : Thread
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

    private bool running = false;

    this(ConnectionInfo connInfo)
    {
        super(&loop);
        this.connInfo = connInfo;
    }

    ~this()
    {
        //TODO: Do something here, tare downs
    }

    private final enum IRCEventType : ulong
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
            super(IRCEventType.GENERIC_EVENT);

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
            super(IRCEventType.PONG_EVENT);
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
        logger.log("Generic("~message.getCommand()~", "~message.getFrom()~"): "~message.getParams());
    }
    public void onCommandReply(Message commandReply)
    {
        /* Default implementation */
        logger.log("Response("~to!(string)(commandReply.getReplyType())~", "~commandReply.getFrom()~"): "~commandReply.toString());
    }

    /**
    * User operations (request-response type)
    */

    /** 
     * Joins the requested channel
     *
     * Params:
     *   channel = the channel to join
     * Throws:
     *   BirchwoodException on invalid channel name
     */
    public void joinChannel(string channel)
    {
        /* Ensure no illegal characters in channel name */
        if(isValidText(channel))
        {
            /* Channel name must start with a `#` */
            if(channel[0] == '#')
            {
                /* Join the channel */
                sendMessage("JOIN "~channel);
            }
            else
            {
                throw new BirchwoodException(BirchwoodException.ErrorType.INVALID_CHANNEL_NAME);
            }
        }
        else
        {
            throw new BirchwoodException(BirchwoodException.ErrorType.ILLEGAL_CHARACTERS);
        }
    }

    /** 
     * Parts from a list of channel(s) in one go
     *
     * Params:
     *   channels = the list of channels to part from
     * Throws:
     *   BirchwoodException if the channels list is empty
     */
    public void leaveChannel(string[] channels)
    {
        // TODO: Add check for valid and non-empty channel names

        /* If single channel */
        if(channels.length == 1)
        {
            /* Leave the channel */
            leaveChannel(channels[0]);
        }
        /* If multiple channels */
        else if(channels.length > 1)
        {
            string channelLine = channels[0];

            /* Ensure valid characters in first channel */
            if(isValidText(channelLine))
            {
                //TODO: Add check for #

                /* Append on a trailing `,` */
                channelLine ~= ",";

                for(ulong i = 1; i < channels.length; i++)
                {
                    string currentChannel = channels[i];

                    /* Ensure the character channel is valid */
                    if(isValidText(currentChannel))
                    {
                        //TODO: Add check for #
                        
                        if(i == channels.length-1)
                        {
                            channelLine~=currentChannel;
                        }
                        else
                        {
                            channelLine~=currentChannel~",";
                        }
                    }
                    else
                    {
                        throw new BirchwoodException(BirchwoodException.ErrorType.ILLEGAL_CHARACTERS);
                    }
                }

                /* Leave multiple channels */
                sendMessage("PART "~channelLine);
            }
            else
            {
                throw new BirchwoodException(BirchwoodException.ErrorType.ILLEGAL_CHARACTERS);
            }
        }
        /* If no channels provided at all (error) */
        else
        {
            throw new BirchwoodException(BirchwoodException.ErrorType.EMPTY_PARAMS);
        }
    }

    /** 
     * Part from a single channel
     *
     * Params:
     *   channel = the channel to leave
     */
    public void leaveChannel(string channel)
    {
        // TODO: Add check for valid and non-empty channel names

        /* Leave the channel */
        sendMessage("PART "~channel);
    }

    /** 
     * Sends a direct message to the intended recipients
     *
     * Params:
     *   message = The message to send
     *   recipients = The receipients of the message
     * Throws:
     *   BirchwoodException if the recipients list is empty
     */
    public void directMessage(string message, string[] recipients)
    {
        /* Single recipient */
        if(recipients.length == 1)
        {
            /* Send a direct message */
            directMessage(message, recipients[0]);
        }
        /* Multiple recipients */
        else if(recipients.length > 1)
        {
            /* Ensure message is valid */
            if(isValidText(message))
            {
                string recipientLine = recipients[0];

                /* Ensure valid characters in first recipient */
                if(isValidText(recipientLine))
                {
                    for(ulong i = 1; i < recipients.length; i++)
                    {
                        string currentRecipient = recipients[i];

                        /* Ensure valid characters in the current recipient */
                        if(isValidText(currentRecipient))
                        {
                            if(i == recipients.length-1)
                            {
                                recipientLine~=currentRecipient;
                            }
                            else
                            {
                                recipientLine~=currentRecipient~",";
                            }
                        }
                        else
                        {
                            throw new BirchwoodException(BirchwoodException.ErrorType.ILLEGAL_CHARACTERS);
                        }
                    }

                    /* Send the message */
                    sendMessage("PRIVMSG "~recipientLine~" "~message);
                }
                else
                {
                    throw new BirchwoodException(BirchwoodException.ErrorType.ILLEGAL_CHARACTERS);
                }
            }
            else
            {
                throw new BirchwoodException(BirchwoodException.ErrorType.ILLEGAL_CHARACTERS);
            }          
        }
        /* If no recipients provided at all (error) */
        else
        {
            throw new BirchwoodException(BirchwoodException.ErrorType.EMPTY_PARAMS);
        }
    }

    /** 
     * Sends a direct message to the intended recipient
     *
     * Params:
     *   message = The message to send
     *   recipients = The receipient of the message
     */
    public void directMessage(string message, string recipient)
    {
        //TODO: Add check on recipient

        /* Ensure the message and recipient are valid text */
        if(isValidText(message) && isValidText(recipient))
        {
            /* Ensure the recipient does NOT start with a # (as that is reserved for channels) */
            if(recipient[0] != '#')
            {
                /* Send the message */
                sendMessage("PRIVMSG "~recipient~" "~message);
            }
            else
            {
                throw new BirchwoodException(BirchwoodException.ErrorType.INVALID_NICK_NAME);
            }
        }
        else
        {
            throw new BirchwoodException(BirchwoodException.ErrorType.ILLEGAL_CHARACTERS);
        }
    }

    /** 
     * Sends a channel message to the intended recipients
     *
     * Params:
     *   message = The message to send
     *   recipients = The receipients of the message
     * Throws:
     *   BirchwoodException if the channels list is empty
     */
    public void channelMessage(string message, string[] channels)
    {
        /* If single channel */
        if(channels.length == 1)
        {
            /* Send to a single channel */
            channelMessage(message, channels[0]);
        }
        /* If multiple channels */
        else if(channels.length > 1)
        {
            /* Ensure message is valid */
            if(isValidText(message))
            {
                string channelLine = channels[0];    

                /* Ensure valid characters in first channel */
                if(isValidText(channelLine))
                {
                    /* Append on a trailing `,` */
                    channelLine ~= ",";

                    for(ulong i = 1; i < channels.length; i++)
                    {
                        string currentChannel = channels[i];

                        /* Ensure valid characters in current channel */
                        if(isValidText(currentChannel))
                        {
                            if(i == channels.length-1)
                            {
                                channelLine~=currentChannel;
                            }
                            else
                            {
                                channelLine~=currentChannel~",";
                            }
                        }
                        else
                        {
                            throw new BirchwoodException(BirchwoodException.ErrorType.ILLEGAL_CHARACTERS);
                        }
                    }

                    /* Send to multiple channels */
                    sendMessage("PRIVMSG "~channelLine~" "~message);
                }
                else
                {
                    throw new BirchwoodException(BirchwoodException.ErrorType.ILLEGAL_CHARACTERS);
                }
            }
            else
            {
                throw new BirchwoodException(BirchwoodException.ErrorType.ILLEGAL_CHARACTERS);
            }
        }
        /* If no channels provided at all (error) */
        else
        {
            throw new BirchwoodException(BirchwoodException.ErrorType.EMPTY_PARAMS);
        }
    }

    /** 
     * Sends a message to a given channel
     *
     * Params:
     *   message = The message to send
     *   channel = The channel to send the message to
     */
    public void channelMessage(string message, string channel)
    {
        //TODO: Add check on recipient
        //TODO: Add emptiness check
        if(isValidText(message) && isValidText(channel))
        {
            if(channel[0] == '#')
            {
                /* Send the channel message */
                sendMessage("PRIVMSG "~channel~" "~message);
            }
            else
            {
                //TODO: Invalid channel name
                throw new BirchwoodException(BirchwoodException.ErrorType.INVALID_CHANNEL_NAME);
            }
        }
        else
        {
            //TODO: Illegal characters
            throw new BirchwoodException(BirchwoodException.ErrorType.ILLEGAL_CHARACTERS);
        }
    }

    /** 
     * Issues a command to the server
     *
     * Params:
     *   message = the Message object containing the command to issue
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
        engine.addEventType(new EventType(IRCEventType.GENERIC_EVENT));
        engine.addEventType(new EventType(IRCEventType.PONG_EVENT));


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
                super(client, [IRCEventType.GENERIC_EVENT]);
            }
            
            public override void handler(Event e)
            {
                /* TODO: Insert cast here to our custoim type */
                IRCEvent ircEvent = cast(IRCEvent)e;
                assert(ircEvent); //Should never fail, unless some BOZO regged multiple handles for 1 - wait idk does eventy do that even mmm
    
                // NOTE: Enable this when debugging
                // logger.log("IRCEvent(message): "~ircEvent.getMessage().toString());

                /* TODO: We should use a switch statement, imagine how nice */
                Message ircMessage = ircEvent.getMessage();
                string command = ircMessage.getCommand();
                string params = ircMessage.getParams();


                if(cmp(command, "PRIVMSG") == 0)
                {
                    /* Split up into (channel/nick) and (message)*/
                    long firstSpaceIdx = indexOf(params, " "); //TODO: validity check;
                    string chanNick = params[0..firstSpaceIdx];

                    /* Extract the message from params */
                    long firstColonIdx = indexOf(params, ":"); //TODO: validity check
                    string message = params[firstColonIdx+1..params.length];

                    /* If it starts with `#` then channel */
                    if(chanNick[0] == '#')
                    {
                        /* Call the channel message handler */
                        onChannelMessage(ircMessage, chanNick, message);
                    } 
                    /* Else, direct message */
                    else
                    {
                        /* Call the direct message handler */
                        onDirectMessage(ircMessage, chanNick, message);
                    }
                }
                // If the command is numeric then it is a reply of some sorts
                else if(ircMessage.isResponseMessage())
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
                super(client, [IRCEventType.PONG_EVENT]);
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

    /** 
     * Connects to the server
     *
     * Throws: BirchwoodException
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

                /* Regsiter default handler */
                initEvents();

                /* TODO: Clean this up and place elsewhere */
                this.recvHandler = new Thread(&recvHandlerFunc);
                this.recvHandler.start();

                this.sendHandler = new Thread(&sendHandlerFunc);
                this.sendHandler.start();

                /* Set running sttaus to true */
                running = true;

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


    /** 
     * Adds a given message onto the receieve queue for
     * later processing by the receieve queue worker thread
     *
     * Params:
     *   message = the message to enqueue to the receieve queue
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

    /** 
     * The receive queue worker function
     *
     * This has the job of dequeuing messages
     * in the receive queue, decoding them
     * into Message objects and then emitting
     * an event depending on the type of message
     *
     * Handles PINGs along with normal messages
     *
     * TODO: Our high load average is from here
     * ... it is getting lock a lot and spinning here
     * ... we should use libsnooze to avoid this
     */
    private void recvHandlerFunc()
    {
        while(running)
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
                // TODO: Remove the Eventy push and replace with a handler call (on second thought no)
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

                // TODO: Remove the Eventy push and replace with a handler call (on second thought no)
                Event ircEvent = new IRCEvent(curMsg);
                engine.push(ircEvent);
            }



            /* Unlock the receive queue */
            recvQueueLock.unlock();

            /* TODO: Threading yield here */
            Thread.yield();
        }
    }

    /** 
     * The send queue worker function
     *
     * TODO: Same issue as recvHandlerFunc
     * ... we should I/O wait (sleep) here
     */
    private void sendHandlerFunc()
    {
        /* TODO: Hoist up into ConnInfo */
        ulong fakeLagInBetween = 1;

        while(running)
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
    
    /** 
     * Sends a message to the server by enqueuing it on
     * the client-side send queue
     *
     * Params:
     *   messageOut = the message to send
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

    /** 
     * Disconnect from the IRC server gracefully
     */
    public void quit()
    {
        /* Generate the quit command using the custom quit message */
        Message quitCommand = new Message("", "QUIT", connInfo.quitMessage);
        sendMessage(quitCommand.encode());

        /* TODO: I don't know how long we should wait here */
        Thread.sleep(dur!("seconds")(1));

        /* Tare down the client */
        disconnect();
    }

    /** 
     * Tare down the client by setting the run state
     * to false, closing the socket, stopping the
     * receieve and send handlers and the event engine
     */
    private void disconnect()
    {
        /* Set the state of running to false */
        running = false;
        logger.log("disconnect() begin");

        /* Close the socket */
        socket.close();
        logger.log("disconnect() socket closed");

        /* Wait for reeceive handler to realise it needs to stop */
        recvHandler.join();
        logger.log("disconnect() recvHandler stopped");

        /* Wait for the send handler to realise it needs to stop */
        sendHandler.join();
        logger.log("disconnect() sendHandler stopped");

        /* TODO: Stop eventy (FIXME: I don't know if this is implemented in Eventy yet, do this!) */
        engine.shutdown();
        logger.log("disconnect() eventy stopped");

        logger.log("disconnect() end");
    }

    /** 
     * Called by the main loop thread to process the received
     * and CRLF-delimited message
     *
     * Params:
     *   message = the message to add to the receive queue
     */
    private void processMessage(ubyte[] message)
    {
        // import std.stdio;
        // logger.log("Message length: "~to!(string)(message.length));
        // logger.log("InterpAsString: "~cast(string)message);

        receiveQ(message);
    }

    /** 
     * The main loop for the Client thread which receives data
     * sent from the server
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
         *
         * FIXME: We need to find a way to tare down this socket, we don't
         * want to block forever after running quit
         */
        while(running)
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
        ConnectionInfo connInfo = ConnectionInfo.newConnection("worcester.community.deavmi.crxn", 6667, "testBirchwood");
        Client client = new Client(connInfo);

        client.connect();


        import core.thread;
        Thread.sleep(dur!("seconds")(2));
        client.command(new Message("", "NICK", "birchwood"));

        Thread.sleep(dur!("seconds")(2));
        client.command(new Message("", "USER", "doggie doggie irc.frdeenode.net :Tristan B. Kildaire"));
        
        Thread.sleep(dur!("seconds")(4));
        // client.command(new Message("", "JOIN", "#birchwood"));
        client.joinChannel("#birchwood");
        // TODO: Add a joinChannels(string[])
        client.joinChannel("#birchwood2");
        client.joinChannel("#birchwoodLeave1");
        client.joinChannel("#birchwoodLeave2");
        client.joinChannel("#birchwoodLeave3");
        
        Thread.sleep(dur!("seconds")(2));
        client.command(new Message("", "NAMES", ""));

        Thread.sleep(dur!("seconds")(2));
        client.command(new Message("", "PRIVMSG", "#birchwood naai"));

        Thread.sleep(dur!("seconds")(2));
        client.command(new Message("", "PRIVMSG", "deavmi naai"));


        /**
         * Test sending a message to a single channel (multi)
         */
        client.channelMessage("This is a test message sent to a channel 1", ["#birchwood"]);

        /**
         * Test sending a message to a single channel (singular)
         */
        client.channelMessage("This is a test message sent to a channel 2", "#birchwood");

        /**
         * Test sending a message to multiple channels (multi)
         */
        client.channelMessage("This is a message sent to multiple channels one-shot", ["#birchwood", "#birchwood2"]);

        /* TODO: Add a check here to make sure the above worked I guess? */
        /* TODO: Make this end */
        // while(true)
        // {

        // }

        /**
         * Test sending a message to myself (singular)
         */
        client.directMessage("Message to myself", "birchwood");

        
        /**
         * Test leaving multiple channels (multi)
         */
        Thread.sleep(dur!("seconds")(2));
        client.leaveChannel(["#birchwood", "#birchwood2"]);

        /**
         * Test leaving a single channel (singular)
         */
        client.leaveChannel("#birchwoodLeave1");

        /**
         * Test leaving a single channel (multi)
         */
        client.leaveChannel(["#birchwoodLeave2"]);

        // TODO: Don't forget to re-enable this when done testing!
        Thread.sleep(dur!("seconds")(15));
        client.quit();


    }


}