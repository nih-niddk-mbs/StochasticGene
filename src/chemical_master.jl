"""
offonPDF(t::Vector,r::Vector,n::Int,nr::Int)

Active (ON) and Inactive (OFF) time distributions for GRSM model
Takes difference of ON and OFF time CDF to produce PDF
"""
function offonPDF(t::Vector,r::Vector,n::Int,nr::Int)
    gammap,gamman = get_gamma(r,n)
    nu = get_nu(r,n,nr)
    eta = get_eta(r,n,nr)
    T,TA,TI = transition_rate_mat(n,nr,gammap,gamman,nu,eta)
    pss = normalized_nullspace(T)
    SA=ontimeCDF(t,r,n,nr,TA,pss)
    SI=offtimeCDF(t,r,n,nr,TI,pss)
    PI = diff(SI)
    PI /= sum(PI)*(t[2]-t[1])
    PA = diff(SA)
    PA /= sum(PA)*(t[2]-t[1])
    return PI,PA
end
function onCDF(t::Vector,r::Vector,n::Int,nr::Int)
    gammap,gamman = get_gamma(r,n)
    nu = get_nu(r,n,nr)
    eta = get_eta(r,n,nr)
    T,TA,TI = transition_rate_mat(n,nr,gammap,gamman,nu,eta)
    pss = normalized_nullspace(T)
    SA=ontimeCDF(t,r,n,nr,TA,pss)
    return SA
end
"""
ontimeCDF(tin::Vector,n::Int,nr::Int,rin::Vector,TA::Matrix,pss::Vector)
offtimeCDF(tin::Vector,n::Int,nr::Int,r::Vector,TI::Matrix,pss::Vector)

ON(OFF) dwell time distributions of GRS model
Found by computing accumulated probability into OFF(ON) states
where transitions out of OFF(ON) states are zeroed, starting from first instance of ON(OFF) state
weighted by steady state distribution (i.e. solving a first passage time problem)x
"""
function ontimeCDF(tin::Vector,rin::Vector,n::Int,nr::Int,TA::Matrix,pss::Vector)
    t = [tin ; tin[end] + tin[2]-tin[1]] #add a time point so that diff() gives original length
    SAinit = init_prob(pss,n,nr)
    TAvals,TAvects = eig_decompose(TA)
    TAweights = solve_vector(TAvects,SAinit)
    SA = time_evolve(t,TAvals,TAvects,TAweights)  # Probability vector for each state
    accumulate(SA,n,nr)  # accumulated prob into OFF states
end
function offtimeCDF(tin::Vector,r::Vector,n::Int,nr::Int,TI::Matrix,pss::Vector)
    t = [tin ; tin[end] + tin[2]-tin[1]]
    nonzerosI = nonzero_rows(TI)  # only keep nonzero rows to reduce singularity of matrix
    TI = TI[nonzerosI,nonzerosI]
    nI = length(nonzerosI)
    SIinit = init_prob(pss,r,n,nr,nonzerosI)
    TIvals,TIvects = eig_decompose(TI)
    TIweights = solve_vector(TIvects,SIinit)
    SI = time_evolve(t,TIvals,TIvects,TIweights)
    accumulate(SI,n,nr,nonzerosI) # accumulated prob into ON states
end
"""
steady_state_offpath(rin::Vector,n::Int,nr::Int,nhist::Int,nalleles::Int)
GRS model where mRNA decay rate is accelerated to account for nonviability of off-pathway pre-mRNA
from RNA that is recursively spliced
"""
function steady_state_offpath(rin::Vector,n::Int,nr::Int,nhist::Int,nalleles::Int)
    r = copy(rin)
    nu = get_nu(r,n,nr)
    eta = get_eta(r,n,nr)
    r[end] /= survival_fraction(nu,eta,nr)
    steady_state(r,n,nr,nhist,nalleles)
end
"""
steady_state(rin::Vector,n::Int,nr::Int,nhist::Int,nalleles::Int)
Steady state distribution of mRNA in GRM model (which is the same as GRSM model)
"""
function steady_state(rin::Vector,n::Int,nr::Int,nhist::Int,nalleles::Int)
    r = rin/rin[end]
    gammap,gamman = get_gamma(r,n)
    nu = get_nu(r,n,nr)
    T,B = transition_rate_mat(n,nr,gammap,gamman,nu)
    P = initial_pmf(T,nu[end],n,nr,nhist)
    mhist=steady_state(nhist,nu,P,T,B)
    allele_convolve(mhist[1:nhist],nalleles) # Convolve to obtain result for n alleles
end

"""
steady_state(nhist::Int,nalleles::Int,ejectrate,P,T,B,tol = 1e-6)
Iterative algorithm for computing null space of truncated transition rate matrix
of Master equation of GR model to give steady state of mRNA in GRM model
for single allele
"""
function steady_state(nhist::Int,ejectrate,P,T,B,tol = 1e-6)
    total = size(P,2)
    steps = 0
    err = 1.
    A = T - B
    while err > tol && steps < 1000
        P0 = copy(P)
        P[:,1] = try -A\P[:,2]
        catch
            P[:,1] = (-A + UniformScaling(1e-18))\P[:,2]
        end
        for m = 2:total-1
            P[:,m] = @inbounds -(A - UniformScaling(m-1))\((B*P[:,m-1]) + m*P[:,m+1])
        end
        P[:,total] = -(T - UniformScaling(total-1))\((B*P[:,total-1]))
        P /=sum(P)
        err = norm(P-P0,Inf)
        steps += 1
    end
    sum(P,dims=1)   # marginalize over GR states
end
"""
steady_state(r,n,nhist,nalleles)
Steady State of mRNA in G (telelgraph) model
"""
function steady_state(r,lossfactor,n,nhist,nalleles)
    mhist = steady_state(r,n,nhist,nalleles)
    noise_convolve(mhist,lossfactor,nhist)
end

function steady_state(r,n,nhist,nalleles)
    M = Mat(r,n,nhist)
    P = normalized_nullspace(M)
    mhist = marginalize(P,n,nhist)
    allele_convolve(mhist,nalleles)
end

function steady_state_full(r,n,nhist)
    M = Mat(r,n,nhist)
    normalized_nullspace(M)
end
"""
Mat(r,n,nhist)
Transition rate matrix of G model
"""
function Mat(r,n,nhist)
    gammap,gamman = get_gamma(r,n)
    transition_rate_mat(n,gammap,gamman, r[2*n+1],r[2*n+2],nhist)
end
"""
transient(ts::Vector,r,n,nhist,nalleles,P0)

Compute mRNA pmf of GM model at times in vector ts starting
with initial condition P0
"""

"""
transient(t,n::Int,nhist::Int,nalleles::Int,P0,Mvals,Mvects)

Compute mRNA pmf of GM model at time t given initial condition P0
and eigenvalues and eigenvectors of model transition rate matrix
"""
function transient(t,r,lossfactor,n,nhist,nalleles,P0)
    mhist = transient(t,r,n,nhist,nalleles,P0)
    noise_convolve(mhist,lossfactor,nhist)
end

function transient(t::Vector,r,n,nhist,nalleles,P0::Vector)
    M = Mat(r,n,nhist)
    Mvals,Mvects = eig_decompose(M)
    TAweights = solve_vector(Mvects,P0)
    P=time_evolve(t,Mvals,Mvects,TAweights)
    mhist = Array{Float64,2}(undef,nhist,length(t))
    for i in 1:size(P,1)
        p = marginalize(P[i,:],n,nhist)
        mhist[:,i]= allele_convolve(p,nalleles)
    end
    return mhist
end
function transient(t::Float64,r,n,nhist,nalleles,P0::Vector)
    M = Mat(r,n,nhist)
    Mvals,Mvects = eig_decompose(M)
    TAweights = solve_vector(Mvects,P0)
    P=time_evolve(t,Mvals,Mvects,TAweights)
    mhist = marginalize(P,n,nhist)
    allele_convolve(mhist,nalleles)
end
function noise_convolve(mhist,lossfactor,nhist)
    p = zeros(nhist)
    for m in eachindex(mhist)
        d = Poisson(lossfactor*m)
        for c in 1:nhist
            p[c] += mhist[m]*pdf(d,c-1)
        end
    end
    return p
end
"""
time_evolve(t,vals::Vector,vects::Matrix,weights::Vector)
First passage time solution for ON and OFF dwell time distributions
"""
function time_evolve(t::Vector,vals::Vector,vects::Matrix,weights::Vector)
    ntime = length(t)
    n = length(vals)
    S = Array{Float64,2}(undef,ntime,n)
    for j = 1:n
        Sj = zeros(ntime)
        for i = 1:n
            Sj += real(weights[i]*vects[j,i]*exp.(vals[i]*t))
        end
        S[:,j]=Sj
    end
    return S
end
function time_evolve(t::Float64,vals::Vector,vects::Matrix,weights::Vector)
    n = length(vals)
    S = zeros(n)
    for j = 1:n
        for i = 1:n
            S[j] += real(weights[i]*vects[j,i]*exp.(vals[i]*t))
        end
    end
    return S
end

"""
solve_vector(A::Matrix,b::vector)
solve A x = b
If matrix divide has error higher than tol
use SVD and pseudoinverse with threshold
"""
function solve_vector(A::Matrix,b::Vector,th = 1e-16,tol=1e-1)
    x = A\b
    if norm(b-A*x,Inf) > tol
        M = svd(A)
        Sv = M.S
        Sv[abs.(Sv) .< th] .= 0.
        Sv[abs.(Sv) .>= th] = 1 ./ Sv[abs.(Sv) .>= th]
        x = M.V * diagm(Sv) * M.U' * b
    end
    return x[:,1] # return as vector
end
"""
initial_pmf(T,ejectrate,n,nr,nhist)

Tensor product of nullspace of T and Poisson density
with rate = mean ejection rate of mRNA
Used for initial condition of iteration algorithm to
compute steady state pmf of GRM Master Equation
"""
function initial_pmf(T,ejectrate,n,nr,nhist)
    t0 = normalized_nullspace(T)
    ejectrate *= sum(t0[(n+1)*2^(nr-1)+1:end])
    d = Poisson(ejectrate)
    nT = length(t0)
    total = nhist + 2
    P = Array{Float64,2}(undef,nT,total)
    for m = 1:total
        P[:,m] = t0 * pdf(d,m)
    end
    P
end
"""
get_gamma(r,n,nr)
G state forward and backward transition rates
for use in transition rate matrices of Master equation
(different from gamma used in Gillespie algorithms)
"""
function get_gamma(r,n)
    gammaf = zeros(n+2)
    gammab = zeros(n+2)
    for i = 1:n
        gammaf[i+1] = r[2*(i-1)+1]
        gammab[i+1] = r[2*i]
    end
    return gammaf, gammab
end
"""
get_nu(r,n,nr)
R step forward transition rates
"""
function get_nu(r,n,nr)
    r[2*n+1 : 2*n+nr+1]
end
"""
get_eta(r,n,nr)
Intron ejection rates at each R step
"""
function get_eta(r,n,nr)
    eta = zeros(nr)
    eta[1] = r[2*n + 1 + nr + 1]
    for i = 2:nr
        eta[i] = eta[i-1] + r[2*n + 1 + nr + i]
    end
    return eta
end
"""
survival_fraction(nu,eta,nr)
Fraction of introns that are not spliced prior to ejection
"""
function survival_fraction(nu,eta,nr)
    pd = 1.
    for i = 1:nr
        pd *= nu[i+1]/(nu[i+1]+eta[i])
    end
    return pd
end
"""
normalized_nullspace(M::AbstractMatrix)
Compute the normalized null space of a nxn matrix
of rank n-1 using QR decomposition with pivoting
"""
function normalized_nullspace(M::AbstractMatrix)
    F = qr(M,Val(true));  #QR decomposition with pivoting
    R = F.R
    m = size(M,1)
    # if rank(M) == m-1
    p = zeros(m)
    # Back substitution to solve R*p = 0
    p[end] = 1.
    for i in 1:m-1
        p[m-i] = -R[m-i,m-i+1:end]'*p[m-i+1:end]/R[m-i,m-i]
    end
    p /= sum(p);
    return F.P*p
    # else
    #     return zeros(m)
    # end
end
"""
allele_convolve(mhist,nalleles)
Convolve to compute distribution for contributions from multiple alleles
"""
function allele_convolve(mhist,nalleles)
    nhist = length(mhist)
    mhists = Array{Array{Float64,1}}(undef,nalleles)
    mhists[1] = vec(mhist)
    for i = 2:nalleles
        mhists[i] = zeros(nhist)
        for m = 0:nhist-1
            for m2 = 0:min(nhist-1,m)
                mhists[i][m+1] += mhists[i-1][m-m2+1]*mhist[m2+1]
            end
        end
    end
    return mhists[nalleles]
end
"""
init_prob(pss,n,nr)
Initial condition for first passage time calculation of active (ON) state
(Sum over all states with first R step occupied weighted by equilibrium state
of all states with first R step not occupied)
"""
function init_prob(pss,n,nr)
    SAinit = zeros((n+1)*3^nr)
    for z=1:2^(nr-1)
        aSAinit = (n+1) + (n+1)*ternary(vcat(2,digits(z-1,base=2,pad=nr-1)))
        apss = (n+1) + (n+1)*ternary(vcat(0,digits(z-1,base=2,pad=nr-1)))
        SAinit[aSAinit] = pss[apss]
    end
    SAinit / sum(SAinit)
end
"""
init_prob(pss,n,nr)
Initial condition for first passage time calculation of inactive (OFF) state
(Sum over all states with no R step introns occupied weighted by equilibrium state
of all states with a single R step intron not)
"""
function init_prob(pss,r,n,nr,nonzeros)
    SIinit = zeros((n+1)*3^nr)
    nu = get_nu(r,n,nr)
    eta = get_eta(r,n,nr)
    # Start of OFF state by ejection
    for i in 1:n+1, z in 1:2^(nr-1)
        exons = digits(z-1,base=2,pad=nr-1)
        ainit = i + (n+1)*ternary(vcat(exons,0))
        apss = i + (n+1)*ternary(vcat(exons,2))
        SIinit[ainit] += pss[apss]*nu[nr+1]
    end
    # Start of OFF state by splicing
    for i in 1:n+1, z in 1:2^(nr)
        exons = digits(z-1,base=2,pad=nr)
        intronindex = findall(exons.==1)
        ainit = i + (n+1)*ternary(exons)
        for j in intronindex
            introns = copy(exons)
            introns[j] = 2
            apss  = i + (n+1)*ternary(introns)
            SIinit[ainit] += pss[apss]*eta[j]
        end
    end
    SIinit = SIinit[nonzeros]
    SIinit/sum(SIinit)
end
"""
accumulate(SA::Matrix,n,nr)
Sum over all probability vectors accumulated into OFF states
"""
function accumulate(SA::Matrix,n,nr)

    SAj = zeros(size(SA)[1])
    for i=1:n+1, z=1:3^nr
        zdigits = digits(z-1,base=3,pad=nr)
        if ~any(zdigits.>1)
            a = i + (n+1)*(z-1)
            SAj += SA[:,a]
        end
    end
    return SAj
end
"""
accumulate(SI::Matrix,n,nr,nonzeros)
Sum over all probability vectors accumulated into ON states
"""
function accumulate(SI::Matrix,n,nr,nonzeros)
    # Sum over all probability vectors accumulated into ON states
    SIj = zeros(size(SI)[1])
    for i=1:n+1, z=1:3^nr
        zdigits = digits(z-1,base=3,pad=nr)
        if any(zdigits.>1)
            a = i + (n+1)*(z-1)
            if a in nonzeros
                SIj += SI[:,findfirst(a .== nonzeros)]
            end
        end
    end
    return SIj
end
"""
marginalize(p,n,nhist)
Marginalize over G states
"""
function marginalize(p,n,nhist)
    mhist = zeros(nhist)
    nT = n+1
    for m in 1:nhist
        i = (m-1)*nT
        mhist[m] = sum(p[i+1:i+nT])
    end
    return mhist
end