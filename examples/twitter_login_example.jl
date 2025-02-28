include("twitter_login.jl")

function main()
    # Get credentials from environment variables
    username = get(ENV, "TWITTER_USERNAME", "")
    password = get(ENV, "TWITTER_PASSWORD", "")
    email = get(ENV, "TWITTER_EMAIL", nothing)
    
    if isempty(username) || isempty(password)
        println("Please set TWITTER_USERNAME and TWITTER_PASSWORD environment variables")
        exit(1)
    end
    
    println("Logging in as $(username)...")
    result = login(username, password; email=email)
    
    if result["success"]
        println("Login successful!")
        
        # Access the authenticated session
        auth = result["auth"]
        profile = result["profile"]
        println("Logged in as: $(profile["name"]) (@$(profile["username"]))")
        
        # Example of how to get cookies for storage
        cookies = result["cookies"]
        println("Got $(length(cookies)) cookies")
        
        # You can save cookies to a file for later use
        open("twitter_cookies.json", "w") do io
            write(io, JSON3.write(cookies))
        end
        println("Saved cookies to twitter_cookies.json")
        
        # Example of how to check if still logged in
        if is_logged_in(auth)
            println("Session is still valid")
        else
            println("Session is no longer valid")
        end
    else
        println("Login failed: $(result["error"])")
    end
end

# Run the example
main()
