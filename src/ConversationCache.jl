# ConversationCache.jl
# Handles conversation history caching for Grok.jl

"""
The core conversation cache structure 
"""
mutable struct ConversationCache
    conversations::Dict{String, Vector{GrokMessage}}
    
    ConversationCache() = new(Dict{String, Vector{GrokMessage}}())
end

# Global conversation cache
const CONVERSATION_CACHE = ConversationCache()

"""
Add or update a conversation in the cache
"""
function cache_conversation!(id::String, messages::Vector{GrokMessage})
    CONVERSATION_CACHE.conversations[id] = copy(messages)
    return messages
end

"""
Get a conversation from the cache
"""
function get_cached_conversation(id::String)
    return get(CONVERSATION_CACHE.conversations, id, nothing)
end

"""
Find a matching conversation based on message history
"""
function find_matching_conversation(messages::Vector{GrokMessage})
    isempty(messages) && return nothing
    
    # Determine how many messages to match (exclude last if it's from user)
    last_is_user = messages[end].role == "user"
    match_count = last_is_user ? length(messages) - 1 : length(messages)
    match_count == 0 && return nothing  # Nothing to match
    
    for (conv_id, conv_messages) in CONVERSATION_CACHE.conversations
        # Need exactly match_count messages in the cache
        length(conv_messages) == match_count || continue
        
        # Check if all messages up to match_count match
        all_matched = true
        for i in 1:match_count
            if conv_messages[i].role != messages[i].role || 
               conv_messages[i].content != messages[i].content
                all_matched = false
                break
            end
        end
        
        all_matched && return conv_id
    end
    
    return nothing
end

"""
List all cached conversations
"""
function list_conversations()
    return [(id=id, messages=msgs) for (id, msgs) in CONVERSATION_CACHE.conversations]
end

"""
Clear all conversations from the cache
"""
function clear_cache!()
    empty!(CONVERSATION_CACHE.conversations)
    return nothing
end

"""
Delete a specific conversation from the cache
"""
function delete_conversation!(id::String)
    if haskey(CONVERSATION_CACHE.conversations, id)
        delete!(CONVERSATION_CACHE.conversations, id)
        return true
    end
    return false
end

"""
Update an existing conversation with a new message
"""
function add_message_to_conversation!(id::String, message::GrokMessage)
    if haskey(CONVERSATION_CACHE.conversations, id)
        push!(CONVERSATION_CACHE.conversations[id], message)
        return true
    end
    return false
end
