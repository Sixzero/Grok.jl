using Grok

# Example usage of Grok chat with streaming
# Get credentials from environment variables

if isempty(username) || isempty(password)
    println("Please set TWITTER_USERNAME and TWITTER_PASSWORD environment variables")
    exit(1)
end

println("Logging in as $(username)...")
result = Grok.login(username, password; email=email)

if !result["success"]
    println("Login failed: $(result["error"])")
    exit(1)
end

println("Login successful")

# Get the auth object from the login result
auth = result["auth"]
#%%
using Grok

using Revise
println("\nSending request to Grok...")

# Define stream callback function
function streamCallback(chunk)
    if chunk.isThinking
        # Handle thinking state (similar to process.stderr.write in JS)
        print("\rThinking: $(chunk.message)")
    elseif !isempty(chunk.message)
        # Handle actual message content (similar to process.stdout.write in JS)
        print(chunk.message)
    end
end

# Create chat options
options = GrokChatOptions(
    [GrokMessage("user", "Write a short poem about programming")],
    stream=true,
    streamCallback=streamCallback,
    # isReasoning=true,
)

# Send request to Grok
response = grokChat(options, auth)

# Print final response
println("\n\nFinal response:")
println(response.message)
#%%

# Start a conversation
response1 = grokChat(
    GrokChatOptions(
        streamCallback=streamCallback,
        [GrokMessage("user", "What are the three laws of robotics?")]
    ),
    auth,
)
#%%
# Continue the conversation with a follow-up question
# The package automatically uses the existing conversation 
response2 = grokChat(
    GrokChatOptions(streamCallback=streamCallback,[
        GrokMessage("user", "What are the three laws of robotics?"),
        GrokMessage("assistant", response1.message),
        GrokMessage("user", "Who created these laws?")
    ]),
    auth,
)
@show response2
;
