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

public final class ReceiverThread : Thread
{
    /** 
     * The receive queue and its lock
     */
    private SList!(ubyte[]) recvQueue;
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
    }

    // TODO: Rename to `receiveQ`
    public void rq(ubyte[] encodedMessage)
    {
        /* Lock queue */
        recvQueueLock.lock();

        /* Add to queue */
        recvQueue.insertAfter(recvQueue[], encodedMessage);

        /* Unlock queue */
        recvQueueLock.unlock();

        // TODO: Add a "register" function which can initialize pipes
        // ... without needing a wait, we'd need a ready flag though
        // ... for receiver's thread start

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
     *
     * TODO: Our high load average is from here
     * ... it is getting lock a lot and spinning here
     * ... we should use libsnooze to avoid this
     */
    private void recvHandlerFunc()
    {
        while(client.running)
        {
            // TODO: Insert libsnooze wait here

            // TODO: Add a for-loop here which one can configure which is
            // ... a "per iteration" how much to process and act on

            // TODO: We could look at libsnooze wait starvation or mutex racing (future thought)

            // TODO: See above notes about libsnooze behaviour due
            // ... to usage in our context
            receiveEvent.wait(); // TODO: Catch any exceptions from libsnooze

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
                EventyEvent pongEvent = new PongEvent(pingID);
                client.engine.push(pongEvent);
            }

            /** 
             * Process each message remaining in the queue now
             * till it is empty
             */
            while(!recvQueue.empty())
            {
                ubyte[] message = recvQueue.front();

                /* Decode message */
                string messageNormal = decodeMessage(message);

                recvQueue.linearRemoveElement(recvQueue.front());

                // writeln("Normal message: "~messageNormal);

                

                /* TODO: Parse message and call correct handler */
                curMsg = Message.parseReceivedMessage(messageNormal);

                // TODO: Remove the Eventy push and replace with a handler call (on second thought no)
                EventyEvent ircEvent = new IRCEvent(curMsg);
                client.engine.push(ircEvent);
            }
        
            /* Unlock the receive queue */
            recvQueueLock.unlock();
        }
    }

    public void end()
    {
        // TODO: See above notes about libsnooze behaviour due
        // ... to usage in our context
        receiveEvent.notifyAll();
    }
}