/** 
 * Receive queue management
 */
module birchwood.client.receiver;

import core.thread : Thread, dur;

import std.container.slist : SList;
import core.sync.mutex : Mutex;

import eventy : EventyEvent = Event;

// TODO: Examine the below import which seemingly fixes stuff for libsnooze
import libsnooze.clib;
import libsnooze;

import birchwood.client;
import birchwood.protocol.messages : Message, decodeMessage;
import std.string : indexOf;
import birchwood.client.events : PongEvent, IRCEvent;
import std.string : cmp;

version(unittest)
{
    import std.stdio : writeln;
}

/** 
 * Manages the receive queue and performs
 * message parsing and event triggering
 * based on said messages
 */
public final class ReceiverThread : Thread
{
    /** 
     * The receive queue
     */
    private SList!(ubyte[]) recvQueue;

    /** 
     * The receive queue's lock
     */
    private Mutex recvQueueLock;

    /** 
     * The libsnooze event to await on which
     * when we wake up signals a new message
     * to be processed and received
     */
    private Event receiveEvent;

    /** 
     * The associated IRC client
     */
    private Client client;

    /** 
     * Constructs a new receiver thread with the associated
     * client
     *
     * Params:
     *   client = the Client to associate with
     */
    this(Client client)
    {
        super(&recvHandlerFunc);
        this.client = client;
        this.receiveEvent = new Event(); // TODO: Catch any libsnooze error here
        this.recvQueueLock = new Mutex();
        this.receiveEvent.ensure(this);
    }

    /** 
     * Enqueues the raw message into the receieve queue
     * for eventual processing
     *
     * Params:
     *   encodedMessage = the message to enqueue
     */
    public void rq(ubyte[] encodedMessage)
    {
        /* Lock queue */
        recvQueueLock.lock();

        /* Add to queue */
        recvQueue.insertAfter(recvQueue[], encodedMessage);

        /* Unlock queue */
        recvQueueLock.unlock();

        /** 
         * Wake up all threads waiting on this event
         * (if any, and if so it would only be the receiver)
         */
        receiveEvent.notifyAll();
    }

    /** 
     * The receive queue worker function
     *
     * This has the job of dequeuing messages
     * in the receive queue, decoding them
     * into Message objects and then emitting
     * an event depending on the type of message
     *
     * Handles PINGs along with normal messages
     */
    private void recvHandlerFunc()
    {
        while(client.running)
        {
            // TODO: We could look at libsnooze wait starvation or mutex racing (future thought)

            try
            {
                receiveEvent.wait();
            }
            catch(InterruptedException e)
            {
                version(unittest)
                {
                    writeln("wait() interrupted");
                }
                continue;
            }
            catch(FatalException e)
            {
                // TODO: This should crash and end
                version(unittest)
                {
                    writeln("wait() had a FATAL error!!!!!!!!!!!");
                }
                continue;
            }
                        

            /* Lock the receieve queue */
            recvQueueLock.lock();

            /* Parsed messages */
            SList!(Message) currentMessageQueue;

            /** 
             * Parse all messages and save them
             * into the above array
             */
            foreach(ubyte[] message; recvQueue[])
            {
                /* Decode the message */
                string decodedMessage = decodeMessage(message);

                /* Parse the message */
                Message parsedMessage = Message.parseReceivedMessage(decodedMessage);

                /* Save it */
                currentMessageQueue.insertAfter(currentMessageQueue[], parsedMessage);
            }


            /** 
             * Search for any PING messages, then store it if so
             * and remove it so it isn't processed again later
             */
            Message pingMessage;
            foreach(Message curMsg; currentMessageQueue[])
            {
                if(cmp(curMsg.getCommand(), "PING") == 0)
                {
                    currentMessageQueue.linearRemoveElement(curMsg);
                    pingMessage = curMsg;
                    break;
                }
            }

            /** 
             * If we have a PING then respond with a PONG
             */
            if(pingMessage !is null)
            {
                logger.log("Found a ping: "~pingMessage.toString());

                /* Extract the PING ID */
                string pingID = pingMessage.getParams();

                /* Spawn a PONG event */
                EventyEvent pongEvent = new PongEvent(pingID);
                client.engine.push(pongEvent);
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

            /** 
             * Process each message remaining in the queue now
             * till it is empty
             */
            while(!currentMessageQueue.empty())
            {
                /* Get the frontmost Message */
                Message curMsg = currentMessageQueue.front();

                // TODO: Remove the Eventy push and replace with a handler call (on second thought no)
                EventyEvent ircEvent = new IRCEvent(curMsg);
                client.engine.push(ircEvent);

                /* Remove the message from the queue */
                currentMessageQueue.linearRemoveElement(curMsg);
            }

            /* Clear the receive queue */
            recvQueue.clear();
        
            /* Unlock the receive queue */
            recvQueueLock.unlock();
        }
    }

    /** 
     * Stops the receive queue manager
     */
    public void end()
    {
        // TODO: See above notes about libsnooze behaviour due
        // ... to usage in our context
        receiveEvent.notifyAll();
    }
}