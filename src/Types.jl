
# Define the GrokStreamChunk type with keyword constructor
@kwdef struct GrokStreamChunk
  message::String
  isThinking::Bool = false
  responseType::Union{String, Nothing} = nothing
  webResults::Union{Vector, Nothing} = nothing
  isComplete::Union{Bool, Nothing} = nothing
  metadata::Union{Dict, Nothing} = nothing
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
