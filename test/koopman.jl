
@testset "DMD" begin
    # Create some linear data
    A = [0.9 -0.2; 0.0 0.2]
    y = [[10.; -10.]]
    for i in 1:10
        push!(y, A*y[end])
    end
    X = hcat(y...)
    @test_throws AssertionError ExactDMD(X[:, 1:end-2], dt = -1.0)
    estimator = ExactDMD(X[:,1:end-2])
    @test isstable(estimator)
    @test estimator.Ã ≈ A
    @test eigvals(estimator) ≈ eigvals(A)
    @test eigvecs(estimator) ≈ eigvecs(A)
    @test_nowarn dynamics(estimator)
    @test_throws AssertionError dynamics(estimator, discrete = false)
    @test_nowarn update!(estimator, X[:, end-1], X[:,end])
end

@testset "EDMD" begin
    # Test for linear system
    function linear_sys(u, p, t)
        x = -0.9*u[1]
        y = -0.3*u[2]
        return [x;y]
    end

    u0 = [π; 1.0]
    tspan = (0.0, 20.0)
    prob = DiscreteProblem(linear_sys, u0, tspan)
    sol = solve(prob,FunctionMap())

    @variables u[1:2]
    h = [1u[1]; 1u[2]; sin(u[1]); cos(u[1]); u[1]*u[2]]
    basis = Basis(h, u)

    @test_throws AssertionError ExtendedDMD(sol[:,:], basis, dt = -1.0)
    estimator = ExtendedDMD(sol[:,:], basis)
    @test basis == estimator.basis
    basis_2 = reduce_basis(estimator, threshold = 1e-5)
    @test size(basis_2)[1] < size(basis)[1]
    estimator_2 = ExtendedDMD(sol[:,:], basis_2)
    p1 = DiscreteProblem(dynamics(estimator), u0, tspan, [])
    s1 = solve(p1,FunctionMap())
    p2 = DiscreteProblem(dynamics(estimator_2), u0, tspan, [])
    s2 = solve(p2,FunctionMap())
    p3 = DiscreteProblem(linear_dynamics(estimator_2), estimator_2(u0), tspan, [])
    s3 = solve(p3,FunctionMap())
    @test sol[:,:] ≈ s1[:,:]
    @test sol[:,:] ≈ s2[:,:]
    @test estimator_2.basis(sol[:,:])≈ s3[:,:]
    @test eigvals(estimator_2) ≈ [-0.9; -0.3]

    # Test for nonlinear system
    function nonlinear_sys(du, u, p, t)
        du[1] = sin(u[1])
        du[2] = -0.3*u[2] -0.9*u[1]
    end

    prob = DiscreteProblem(nonlinear_sys, u0, tspan)
    sol = solve(prob,FunctionMap())
    estimator = ExtendedDMD(sol[:,:], basis)
    p4 = DiscreteProblem(dynamics(estimator), u0, tspan, [])
    s4 = solve(p4,FunctionMap())
    @test sol[:,:] ≈ s4[:,:]
end


@testset "DMDc" begin
    # Define measurements from unstable system with known control input
    X = [4 2 1 0.5 0.25; 7 0.7 0.07 0.007 0.0007]
    U = [-4 -2 -1 -0.5]
    B = Float32[1; 0]

    # But with a little more knowledge
    sys = DMDc(X, U, B = B)
    @test isa(get_dynamics(sys), ExactDMD)
    @test sys.koopman.Ã ≈[1.5 0; 0 0.1]
    @test get_input_map(sys) ≈ [1.0; 0.0]
    @test !isstable(sys)
    @test_nowarn eigen(sys)

    # Check the solution of an unforced and forced system against each other
    dudt_ = dynamics(sys)
    prob = DiscreteProblem(dudt_, X[:, 1], (0., 10.))
    sol_unforced = solve(prob,  FunctionMap())

    dudt_ = dynamics(sys, control = (u, p, t) -> -0.5u[1])
    prob = DiscreteProblem(dudt_, X[:, 1], (0., 10.))
    sol = solve(prob, FunctionMap())

    @test all(abs.(diff(sol[1,:])) .< 1e-5)
    @test sol[2,:] ≈ sol_unforced[2,:]
end
