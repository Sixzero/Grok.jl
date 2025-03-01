using StreamCallbacks
using StreamCallbacks: AbstractStreamFlavor, AbstractStreamChunk, AbstractStreamCallback

# Implementation of StreamCallbacks for Grok API

"""
    GrokStream <: AbstractStreamFlavor

Stream flavor for Grok API.
"""
struct GrokStream <: AbstractStreamFlavor end

"""
    is_done(::GrokStream, chunk::AbstractStreamChunk; kwargs...)

Check if the streaming is done for Grok API.
"""
function StreamCallbacks.is_done(::GrokStream, chunk::AbstractStreamChunk; kwargs...)
    return chunk.data == "[DONE]"
end

"""
    extract_content(::GrokStream, chunk::AbstractStreamChunk; kwargs...)

Extract the content from a Grok API chunk.
"""
function StreamCallbacks.extract_content(::GrokStream, chunk::AbstractStreamChunk; kwargs...)
    if isnothing(chunk.json)
        return ""
    end
    
    # Extract the content based on Grok's response format
    if haskey(chunk.json, :result) && haskey(chunk.json.result, :message)
        return chunk.json.result.message
    end
    
    # Fallback to data if it's a string
    if isa(chunk.data, String)
        return chunk.data
    end
    
    return ""
end

"""
    build_response_body(::GrokStream, cb::AbstractStreamCallback; kwargs...)

Build a complete response body from the collected chunks for Grok API.
"""
function StreamCallbacks.build_response_body(::GrokStream, cb::AbstractStreamCallback; kwargs...)
    if isempty(cb.chunks)
        return Dict{Symbol,Any}()
    end
    
    # Initialize with the structure from the first chunk
    first_json = nothing
    for chunk in cb.chunks
        if !isnothing(chunk.json)
            first_json = chunk.json
            break
        end
    end
    
    if isnothing(first_json)
        return Dict{Symbol,Any}()
    end
    
    # Create a deep copy to avoid modifying the original
    response = JSON3.read(JSON3.write(first_json), Dict{Symbol,Any})
    
    # Collect all content from the chunks
    full_content = ""
    for chunk in cb.chunks
        content = StreamCallbacks.extract_content(GrokStream(), chunk; kwargs...)
        full_content *= content
    end
    
    # Update the response with the full content
    if haskey(response, :result)
        response[:result][:message] = full_content
        response[:result][:isThinking] = false
    end
    
    return response
end
