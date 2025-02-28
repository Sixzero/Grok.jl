using Grok

# Example demonstrating the conversation cache functionality
# Get credentials from environment variables
username = get(ENV, "TWITTER_USERNAME", "")
password = get(ENV, "TWITTER_PASSWORD", "")
email = get(ENV, "TWITTER_EMAIL", nothing)

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

# Define stream callback function
function streamCallback(chunk)
    if chunk.isThinking
        print("\rThinking: $(chunk.message)")
    elseif !isempty(chunk.message)
        print(chunk.message)
    end
end

# Example 1: Start a new conversation
println("\n\n--- Example 1: Start a new conversation ---")
options1 = GrokChatOptions(
    [GrokMessage("user", "What are the three laws of robotics?")],
    stream=true,
    streamCallback=streamCallback
)

response1 = grokChat(options1, auth)
println("\n\nConversation ID: $(response1.conversationId)")

# List cached conversations
println("\nCached conversations after first query:")
for conv in list_conversations()
    println("ID: $(conv.id) - $(length(conv.messages)) messages")
end

# Example 2: Continue the conversation with a follow-up question
println("\n\n--- Example 2: Continue with follow-up using continue_conversation ---")
response2 = continue_conversation(
    response1.conversationId, 
    "Who created these laws?",
    auth,
    stream=true,
    streamCallback=streamCallback
)

println("\n\nConversation ID: $(response2.conversationId)")

# Example 3: Starting with the same question automatically reuses conversation
println("\n\n--- Example 3: Starting with same question finds existing conversation ---")
options3 = GrokChatOptions(
    [GrokMessage("user", "What are the three laws of robotics?")],
    stream=true,
    streamCallback=streamCallback
)

response3 = grokChat(options3, auth)
println("\n\nReused conversation ID: $(response3.conversationId)")
println("Should match original ID: $(response1.conversationId)")

# Example 4: Providing explicit conversation history
println("\n\n--- Example 4: Providing explicit conversation history ---")
options4 = GrokChatOptions(
    [
        GrokMessage("user", "What are the three laws of robotics?"),
        GrokMessage("assistant", response1.message),
        GrokMessage("user", "Are there any stories where these laws are broken?")
    ],
    stream=true,
    streamCallback=streamCallback
)

response4 = grokChat(options4, auth)
println("\n\nConversation ID: $(response4.conversationId)")

# Show all cached conversations
println("\nFinal cached conversations:")
for conv in list_conversations()
    println("ID: $(conv.id) - $(length(conv.messages)) messages")
    println("First message: $(conv.messages[1].content[1:min(50, length(conv.messages[1].content))])...")
end

# Clean up if needed
# clear_cache!()
