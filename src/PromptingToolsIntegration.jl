# Integration with PromptingTools.jl
using PromptingTools
using HTTP
using JSON3

export GrokPromptSchema, register_grok_model

"""
    GrokPromptSchema <: AbstractPromptSchema

Schema for interacting with Twitter/X's Grok AI model.
"""
struct GrokPromptSchema <: PromptingTools.AbstractPromptSchema end

"""
    render(schema::GrokPromptSchema, messages; kwargs...)

Convert PromptingTools messages to Grok format.
"""
function PromptingTools.render(schema::GrokPromptSchema,
                             messages::Vector{<:PromptingTools.AbstractMessage};
                             conversation::AbstractVector{<:PromptingTools.AbstractMessage} = PromptingTools.AbstractMessage[],
                             kwargs...)
    # First pass: make replacements provided in kwargs and handle conversation history
    # This preserves the original message structure for return_all
    messages_replaced = PromptingTools.render(
        PromptingTools.NoSchema(), messages; conversation, kwargs...)
    
    # Second pass: Convert to Grok format
    grok_messages = Grok.GrokMessage[]
    
    # Find system message if it exists
    system_content = nothing
    system_index = findfirst(PromptingTools.issystemmessage, messages_replaced)
    if !isnothing(system_index)
        system_content = messages_replaced[system_index].content
    end
    
    # Process all messages for Grok format
    first_user_found = false
    for msg in messages_replaced
        if PromptingTools.isabstractannotationmessage(msg)
            continue
        end
        
        if PromptingTools.issystemmessage(msg)
            # Skip system messages - they'll be handled with the first user message
            continue
        end
        
        role = if msg isa PromptingTools.UserMessage
            "user"
        elseif msg isa PromptingTools.AIMessage
            "assistant"
        else
            continue
        end
        
        content = msg.content
        
        # If this is the first user message and we have a system message,
        # prepend the system content to the user message
        if role == "user" && !first_user_found && !isnothing(system_content)
            content = """System: 
            $system_content
            
            User: 
            $content"""
            first_user_found = true
        end
        
        push!(grok_messages, Grok.GrokMessage(role, content))
    end
    
    return (original_messages=messages_replaced, grok_messages=grok_messages)
end

"""
    get_auth_from_kwargs(api_kwargs)

Helper function to get authentication from api_kwargs or environment variables.
"""
function get_auth_from_kwargs(api_kwargs)
    # First check if auth is directly provided
    auth = get(api_kwargs, :auth, nothing)
    if !isnothing(auth)
        return auth
    end
    
    # Check if username and password are provided
    username = get(api_kwargs, :username, nothing)
    password = get(api_kwargs, :password, nothing)
    
    if !isnothing(username) && !isnothing(password)
        # Login with provided credentials
        return Grok.login(username, password)["auth"]
    end
    
    # Try to get auth from cached credentials or environment variables
    return Grok.login(get(ENV, "TWITTER_USERNAME", nothing), get(ENV, "TWITTER_PASSWORD", nothing))["auth"]
end

"""
    aigenerate(schema::GrokPromptSchema, prompt; kwargs...)

Generate a response from Grok using the PromptingTools interface.

# Authentication
You can authenticate in several ways:
1. Provide `auth` directly in `api_kwargs`
2. Provide `username` and `password` in `api_kwargs`
3. Set environment variables `TWITTER_USERNAME` and `TWITTER_PASSWORD`
4. Use previously cached authentication

# Example
```julia
# Using environment variables or cached auth
response = aigenerate("What is the meaning of life?"; model="grok")

# Using explicit credentials
response = aigenerate("What is the meaning of life?"; 
                     model="grok", 
                     api_kwargs=(; username="your_username", password="your_password"))

# Using pre-authenticated auth object
auth = Grok.TwitterLogin.get_auth()
response = aigenerate("What is the meaning of life?"; 
                     model="grok", 
                     api_kwargs=(; auth=auth))
```
"""
function PromptingTools.aigenerate(schema::GrokPromptSchema, 
                                 prompt::PromptingTools.ALLOWED_PROMPT_TYPE;
                                 verbose::Bool = true,
                                 return_all::Bool = false,
                                 dry_run::Bool = false,
                                 conversation::AbstractVector{<:PromptingTools.AbstractMessage} = PromptingTools.AbstractMessage[],
                                 streamcallback::Any = nothing,
                                 api_kwargs::NamedTuple = NamedTuple(),
                                 kwargs...)
    # Render the messages
    rendered = PromptingTools.render(schema, prompt; conversation, kwargs...)
    original_messages = rendered.original_messages
    grok_messages = rendered.grok_messages
    
    # Get authentication
    auth = get_auth_from_kwargs(api_kwargs)
    if isnothing(auth)
        error("Authentication failed. Please provide valid credentials via api_kwargs or environment variables.")
    end
    
    # Create a new conversation if not provided
    conversationId = get(api_kwargs, :conversationId, nothing)
    
    if dry_run
        # Return a dummy response for dry runs
        msg = PromptingTools.AIMessage(
            content = "[Dry run] This would be sent to Grok: $(grok_messages)",
            status = 200,
            tokens = (0, 0),
            elapsed = 0.0
        )
        return return_all ? PromptingTools.finalize_outputs(prompt, original_messages, msg; 
                                                          return_all, dry_run, conversation, kwargs...) : msg
    end
    
    # Start timing
    start_time = time()
    
    # Create stream callback if needed
    grok_stream_callback = nothing
    if !isnothing(streamcallback)
        grok_stream_callback = function(chunk)
            if !chunk.isThinking && !isempty(chunk.message)
                if isa(streamcallback, IO)
                    write(streamcallback, chunk.message)
                else
                    # Assume it's a callback function
                    streamcallback(chunk.message)
                end
            end
        end
    end
    
    # Create chat options
    options = GrokChatOptions(
        grok_messages,
        conversationId=conversationId,
        stream=!isnothing(streamcallback),
        streamCallback=grok_stream_callback
    )
    
    # Make the request
    response = grokChat(options, auth)
    
    # Calculate elapsed time
    elapsed = time() - start_time
    
    # Create AIMessage from response
    msg = PromptingTools.AIMessage(;
        content = response.message,
        status = 200,
        tokens = (0, 0),  # Grok doesn't provide token counts
        elapsed = elapsed,
        extras = Dict{Symbol, Any}(:conversationId => response.conversationId)
    )
    
    # Use finalize_outputs to handle return_all properly
    return PromptingTools.finalize_outputs(prompt, original_messages, msg; 
                                         return_all, dry_run, conversation, kwargs...)
end

"""
    register_grok_model()

Registers the Grok model with PromptingTools.jl.
This allows using Grok with the standard PromptingTools interface.

# Example
```julia
using Grok
using PromptingTools

# Now you can use Grok with PromptingTools
response = aigenerate("What is the meaning of life?"; model="grok")

# Or with explicit credentials
response = aigenerate("What is the meaning of life?"; 
                     model="grok", 
                     api_kwargs=(; username="your_username", password="your_password"))
```
"""
function register_grok_model()
    # Register the Grok model
    PromptingTools.register_model!(
        name = "grok-3",
        schema = GrokPromptSchema(),
        cost_of_token_prompt = 0.0,
        cost_of_token_generation = 0.0,
        description = "Twitter/X's Grok-3 AI model. Requires Twitter authentication."
    )
    
    # Add model aliases for easier access
    PromptingTools.MODEL_ALIASES["grok"] = "grok-3"
    
    @info "Grok model registered with PromptingTools. Use alias 'grok' to access it."
    return nothing
end
