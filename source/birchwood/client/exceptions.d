module birchwood.client.exceptions;

import std.conv : to;

public class BirchwoodException : Exception
{
    // TODO: Move outside one level
    public enum ErrorType
    {
        INVALID_CONN_INFO,
        ALREADY_CONNECTED,
        CONNECT_ERROR,
        EMPTY_PARAMS,
        INVALID_CHANNEL_NAME,
        INVALID_NICK_NAME,
        ILLEGAL_CHARACTERS,
        COMMAND_TOO_LONG
    }

    private ErrorType errType;

    /* Auxillary error information */
    /* TODO: Make these actually Object */
    private string auxInfo;

    this(ErrorType errType)
    {
        super("BirchwoodError("~to!(string)(errType)~")"~(auxInfo.length == 0 ? "" : " "~auxInfo));
        this.errType = errType;
    }

    this(ErrorType errType, string auxInfo)
    {
        this(errType);
        this.auxInfo = auxInfo;
    }

    public ErrorType getType()
    {
        return errType;
    }
}