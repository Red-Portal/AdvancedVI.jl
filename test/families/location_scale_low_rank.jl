
@testset "interface LocationScaleLowRank" begin
    @testset "$(basedist) rank=$(rank) $(realtype)" for
        basedist = [:gaussian],
        rank     = [1, 2],
        realtype = [Float32, Float64]

        n_dims       = 10
        n_montecarlo = 1000_000

        μ = randn(realtype, n_dims)
        D = ones(realtype, n_dims)
        U = randn(realtype, n_dims, rank)
        Σ = Diagonal(D.^2) + U*U'

        q = if basedist == :gaussian
            LowRankGaussian(μ, D, U)
        end
        q_true = if basedist == :gaussian
            MvNormal(μ, Σ)
        end

        @testset "eltype" begin
            @test eltype(q) == realtype
        end

        @testset "logpdf" begin
            z = rand(q)
            @test logpdf(q, z)          ≈  logpdf(q_true, z)  rtol=realtype(1e-2)
            @test eltype(logpdf(q, z))  == realtype 
        end

        @testset "entropy" begin
            @test eltype(entropy(q)) == realtype
            @test entropy(q)         ≈ entropy(q_true)
        end

        @testset "length" begin
            @test length(q) == n_dims
        end

        @testset "statistics" begin
            @testset "mean" begin
                 @test eltype(mean(q)) == realtype
                 @test mean(q)         == μ
            end
            @testset "var" begin
                 @test eltype(var(q)) == realtype
		 @test var(q)         ≈  Diagonal(Σ)
            end
            @testset "cov" begin
                 @test eltype(cov(q)) == realtype
		 @test cov(q)         ≈  Σ
            end
        end

        @testset "sampling" begin
            @testset "rand" begin
                z_samples  = mapreduce(x -> rand(q), hcat, 1:n_montecarlo)
                @test eltype(z_samples) == realtype
                @test dropdims(mean(z_samples, dims=2), dims=2) ≈ μ       rtol=realtype(1e-2)
                @test dropdims(var(z_samples, dims=2),  dims=2) ≈ diag(Σ) rtol=realtype(1e-2)
                @test cov(z_samples, dims=2)                    ≈ Σ       rtol=realtype(1e-2)

                z_sample_ref = rand(StableRNG(1), q)
                @test z_sample_ref == rand(StableRNG(1), q)
            end

            @testset "rand batch" begin
                z_samples  = rand(q, n_montecarlo)
                @test eltype(z_samples) == realtype
                @test dropdims(mean(z_samples, dims=2), dims=2) ≈ μ       rtol=realtype(1e-2)
                @test dropdims(var(z_samples, dims=2),  dims=2) ≈ diag(Σ) rtol=realtype(1e-2)
                @test cov(z_samples, dims=2)                    ≈ Σ       rtol=realtype(1e-2)

                samples_ref = rand(StableRNG(1), q, n_montecarlo)
                @test samples_ref == rand(StableRNG(1), q, n_montecarlo)
            end

            @testset "rand! AbstractVector" begin
                res = map(1:n_montecarlo) do _
                    z_sample     = Array{realtype}(undef, n_dims)
                    z_sample_ret = rand!(q, z_sample)
                    (z_sample, z_sample_ret)
                end
                z_samples     = mapreduce(first, hcat, res)
                z_samples_ret = mapreduce(last, hcat, res)
                @test z_samples == z_samples_ret
                @test dropdims(mean(z_samples, dims=2), dims=2) ≈ μ       rtol=realtype(1e-2)
                @test dropdims(var(z_samples, dims=2),  dims=2) ≈ diag(Σ) rtol=realtype(1e-2)
                @test cov(z_samples, dims=2)                    ≈ Σ       rtol=realtype(1e-2)

                z_sample_ref = Array{realtype}(undef, n_dims)
                rand!(StableRNG(1), q, z_sample_ref)

                z_sample = Array{realtype}(undef, n_dims)
                rand!(StableRNG(1), q, z_sample)
                @test z_sample_ref == z_sample
            end

            @testset "rand! AbstractMatrix" begin
                z_samples     = Array{realtype}(undef, n_dims, n_montecarlo)
                z_samples_ret = rand!(q, z_samples)
                @test z_samples == z_samples_ret
                @test dropdims(mean(z_samples, dims=2), dims=2) ≈ μ       rtol=realtype(1e-2)
                @test dropdims(var(z_samples, dims=2),  dims=2) ≈ diag(Σ) rtol=realtype(1e-2)
                @test cov(z_samples, dims=2)                    ≈ Σ       rtol=realtype(1e-2)

                z_samples_ref = Array{realtype}(undef, n_dims, n_montecarlo)
                rand!(StableRNG(1), q, z_samples_ref)

                z_samples = Array{realtype}(undef, n_dims, n_montecarlo)
                rand!(StableRNG(1), q, z_samples)
                @test z_samples_ref == z_samples
            end
        end
    end

    @testset "diagonal positive definite projection" begin
        @testset "$(realtype) $(bijector)" for
            realtype    = [Float32,     Float64],
            bijector    = [nothing,    :identity]

            rank = 2
            d = 5
            μ = zeros(realtype, d)
            ϵ = sqrt(realtype(0.5))
            D = ones(realtype, d)
            U = randn(realtype, d, rank)
            q = MvLocationScaleLowRank(
                μ, D, U, Normal{realtype}(zero(realtype), one(realtype)); scale_eps=ϵ
            )
            q_trans = if isnothing(bijector) 
                q
            else
                Bijectors.TransformedDistribution(q, identity)
            end
            g = deepcopy(q)

            λ, re   = Optimisers.destructure(q)
            grad, _ = Optimisers.destructure(g)
            opt_st  = Optimisers.setup(Descent(one(realtype)), λ)
            _, λ′    = AdvancedVI.update_variational_params!(typeof(q), opt_st, λ, re, grad)
            q′       = re(λ′)
            @test all(diag(var(q′)) .≥ ϵ^2)
        end
    end
end
