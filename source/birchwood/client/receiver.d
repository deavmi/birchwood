/** 
 * Receive queue management
 */
module birchwood.client.receiver;

import core.thread : Thread, dur;

import std.container.slist : SList;
import core.sync.mutex : Mutex;
import core.sync.condition : Condition;

import eventy : EventyEvent = Event;

import birchwood.client;
import birchwood.protocol.messages : Message, decodeMessage;
import std.string : indexOf;
import birchwood.client.events : PongEvent, IRCEvent;
import std.string : cmp;

version(unittest)
{
    import std.stdio : writeln;
}
import birchwood.logging;

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
     * Condition variable for waking
     * up receive queue reader
     */
    private Condition recvQueueCond;

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
     * Throws:
     *   `SnoozeError` on failure to construct an
     * `Event` or ensure ourselves
     */
    this(Client client)
    {
        super(&recvHandlerFunc);
        this.client = client;
        this.recvQueueLock = new Mutex();
        this.recvQueueCond = new Condition(this.recvQueueLock);
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

        /* Wake the sleeping message handler */
        recvQueueCond.notify();

        /* Unlock queue */
        recvQueueLock.unlock();
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
        while(client.isRunning())
        {
            /* Lock the queue */
            recvQueueLock.lock();

            /* Sleep till woken (new message) */
            recvQueueCond.wait(); // TODO: Check SyncError?

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
                DEBUG("Found a ping: "~pingMessage.toString());

                /* Extract the PING ID */
                string pingID = pingMessage.getParams();

                /* Spawn a PONG event */
                EventyEvent pongEvent = new PongEvent(pingID);
                client.getEngine().push(pongEvent);
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
                client.getEngine.push(ircEvent);

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
        /* Lock the queue */
        recvQueueLock.lock();

        /* Wake up sleeping thread (so it can exit) */
        recvQueueCond.notify();

        /* Unlock the queue */
        recvQueueLock.unlock();

        // Wait on the manager thread to end
        join();
    }
}