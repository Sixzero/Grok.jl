using HTTP
using JSON3
using Dates
using Base64

# Global authentication cache
const AUTH_CACHE = Dict{String, Dict{String, Any}}()

"""
Generate a cache key for login credentials
"""
function generate_auth_cache_key(username::String, password::String, email::Union{String,Nothing})
    # Create a unique key based on credentials
    key_string = string(username, "|", password, "|", email)
    # Convert string to bytes then encode
    return Base64.base64encode(key_string)
end

"""
TwitterAuth structure to handle Twitter authentication
"""
mutable struct TwitterAuth
    bearer_token::String
    cookies::Dict{String,String}
    guest_token::Union{String,Nothing}
    guest_created_at::Union{DateTime,Nothing}
    user_profile::Union{Dict{String,Any},Nothing}
    user_agent::String
    
    # Constructor with default values
    function TwitterAuth(bearer_token::String)
        # Common mobile user agents for more realistic fingerprinting
        mobile_user_agents = [
            "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1",
            "Mozilla/5.0 (Linux; Android 12; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.45 Mobile Safari/537.36",
            "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.210 Mobile Safari/537.36",
            "Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1",
            "Mozilla/5.0 (Linux; Android 10; SM-A505F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/89.0.4389.105 Mobile Safari/537.36"
        ]
        
        # Select a random user agent
        user_agent = mobile_user_agents[rand(1:length(mobile_user_agents))]
        
        new(
            bearer_token, 
            Dict{String,String}(), 
            nothing, 
            nothing,
            nothing,
            user_agent
        )
    end
end

"""
Update the guest token for authentication
"""
function update_guest_token!(auth::TwitterAuth)
    guest_activate_url = "https://api.twitter.com/1.1/guest/activate.json"
    
    headers = [
        "Authorization" => "Bearer $(auth.bearer_token)"
    ]
    
    if !isempty(auth.cookies)
        cookie_str = join(["$k=$v" for (k,v) in auth.cookies], "; ")
        push!(headers, "Cookie" => cookie_str)
    end
    
    response = HTTP.post(
        guest_activate_url,
        headers;
        status_exception=false
    )
    
    # Update cookies from response
    update_cookies_from_headers!(auth, response.headers)
    
    if response.status != 200
        error_body = String(response.body)
        throw(ErrorException("Failed to get guest token: $(response.status) - $error_body"))
    end
    
    o = JSON3.read(response.body)
    if isnothing(o) || !haskey(o, :guest_token)
        throw(ErrorException("guest_token not found in response: $(String(response.body))"))
    end
    
    auth.guest_token = o.guest_token
    auth.guest_created_at = now()
    
    println("Successfully obtained guest token: $(auth.guest_token)")
end

"""
Install CSRF token to headers - similar to TypeScript's installCsrfToken
"""
function install_csrf_token!(headers, auth::TwitterAuth)
    if haskey(auth.cookies, "ct0")
        push!(headers, "x-csrf-token" => auth.cookies["ct0"])
    end
end

"""
Parse and update cookies from Set-Cookie headers
Similar to updateCookieJar in the JavaScript implementation
"""
function update_cookies_from_headers!(auth::TwitterAuth, headers)
    # Find all Set-Cookie headers (case insensitive)
    set_cookie_headers = filter(p -> lowercase(p.first) == "set-cookie", headers)
    
    if !isempty(set_cookie_headers)
        for (_, cookie_header) in set_cookie_headers
            # Split multiple cookies in a single header (separated by commas)
            # But be careful with commas inside quoted values
            cookie_strings = []
            current_cookie = ""
            in_quotes = false
            
            for char in cookie_header
                if char == '"'
                    in_quotes = !in_quotes
                    current_cookie *= char
                elseif char == ',' && !in_quotes
                    # End of a cookie
                    push!(cookie_strings, strip(current_cookie))
                    current_cookie = ""
                else
                    current_cookie *= char
                end
            end
            
            # Don't forget the last cookie
            if !isempty(current_cookie)
                push!(cookie_strings, strip(current_cookie))
            end
            
            # Process each cookie
            for cookie_str in cookie_strings
                # Split the cookie string at the first semicolon to get the name-value part
                parts = split(cookie_str, ";")
                name_value = parts[1]
                
                # Find the position of the first equals sign
                eq_pos = findfirst(isequal('='), name_value)
                
                if !isnothing(eq_pos) && eq_pos > 1
                    # Extract name and value
                    cookie_name = strip(name_value[1:eq_pos-1])
                    cookie_value = strip(name_value[eq_pos+1:end])
                    
                    # Remove quotes if present
                    if startswith(cookie_value, "\"") && endswith(cookie_value, "\"")
                        cookie_value = cookie_value[2:end-1]
                    end
                    
                    # Store in the auth object's cookies dictionary
                    auth.cookies[cookie_name] = cookie_value
                end
            end
        end
    end
end

"""
Execute a flow task in the Twitter authentication process
"""
function execute_flow_task(auth::TwitterAuth, data::Dict)
    onboarding_task_url = "https://api.twitter.com/1.1/onboarding/task.json"
    
    if isnothing(auth.guest_token)
        throw(ErrorException("Authentication token is null or undefined."))
    end
    
    # Prepare cookie string
    cookie_str = join(["$k=$v" for (k,v) in auth.cookies], "; ")
    
    headers = [
        "authorization" => "Bearer $(auth.bearer_token)",
        "cookie" => cookie_str,
        "content-type" => "application/json",
        "User-Agent" => auth.user_agent,
        "x-guest-token" => auth.guest_token,
        "x-twitter-auth-type" => "OAuth2Client",
        "x-twitter-active-user" => "yes",
        "x-twitter-client-language" => "en"
    ]
    
    # Use the dedicated function to install CSRF token
    install_csrf_token!(headers, auth)
    
    # Add credentials: 'include' equivalent - HTTP.jl handles cookies automatically
    response = HTTP.post(
        onboarding_task_url,
        headers,
        JSON3.write(data);
        status_exception=false,
        cookies=true
    )
    
    # Update cookies from response
    update_cookies_from_headers!(auth, response.headers)
    
    if response.status != 200
        return Dict("status" => "error", "err" => String(response.body))
    end
    
    flow = JSON3.read(response.body)
    
    # Check if flow_token is null or missing
    if !haskey(flow, :flow_token) || isnothing(flow.flow_token)
        return Dict("status" => "error", "err" => "flow_token not found.")
    end
    
    # Check if flow_token is a string
    if typeof(flow.flow_token) != String
        return Dict("status" => "error", "err" => "flow_token was not a string.")
    end
    
    # Check for errors
    if haskey(flow, :errors) && !isnothing(flow.errors) && length(flow.errors) > 0
        return Dict(
            "status" => "error",
            "err" => "Authentication error ($(flow.errors[1].code)): $(flow.errors[1].message)"
        )
    end
    
    # Get the first subtask if available
    subtask = haskey(flow, :subtasks) && length(flow.subtasks) > 0 ? flow.subtasks[1] : nothing
    
    # Check for DenyLoginSubtask
    if !isnothing(subtask) && subtask.subtask_id == "DenyLoginSubtask"
        println("Login denied by Twitter security:", subtask)
        return Dict(
            "status" => "error",
            "err" => "Authentication error: DenyLoginSubtask"
        )
    end
    
    return Dict(
        "status" => "success",
        "subtask" => subtask,
        "flowToken" => flow.flow_token
    )
end

"""
Remove specific cookies
"""
function remove_cookie!(auth::TwitterAuth, key::String)
    if haskey(auth.cookies, key)
        delete!(auth.cookies, key)
    end
end

"""
Initialize login by setting up the session
"""
function init_login(auth::TwitterAuth)
    # Reset certain session-related cookies
    remove_cookie!(auth, "twitter_ads_id")
    remove_cookie!(auth, "ads_prefs")
    remove_cookie!(auth, "_twitter_sess")
    remove_cookie!(auth, "zipbox_forms_auth_token")
    remove_cookie!(auth, "lang")
    remove_cookie!(auth, "bouncer_reset_cookie")
    remove_cookie!(auth, "twid")
    remove_cookie!(auth, "twitter_ads_idb")
    remove_cookie!(auth, "email_uid")
    remove_cookie!(auth, "external_referer")
    remove_cookie!(auth, "ct0")
    remove_cookie!(auth, "aa_u")

    return execute_flow_task(auth, Dict(
        "flow_name" => "login",
        "input_flow_data" => Dict(
            "flow_context" => Dict(
                "debug_overrides" => Dict(),
                "start_location" => Dict(
                    "location" => "splash_screen"
                ),
                "client_language" => "en"
            )
        )
    ))
end

"""
Handle JS instrumentation subtask
"""
function handle_js_instrumentation_subtask(auth::TwitterAuth, prev::Dict)
    # Provide a more realistic JS instrumentation response
    js_response = JSON3.write(Dict(
        "rf" => Dict(
            "af" => rand() * 100,
            "bl" => floor(Int, rand() * 500) + 100,
            "ce" => true,
            "dnt" => false,
            "je" => true,
            "jv" => true,
            "re" => true,
            "sc" => Dict(
                "h" => floor(Int, rand() * 500) + 800,
                "w" => floor(Int, rand() * 300) + 400
            ),
            "tz" => -div(Dates.value(now()) - Dates.value(now() - Dates.Hour(1)), 60)  # Timezone offset in minutes
        )
    ))
    
    return execute_flow_task(auth, Dict(
        "flow_token" => prev["flowToken"],
        "subtask_inputs" => [Dict(
            "subtask_id" => "LoginJsInstrumentationSubtask",
            "js_instrumentation" => Dict(
                "response" => js_response,
                "link" => "next_link"
            )
        )]
    ))
end

"""
Handle enter user identifier subtask
"""
function handle_enter_user_identifier_sso(auth::TwitterAuth, prev::Dict, username::String)
    return execute_flow_task(auth, Dict(
        "flow_token" => prev["flowToken"],
        "subtask_inputs" => [Dict(
            "subtask_id" => "LoginEnterUserIdentifierSSO",
            "settings_list" => Dict(
                "setting_responses" => [Dict(
                    "key" => "user_identifier",
                    "response_data" => Dict(
                        "text_data" => Dict("result" => username)
                    )
                )],
                "link" => "next_link"
            )
        )]
    ))
end

"""
Handle enter alternate identifier subtask
"""
function handle_enter_alternate_identifier_subtask(auth::TwitterAuth, prev::Dict, email::String)
    return execute_flow_task(auth, Dict(
        "flow_token" => prev["flowToken"],
        "subtask_inputs" => [Dict(
            "subtask_id" => "LoginEnterAlternateIdentifierSubtask",
            "enter_text" => Dict(
                "text" => email,
                "link" => "next_link"
            )
        )]
    ))
end

"""
Handle enter password subtask
"""
function handle_enter_password(auth::TwitterAuth, prev::Dict, password::String)
    return execute_flow_task(auth, Dict(
        "flow_token" => prev["flowToken"],
        "subtask_inputs" => [Dict(
            "subtask_id" => "LoginEnterPassword",
            "enter_password" => Dict(
                "password" => password,
                "link" => "next_link"
            )
        )]
    ))
end

"""
Handle account duplication check subtask
"""
function handle_account_duplication_check(auth::TwitterAuth, prev::Dict)
    return execute_flow_task(auth, Dict(
        "flow_token" => prev["flowToken"],
        "subtask_inputs" => [Dict(
            "subtask_id" => "AccountDuplicationCheck",
            "check_logged_in_account" => Dict(
                "link" => "AccountDuplicationCheck_false"
            )
        )]
    ))
end

"""
Handle two factor authentication challenge
"""
function handle_two_factor_auth_challenge(auth::TwitterAuth, prev::Dict, secret::String)
    # Generate TOTP code
    # Note: This is a simplified implementation
    # In a real implementation, you would use a proper TOTP library
    totp_code = generate_totp(secret)
    
    for attempts in 1:3
        try
            return execute_flow_task(auth, Dict(
                "flow_token" => prev["flowToken"],
                "subtask_inputs" => [Dict(
                    "subtask_id" => "LoginTwoFactorAuthChallenge",
                    "enter_text" => Dict(
                        "link" => "next_link",
                        "text" => totp_code
                    )
                )]
            ))
        catch err
            sleep(2 * attempts)
            if attempts == 3
                throw(err)
            end
        end
    end
end

"""
Handle acid subtask
"""
function handle_acid(auth::TwitterAuth, prev::Dict, email::Union{String,Nothing})
    return execute_flow_task(auth, Dict(
        "flow_token" => prev["flowToken"],
        "subtask_inputs" => [Dict(
            "subtask_id" => "LoginAcid",
            "enter_text" => Dict(
                "text" => email,
                "link" => "next_link"
            )
        )]
    ))
end

"""
Handle success subtask
"""
function handle_success_subtask(auth::TwitterAuth, prev::Dict)
    return execute_flow_task(auth, Dict(
        "flow_token" => prev["flowToken"],
        "subtask_inputs" => []
    ))
end

"""
Handle deny login subtask
"""
function handle_deny_login_subtask(auth::TwitterAuth, prev::Dict)
    return Dict(
        "status" => "error",
        "err" => "Login blocked by Twitter security. Please try again later or use a different IP address."
    )
end

"""
Simple TOTP implementation (for 2FA)
Note: In a real implementation, you would use a proper TOTP library
"""
function generate_totp(secret::String)
    # This is a placeholder - in a real implementation you would:
    # 1. Decode the base32 secret
    # 2. Calculate the HMAC-SHA1 of the current 30-second time window
    # 3. Extract 6 digits from the HMAC
    
    # For a real implementation, you would use a library like PyOTP or implement the algorithm
    # Here's a simplified version that just returns the current time-based code
    time_step = 30
    t = floor(Int, time() / time_step)
    
    # In a real implementation, this would be HMAC-SHA1(secret, t)
    # For now, we'll just return a 6-digit number based on the current time
    return string(mod(t, 1000000), pad=6)
end

"""
Check if user is logged in
"""
function is_logged_in(auth::TwitterAuth)
    verify_url = "https://api.twitter.com/1.1/account/verify_credentials.json"
    
    headers = [
        "authorization" => "Bearer $(auth.bearer_token)",
        "cookie" => join(["$k=$v" for (k,v) in auth.cookies], "; "),
        "User-Agent" => auth.user_agent
    ]
    
    install_csrf_token!(headers, auth)
    
    if !isnothing(auth.guest_token)
        push!(headers, "x-guest-token" => auth.guest_token)
    end
    
    response = HTTP.get(
        verify_url,
        headers;
        status_exception=false
    )
    
    if response.status != 200
        return false
    end
    
    verify = JSON3.read(response.body)
    
    if haskey(verify, :errors) && length(verify.errors) > 0
        return false
    end
    
    # Parse and store user profile
    auth.user_profile = Dict{String,Any}(
        "id" => verify.id_str,
        "name" => verify.name,
        "username" => verify.screen_name,
        "verified" => verify.verified
    )
    
    return true
end

"""
Get user profile
"""
function get_profile(auth::TwitterAuth)
    if isnothing(auth.user_profile)
        is_logged_in(auth)
    end
    return auth.user_profile
end

"""
Login to Twitter with caching support
"""
function login(username::String, password::String; 
               email::Union{String,Nothing}=nothing, 
               two_factor_secret::Union{String,Nothing}=nothing,
               force::Bool=false)
    # Check cache first unless force=true
    if !force
        cache_key = generate_auth_cache_key(username, password, email)
        
        if haskey(AUTH_CACHE, cache_key)
            cached_auth = AUTH_CACHE[cache_key]
            
            # Verify cached authentication is still valid
            if is_logged_in(cached_auth["auth"])
                println("Using cached authentication for $username")
                return cached_auth
            else
                # Remove invalid cache entry
                delete!(AUTH_CACHE, cache_key)
                println("Cached authentication expired, logging in again")
            end
        end
    end
    
    # Twitter's bearer token
    bearer_token = "AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHbmHVvQxYYpTw%3DckAlMINMjmCwxUcaXbAN4XqJVdgMJaHqNOFgPMK0zN1qLqLQCF"
    
    auth = TwitterAuth(bearer_token)
    
    # Update guest token
    update_guest_token!(auth)
    
    try
        # Initialize login flow
        next = init_login(auth)
        
        while next["status"] == "success" && haskey(next, "subtask") && !isnothing(next["subtask"])
            
            subtask_id = next["subtask"].subtask_id
            
            if subtask_id == "LoginJsInstrumentationSubtask"
                next = handle_js_instrumentation_subtask(auth, next)
            elseif subtask_id == "LoginEnterUserIdentifierSSO"
                next = handle_enter_user_identifier_sso(auth, next, username)
            elseif subtask_id == "LoginEnterAlternateIdentifierSubtask" && !isnothing(email)
                next = handle_enter_alternate_identifier_subtask(auth, next, email)
            elseif subtask_id == "LoginEnterPassword"
                next = handle_enter_password(auth, next, password)
            elseif subtask_id == "AccountDuplicationCheck"
                next = handle_account_duplication_check(auth, next)
            elseif subtask_id == "LoginTwoFactorAuthChallenge"
                if !isnothing(two_factor_secret)
                    next = handle_two_factor_auth_challenge(auth, next, two_factor_secret)
                else
                    return Dict(
                        "success" => false, 
                        "error" => "Requested two factor authentication code but no secret provided"
                    )
                end
            elseif subtask_id == "LoginAcid"
                next = handle_acid(auth, next, email)
            elseif subtask_id == "LoginSuccessSubtask"
                println("Login success subtask detected!")
                next = handle_success_subtask(auth, next)
            elseif subtask_id == "DenyLoginSubtask"
                next = handle_deny_login_subtask(auth, next)
            else
                return Dict(
                    "success" => false,
                    "error" => "Unknown subtask $(subtask_id)"
                )
            end
            
            if next["status"] == "error"
                return Dict("success" => false, "error" => next["err"])
            end
        end
        
        # Verify login was successful
        if is_logged_in(auth)
            result = Dict(
                "success" => true, 
                "auth" => auth,
                "cookies" => auth.cookies,
                "profile" => auth.user_profile
            )
            
            # Cache successful authentication unless force=true
            if !force
                cache_key = generate_auth_cache_key(username, password, email)
                AUTH_CACHE[cache_key] = result
            end
            
            return result
        else
            return Dict(
                "success" => false,
                "error" => "Login completed but verification failed"
            )
        end
        
    catch e
        println("Login error: ", e)
        return Dict("success" => false, "error" => string(e))
    end
end

"""
Clear the authentication cache
"""
function clear_auth_cache!()
    empty!(AUTH_CACHE)
    return nothing
end

