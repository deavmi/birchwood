module birchwood.messages;

/**
 * Message types
 */
public class Message
{
    public string from;
    public string command;
    public string message;

    this(string from, string command, string message)
    {
        this.from = from;
        this.command = command;
        this.message = message;
    }

    public override string toString()
    {
        return "(from: "~from~", command: "~command~", message: `"~message~"`)";
    }
}