module birchwood.client.sender;

import core.thread : Thread;

import std.container.slist : SList;
import core.sync.mutex : Mutex;

// TODO: Examine the below import which seemingly fixes stuff for libsnooze
import libsnooze.clib;
import libsnooze;

import birchwood.client.core : Client;

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
    private Event receiveEvent;

    /** 
     * The associated IRC client
     */
    private Client client;
}