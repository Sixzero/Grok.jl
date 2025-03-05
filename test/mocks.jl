# Mock HTTP responses for testing Grok.jl
using HTTP
using JSON3
using Grok

# Mock response data
const MOCK_LOGIN_RESPONSE = Dict(
    "auth_token" => "test_auth_token",
    "csrf_token" => "test_csrf"
)

const MOCK_CONVERSATION_RESPONSE = Dict(
    "data" => Dict(
        "create_grok_conversation" => Dict(
            "conversation_id" => "mock-conversation-id"
        )
    )
)

const MOCK_CHAT_RESPONSE = Dict(
    "conversationId" => "mock-conversation-id",
    "chunks" => [
        Dict(
            "result" => Dict(
                "message" => "Hello! How can I help you today?",
                "isThinking" => false
            ),
            "conversationId" => "mock-conversation-id"
        )
    ]
)

# Create mock objects directly instead of trying to replace functions
function create_mock_auth()
    auth = TwitterAuth("test_bearer_token")
    auth.cookies = Dict("ct0" => "test_csrf")
    return auth
end

function create_mock_chat_response(options::GrokChatOptions)
    message = "Hello! How can I help you today?"
    
    # Call stream callback if provided
    if options.stream && !isnothing(options.streamCallback)
        # Use the @kwdef constructor with named parameters
        chunk = GrokStreamChunk(message=message)
        options.streamCallback(chunk)
    end
    
    # Create full conversation by appending assistant response
    full_conversation = [options.messages..., GrokMessage("assistant", message)]
    
    return GrokChatResponse(
        "mock-conversation-id",
        message,
        full_conversation,
        nothing,
        MOCK_CHAT_RESPONSE["chunks"][1],
        nothing
    )
end
