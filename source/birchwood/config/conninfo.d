/** 
 * Configuration-related types
 */
module birchwood.config.conninfo;

import std.socket : SocketException, Address, getAddress;
import birchwood.client.exceptions;

/** 
 * Represents the connection details for a server
 * to connect to
 */
public struct ConnectionInfo
{
    /** 
     * Server address
     */
    private Address addrInfo;

    /** 
     * Nickname to use
     */
    private string nickname;

    /** 
     * Size to use to dequeue bytes
     * from socket in read-loop
     */
    private ulong bulkReadSize;

    //TODO: Make this a Duration
    /** 
     * Time to wait (in seconds) between
     * sending messages
     */
    private ulong fakeLag;

    /**
     * Quit message
     */
    public const string quitMessage;

    /* TODO: before publishing change this bulk size */

    /** 
     * Constructs a new ConnectionInfo instance with the
     * provided details
     *
     * Params:
     *   addrInfo = the server's endpoint
     *   nickname = the nickname to use
     *   bulkReadSize = the dequeue read size
     *   quitMessage = the message to use when quitting
     */
    private this(Address addrInfo, string nickname, ulong bulkReadSize = 20, string quitMessage = "birchwood client disconnecting...")
    {
        this.addrInfo = addrInfo;
        this.nickname = nickname;
        this.bulkReadSize = bulkReadSize;
        this.quitMessage = quitMessage;

        // Set the default fakelag to 1
        this.fakeLag = 1;
    }

    /** 
     * Retrieve the read-dequeue size
     *
     * Returns: the number of bytes
     */
    public ulong getBulkReadSize()
    {
        return this.bulkReadSize;
    }

    /** 
     * Get the address of the endpoint server
     *
     * Returns: the server's address
     */
    public Address getAddr()
    {
        return addrInfo;
    }

    /** 
     * Get the chosen fake lag
     *
     * Returns: the fake lag in seconds
     */
    public ulong getFakeLag()
    {
        return fakeLag;
    }

    /** 
     * Sets the fake lag in seconds
     *
     * Params:
     *   fakeLag = the fake lag to use
     */
    public void setFakeLag(ulong fakeLag)
    {
        this.fakeLag = fakeLag;
    }

    /** 
     * Creates a ConnectionInfo struct representing a client configuration which
     * can be provided to the Client class to create a new connection based on its
     * parameters
     *
     * Params:
     *   hostname = hostname of the server
     *   port = server port
     *   nickname = nickname to use
     * Returns: ConnectionInfo for this server
     */
    public static ConnectionInfo newConnection(string hostname, ushort port, string nickname)
    {
        try
        {
            /* Attempt to resolve the address (may throw SocketException) */
            Address[] addrInfo = getAddress(hostname, port);

            /* Username check */
            if(!nickname.length)
            {
                throw new BirchwoodException(ErrorType.INVALID_CONN_INFO);
            }

            /* TODO: Add feature to choose which address to use, prefer v4 or v6 type of thing */
            Address chosenAddress = addrInfo[0];

            return ConnectionInfo(chosenAddress, nickname);
        }
        catch(SocketException e)
        {
            throw new BirchwoodException(ErrorType.INVALID_CONN_INFO);
        }
    }

    /**
    * Tests invalid conneciton information
    *
    * 1. Invalid hostnames
    * 2. Invalid usernames
    */
    unittest
    {
        try
        {
            newConnection("1.", 21, "deavmi");
            assert(false);
        }
        catch(BirchwoodException e)
        {
            assert(e.getType() == BirchwoodException.ErrorType.INVALID_CONN_INFO);
        }

        try
        {
            newConnection("1.1.1.1", 21, "");
            assert(false);
        }
        catch(BirchwoodException e)
        {
            assert(e.getType() == BirchwoodException.ErrorType.INVALID_CONN_INFO);
        }
        
    }
}