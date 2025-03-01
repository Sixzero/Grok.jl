# Example of using Grok.jl with PromptingTools.jl

using PromptingTools
using Grok
using StreamCallbacks


# Method 1: Using environment variables or cached authentication
response = aigenerate("What is the meaning of life?"; model="grok",
streamcallback=stdout)
println()
println("Response: ", response.content)

# Method 2: Using explicit credentials
# response = aigenerate("What is the meaning of life?"; 
#                      model="grok", 
#                      api_kwargs=(; username="your_username", password="your_password"))

# # Method 3: Using pre-authenticated auth object
# response = aigenerate("What is the meaning of life?"; 
#                      model="grok", )
# println("Response with explicit auth: ", response.c

# Using streaming for real-time responses
# response = aigenerate("Count from 1 to 10"; 
#                      model="grok", 
#                      streamcallback=stdout)
# println("\nFinal response: ", response.content)
#%%
# Using with conversation history
conversation = aigenerate("Hi, I'm a Julia programmer"; 
                         model="grok", 
                         return_all=true)
println("First response: ", last(conversation).content)
#%%
@show conversation
#%%
# Continue the conversation

conversation = aigenerate("What programming language am I using?"; 
                         model="grok", 
                         conversation=conversation,
                         return_all=true)
println("Follow-up response: ", last(conversation).content)