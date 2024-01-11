/** 
 * Client definition
 */
module birchwood.client.client;

import std.socket : Socket, SocketException, Address, getAddress, SocketType, ProtocolType, SocketOSException;
import std.socket : SocketFlags, SocketShutdown;
import std.conv : to;
import std.container.slist : SList;
import core.sync.mutex : Mutex;
import core.thread : Thread, dur;
import std.string;
import eventy : EventyEvent = Event, Engine, EventType, Signal, EventyException;
import birchwood.config;
import birchwood.client.exceptions : BirchwoodException, ErrorType;
import birchwood.protocol.messages : Message, encodeMessage, decodeMessage, isValidText;
import birchwood.protocol.constants : ReplyType;

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
    private Engine engine;

    /** 
     * Whether the client is running or not
     */
    private bool running = false;

    /** 
     * Checks whether this client is running
     *
     * Returns: `true` if running, `false`
     * otherwise
     */
    package bool isRunning()
    {
        return this.running;
    }

    /** 
     * Returns the eventy engine
     *
     * Returns: the `Engine`
     */
    package Engine getEngine()
    {
        return this.engine;
    }

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
         * Set defaults in db
         */
        setDefaults(this.connInfo);
    }

    // TODO: ANything worth callin on destruction?
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

            /* Fetch and parse the received key-value pairs */
            string[string] receivedKV = commandReply.getKVPairs();
            foreach(string key; receivedKV.keys())
            {
                /* Update the db */
                string value = receivedKV[key];
                connInfo.updateDB(key, value);
                logger.log("Updated key in db '"~key~"' with value '"~value~"'");
            }

        }
    }

    /** 
     * Called when the connection to the remote host is closed
     */
    public void onConnectionClosed()
    {
        // TODO: Add log as default behaviour?
        logger.log("Connection was closed, not doing anything");
    }

    /** 
     * Requests setting of the provided nickname
     *
     * Params:
     *   nickname = the nickname to request
     * Throws:
     *   `BirchwoodException` on invalid nickname
     */
    public void nick(string nickname)
    {
        /* Ensure no illegal characters in nick name */
        if(textPass(nickname))
        {
            // TODO: We could investigate this later if we want to be safer
            ulong maxNickLen = connInfo.getDB!(ulong)("MAXNICKLEN");

            /* If the username's lenght is within the allowed bounds */
            if(nickname.length <= maxNickLen)
            {
                /* Set the nick */
                Message nickMessage = new Message("", "NICK", nickname);
                sendMessage(nickMessage);
            }
            /* If not */
            else
            {
                throw new BirchwoodException(ErrorType.NICKNAME_TOO_LONG, "The nickname was over thge length of "~to!(string)(maxNickLen)~" characters");
            }
        }
        else
        {
            throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS, "There are illegal characters in the nickname");
        }
    }

    /** 
     * Joins the requested channel
     *
     * Params:
     *   channel = the channel to join
     * Throws:
     *   `BirchwoodException` on invalid channel name
     */
    public void joinChannel(string channel)
    {
        /* Ensure no illegal characters in channel name */
        if(textPass(channel))
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
                throw new BirchwoodException(ErrorType.INVALID_CHANNEL_NAME, "Channel name does not start with a #");
            }
        }
        else
        {
            throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS, "Invalid characters in channel");
        }
    }


    /** 
     * Provided with a reference to a string
     * this will check to see if it contains
     * any illegal characters and then if so
     * it will strip them if the `ChecksMode`
     * is set to `EASY` (and return `true`)
     * else it will return `false` if set to
     * `HARDCORE` whilst illegal characters
     * are present.
     *
     * Params:
     *   text = the ref'd `string`
     * Returns: `true` if validated, `false`
     * otherwise
     */
    private bool textPass(ref string text)
    {
        /* If there are any invalid characters */
        if(Message.hasIllegalCharacters(text))
        {
            import birchwood.config.conninfo : ChecksMode;
            if(connInfo.getMode() == ChecksMode.EASY)
            {
                // Filter the text and update it in-place
                text = Message.stripIllegalCharacters(text);
                return true;
            }
            else
            {
                return false;
            }
        }
        /* If there are no invalid characters prewsent */
        else
        {
            return true;
        }
    }

    /** 
     * Joins the requested channels
     *
     * Params:
     *   channels = the channels to join
     * Throws:
     *   `BirchwoodException` on invalid channel name or
     * if the list is empty
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
            if(textPass(channelLine))
            {
                //TODO: Add check for #

                /* Append on a trailing `,` */
                channelLine ~= ",";

                for(ulong i = 1; i < channels.length; i++)
                {
                    string currentChannel = channels[i];

                    /* Ensure the character channel is valid */
                    if(textPass(currentChannel))
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
                        throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS, "Invalid characters in the channel");
                    }
                }

                /* Join multiple channels */
                Message joinMessage = new Message("", "JOIN", channelLine);
                sendMessage(joinMessage);
            }
            else
            {
                throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS, "Invalid characters in the channel");
            }
        }
        /* If no channels provided at all (error) */
        else
        {
            throw new BirchwoodException(ErrorType.EMPTY_PARAMS, "No channels provided");
        }
    }

    /** 
     * Parts from a list of channel(s) in one go
     *
     * Params:
     *   channels = the list of channels to part from
     * Throws:
     *   `BirchwoodException` if the channels list is empty
     * or there are illegal characters present
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
            if(textPass(channelLine))
            {
                //TODO: Add check for #

                /* Append on a trailing `,` */
                channelLine ~= ",";

                for(ulong i = 1; i < channels.length; i++)
                {
                    string currentChannel = channels[i];

                    /* Ensure the character channel is valid */
                    if(textPass(currentChannel))
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
                        throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS, "Invalid characters in the channel");
                    }
                }

                /* Leave multiple channels */
                Message leaveMessage = new Message("", "PART", channelLine);
                sendMessage(leaveMessage);
            }
            else
            {
                throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS, "Invalid characters in the channel");
            }
        }
        /* If no channels provided at all (error) */
        else
        {
            throw new BirchwoodException(ErrorType.EMPTY_PARAMS, "No channels were provided");
        }
    }

    /** 
     * Part from a single channel
     *
     * Params:
     *   channel = the channel to leave
     * Throws:
     *   `BirchwoodException` if the channel name
     * is invalid
     */
    public void leaveChannel(string channel)
    {
        /* Ensure the channel name contains only valid characters */
        if(textPass(channel))
        {
            /* Leave the channel */
            Message leaveMessage = new Message("", "PART", channel);
            sendMessage(leaveMessage);
        }
        /* If invalid characters were present */
        else
        {
            throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS, "There are illegal characters in the channel name");
        }
    }

    /** 
     * Sends a direct message to the intended recipients
     *
     * Params:
     *   message = The message to send
     *   recipients = The receipients of the message
     * Throws:
     *   `BirchwoodException` if the recipients list is empty
     * or illegal characters are present
     */
    public void directMessage(string message, string[] recipients)
    {
        // TODO: Chunked sends when over limit of `message`
        
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
            if(textPass(message))
            {
                string recipientLine = recipients[0];

                /* Ensure valid characters in first recipient */
                if(textPass(recipientLine))
                {
                    /* Append on a trailing `,` */
                    recipientLine ~= ",";

                    for(ulong i = 1; i < recipients.length; i++)
                    {
                        string currentRecipient = recipients[i];

                        /* Ensure valid characters in the current recipient */
                        if(textPass(currentRecipient))
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
                            throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS, "There are illegal characters in the recipient");
                        }
                    }

                    /* Send the message */
                    Message privMessage = new Message("", "PRIVMSG", recipientLine~" "~message);
                    sendMessage(privMessage);
                }
                else
                {
                    throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS, "There are illegal characters in the recipient");
                }
            }
            else
            {
                throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS, "The message contains invalid characters");
            }          
        }
        /* If no recipients provided at all (error) */
        else
        {
            throw new BirchwoodException(ErrorType.EMPTY_PARAMS, "No recipients were provided");
        }
    }

    /** 
     * Sends a direct message to the intended recipient
     *
     * Params:
     *   message = The message to send
     *   recipients = The receipient of the message
     * Throws:
     *   `BirchwoodException` if the receipient's nickname
     * is invalid or there are illegal characters present
     */
    public void directMessage(string message, string recipient)
    {
        // TODO: Chunked sends when over limit of `message`

        /* Ensure the message and recipient are valid text */
        if(textPass(message) && textPass(recipient))
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
                throw new BirchwoodException(ErrorType.INVALID_NICK_NAME, "The provided nickname contains invalid characters");
            }
        }
        else
        {
            throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS, "There are illegal characters in either the message of the recipient");
        }
    }

    /** 
     * Sends a channel message to the intended recipients
     *
     * Params:
     *   message = The message to send
     *   recipients = The receipients of the message
     * Throws:
     *   `BirchwoodException` if the channels list is empty
     */
    public void channelMessage(string message, string[] channels)
    {
        // TODO: Chunked sends when over limit of `message`

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
            if(textPass(message))
            {
                string channelLine = channels[0];    

                /* Ensure valid characters in first channel */
                if(textPass(channelLine))
                {
                    /* Append on a trailing `,` */
                    channelLine ~= ",";

                    for(ulong i = 1; i < channels.length; i++)
                    {
                        string currentChannel = channels[i];

                        /* Ensure valid characters in current channel */
                        if(textPass(currentChannel))
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
                            throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS, "One of the channel names contains invalid characters");
                        }
                    }

                    /* Send to multiple channels */
                    Message privMessage = new Message("", "PRIVMSG", channelLine~" "~message);
                    sendMessage(privMessage);
                }
                else
                {
                    throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS, "One of the channel names contains invalid characters");
                }
            }
            else
            {
                throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS, "Invalid characters in the message");
            }
        }
        /* If no channels provided at all (error) */
        else
        {
            throw new BirchwoodException(ErrorType.EMPTY_PARAMS, "No channels were provided");
        }
    }

    /** 
     * Sends a message to a given channel
     *
     * Params:
     *   message = The message to send
     *   channel = The channel to send the message to
     * Throws:
     *   `BirchwoodException` if the message or channel name
     * contains illegal characters
     */
    public void channelMessage(string message, string channel)
    {
        // TODO: Chunked sends when over limit of `message`

        //TODO: Add check on recipient
        //TODO: Add emptiness check
        if(textPass(message) && textPass(channel))
        {
            if(channel[0] == '#')
            {
                /* Send the channel message */
                Message privMessage = new Message("", "PRIVMSG", channel~" "~message);
                sendMessage(privMessage);
            }
            else
            {
                throw new BirchwoodException(ErrorType.INVALID_CHANNEL_NAME, "The channel is missign a # infront of its name");
            }
        }
        else
        {
            throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS, "Channel name of message contains invalid characters");
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
     *
     * Throws:
     *   `EventyException` on error registering
     * the signals and event types
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
     *
     * Throws:
     *  `BirchwoodException` if there is an error connecting
     * or something failed internally
     */
    public void connect()
    {
        if(!running)
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

                /* Set the running status to true */
                running = true;

                /** 
                 * Setups the receiver and sender queue managers
                 */
                this.receiver = new ReceiverThread(this);
                this.sender = new SenderThread(this);

                /* Start the receive queue and send queue managers */
                this.receiver.start();
                this.sender.start();

                /* Start the socket read-decode loop */
                this.start();

                /* Do the /NICK and /USER handshake */
                doAuth();
            }
            catch(SocketOSException e)
            {
                throw new BirchwoodException(ErrorType.CONNECT_ERROR);
            }
            catch(EventyException e)
            {
                // TODO: Could deallocate here
                throw new BirchwoodException(ErrorType.INTERNAL_FAILURE, e.toString());
            }
        }
        // TODO: Do actual liveliness check here
        else
        {
            throw new BirchwoodException(ErrorType.ALREADY_CONNECTED);
        }
    }

    /** 
     * Performs the /NICK and /USER handshake.
     *
     * This method will set the hostname to be equal to the chosen
     * username in the ConnectionInfo struct
     *
     * Params:
     *   servername = the servername to use (default: bogus.net)
     */
    private void doAuth(string servername = "bogus.net")
    {
        Thread.sleep(dur!("seconds")(2));
        nick(connInfo.nickname);

        Thread.sleep(dur!("seconds")(2));
        // TODO: Note I am making hostname the same as username always (is this okay?)
        // TODO: Note I am making the servername always bogus.net
        user(connInfo.username, connInfo.username, servername, connInfo.realname);
    }

    /** 
     * Performs user identification
     *
     * Params:
     *   username = the username to identify with
     *   hostname = the hostname to use
     *   servername = the servername to use
     *   realname = your realname
     * Throws:
     *   `BirchwoodException` if the username, jostname,
     * servername or realname contains illegal characters
     */
    public void user(string username, string hostname, string servername, string realname)
    {
        // TODO: Implement me properly with all required checks

        if(textPass(username) && textPass(hostname) && textPass(servername) && textPass(realname))
        {
            /* User message */
            Message userMessage = new Message("", "USER", username~" "~hostname~" "~servername~" "~":"~realname);
            sendMessage(userMessage);
        }
        else
        {
            throw new BirchwoodException(ErrorType.ILLEGAL_CHARACTERS, "Illegal characters present in either the username, hostname, server name or real name");
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
     * Any invalid characters will be stripped prior
     * to encoding IF `ChecksMode` is set to `EASY` (default)
     *
     * Params:
     *   message = the message to send
     * Throws:
     *  A `BirchwoodException` is thrown if the messages
     *  final length exceeds 512 bytes of if `ChecksMode`
     *  is set to `HARDCORE`
     */
    private void sendMessage(Message message)
    {
        /* Encode the message */
        ubyte[] encodedMessage = encodeMessage(message.encode(connInfo.getMode()));

        /* If the message is 512 bytes or less then send */
        if(encodedMessage.length <= 512)
        {
            /* Enqueue the message to the send queue */
            sender.sq(encodedMessage);
        }
        /* If above then throw an exception */
        else
        {
            throw new BirchwoodException(ErrorType.COMMAND_TOO_LONG, "The final encoded length of the message is too long");
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

        /* Shutdown the socket */

        /**
         * Shutdown the socket unblocking
         * any reads and writes occuring
         *
         * Notably this unblocks the receiver
         * thread and causes it to handle
         * the shutdown.
         */
        import std.socket : SocketShutdown;
        socket.shutdown(SocketShutdown.BOTH);
        logger.log("disconnect() socket shutdown");

        
    }

    /** 
     * Cleans up resources which would have been allocated
     * during the call to `connect()` and for the duration
     * of the open session
     */
    private void doThreadCleanup()
    {
        /* Stop the receive queue manager and wait for it to stop */
        receiver.end();
        logger.log("doThreadCleanup() recvQueue manager stopped");
        receiver = null;

        /* Stop the send queue manager and wait for it to stop */
        sender.end();
        logger.log("doThreadCleanup() sendQueue manager stopped");
        sender = null;

        /* TODO: Stop eventy (FIXME: I don't know if this is implemented in Eventy yet, do this!) */
        engine.shutdown();
        logger.log("doThreadCleanup() eventy stopped");
        engine = null;

        logger.log("doThreadCleanup() end");
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
        readLoop: while(running)
        {
            /* Receieve at most 512 bytes (as per RFC) */
            ptrdiff_t bytesRead = socket.receive(currentData, SocketFlags.PEEK);

            // TODO: Should not be JUST unittest builds
            // TODO: This sort of logic should be used by EVERY read
            version(unittest)
            {
                import std.stdio;
                writeln("(peek) bytesRead: '", bytesRead, "' (status var or count)");
                writeln("(peek) currentData: '", currentData, "'");
            }

            /**
             * Check if the remote host closed the connection
             * OR some general error occurred
             *
             * TODO: See if the code is safe enough to only
             * have to do this ONCE
             */
            if(bytesRead == 0 || bytesRead < 0)
            {
                version(unittest)
                {
                    import std.stdio;
                    writeln("Remote host ended connection or general error, Socket.ERROR: '", bytesRead, "'");
                }

                /* Set running state to false, then exit loop */
                this.running = false;
                continue readLoop;
            }

            

            

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
                    long status = this.socket.receive(scratch);

                    /**
                     * Check if the remote host closed the connection
                     * OR some general error occurred
                     */
                    if(status == 0 || status < 0)
                    {
                        /* Set running state to false, then exit loop */
                        this.running = false;
                        continue readLoop;
                    }

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
                long status = this.socket.receive(scratch);

                /**
                 * Check if the remote host closed the connection
                 * OR some general error occurred
                 */
                if(status == 0 || status < 0)
                {
                    /* Set running state to false, then exit loop */
                    this.running = false;
                    continue readLoop;
                }

                continue;
            }

            /* Add whatever we have read to build-up */
            currentMessage~=currentData[0..bytesRead];

            /* TODO: Dequeue without peek after this */
            ubyte[] scratch;
            scratch.length = bytesRead;
            long status = this.socket.receive(scratch);
            
            /**
             * Check if the remote host closed the connection
             * OR some general error occurred
             */
            if(status == 0 || status < 0)
            {
                /* Set running state to false, then exit loop */
                this.running = false;
                continue readLoop;
            }

            /* TODO: Yield here and in other places before continue */
        }

        /* Shut down socket AND close it */
        socket.shutdown(SocketShutdown.BOTH);
        socket.close();

        /* Shutdown sub-systems */
        doThreadCleanup();

        // FIXME: Really invalidate everything here

        /* Call the onDisconnect thing (TODO) */
        onConnectionClosed();
    }


    version(unittest)
    {
        import core.thread;
    }

    unittest
    {
        // ConnectionInfo connInfo = ConnectionInfo.newConnection("irc.freenode.net", 6667, "testBirchwood");
        //freenode: 149.28.246.185
        //snootnet: 178.62.125.123
        //bonobonet: fd08:8441:e254::5
        ConnectionInfo connInfo = ConnectionInfo.newConnection("rany.irc.bnet.eu.org", 6667, "birchwood", "doggie", "Tristan B. Kildaire");

        // Set the fakelag to 1 second (server kicks me for spam me thinks if not)
        connInfo.setFakeLag(1);

        // Create a new Client
        Client client = new Client(connInfo);

        // Authenticate
        client.connect();


        // TODO: The below should all be automatic, maybe once IRCV3 is done
        // ... we should automate sending in NICK and USER stuff
        // Thread.sleep(dur!("seconds")(2));
        // client.nick("birchwood");

        // Thread.sleep(dur!("seconds")(2));
        // client.command(new Message("", "USER", "doggie doggie irc.frdeenode.net :Tristan B. Kildaire"));
        // client.user("doggie", "doggie", "irc.frdeenode.net", "Tristan B. Kildaire");




        
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


        /**
         * Definately by now we would have learnt the new MAXNICLEN
         * which on BonoboNET is 30, hence the below should work
         */
        try
        {
            client.nick("birchwood123456789123456789123");
            assert(true);
        }
        catch(BirchwoodException e)
        {
            assert(false);
        }

        // TODO: Don't forget to re-enable this when done testing!
        Thread.sleep(dur!("seconds")(4));
        client.quit();


        /**
         * Reconnect again (to test it)
         */
        client.connect();

        /**
         * Join #birchwood, send a message
         * and then quit once again
         */
        Thread.sleep(dur!("seconds")(4));
        client.joinChannel("#birchwood");
        client.channelMessage("Lekker", "#birchwood");
        client.quit();
    }
}