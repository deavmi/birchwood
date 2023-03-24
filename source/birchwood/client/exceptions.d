/** 
 * Exception handling
 */
module birchwood.client.exceptions;

import std.conv : to;

/** 
 * The type of error to be used
 * with BirchwoodException
 *
 * TODO: Make this STRING and associate a message with it
 * but make it include the enum name and corresponding value
 * when throwin an exception
 */
public enum ErrorType
{
    /** 
     * If the provided connection information
     * is invalid, such as incorrect hostname,
     * invalid nick
     */
    INVALID_CONN_INFO,

    /** 
     * If an attempt to call connect() is made
     * when already connected
     */
    ALREADY_CONNECTED,

    /** 
     * If there is an erroring opening a connection
     * to the endpoint server
     */
    CONNECT_ERROR,

    /** 
     * If invalid parameter information is provided
     * to an IRC command method
     */
    EMPTY_PARAMS,

    /** 
     * If an invalid channel name is provided
     */
    INVALID_CHANNEL_NAME,

    /** 
     * If an invalid nickname is provided
     */
    INVALID_NICK_NAME,

    /** 
     * If illegal characters exist within the
     * message
     */
    ILLEGAL_CHARACTERS,

    /** 
     * If the final encoded IRC message
     * is too long to send to the server
     */
    COMMAND_TOO_LONG,

    /** 
     * If invalid parameters are passed
     * to any of the text formatting functions
     */
    INVALID_FORMATTING
}

/** 
 * A runtime exception in the Birchwood library
 */
public class BirchwoodException : Exception
{
    /** 
     * The specific type of error occurred
     */
    private ErrorType errType;

    /** 
     * Auxillary information
     */
    private string auxInfo;

    /** 
     * Constructs a new exception with the given sub-error type
     * and infers the auxillary information based on said sub-error
     * type
     *
     * Params:
     *   errType = the sub-error type
     */
    this(ErrorType errType)
    {
        super("BirchwoodError("~to!(string)(errType)~")"~(auxInfo.length == 0 ? "" : " "~auxInfo));
        this.errType = errType;
    }
    
    /** 
     * Constructs a new exception with the given sub-error type
     * and auxillary information
     *
     * Params:
     *   errType = the sub-error type
     *   auxInfo = the auxillary information
     */
    this(ErrorType errType, string auxInfo)
    {
        this(errType);
        this.auxInfo = auxInfo;
    }

    /** 
     * Retrieve the specific error which occurred
     *
     * Returns: the ErrorType of the error
     */
    public ErrorType getType()
    {
        return errType;
    }
}