# Grok.jl [![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://sixzero.github.io/Grok.jl/stable/) [![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://sixzero.github.io/Grok.jl/dev/) [![Build Status](https://github.com/sixzero/Grok.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/sixzero/Grok.jl/actions/workflows/CI.yml?query=branch%3Amaster) [![Coverage](https://codecov.io/gh/sixzero/Grok.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/sixzero/Grok.jl) [![Aqua](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

A Julia package for interacting with the Grok AI chatbot API provided by X (formerly Twitter). This package uses reverse-engineered browser APIs to communicate with Grok without requiring official API access.

## Installation

```julia
using Pkg
Pkg.add("Grok")
```

## Features

- Authenticate with Twitter/X accounts using browser-based login flow
- Create and manage conversations with Grok
- Stream responses in real-time with support for [StreamCallbacks.jl](https://github.com/svilupp/StreamCallbacks.jl)
- Smart and lighweight conversation caching to continue existing conversations
- Support for web search results
- Session caching for more efficient authentication
- Integration with [PromptingTools.jl](https://github.com/svilupp/PromptingTools.jl) via the `aigenerate` interface

## Quick Start

```julia
using Grok

# Set environment variables for authentication
# ENV["TWITTER_USERNAME"] = "your_username"
# ENV["TWITTER_PASSWORD"] = "your_password"
# ENV["TWITTER_EMAIL"] = "your_email@example.com"  # Optional

# Login using environment variables
result = Grok.login()  # Uses ENV vars by default
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

Grok.jl automatically caches conversations in memory, allowing you to continue them later:

```julia
# Start a conversation
response1 = grokChat(
    GrokChatOptions([GrokMessage("user", "What are the three laws of robotics?")]),
    auth
)

# Continue the conversation with a follow-up question
# The package automatically uses the existing conversation 
response2 = grokChat(
    GrokChatOptions([
        GrokMessage("user", "What are the three laws of robotics?"),
        GrokMessage("assistant", response1.message),
        GrokMessage("user", "Who created these laws?")
    ]),
    auth
)
```

## Authentication Caching

Grok.jl caches successful authentications to avoid unnecessary logins:

```julia
# First login performs full authentication
result1 = Grok.login()  # Uses environment variables

# Subsequent logins use cached session
result2 = Grok.login()  # Uses cached auth

# Force a fresh login if needed
result3 = Grok.login(force=true)  # Bypasses cache

# Explicitly provide credentials
result4 = Grok.login("username", "password")
```

## Integration with PromptingTools.jl

Grok.jl integrates with [PromptingTools.jl](https://github.com/svilupp/PromptingTools.jl), allowing you to use Grok with the familiar `aigenerate` interface:

```julia
using Grok
using PromptingTools

# Use Grok with PromptingTools
response = aigenerate("What is the meaning of life?"; model="grok")

# With explicit credentials
response = aigenerate("What is the meaning of life?"; 
                     model="grok", 
                     api_kwargs=(; username="your_username", password="your_password"))
```

## StreamCallbacks.jl Support

Grok.jl supports [StreamCallbacks.jl](https://github.com/svilupp/StreamCallbacks.jl) for advanced stream handling:

```julia
using Grok
using StreamCallbacks

# Create a stream callback
cb = StreamCallback()

# Use Grok with PromptingTools
response = aigenerate("What is the meaning of life?"; model="grok", streamcallback=cb)
```

## Examples

Check the `examples/` directory for more detailed usage examples:
- `twitter_login_example.jl` - Basic Twitter authentication
- `grok_example.jl` - Simple Grok chat interaction
- `conversation_cache_example.jl` - Working with conversation history
- `grok_with_promptingtools.jl` - Using Grok with PromptingTools.jl

## License

MIT
