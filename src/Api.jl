using HTTP
using JSON3
using Dates

"""
An API result container.
"""
function requestApi(
    url::String,
    auth::TwitterAuth,
    method::String="GET",
    body=nothing,
    stream::Bool=false,
    streamCallback=nothing
)
    headers = Dict{String,String}()
    
    # Install auth headers
    if haskey(auth.cookies, "ct0")
        headers["x-csrf-token"] = auth.cookies["ct0"]
    end
    
    headers["authorization"] = "Bearer $(auth.bearer_token)"
    headers["cookie"] = join(["$k=$v" for (k,v) in auth.cookies], "; ")
    headers["User-Agent"] = auth.user_agent
    
    if !isnothing(auth.guest_token)
        headers["x-guest-token"] = auth.guest_token
    end
    
    if !isnothing(body)
        headers["content-type"] = "application/json"
    end
    
    # Add Twitter-specific headers
    headers["x-twitter-auth-type"] = "OAuth2Client"
    headers["x-twitter-active-user"] = "yes"
    headers["x-twitter-client-language"] = "en"
    
    # Handle streaming requests differently
    if stream && method == "POST" && !isnothing(body)
        return handle_streaming_request(url, headers, body, auth, streamCallback)
    end
    
    # For non-streaming requests, use the regular approach
    options = Dict{Symbol,Any}(
        :status_exception => false
    )
    
    if !isnothing(body)
        options[:body] = JSON3.write(body)
    end
    
    # Make the request
    try
        response = if method == "GET"
            HTTP.get(url, [k => v for (k,v) in headers]; options...)
        else
            HTTP.post(url, [k => v for (k,v) in headers]; options...)
        end
        
        # Update cookies from response
        update_cookies_from_headers!(auth, response.headers)
    
        # Handle rate limiting
        if response.status == 429
            xRateLimitReset = HTTP.header(response, "x-rate-limit-reset", "")
            if !isempty(xRateLimitReset)
                currentTime = time()
                resetTime = parse(Float64, xRateLimitReset)
                timeDeltaMs = 1000 * (resetTime - currentTime)
                
                if timeDeltaMs > 0
                    sleep(timeDeltaMs / 1000)
                    # Retry the request recursively
                    return requestApi(url, auth, method, body, stream, streamCallback)
                end
            end
        end
        
        if response.status != 200
            return Dict(
                "success" => false,
                "err" => "HTTP Error: $(response.status)"
            )
        end
        
        # Handle regular JSON response
        contentType = HTTP.header(response, "content-type", "")
        if occursin("application/json", contentType)
            value = JSON3.read(response.body)
            return Dict("success" => true, "value" => value)
        else
            # Return empty object for non-JSON responses
            return Dict("success" => true, "value" => Dict())
        end
    catch e
        return Dict(
            "success" => false,
            "err" => "Request failed: $(e)"
        )
    end
end

"""
Handle streaming requests using HTTP.open for real-time processing
"""
function handle_streaming_request(url, headers, body, auth, streamCallback)
    buffer = IOBuffer()
    all_chunks = []
    
    try
        # Use HTTP.open with a proper streaming approach
        HTTP.open("POST", url, [k => v for (k,v) in headers]) do stream
            # Write the request body
            write(stream, JSON3.write(body))
            HTTP.closewrite(stream)  # Signal we're done writing
            
            # Start reading the response
            response = HTTP.startread(stream)
            
            # Update cookies from response headers
            update_cookies_from_headers!(auth, response.headers)
            
            # Check if we got an error response
            if response.status != 200
                return Dict(
                    "success" => false,
                    "err" => "HTTP Error: $(response.status)"
                )
            end
            
            # Process the streaming response
            was_thinking = false
            current_line = IOBuffer()
            
            # Read the stream in chunks until EOF
            while !eof(stream)
                # Read available data (this is truly streaming)
                chunk = readavailable(stream)
                
                # Process the chunk byte by byte to handle partial JSON objects
                for byte in chunk
                    if byte == UInt8('\n')
                        # We have a complete line, process it
                        line = String(take!(current_line))
                        if !isempty(line)
                            process_json_line(line, all_chunks, buffer, was_thinking, streamCallback)
                        end
                    else
                        # Add byte to current line buffer
                        write(current_line, byte)
                    end
                end
            end
            
            # Process any remaining data in the buffer
            remaining = String(take!(current_line))
            if !isempty(remaining)
                process_json_line(remaining, all_chunks, buffer, was_thinking, streamCallback, true)
            end
        end
        
        # Construct the full message from chunks if buffer is empty
        responseText = extract_full_message(buffer, all_chunks)
        
        return Dict(
            "success" => true,
            "value" => Dict(
                "text" => responseText,
                "chunks" => all_chunks
            )
        )
    catch e
        println("Streaming error: $e")
        return Dict(
            "success" => false,
            "err" => "Streaming request failed: $(e)"
        )
    end
end

"""
Process a single JSON line from the streamed response
"""
function process_json_line(line, all_chunks, buffer, was_thinking, streamCallback, is_final=false)
    try
        json_chunk = JSON3.read(line)
        push!(all_chunks, json_chunk)
        
        if haskey(json_chunk, :result)
            result = json_chunk.result
            
            # Check for rate limiting
            if get(result, :responseType, "") == "limiter"
                # Rate limit hit
                if !isnothing(streamCallback)
                    streamCallback(GrokStreamChunk(
                        get(result, :message, ""),
                        false,
                        "limiter",
                        nothing,
                        true,
                        json_chunk
                    ))
                end
                return
            elseif haskey(result, :message)
                is_thinking = get(result, :isThinking, false)
                
                # Call the callback if provided
                if !isnothing(streamCallback)
                    streamCallback(GrokStreamChunk(
                        get(result, :message, ""),
                        is_thinking,
                        get(result, :responseType, nothing),
                        get(result, :webResults, nothing),
                        is_final,
                        json_chunk
                    ))
                end
                
                # Only append non-thinking messages to the buffer
                if !is_thinking
                    write(buffer, result.message)
                end
            end
        end
    catch e
        # Skip invalid JSON
        println("Error parsing JSON chunk: $e")
    end
end
"""
Extract the full message from buffer or chunks
"""
function extract_full_message(buffer, chunks)
    # First try from buffer
    responseText = String(take!(buffer))
    
    # If buffer is empty, extract from chunks
    if isempty(responseText) && !isempty(chunks)
        for chunk in chunks
            if haskey(chunk, :result) && 
               haskey(chunk.result, :message) && 
               !get(chunk.result, :isThinking, false)
                responseText *= chunk.result.message
            end
        end
    end
    
    return responseText
end