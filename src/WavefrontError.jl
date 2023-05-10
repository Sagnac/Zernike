# Estimates wavefront error by expressing the aberrations as a linear combination
# of weighted Zernike polynomials. The representation is approximate,
# especially for a small set of data.
function Wf(r::Vector, ϕ::Vector, OPD::Vector, n_max::Integer)

    if !allequal(length.((r, ϕ, OPD)))
        error("Vectors must be of equal length.\n")
    end

    j_max = get_j(n_max, n_max)

    Zᵢ = Function[]

    inds = @NamedTuple{j::Int, n::Int, m::Int}[]

    for j = 0:j_max
        Zⱼ, j_n_m = Z(j, Fit())
        push!(Zᵢ, Zⱼ)
        push!(inds, j_n_m)
    end

    # linear least squares
    A = reduce(hcat, Zᵢ[i].(r, ϕ) for i = 1:j_max+1)

    # Zernike expansion coefficients
    v::Vector{Float64} = A \ OPD

    a = @NamedTuple{j::Int, n::Int, m::Int, a::Float64}[]

    # store the non-trivial coefficients
    for (i, aᵢ) in pairs(v)
        aᵢ = round(aᵢ; digits = 3)
        if !iszero(aᵢ)
            push!(a, (; inds[i]..., a = aᵢ))
        end
    end

    # create the fitted polynomial
    ΔW(ρ, θ)::Float64 = ∑(v[i] * Zᵢ[i](ρ, θ) for i = 1:j_max+1)

    return a, v, ΔW

end

function metrics(ΔWp, v)

    # Peak-to-valley wavefront error
    PV = maximum(ΔWp) - minimum(ΔWp)

    # RMS wavefront error
    # where σ² is the variance (second central moment about the mean)
    # the mean is the first a00 piston term
    σ = ∑(v[i]^2 for i = 2:lastindex(v)) |> sqrt

    Strehl_ratio = exp(-(2π * σ)^2)

    return (PV = PV, RMS = σ, Strehl = Strehl_ratio)

end

function format_strings(a::Vector)

    W_LaTeX = "ΔW ≈ "

    function ζ(i, sub_index = 0)
        aᵢ = a[i][:a]
        (sub_index ≠ 1 ? abs(aᵢ) : aᵢ), "Z_{$(a[i][:n])}^{$(a[i][:m])}"
    end

    function η(index, a)
        for i = 1:length(a)-1
            W_LaTeX *= string(ζ(index[i], i)..., a[i+1][:a] > 0 ? " + " : " - ")
        end
    end

    if length(a) > 8
        sorted_indices = sortperm(abs.([aᵢ[:a] for aᵢ ∈ a]); rev = true)
        sorted_indices = [i for i ∈ sorted_indices if a[i][:j] ∉ 0:2]
        subset_a = getindex(a, sorted_indices[1:4])
        η(sorted_indices, subset_a)
        W_LaTeX *= string(ζ(sorted_indices[4])...) * "..."
    else
        η(keys(a), a)
        W_LaTeX *= string(ζ(lastindex(a))...)
    end

    return W_LaTeX

end

function W(r::T, ϕ::T, OPD::T, n_max::Integer) where T <: Vector

    a, v, ΔW = Wf(r, ϕ, OPD, n_max)

    ρ, θ = polar(n_max, n_max)

    # construct the estimated wavefront error
    ΔWp = ΔW.(ρ', θ)

    W_LaTeX = format_strings(a)

    titles = (plot = W_LaTeX, window = "Estimated wavefront error")

    fig = ZPlot(ρ, θ, ΔWp; titles...)
        
    return a, v, metrics(ΔWp, v), fig

end

# methods

W(; r, t, OPD, n_max) = W(r, t, OPD, n_max)

function W(x::Vector, y::Vector, OPD::Vector; n_max::Integer)
    r = hypot.(x, y)
    ϕ = atan.(y, x)
    W(r, ϕ, OPD, n_max; kwargs...)
end

function W(data::Matrix, n_max::Integer)
    r, ϕ, OPD = [data[:, i] for i = 1:3]
    W(r, ϕ, OPD, n_max)
end

W(data; n_max) = W(data, n_max)
