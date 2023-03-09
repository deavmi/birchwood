module birchwood.client.receiver;

import core.thread : Thread;

import std.container.slist : SList;
import core.sync.mutex : Mutex;

// TODO: Examine the below import which seemingly fixes stuff for libsnooze
import libsnooze.clib;
import libsnooze;

import birchwood.client.core : Client;

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
        this.client = client;
    }
}