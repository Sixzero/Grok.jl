using Grok
using Test
using Aqua

@testset "Grok.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(Grok)
    end
    # Write your tests here.
end
