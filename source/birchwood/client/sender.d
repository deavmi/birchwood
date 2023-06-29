/** 
 * Send queue management
 */
module birchwood.client.sender;

import core.thread : Thread, dur;

import std.container.slist : SList;
import core.sync.mutex : Mutex;

// TODO: Examine the below import which seemingly fixes stuff for libsnooze
import libsnooze.clib;
import libsnooze;

import birchwood.client;

version(unittest)
{
    import std.stdio : writeln;
}

/** 
 * Manages the send queue
 */
public final class SenderThread : Thread
{
    /** 
     * The send queue
     */
    private SList!(ubyte[]) sendQueue;

    /** 
     * The send queue's lock
     */
    private Mutex sendQueueLock;

    /** 
     * The libsnooze event to await on which
     * when we wake up signals a new message
     * to be processed and sent
     */
    private Event sendEvent;

    /** 
     * The associated IRC client
     */
    private Client client;

    /** 
     * Constructs a new sender thread with the associated
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
        super(&sendHandlerFunc);
        this.client = client;
        this.sendEvent = new Event();
        this.sendQueueLock = new Mutex();
        this.sendEvent.ensure(this);
    }

    /** 
     * Enqueues the raw message into the send queue
     * for eventual sending
     *
     * Params:
     *   encodedMessage = the message to enqueue
     */
    public void sq(ubyte[] encodedMessage)
    {
        /* Lock queue */
        sendQueueLock.lock();

        /* Add to queue */
        sendQueue.insertAfter(sendQueue[], encodedMessage);

        /* Unlock queue */
        sendQueueLock.unlock();

        /** 
         * Wake up all threads waiting on this event
         * (if any, and if so it would only be the sender)
         */
        sendEvent.notifyAll();
    }

    /** 
     * The send queue worker function
     */
    private void sendHandlerFunc()
    {
        while(client.running)
        {
            // TODO: We could look at libsnooze wait starvation or mutex racing (future thought)

            /* TODO: handle normal messages (xCount with fakeLagInBetween) */

            try
            {
                sendEvent.wait();
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


            /* Lock queue */
            sendQueueLock.lock();

            foreach(ubyte[] message; sendQueue[])
            {
                client.socket.send(message);
                Thread.sleep(dur!("seconds")(client.connInfo.getFakeLag()));
            }

            /* Empty the send queue */
            sendQueue.clear();

            /* Unlock queue */
            sendQueueLock.unlock();
        }
    }

    /** 
     * Stops the send queue manager
     */
    public void end()
    {
        // TODO: See above notes about libsnooze behaviour due
        // ... to usage in our context
        sendEvent.notifyAll();

        // Wait on the manager thread to end
        join();

        // Dispose the eventy event (TODO: We could do this then join for same effect)
        sendEvent.dispose();
    }
}