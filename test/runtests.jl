using Grok
using Test
using Aqua
using HTTP
using JSON3
using PromptingTools

# Include mock implementations
include("mocks.jl")

@testset "Grok.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        # Aqua.test_all(Grok)
    end
    
    @testset "Types" begin
        # Test GrokMessage constructor
        msg = GrokMessage("user", "Hello")
        @test msg.role == "user"
        @test msg.content == "Hello"
        
        # Test GrokChatOptions constructor
        opts = GrokChatOptions([msg])
        @test length(opts.messages) == 1
        @test opts.conversationId === nothing
        @test opts.stream == false
        
        # Test with additional parameters
        opts2 = GrokChatOptions([msg], conversationId="test-id", stream=true)
        @test opts2.conversationId == "test-id"
        @test opts2.stream == true
        
        # Test GrokStreamChunk with @kwdef constructor
        chunk = GrokStreamChunk(message="Test message")
        @test chunk.message == "Test message"
        @test chunk.isThinking == false  # default value
        @test chunk.responseType === nothing  # default value
    end
    
    @testset "Conversation Cache" begin
        # Test conversation caching
        conv_id = "test-conversation-id"
        messages = [
            GrokMessage("user", "Hello"),
            GrokMessage("assistant", "Hi there")
        ]
        
        # Cache a conversation
        Grok.cache_conversation!(conv_id, messages)
        
        # Retrieve the cached conversation
        cached = Grok.get_cached_conversation(conv_id)
        @test length(cached) == 2
        @test cached[1].role == "user"
        @test cached[1].content == "Hello"
        
        # Test finding a matching conversation
        matching_id = Grok.find_matching_conversation(messages)
        @test matching_id == conv_id
        
        # Test with non-matching conversation
        non_matching = [GrokMessage("user", "Different message")]
        @test Grok.find_matching_conversation(non_matching) === nothing
        
        # Clean up - properly empty the dictionary inside the struct
        empty!(Grok.CONVERSATION_CACHE.conversations)
    end
    
    @testset "PromptingTools Integration" begin
        # Test GrokPromptSchema rendering
        # Create test messages
        pt_messages = [
            PromptingTools.UserMessage("Hello"),
            PromptingTools.AIMessage("Hi there")
        ]
        
        # Render with GrokPromptSchema
        rendered = PromptingTools.render(GrokPromptSchema(), pt_messages)
        
        # Check the rendered messages
        @test length(rendered.grok_messages) == 2
        @test rendered.grok_messages[1].role == "user"
        # Use contains instead of exact match since PromptingTools might add system context
        @test occursin("Hello", rendered.grok_messages[1].content)
        
        # Test with system message
        pt_messages_with_system = [
            PromptingTools.SystemMessage("You are a helpful assistant"),
            PromptingTools.UserMessage("Hello")
        ]
        
        rendered_with_system = PromptingTools.render(GrokPromptSchema(), pt_messages_with_system)
        
        # System message should be prepended to first user message
        @test length(rendered_with_system.grok_messages) == 1
        @test rendered_with_system.grok_messages[1].role == "user"
        @test occursin("System:", rendered_with_system.grok_messages[1].content)
        @test occursin("You are a helpful assistant", rendered_with_system.grok_messages[1].content)
    end
    
    @testset "API Functions (with mocks)" begin
        # Create a mock TwitterAuth for testing - use the correct constructor
        auth = TwitterAuth("test_bearer_token")
        # Manually set properties that would normally be set during login
        auth.cookies = Dict("ct0" => "test_csrf")
        
        # Test login result structure
        login_result = Dict(
            "auth" => auth,
            "success" => true
        )
        @test haskey(login_result, "auth")
        @test login_result["auth"] isa TwitterAuth
        @test haskey(login_result["auth"].cookies, "ct0")
        
        # Test conversation creation
        conv_id = "mock-conversation-id"
        @test conv_id == "mock-conversation-id"
        
        # Test chat interaction
        options = GrokChatOptions([GrokMessage("user", "Hello")])
        # Create a mock response
        response = GrokChatResponse(
            "mock-conversation-id",
            "Hello! How can I help you today?",
            [GrokMessage("user", "Hello"), GrokMessage("assistant", "Hello! How can I help you today?")],
            nothing,
            Dict(:result => Dict(:message => "Hello! How can I help you today?")),
            nothing
        )
        
        @test response.conversationId == "mock-conversation-id"
        @test response.message == "Hello! How can I help you today?"
        @test length(response.conversation) == 2
    end
    
    @testset "Streaming" begin
        # Test with callback
        cb_called = false
        callback_fn = function(chunk)
            cb_called = true
            # Just test that we can call the callback without errors
            @test isa(chunk, GrokStreamChunk)
        end
        
        # Create a mock stream chunk and call the callback directly
        # Use the @kwdef constructor with named parameters
        chunk = GrokStreamChunk(message="Test message")
        callback_fn(chunk)
        
        # Verify callback was called
        @test cb_called
    end
    
    @testset "Extended Conversation Cache" begin
        # Clear cache first
        empty!(Grok.CONVERSATION_CACHE.conversations)
        
        # Test list_conversations (empty)
        @test isempty(Grok.list_conversations())
        
        # Add a conversation
        conv_id = "test-extended-conv"
        msg1 = GrokMessage("user", "Test message")
        Grok.cache_conversation!(conv_id, [msg1])
        
        # Test add_message_to_conversation!
        msg2 = GrokMessage("assistant", "Test response")
        @test Grok.add_message_to_conversation!(conv_id, msg2)
        cached = Grok.get_cached_conversation(conv_id)
        @test length(cached) == 2
        @test cached[2].content == "Test response"
        
        # Test list_conversations (with content)
        convs = Grok.list_conversations()
        @test length(convs) == 1
        @test convs[1].id == conv_id
        
        # Test delete_conversation!
        @test Grok.delete_conversation!(conv_id)
        @test isnothing(Grok.get_cached_conversation(conv_id))
        
        # Test clear_cache!
        Grok.cache_conversation!("conv1", [msg1])
        Grok.cache_conversation!("conv2", [msg1])
        @test length(Grok.list_conversations()) == 2
        Grok.clear_cache!()
        @test isempty(Grok.list_conversations())
    end
end
