module birchwood.client.sender;

import core.thread : Thread, dur;

import std.container.slist : SList;
import core.sync.mutex : Mutex;

// TODO: Examine the below import which seemingly fixes stuff for libsnooze
import libsnooze.clib;
import libsnooze;

import birchwood.client;

public final class SenderThread : Thread
{
    /** 
     * The send queue and its lock
     */
    private SList!(ubyte[]) sendQueue;
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
     */
    this(Client client)
    {
        super(&sendHandlerFunc);
        this.client = client;
        this.sendEvent = new Event(); // TODO: Catch any libsnooze error here
        this.sendQueueLock = new Mutex();
    }

    // TODO: Rename to `sendQ`
    public void sq(ubyte[] encodedMessage)
    {
        /* Lock queue */
        sendQueueLock.lock();

        /* Add to queue */
        sendQueue.insertAfter(sendQueue[], encodedMessage);

        /* Unlock queue */
        sendQueueLock.unlock();

        // TODO: Add libsnooze event wake up
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

        while(client.running)
        {
            // TODO: Insert libsnooze wait here

            // TODO: Add a for-loop here which one can configure which is
            // ... a "per iteration" how much to process and act on

            // TODO: We could look at libsnooze wait starvation or mutex racing (future thought)

            /* TODO: handle normal messages (xCount with fakeLagInBetween) */

            /* Lock queue */
            sendQueueLock.lock();

            foreach(ubyte[] message; sendQueue[])
            {
                client.socket.send(message);
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
}