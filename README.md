# Grok.jl [![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://sixzero.github.io/Grok.jl/stable/) [![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://sixzero.github.io/Grok.jl/dev/) [![Build Status](https://github.com/sixzero/Grok.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/sixzero/Grok.jl/actions/workflows/CI.yml?query=branch%3Amaster) [![Coverage](https://codecov.io/gh/sixzero/Grok.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/sixzero/Grok.jl) [![Aqua](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

A Julia package for interacting with the Grok AI chatbot API provided by X (formerly Twitter).

## Installation

```julia
using Pkg
Pkg.add("Grok")
```

## Features

- Authenticate with Twitter/X accounts
- Create and manage conversations with Grok
- Stream responses in real-time
- Cache conversations for continued interactions
- Support for web search results
- Session caching for more efficient authentication

## Quick Start

```julia
using Grok

# Login to X (Twitter)
username = get(ENV, "TWITTER_USERNAME", "")
password = get(ENV, "TWITTER_PASSWORD", "")
email = get(ENV, "TWITTER_EMAIL", nothing)  # Optional, may be required for some accounts

# Authenticate
result = Grok.login(username, password; email=email)
auth = result["auth"]

# Create a simple chat request
response = grokChat(
    GrokChatOptions([GrokMessage("user", "What is Julia programming language?")]),
    auth
)

# Print the response
println(response.message)
```

## Streaming Responses

```julia
# Define a callback function to handle streamed responses
function streamCallback(chunk)
    if chunk.isThinking
        print("\rThinking: $(chunk.message)")
    elseif !isempty(chunk.message)
        print(chunk.message)
    end
end

# Create streaming chat options
options = GrokChatOptions(
    [GrokMessage("user", "Write a short poem about programming")],
    stream=true,
    streamCallback=streamCallback
)

# Send request with streaming enabled
response = grokChat(options, auth)
```

## Conversation Management

Grok.jl automatically caches conversations, allowing you to continue them later:

```julia
# Start a conversation
response1 = grokChat(
    GrokChatOptions([GrokMessage("user", "What are the three laws of robotics?")]),
    auth
)

# Continue the conversation with a follow-up question
# The package automatically uses the existing conversation 
# when you provide the same first message
response2 = grokChat(
    GrokChatOptions([
        GrokMessage("user", "What are the three laws of robotics?"),
        GrokMessage("assistant", response1.message),
        GrokMessage("user", "Who created these laws?")
    ]),
    auth
)

# List all cached conversations
conversations = list_conversations()
```

## Authentication Caching

Grok.jl caches successful authentications to avoid unnecessary logins:

```julia
# First login will perform full authentication
result1 = Grok.login(username, password)

# Subsequent logins with same credentials use cached session
result2 = Grok.login(username, password)  # Uses cached auth

# Force a fresh login if needed
result3 = Grok.login(username, password; force=true)  # Bypasses cache
```

## Examples

Check the `examples/` directory for more detailed usage examples:
- `twitter_login_example.jl` - Basic Twitter authentication
- `grok_example.jl` - Simple Grok chat interaction
- `conversation_cache_example.jl` - Working with conversation history

## License

MIT
