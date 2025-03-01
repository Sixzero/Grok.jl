
# Define the GrokStreamChunk type
struct GrokStreamChunk
  message::String
  isThinking::Bool
  responseType::Union{String, Nothing}
  webResults::Union{Vector, Nothing}
  isComplete::Union{Bool, Nothing}
  metadata::Union{Dict, Nothing}
end

# Define the GrokMessage type
struct GrokMessage
  role::String  # "user" or "assistant"
  content::String
end

# Define the GrokChatOptions type
struct GrokChatOptions
  messages::Vector{GrokMessage}
  conversationId::Union{String, Nothing}
  returnSearchResults::Bool
  returnCitations::Bool
  isReasoning::Bool
  stream::Bool
  streamCallback::Union{Function, Nothing}
end

# Constructor with default values
function GrokChatOptions(
  messages::Vector{GrokMessage};
  conversationId=nothing,
  returnSearchResults=true,
  returnCitations=true,
  isReasoning=false,
  stream=false,
  streamCallback=nothing
)
  return GrokChatOptions(
      messages,
      conversationId,
      returnSearchResults,
      returnCitations,
      isReasoning,
      stream,
      streamCallback
  )
end

# Define the GrokChatResponse type
struct GrokChatResponse
  conversationId::String
  message::String
  messages::Vector{GrokMessage}
  webResults::Union{Vector, Nothing}
  metadata::Union{Dict, Nothing}
  rateLimit::Union{Dict, Nothing}
end
