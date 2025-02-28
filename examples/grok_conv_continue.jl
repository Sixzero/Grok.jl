
# Create chat options
options = GrokChatOptions(
    [GrokMessage("user", "Tell me what did we talk about?")],
    stream=true,
    streamCallback=streamCallback,
    # isReasoning=true,
    conversationId="1895496636496764967",
)

# Send request to Grok
response = grokChat(options, auth)

# Print final response
println("\n\nFinal response:")
println(response.message)

println("\nConversation ID: $(response.conversationId)")
#%%
# Create chat options
options = GrokChatOptions(
    [GrokMessage("user", "Write a short poem about programming"),
    GrokMessage("assistant", """Lines of code in endless streams,  
Logic weaves through silent dreams,  
Fingers dance on keys so fast,  
Bugs arise, but we outlast..."""),
    GrokMessage("user", "Tell me what did I say to you? Don't miss out anything.")],
    stream=true,
    streamCallback=streamCallback,
    # isReasoning=true,
)

# Send request to Grok
response = grokChat(options, auth)

# Print final response
println("\n\nFinal response:")
println(response.message)

println("\nConversation ID: $(response.conversationId)")