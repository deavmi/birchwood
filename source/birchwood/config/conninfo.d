/** 
 * Configuration-related types
 */
module birchwood.config.conninfo;

import std.socket : SocketException, Address, getAddress;
import birchwood.client.exceptions;
import std.conv : to, ConvException;

/** 
 * Represents the connection details for a server
 * to connect to
 */
public shared struct ConnectionInfo
{
    /** 
     * Server address
     */
    private Address addrInfo;

    /** 
     * Nickname to use
     */
    public string nickname;

    /** 
     * Username
     */
    public string username;

    /** 
     * Real name
     */
    public string realname;

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

    /** 
     * Key-value pairs learnt from the
     * server
     */
    private string[string] db;

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
    private this(Address addrInfo, string nickname, string username, string realname, ulong bulkReadSize = 20, string quitMessage = "birchwood client disconnecting...")
    {
        // NOTE: Not sure if much mutable in Address anyways
        this.addrInfo = cast(shared Address)addrInfo;
        this.nickname = nickname;
        this.username = username;
        this.realname = realname;
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
     * Sets the read-dequeue size
     *
     * Params:
     *   bytes = the number of bytes to dequeue at a time
     */
    public void setBulkReadSize(ulong bytes)
    {
        this.bulkReadSize = bytes;
    }

    /** 
     * Get the address of the endpoint server
     *
     * Returns: the server's address
     */
    public Address getAddr()
    {
        return cast(Address)addrInfo;
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

    public void updateDB(string key, string value)
    {
        db[key] = value;
    }

    public T getDB(T)(string key)
    {
        import std.stdio;
        writeln("GETDB: '"~key~"' with len ", key.length);
        if(key in db)
        {
            /* Attempt conversion into T */
            try
            {
                /* Fetch and convert */
                T value = to!(T)(db[key]);
                return value;
            }
            /* If conversion to type T fails */
            catch(ConvException e)
            {
                /* Return the initial value for such a paremeter */
                return T.init;
            }
        }
        else
        {
            throw new BirchwoodException(ErrorType.DB_KEY_NOT_FOUND, "Could not find key '"~key~"'");
        }
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
     *
     * Returns: ConnectionInfo for this server
     */
    public static ConnectionInfo newConnection(string hostname, ushort port, string nickname, string username, string realname)
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

            return ConnectionInfo(chosenAddress, nickname, username, realname);
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
            newConnection("1.", 21, "deavmi", "thedeavmi", "Tristan Brice Birchwood Kildaire");
            assert(false);
        }
        catch(BirchwoodException e)
        {
            assert(e.getType() == ErrorType.INVALID_CONN_INFO);
        }

        try
        {
            newConnection("1.1.1.1", 21, "", "thedeavmi", "Tristan Brice Birchwood Kildaire");
            assert(false);
        }
        catch(BirchwoodException e)
        {
            assert(e.getType() == ErrorType.INVALID_CONN_INFO);
        }
        
    }
}

/** 
 * Sets the default values as per rfc1459 in the
 * key-value pair DB
 *
 * Params:
 *   connInfo = a reference to the ConnectionInfo struct to update
 */
public void setDefaults(ref ConnectionInfo connInfo)
{
    /* Set the `MAXNICKLEN` to a default of 9 */
    connInfo.updateDB("MAXNICKLEN", "9");
}