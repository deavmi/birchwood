module birchwood.client.receiver;

import core.thread : Thread;

// TODO: Examine the below import which seemingly fixes stuff for libsnooze
import libsnooze.clib;
import libsnooze;

public final class ReceiverThread : Thread
{
    /** 
     * The libsnooze event to await on which
     * when we wake up signals a new message
     * to be processed and received
     */
    private Event receiveEvent;
}