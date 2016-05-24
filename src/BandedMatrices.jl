__precompile__()

module BandedMatrices
    using Base


import Base: getindex,setindex!,*,.*,+,.+,-,.-,==,<,<=,>,
                >=,./,/,.^,^,\,transpose

export BandedMatrix, bandrange, bzeros,beye,brand,bones,bandwidth




# AbstractBandedMatrix must implement

abstract AbstractBandedMatrix{T} <: AbstractSparseMatrix{T,Int}


bandwidths(A::AbstractBandedMatrix) = bandwidth(A,1),bandwidth(A,2)
bandinds(A::AbstractBandedMatrix) = -bandwidth(A,1),bandwidth(A,2)
bandinds(A::AbstractBandedMatrix,k::Integer) = k==1?-bandwidth(A,1):bandwidth(A,2)
bandrange(A::AbstractBandedMatrix) = -bandwidth(A,1):bandwidth(A,2)



function getindex(A::AbstractBandedMatrix,k::Integer,j::Integer)
    if k>size(A,1) || j>size(A,2)
        throw(BoundsError(A,(k,j)))
    elseif (bandinds(A,1)≤j-k≤bandinds(A,2))
        unsafe_getindex(A,k,j)
    else
        zero(eltype(A))
    end
end

# override bandwidth(A,k) for each AbstractBandedMatrix
# override unsafe_getindex(A,k,j)



## Gives an iterator over the banded entries of a BandedMatrix

immutable BandedIterator
    n::Int
    m::Int
    l::Int
    u::Int
end


Base.start(B::BandedIterator)=(1,1)


Base.next(B::BandedIterator,state)=
    state,ifelse(state[1]==min(state[2]+B.l,B.n),
                (max(state[2]+1-B.u,1),state[2]+1),
                (state[1]+1,  state[2])
                 )

Base.done(B::BandedIterator,state)=state[2]>B.m || state[2]>B.n+B.u

Base.eltype(::Type{BandedIterator})=Tuple{Int,Int}

# Commented out since there's an error

# function Base.length(B::BandedIterator)
#     if B.m > B.n
#         p=max(0,B.u+B.n-B.m)
#         B.n*(B.u+1)+
#             div(B.l*(2*B.n-B.l-1),2)-div(p*(1+p),2)
#     else
#         p=max(0,B.l+B.m-B.n)
#         B.m*(B.l+1)+
#             div(B.u*(2*B.m-B.u-1),2)-div(p*(1+p),2)
#     end
# end

# returns an iterator of each index in the banded part of a matrix
eachbandedindex(B)=BandedIterator(size(B,1),size(B,2),bandwidth(B,1),bandwidth(B,2))




##
# Represent a banded matrix
# [ a_11 a_12
#   a_21 a_22 a_23
#   a_31 a_32 a_33 a_34
#        a_42 a_43 a_44  ]
# ordering the data like  (columns first)
#       [ *      a_12   a_23    a_34
#         a_11   a_22   a_33    a_44
#         a_21   a_32   a_43    *
#         a_31   a_42   *       *       ]
###
type BandedMatrix{T} <: AbstractBandedMatrix{T}
    data::Matrix{T}  # l+u+1 x n (# of columns)
    m::Int #Number of rows
    l::Int # lower bandwidth ≥0
    u::Int # upper bandwidth ≥0
    function BandedMatrix(data::Matrix{T},m,l,u)
        if l < 0 || u < 0
            error("Bandwidths must be non-negative")
        elseif size(data,1)!=l+u+1
            error("Data matrix must have number rows equal to number of bands")
        else
            new(data,m,l,u)
        end
    end
end


include("blas.jl")


## Constructors

BandedMatrix(data::Matrix,m::Integer,a::Integer,b::Integer) = BandedMatrix{eltype(data)}(data,m,a,b)

BandedMatrix{T}(::Type{T},n::Integer,m::Integer,a::Integer,b::Integer) = BandedMatrix{T}(Array(T,b+a+1,m),n,a,b)
BandedMatrix{T}(::Type{T},n::Integer,a::Integer,b::Integer) = BandedMatrix(T,n,n,a,b)
BandedMatrix{T}(::Type{T},n::Integer,::Colon,a::Integer,b::Integer) = BandedMatrix(T,n,n+b,a,b)


BandedMatrix(data::Matrix,m::Integer,a) = BandedMatrix(data,m,-a[1],a[end])
BandedMatrix{T}(::Type{T},n::Integer,m::Integer,a) = BandedMatrix(T,n,m,-a[1],a[end])
BandedMatrix{T}(::Type{T},n::Integer,::Colon,a) = BandedMatrix(T,n,:,-a[1],a[end])
BandedMatrix{T}(::Type{T},n::Integer,a) = BandedMatrix(T,n,-a[1],a[end])


Base.convert{V}(::Type{BandedMatrix{V}},M::BandedMatrix) = BandedMatrix{V}(convert(Matrix{V},M.data),M.m,M.l,M.u)
function Base.convert{BM<:BandedMatrix}(::Type{BM},M::Matrix)
    ret=BandedMatrix(eltype(BM)==Any?eltype(M):promote_type(eltype(BM),eltype(M)),size(M,1),size(M,2),size(M,1)-1,size(M,2)-1)
    for k=1:size(M,1),j=1:size(M,2)
        ret[k,j]=M[k,j]
    end
    ret
end


Base.promote_rule{T,V}(::Type{BandedMatrix{T}},::Type{BandedMatrix{V}})=BandedMatrix{promote_type(T,V)}



for (op,bop) in ((:(Base.rand),:brand),(:(Base.zeros),:bzeros),(:(Base.ones),:bones))
    @eval begin
        $bop{T}(::Type{T},n::Integer,m::Integer,a::Integer,b::Integer)=BandedMatrix($op(T,b+a+1,m),n,a,b)
        $bop{T}(::Type{T},n::Integer,a::Integer,b::Integer)=$bop(T,n,n,a,b)
        $bop{T}(::Type{T},n::Integer,::Colon,a::Integer,b::Integer)=$bop(T,n,n+b,a,b)
        $bop{T}(::Type{T},::Colon,m::Integer,a::Integer,b::Integer)=$bop(T,m+a,m,a,b)
        $bop(n::Integer,m::Integer,a::Integer,b::Integer)=$bop(Float64,n,m,a,b)
        $bop(n::Integer,a::Integer,b::Integer)=$bop(n,n,a,b)

        $bop{T}(::Type{T},n::Integer,m::Integer,a)=$bop(T,n,m,-a[1],a[end])
        $bop{T}(::Type{T},n::Number,::Colon,a)=$bop(T,n,:,-a[1],a[end])
        $bop{T}(::Type{T},::Colon,m::Integer,a)=$bop(T,:,m,-a[1],a[end])
        $bop{T}(::Type{T},n::Integer,a)=$bop(T,n,-a[1],a[end])
        $bop(n::Integer,m::Integer,a)=$bop(Float64,n,m,-a[1],a[end])
        $bop(n::Integer,a)=$bop(n,-a[1],a[end])

        $bop(B::AbstractBandedMatrix)=$bop(eltype(B),size(B,1),size(B,2),bandwidth(B,1),bandwidth(B,2))
    end
end

Base.similar(B::AbstractBandedMatrix)=BandedMatrix(eltype(B),size(B,1),size(B,2),bandwidth(B,1),bandwidth(B,2))



function beye{T}(::Type{T},n::Integer,a...)
    ret=bzeros(T,n,a...)
    for k=1:n
         ret[k,k]=one(T)
    end
    ret
end
beye{T}(::Type{T},n::Integer) = beye(T,n,0,0)
beye(n::Integer) = beye(n,0,0)
beye(n::Integer,a...) = beye(Float64,n,a...)



## Abstract Array Interface

Base.size(A::BandedMatrix,k) = ifelse(k==2,size(A.data,2),A.m)
Base.size(A::BandedMatrix) = A.m,size(A.data,2)

Base.linearindexing{T}(::Type{BandedMatrix{T}})=Base.LinearSlow()


unsafe_getindex(A::BandedMatrix,k::Integer,j::Integer)=A.data[k-j+A.u+1,j]


function getindex(A::BandedMatrix,kr::UnitRange,jr::UnitRange)
    shft=first(kr)-first(jr)
    if A.l-shft ≥ 0 && A.u+shft ≥ 0
        BandedMatrix(A.data[:,jr],length(kr),A.l-shft,A.u+shft)
    else
        #TODO: Make faster
        ret=bzeros(eltype(A),length(kr),length(jr),max(0,A.l-shft),max(0,A.u+shft))
        for (k,j) in eachbandedindex(ret)
            ret[k,j]=A[kr[k],jr[j]]
        end
        ret
    end
end

getindex(A::BandedMatrix,::Colon,jr::UnitRange)=A[1:size(A,1),jr]
getindex(A::BandedMatrix,kr::UnitRange,jr::Colon)=A[kr,1:size(A,2)]
getindex(A::BandedMatrix,kr::Colon,jr::Colon)=copy(A)



unsafe_setindex!(A::BandedMatrix,v,k::Integer,j::Integer)=(@inbounds A.data[k-j+A.u+1,j]=v)
function setindex!(A::BandedMatrix,v,k::Integer,j::Integer)
    if k>size(A,1) || j>size(A,2)
        throw(BoundsError(A,(k,j)))
    elseif (bandinds(A,1)≤j-k≤bandinds(A,2))
        unsafe_setindex!(A,v,k,j)
    else
        error("Attempt to set array outside of bands $(bandwidth(A,1)), $(bandwidth(A,2))")
    end
end





# Additional get index overrides
unsafe_getindex(A::BandedMatrix,kr::Range,jr::Integer)=vec(A.data[kr-j+A.u+1,j])

getindex(A::BandedMatrix,kr::Range,j::Integer)=-A.l≤j-kr[1]≤j-kr[end]≤A.u?unsafe_getindex(A,kr,j):[A[k,j] for k=kr]

getindex(A::BandedMatrix,kr::Range,j::Integer)=[A[k,j] for k=kr]
getindex(A::BandedMatrix,kr::Range,jr::Range)=[A[k,j] for k=kr,j=jr]


function setindex!(A::BandedMatrix,v,kr::Range,jr::Range)
    for j in jr
        A[kr,j]=slice(v,:,j)
    end
end
function setindex!(A::BandedMatrix,v,k::Integer,jr::Range)
    for j in jr
        A[k,j]=v[j]
    end
end



function Base.full(A::BandedMatrix)
    ret=zeros(eltype(A),size(A,1),size(A,2))
    for (k,j) in eachbandedindex(A)
        @inbounds ret[k,j]=A[k,j]
    end
    ret
end


## Band range

bandwidth(A::BandedMatrix,k)=k==1?A.l:A.u


function Base.sparse(B::BandedMatrix)
    i=Array(Int,length(B.data));j=Array(Int,length(B.data))
    n,m=size(B.data)
    Bn=size(B,1)
    vb=copy(vec(B.data))
    for κ=1:n,ℓ=1:m
        j[κ+n*(ℓ-1)]=ℓ
        ii=κ+ℓ-B.u-1
        if ii <1 || ii > Bn
            vb[κ+n*(ℓ-1)] = 0
        end
        i[κ+n*(ℓ-1)]=min(max(ii,1),Bn)
    end

    sparse(i,j,vb,Bn,m)
end




# pass standard routines to full matrix

Base.norm(B::BandedMatrix,opts...)=norm(full(B),opts...)


# We turn off bound checking to allow nicer syntax without branching
#setindex!(A::BandedMatrix,v,k::Integer,j::Integer)=((A.l≤j-k≤A.u)&&k≤A.n)?ussetindex!(A,v,k,j):throw(BoundsError())
#setindex!(A::BandedMatrix,v,kr::Range,j::Integer)=(A.l≤j-kr[end]≤j-kr[1]≤A.u&&kr[end]≤A.n)?ussetindex!(A,v,kr,j):throw(BoundsError())


## ALgebra and other functions

function Base.maximum(B::BandedMatrix)
    m=zero(eltype(B))
    for (k,j) in eachbandedindex(B)
        m=max(B[k,j],m)
    end
    m
end


for OP in (:*,:.*,:+,:.+,:-,:.-)
    @eval begin
        $OP(B::BandedMatrix{Bool},x::Bool) = BandedMatrix($OP(B.data,x),B.m,B.l,B.u)
        $OP(x::Bool,B::BandedMatrix{Bool}) = BandedMatrix($OP(x,B.data),B.m,B.l,B.u)
        $OP(B::BandedMatrix,x::Number) = BandedMatrix($OP(B.data,x),B.m,B.l,B.u)
        $OP(x::Number,B::BandedMatrix) = BandedMatrix($OP(x,B.data),B.m,B.l,B.u)
    end
end

function +{T,V}(A::BandedMatrix{T},B::BandedMatrix{V})
    if size(A) != size(B)
        throw(DimensionMismatch("+"))
    end
    n,m=size(A,1),size(A,2)

    ret = bzeros(promote_type(T,V),n,m,max(A.l,B.l),max(A.u,B.u))
    BLAS.axpy!(1.,A,ret)
    BLAS.axpy!(1.,B,ret)

    ret
end

function -{T,V}(A::BandedMatrix{T},B::BandedMatrix{V})
    if size(A) != size(B)
        throw(DimensionMismatch("+"))
    end
    n,m=size(A,1),size(A,2)

    ret = bzeros(promote_type(T,V),n,m,max(A.l,B.l),max(A.u,B.u))
    BLAS.axpy!(1.,A,ret)
    BLAS.axpy!(-1.,B,ret)

    ret
end


function *(A::BandedMatrix,B::BandedMatrix)
    if size(A,2)!=size(B,1)
        throw(DimensionMismatch("*"))
    end
    n,m=size(A,1),size(B,2)

    ret=BandedMatrix(promote_type(eltype(A),eltype(B)),n,m,A.l+B.l,A.u+B.u)
    for (k,j) in eachbandedindex(ret)
        νmin=max(1,k-bandwidth(A,1),j-bandwidth(B,2))
        νmax=min(size(A,2),k+bandwidth(A,2),j+bandwidth(B,1))

        ret[k,j]=A[k,νmin]*B[νmin,j]
        for ν=νmin+1:νmax
            ret[k,j]+=A[k,ν]*B[ν,j]
        end
    end

    ret
end



function *{T<:Number,V<:Number}(A::BandedMatrix{T},B::BandedMatrix{V})
    if size(A,2)!=size(B,1)
        throw(DimensionMismatch("*"))
    end
    n,m=size(A,1),size(B,2)

    A_mul_B!(bzeros(promote_type(T,V),n,m,A.l+B.l,A.u+B.u),A,B)
end

function *{T<:Number,V<:Number}(A::BandedMatrix{T},B::Matrix{V})
    if size(A,2)!=size(B,1)
        throw(DimensionMismatch("*"))
    end
    n,m=size(A,1),size(B,2)

    A_mul_B!(Array(promote_type(T,V),n,m),A,B)
end



*{T}(A::BandedMatrix{T},b::Vector{T})=BLAS.gbmv('N',A.m,A.l,A.u,one(T),A.data,b)

function *(A::BandedMatrix,b::Vector)
    T=promote_type(eltype(A),eltype(b))
    convert(BandedMatrix{T},A)*convert(Vector{T},b)
end

function Base.transpose(B::BandedMatrix)
    Bt=bzeros(eltype(B),size(B,2),size(B,1),B.u,B.l)
    for (k,j) in eachbandedindex(B)
       Bt[j,k]=B[k,j]
    end
    Bt
end

function Base.ctranspose(B::BandedMatrix)
    Bt=bzeros(eltype(B),size(B,2),size(B,1),B.u,B.l)
    for (k,j) in eachbandedindex(B)
       Bt[j,k]=conj(B[k,j])
    end
    Bt
end



function Base.diag{T}(A::BandedMatrix{T})
    n=size(A,1)
    @assert n==size(A,2)

    vec(A.data[A.u+1,1:n])
end




## Matrix.*Matrix

function .*(A::BandedMatrix,B::BandedMatrix)
    @assert size(A,1)==size(B,1)&&size(A,2)==size(B,2)

    l=min(A.l,B.l);u=min(A.u,B.u)
    T=promote_type(eltype(A),eltype(B))
    ret=BandedMatrix(T,size(A,1),size(A,2),l,u)

    for (k,j) in eachbandedindex(ret)
        @inbounds ret[k,j]=A[k,j]*B[k,j]
    end
    ret
end


#implements fliplr(flipud(A))
function fliplrud(A::BandedMatrix)
    n,m=size(A)
    l=A.u+n-m
    u=A.l+m-n
    ret=BandedMatrix(eltype(A),n,m,l,u)
    for (k,j) in eachbandedindex(ret)
        @inbounds ret[k,j]=A[n-k+1,m-j+1]
    end
    ret
end


for OP in (:(Base.real),:(Base.imag))
    @eval $OP(A::BandedMatrix) =
        BandedMatrix($OP(A.data),A.m,A.l,A.u)
end



## Show

type PrintShow
    str
end
Base.show(io::IO,N::PrintShow) = print(io,N.str)

function Base.showarray(io::IO,B::AbstractBandedMatrix;
                   header::Bool=true, limit::Bool=Base._limit_output,
                   sz = (s = Base.tty_size(); (s[1]-4, s[2])), repr=false)
    header && print(io,summary(B))

    if !isempty(B) && size(B,1) ≤ 1000 && size(B,2) ≤ 1000
        header && println(io,":")
        M=Array(Any,size(B)...)
        fill!(M,PrintShow(""))
        for (k,j) in eachbandedindex(B)
            M[k,j]=B[k,j]
        end

        Base.showarray(io,M;header=false)
    end
end


## SubArray routines

bandshift(S) = first(parentindexes(S)[1])-first(parentindexes(S)[2])

bandwidth{T,BM<:BandedMatrix}(S::SubArray{T,2,BM},k) = bandwidth(parent(S),k) +
        (k==1?-1:1)*bandshift(S)


unsafe_getindex{T,BM<:BandedMatrix}(S::SubArray{T,2,BM},k,j) =
    unsafe_getindex(parent(S),parentindexes(S)[1][k],parentindexes(S)[2][j])



end #module
