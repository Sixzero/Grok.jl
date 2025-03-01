module Grok

using HTTP
using JSON3
using Dates

include("Types.jl")
include("TwitterLogin.jl")
include("Api.jl")
include("PromptingToolsIntegration.jl")

# Include ConversationCache after defining GrokMessage
include("ConversationCache.jl")


# Export the types and functions
export TwitterAuth, GrokMessage, GrokChatOptions, GrokChatResponse, GrokStreamChunk
export grokChat

"""
Creates a new conversation with Grok.
"""
function createGrokConversation(auth::TwitterAuth)
    res = requestApi(
        "https://x.com/i/api/graphql/6cmfJY3d7EPWuCSXWrkOFg/CreateGrokConversation",
        auth,
        "POST",
        Dict()  # Empty body but required for POST
    )

    if !res["success"]
        throw(ErrorException("Failed to create conversation: $(res["err"])"))
    end

    # Extract conversation ID from response
    if !haskey(res["value"], :data) || 
       !haskey(res["value"].data, :create_grok_conversation) ||
       !haskey(res["value"].data.create_grok_conversation, :conversation_id)
        throw(ErrorException("Invalid response format when creating conversation"))
    end

    return res["value"].data.create_grok_conversation.conversation_id
end

"""
Extract messages from response chunks
"""
function extract_messages_from_chunks(chunks)
    fullMessage = ""
    for chunk in chunks
        if haskey(chunk, :result) && 
           haskey(chunk.result, :message) && 
           !get(chunk.result, :isThinking, false)
            fullMessage *= chunk.result.message
        end
    end
    return fullMessage
end

"""
Find web results in chunks
"""
function find_web_results(chunks)
    for chunk in chunks
        if haskey(chunk, :result) && haskey(chunk.result, :webResults)
            return chunk.result.webResults
        end
    end
    return nothing
end

"""
Main method for interacting with Grok in a chat-like manner.
"""
function grokChat(options::GrokChatOptions, auth::TwitterAuth)
    conversationId = options.conversationId
    original_messages = options.messages
    messages = copy(original_messages)
    
    # Step 1: Determine the conversation ID
    if isnothing(conversationId)
        # Try to find a matching conversation based on message history
        conversationId = find_matching_conversation(messages)
        if !isnothing(conversationId)
            println("Found matching conversation with ID: $conversationId")
        end
    end
    
    # Step 2: Check if we have this conversation cached
    cached_msgs = isnothing(conversationId) ? nothing : get_cached_conversation(conversationId)
    
    # Step 3: For existing conversations, just send the last user message
    if !isnothing(cached_msgs) && length(messages) > 0 && messages[end].role == "user"
        println("Using existing conversation - sending only the latest user message")
        messages = [messages[end]]
    end
    
    # Step 4: Create new conversation if needed
    if isnothing(conversationId)
        conversationId = createGrokConversation(auth)
        println("Created new conversation with ID: $conversationId")
    end

    # Convert OpenAI-style messages to Grok's internal format
    responses = []
    for msg in messages
        response_dict = Dict(
            "message" => msg.content,
            "sender" => msg.role == "user" ? 1 : 2
        )
        
        # Add promptSource and fileAttachments for user messages
        if msg.role == "user"
            response_dict["promptSource"] = ""
            response_dict["fileAttachments"] = []
        end
        
        push!(responses, response_dict)
    end

    # Log the messages being sent for debugging
    # println("Sending conversation with $(length(responses)) messages")
    
    payload = Dict(
        "responses" => responses,
        "systemPromptName" => "",
        "grokModelOptionId" => "grok-3",
        "conversationId" => conversationId,
        "isReasoning" => options.isReasoning,
        "returnSearchResults" => options.returnSearchResults,
        "returnCitations" => options.returnCitations,
        "promptMetadata" => Dict(
            "promptSource" => "NATURAL",
            "action" => "INPUT"
        ),
        "imageGenerationCount" => 4,
        "requestFeatures" => Dict(
            "eagerTweets" => true,
            "serverHistory" => true
        )
    )

    res = requestApi(
        "https://api.x.com/2/grok/add_response.json",
        auth,
        "POST",
        payload,
        options.stream,
        options.streamCallback
    )

    if !res["success"]
        throw(ErrorException("Failed to get response: $(res["err"])"))
    end

    # Parse response chunks - Grok may return either a single response or multiple chunks
    chunks = []
    if haskey(res["value"], "chunks") && !isempty(res["value"]["chunks"])
        # Use chunks directly if available
        chunks = res["value"]["chunks"]
    elseif haskey(res["value"], "text")
        # For streaming responses, split text into chunks and parse each JSON chunk
        for chunk_text in split(res["value"]["text"], '\n')
            if !isempty(chunk_text)
                try
                    push!(chunks, JSON3.read(chunk_text))
                catch e
                    # Skip invalid JSON
                end
            end
        end
    else
        # For single responses, wrap the value itself in array
        push!(chunks, res["value"])
    end

    if isempty(chunks)
        throw(ErrorException("No valid response chunks received"))
    end

    # Check if we hit rate limits by examining first chunk
    firstChunk = chunks[1]
    if haskey(firstChunk, :result) && 
       haskey(firstChunk.result, :responseType) && 
       firstChunk.result.responseType == "limiter"
        result = firstChunk.result
        
        # Create upsell info if available
        upsellInfo = nothing
        if haskey(result, :upsell)
            upsellInfo = Dict(
                "usageLimit" => result.upsell.usageLimit,
                "quotaDuration" => "$(result.upsell.quotaDurationCount) $(result.upsell.quotaDurationPeriod)",
                "title" => result.upsell.title,
                "message" => result.upsell.message
            )
        end
        
        # Return rate limit response
        return GrokChatResponse(
            conversationId,
            result.message,
            [original_messages..., GrokMessage("assistant", result.message)],
            nothing,
            nothing,
            Dict(
                "isRateLimited" => true,
                "message" => result.message,
                "upsellInfo" => upsellInfo
            )
        )
    end

    # Combine all message chunks into single response
    fullMessage = ""
    
    # First try to use the text from the response if available
    if haskey(res["value"], "text") && !isempty(res["value"]["text"])
        fullMessage = res["value"]["text"]
    else
        fullMessage = extract_messages_from_chunks(chunks)
    end
    
    # If we still have no message, try to extract conversation ID from first chunk
    if isempty(fullMessage) && !isempty(chunks)
        # Try to find the conversation ID if not already set
        if isnothing(conversationId) && haskey(chunks[1], :conversationId)
            conversationId = chunks[1].conversationId
        end
        
        # Extract message from all chunks without filtering by isThinking
        for chunk in chunks
            if haskey(chunk, :result) && haskey(chunk.result, :message)
                fullMessage *= chunk.result.message
            end
        end
    end
    
    # If still empty, create a placeholder message
    if isempty(fullMessage)
        fullMessage = "No message content could be extracted from the response."
    end

    # Find web results if any
    webResults = find_web_results(chunks)
    
    # Create the updated conversation history - just append the AI response to original messages
    full_conversation = [original_messages..., GrokMessage("assistant", fullMessage)]
    
    # Save to cache for future use
    cache_conversation!(conversationId, full_conversation)

    # Return complete response with conversation history and metadata
    return GrokChatResponse(
        conversationId,
        fullMessage,
        full_conversation,
        webResults,
        chunks[1],
        nothing
    )
end

# Initialize PromptingTools integration if available
function __init__()
    # Register Grok with PromptingTools
    register_grok_model()
end

end # End of module Grok