module birchwood.client.client;

import std.socket : Socket, SocketException, Address, getAddress, SocketType, ProtocolType, SocketOSException;
import std.socket : SocketFlags;
import std.conv : to;
import std.container.slist : SList;
import core.sync.mutex : Mutex;
import core.thread : Thread, dur;
import std.string;
import eventy : EventyEvent = Event, Engine, EventType, Signal;
import birchwood.config : ConnectionInfo;
import birchwood.client.exceptions : BirchwoodException, ErrorType;
import birchwood.protocol.messages : Message, encodeMessage, decodeMessage, isValidText;

import birchwood.client.receiver : ReceiverThread;
import birchwood.client.sender : SenderThread;
import birchwood.client.events;

import dlog;

package __gshared Logger logger;
__gshared static this()
{
    logger = new DefaultLogger();
}

// TODO: Make abstract and for unit tests make a `DefaultClient`
// ... which logs outputs for the `onX()` handler functions

/** 
 * IRC client
 */
public class Client : Thread
{
    /** 
     * Connection information
     */
    package shared ConnectionInfo connInfo;

    /* TODO: We should learn some info in here (or do we put it in connInfo)? */
    private string serverName; //TODO: Make use of

    /** 
     * Underlying connection to the server
     */
    package Socket socket;

    /** 
     * Receive queue meneger
     */
    private ReceiverThread receiver;

    /** 
     * Send queue manager
     */
    private SenderThread sender;

    /** 
     * Eventy event engine
     */
    package Engine engine;

    package bool running = false;


    /** 
     * Constructs a new IRC client with the given configuration
     * info
     *
     * Params:
     *   connInfo = the connection parameters
     */
    this(ConnectionInfo connInfo)
    {
        super(&loop);
        this.connInfo = connInfo;

        /** 
         * Setups the receiver and sender queue managers
         */
        this.receiver = new ReceiverThread(this);
        this.sender = new SenderThread(this);
    }

    /** 
     * TODO: ANything worth callin on destruction?
     */
    ~this()
    {
        //TODO: Do something here, tare downs
    }

    /** 
     * Retrieve the active configuration at this
     * moment
     *
     * Returns: the ConnectionInfo struct
     */
    public ConnectionInfo getConnInfo()
    {
        return connInfo;
    }
    
    /** 
     * Called on reception of a channel message
     *
     * Params:
     *   fullMessage = the channel message in its entirety
     *   channel = the channel
     *   msgBody = the body of the message
     */
    public void onChannelMessage(Message fullMessage, string channel, string msgBody)
    {
        /* Default implementation */
        logger.log("Channel("~channel~"): "~msgBody);
    }

    /** 
     * Called on reception of a direct message
     *
     * Params:
     *   fullMessage = the direct message in its entirety
     *   nickname = the sender
     *   msgBody = the body of the message
     */
    public void onDirectMessage(Message fullMessage, string nickname, string msgBody)
    {
        /* Default implementation */
        logger.log("DirectMessage("~nickname~"): "~msgBody);
    }

    /** 
     * Called on generic commands
     *
     * Params:
     *   commandReply = the generic message
     */
    public void onGenericCommand(Message message)
    {
        /* Default implementation */
        logger.log("Generic("~message.getCommand()~", "~message.getFrom()~"): "~message.getParams());
    }


    // TODO: Hook certain ones default style with an implemenation
    // ... for things that the client can learn from
    // TODO: comment
    /** 
     * Called on command replies
     *
     * Params:
     *   commandReply = the command's reply
     */
    public void onCommandReply(Message commandReply)
    {
        // TODO: Add numeric response check here for CERTAIN ones which add to client
        // ... state

        /* Default implementation */
        logger.log("Response("~to!(string)(commandReply.getReplyType())~", "~commandReply.getFrom()~"): "~commandReply.toString());

        import birchwood.protocol.constants : ReplyType;

        if(commandReply.getReplyType() == ReplyType.RPL_ISUPPORT)
        {
            // TODO: Testing code was here
            // logger.log();
            // logger.log("<<<>>>");

            // logger.log("Take a look:\n\n"~commandReply.getParams());

            // logger.log("And here is key-value pairs: ", commandReply.getKVPairs());
            // logger.log("And here is array: ", commandReply.getPairs());

            // // TODO: DLog bug, this prints nothing
            // logger.log("And here is trailing: ", commandReply.getTrailing());

            // import std.stdio;
            // writeln("Trailer: "~commandReply.getTrailing());

            // writeln(cast(ubyte[])commandReply.getTrailing());

            // logger.log("<<<>>>");
            // logger.log();

            import std.stdio;
            writeln("Support stuff: ", commandReply.getKVPairs());

            
            testing(commandReply.getKVPairs());



        }
    }

    private string[string] attrs;
    private void testing(string[string] newData)
    {
        foreach(string key; newData.keys())
        {
            attrs[key] = newData[key];
        }

        foreach(string key; attrs.keys())
        {
            logger.debug_("Attribute name:", key);
            logger.debug_("Attribute value:", attrs[key]);
        }
    }


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
                Message joinMessage = new Message("", "JOIN", channel);
                sendMessage(joinMessage);
            }
            else
            {
                throw new BirchwoodException(ErrorType.INVALID_CHANNEL_NAME);
            }
        }
        else
        {
            throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS);
        }
    }

    /** 
     * Joins the requested channels
     *
     * Params:
     *   channels = the channels to join
     * Throws:
     *   BirchwoodException on invalid channel name
     */
    public void joinChannel(string[] channels)
    {
        /* If single channel */
        if(channels.length == 1)
        {
            /* Join the channel */
            joinChannel(channels[0]);
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
                        throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS);
                    }
                }

                /* Join multiple channels */
                Message joinMessage = new Message("", "JOIN", channelLine);
                sendMessage(joinMessage);
            }
            else
            {
                throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS);
            }
        }
        /* If no channels provided at all (error) */
        else
        {
            throw new BirchwoodException(ErrorType.EMPTY_PARAMS);
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
                        throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS);
                    }
                }

                /* Leave multiple channels */
                Message leaveMessage = new Message("", "PART", channelLine);
                sendMessage(leaveMessage);
            }
            else
            {
                throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS);
            }
        }
        /* If no channels provided at all (error) */
        else
        {
            throw new BirchwoodException(ErrorType.EMPTY_PARAMS);
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
        Message leaveMessage = new Message("", "PART", channel);
        sendMessage(leaveMessage);
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
                    /* Append on a trailing `,` */
                    recipientLine ~= ",";

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
                            throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS);
                        }
                    }

                    /* Send the message */
                    Message privMessage = new Message("", "PRIVMSG", recipientLine~" "~message);
                    sendMessage(privMessage);
                }
                else
                {
                    throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS);
                }
            }
            else
            {
                throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS);
            }          
        }
        /* If no recipients provided at all (error) */
        else
        {
            throw new BirchwoodException(ErrorType.EMPTY_PARAMS);
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
                Message privMessage = new Message("", "PRIVMSG", recipient~" "~message);
                sendMessage(privMessage);
            }
            else
            {
                throw new BirchwoodException(ErrorType.INVALID_NICK_NAME);
            }
        }
        else
        {
            throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS);
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
                            throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS);
                        }
                    }

                    /* Send to multiple channels */
                    Message privMessage = new Message("", "PRIVMSG", channelLine~" "~message);
                    sendMessage(privMessage);
                }
                else
                {
                    throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS);
                }
            }
            else
            {
                throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS);
            }
        }
        /* If no channels provided at all (error) */
        else
        {
            throw new BirchwoodException(ErrorType.EMPTY_PARAMS);
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
                Message privMessage = new Message("", "PRIVMSG", channel~" "~message);
                sendMessage(privMessage);
            }
            else
            {
                //TODO: Invalid channel name
                throw new BirchwoodException(ErrorType.INVALID_CHANNEL_NAME);
            }
        }
        else
        {
            //TODO: Illegal characters
            throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS);
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
        /* Send the message */
        sendMessage(message);
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
            
            public override void handler(EventyEvent e)
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
                    // TODO: We will need a non kv pair thing as well to see (in the
                    // ... case of channel messages) the singular pair <channel>
                    // ... name.
                    //
                    // Then our message will be in `getTrailing()`
                    logger.debug_("PrivMessage parser (kv-pairs): ", ircMessage.getKVPairs());
                    logger.debug_("PrivMessage parser (trailing): ", ircMessage.getTrailing());

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
                    // TODO: Add numeric response check here for CERTAIN ones which add to client
                    // ... state

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
            public override void handler(EventyEvent e)
            {
                PongEvent pongEvent = cast(PongEvent)e;
                assert(pongEvent);

                // string messageToSend = "PONG "~pongEvent.getID();
                Message pongMessage = new Message("", "PONG", pongEvent.getID());
                client.sendMessage(pongMessage);
                logger.log("Ponged back with "~pongEvent.getID());
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

                /* Start the event engine */
                this.engine = new Engine();

                /* Register default handler */
                initEvents();

                // /**
                //  * Initialize the ready events for both the
                //  * receive and send queue managers, then after
                //  * doing so start both managers and spin for
                //  * both of them to enter a ready state (i.e.
                //  * they have ensured a waiting-pipe pair for
                //  * libsnooze exists)
                //  */

                /* Set the running status to true */
                running = true;

                /* Start the receive queue and send queue managers */
                this.receiver.start();
                this.sender.start();
                // while(!receiver.isReady() || !sender.isReady()) {}

                /* Start the socket read-decode loop */
                this.start();
            }
            catch(SocketOSException e)
            {
                throw new BirchwoodException(ErrorType.CONNECT_ERROR);
            }
        }
        // TODO: Do actual liveliness check here
        else
        {
            throw new BirchwoodException(ErrorType.ALREADY_CONNECTED);
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
        /* Enqueue the message to the receive queue */
        receiver.rq(message);
    }
    
    /** 
     * Sends a message to the server by enqueuing it on
     * the client-side send queue.
     *
     * A BirchwoodException is thrown if the messages
     * final length exceeds 512 bytes
     *
     * Params:
     *   message = the message to send
     */
    private void sendMessage(Message message)
    {
        // TODO: Do message splits here
        
        /* Encode the message */
        ubyte[] encodedMessage = encodeMessage(message.encode());

        /* If the message is 512 bytes or less then send */
        if(encodedMessage.length <= 512)
        {
            /* Enqueue the message to the send queue */
            sender.sq(encodedMessage);
        }
        /* If above then throw an exception */
        else
        {
            throw new BirchwoodException(ErrorType.COMMAND_TOO_LONG);
        }
    }

    /** 
     * Disconnect from the IRC server gracefully
     */
    public void quit()
    {
        /* Generate the quit command using the custom quit message */
        Message quitCommand = new Message("", "QUIT", connInfo.quitMessage);
        sendMessage(quitCommand);

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

        // TODO: See libsnooze notes in `receiver.d` and `sender.d`, we could technically in some
        // ... teribble situation have a unregistered situaion which would then have a fallthrough
        // ... notify and a wait which never wakes up (the solution is mentioned in `receiver.d`/`sender.d`)
        receiver.end();
        sender.end();

        /* Wait for receive queue manager to realise it needs to stop */
        receiver.join();
        logger.log("disconnect() recvQueue manager stopped");

        /* Wait for the send queue manager to realise it needs to stop */
        sender.join();
        logger.log("disconnect() sendQueue manager stopped");

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


    version(unittest)
    {
        import core.thread;
    }

    unittest
    {
        /* FIXME: Get domaina name resolution support */
        // ConnectionInfo connInfo = ConnectionInfo.newConnection("irc.freenode.net", 6667, "testBirchwood");
        //freenode: 149.28.246.185
        //snootnet: 178.62.125.123
        //bonobonet: fd08:8441:e254::5
        ConnectionInfo connInfo = ConnectionInfo.newConnection("worcester.community.networks.deavmi.assigned.network", 6667, "testBirchwood");

        // // Set the fakelag to 1 second
        // connInfo.setFakeLag(1);

        // Create a new Client
        Client client = new Client(connInfo);

        client.connect();


        // TODO: The below should all be automatic, maybe once IRCV3 is done
        // ... we should automate sending in NICK and USER stuff
        Thread.sleep(dur!("seconds")(2));
        client.command(new Message("", "NICK", "birchwood")); // TODO: add nickcommand

        Thread.sleep(dur!("seconds")(2));
        client.command(new Message("", "USER", "doggie doggie irc.frdeenode.net :Tristan B. Kildaire"));
        
        Thread.sleep(dur!("seconds")(4));
        // client.command(new Message("", "JOIN", "#birchwood"));
        client.joinChannel("#birchwood");
        // TODO: Add a joinChannels(string[])
        client.joinChannel("#birchwood2");

        client.joinChannel(["#birchwoodLeave1", "#birchwoodLeave2", "#birchwoodLeave3"]);
        // client.joinChannel("#birchwoodLeave1");
        // client.joinChannel("#birchwoodLeave2");
        // client.joinChannel("#birchwoodLeave3");
        
        Thread.sleep(dur!("seconds")(2));
        client.command(new Message("", "NAMES", "")); // TODO: add names commdn

        Thread.sleep(dur!("seconds")(2));
        client.channelMessage("naai", "#birchwood");

        Thread.sleep(dur!("seconds")(2));
        client.directMessage("naai", "deavmi");


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
        client.directMessage("(1) Message to myself", "birchwood");

        /**
         * Test sending a message to myself (multi)
         */
        client.directMessage("(2) Message to myself (multi)", ["birchwood"]);

        /**
         * Test sending a message to myself 2x (multi)
         */
        client.directMessage("(3) Message to myself (multi)", ["birchwood", "birchwood"]);

        
        /** 
         * Test formatting of text
         */
        import birchwood.protocol.formatting;
        string formattedTextBold = bold("Hello in bold!");
        string formattedTextItalics = italics("Hello in italics!");
        string formattedTextUnderline = underline("Hello in underline!");
        string formattedTextMonospace = monospace("Hello in monospace!");
        string formattedTextStrikthrough = strikethrough("Hello in strikethrough!");
        client.channelMessage(formattedTextBold, "#birchwood");
        client.channelMessage(formattedTextItalics, "#birchwood");
        client.channelMessage(formattedTextUnderline, "#birchwood");
        client.channelMessage(formattedTextMonospace, "#birchwood");
        client.channelMessage(formattedTextStrikthrough, "#birchwood");

        string combination = bold(italics("Italiano Boldino"));
        client.channelMessage(combination, "#birchwood");

        string foregroundRedtext = setForeground(SimpleColor.RED)~"This is red text";
        client.channelMessage(foregroundRedtext, "#birchwood");

        string alternatePattern = setForeground(SimpleColor.RED)~"This "~setForeground(SimpleColor.WHITE)~"is "~setForeground(SimpleColor.BLUE)~"America!";
        client.channelMessage(alternatePattern, "#birchwood");

        string backgroundText = setForegroundBackground(SimpleColor.RED, SimpleColor.CYAN)~"Birchwood";
        client.channelMessage(backgroundText, "#birchwood");

        string combined = combination~foregroundRedtext~resetForegroundBackground()~backgroundText~resetForegroundBackground()~alternatePattern;
        client.channelMessage(combined, "#birchwood");

        
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