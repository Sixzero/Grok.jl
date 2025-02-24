using Grok
using Documenter

DocMeta.setdocmeta!(Grok, :DocTestSetup, :(using Grok); recursive=true)

makedocs(;
    modules=[Grok],
    authors="SixZero <havliktomi@hotmail.com> and contributors",
    sitename="Grok.jl",
    format=Documenter.HTML(;
        canonical="https://sixzero.github.io/Grok.jl",
        edit_link="master",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/sixzero/Grok.jl",
    devbranch="master",
)
