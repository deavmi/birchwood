/** 
 * Send queue management
 */
module birchwood.client.sender;

import core.thread : Thread, dur;

import std.container.slist : SList;
import core.sync.mutex : Mutex;
import core.sync.condition : Condition;

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
     * Condition variable for waking
     * up send queue reader
     */
    private Condition sendQueueCond;

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
        this.sendQueueLock = new Mutex();
        this.sendQueueCond = new Condition(this.sendQueueLock);
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

        /* Wake the sleeping message handler */
        sendQueueCond.notify();

        /* Unlock queue */
        sendQueueLock.unlock();
    }

    /** 
     * The send queue worker function
     */
    private void sendHandlerFunc()
    {
        while(client.isRunning())
        {
            /* TODO: handle normal messages (xCount with fakeLagInBetween) */

            /* Lock the queue */
            sendQueueLock.lock();

            /* Sleep till woken (new message) */
            sendQueueCond.wait(); // TODO: Check SyncError?

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
        /* Lock the queue */
        sendQueueLock.lock();

        /* Wake up sleeping thread (so it can exit) */
        sendQueueCond.notify();

        /* Unlock the queue */
        sendQueueLock.unlock();

        // Wait on the manager thread to end
        join();
    }
}