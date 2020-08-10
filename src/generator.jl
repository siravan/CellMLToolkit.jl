relu(x) = x > 0 ? x : zero(x)
plog(x) = log(relu(x))

function generate_functions(name::String, ml::CellModel; p=list_params(ml), u0=list_initial_conditions(ml), level=1)
    io = open(name, "w")
    generate_lists(io, p, u0)
    generate_f(io, ml, p, u0)
    generate_j(io, ml, p, u0; level=level)
    close(io)
end

function generate_preabmle(io, iv, p, u0)
    write(io, "\t$(iv) = tₚ\n\n")

    write(io, "\t# state variables:\n")
    for (i,v) in enumerate(u0)
        write(io, "\t$(first(v)) = uₚ[$i]\n")
    end

    write(io, "\n\t# parameters:\n")

    for (i,v) in enumerate(p)
        write(io, "\t$(first(v)) = pₚ[$i]\n")
    end

    write(io, "\n")
end

function generate_lists(io, p, u0)
    write(io, "# initial conditions\n")
    write(io, "u0 = [" * join(last.(u0), ", ") * "]\n\n")

    write(io, "# parameters\n")
    write(io, "p = [" * join(last.(p), ", ") * "]\n\n")
end

function generate_f(io, ml::CellModel, p, u0)
    write(io, "function f!(duₚ, uₚ, pₚ, tₚ)\n")

    generate_preabmle(io, ml.iv, p, u0)

    write(io, "\t# algebraic equations:\n")

    for a in ml.alg
        eq = simplify(a.rhs)
        write(io, "\t$(a.lhs) = $eq\n")
    end

    write(io, "\n\t# system of ODEs:\n")

    # eqs, v = flat_equations(ml; level=1)

    for a in ml.eqs
        eq = simplify(a.rhs)
        write(io, "\t∂$(a.lhs.args[1]) = $eq\n")
    end

    write(io, "\n\t# state variables:\n")

    for (i,v) in enumerate(u0)
        write(io, "\tduₚ[$i] = ∂$(first(v))\n")
    end

    write(io, "\tnothing\n")
    write(io, "end\n\n")
end

function generate_j(io, ml::CellModel, p, u0; level=1)
    write(io, "function J!(J, uₚ, pₚ, tₚ)\n")

    generate_preabmle(io, ml.iv, p, u0)

    write(io, "\t# Jacobian:\n")

    eqs, v = flat_equations(ml; level=level)
    n = length(v)

    for i = 1:n
        for j = 1:n
            eq = simplify(derivate(eqs[i].rhs, v[j]))
            if !iszero(eq)
                write(io, "\tJ[$i,$j] = $eq\n")
            end
        end
    end

    write(io, "\tnothing\n")
    write(io, "end\n\n")
end


#############################################################################

function derivate(op::Operation, v::Operation)
    n = length(op.args)

    if typeof(op.op) == Variable && op.op == v.op
        return 1
    elseif n == 0
        if op.op == v.op
            return 1
        else
            return 0
        end
    elseif n == 1
        a = derivate(op.args[1], v)
        δa = ModelingToolkit.derivative(op, 1)
        return a * δa
    elseif n >= 2
        l = Operation[]
        for i = 1:n
            push!(l, derivate(op.args[i], v) * ModelingToolkit.derivative(op, i))
        end
        # a = derivate(op.args[1], v)
        # δa = ModelingToolkit.derivative(op, 1)
        # b = derivate(op.args[2], v)
        # δb = ModelingToolkit.derivative(op, 2)
        # return Operation(+, [a * δa, b * δb])
        return Operation(+, l)
    end
end

derivate(::ModelingToolkit.Constant, ::Operation) = 0

import Base.isconst

isconst(x) = (typeof(x) == ModelingToolkit.Constant)
# iszero(x::Operation) = isconst(x) && iszero(x.value)
# isone(x::Operation) = isconst(x) && isone(x.value)
isminusone(x::Operation) = false
isminusone(x::ModelingToolkit.Constant) = isone(-x.value)
isminusone(x) = isone(-x)

simplify(x::ModelingToolkit.Constant) = x.value
simplify(x::Equation) = x.lhs ~ simplify(x.rhs)

function simplify(op::Operation)
    n = length(op.args)

    if n == 0
        return op
    elseif n == 1
        return simplify_unary(op)
    elseif n == 2
        return simplify_binary(op)
    else
        return simplify_nary(op)
        # l = map(simplify, op.args)
        # return Operation(op.op, l)
    end
end

function simplify_unary(op::Operation)
    return op
end

function simplify_binary(op::Operation)
    g = op.op
    x = simplify(op.args[1])
    y = simplify(op.args[2])

    if g == +
        if iszero(x)
            return y
        elseif iszero(y)
            return x
        elseif isconst(x) && isconst(y)
            return x.value + y.value
        else
            return x + y
        end
    elseif g == -
        if iszero(x)
            return -y
        elseif iszero(y)
            return x
        elseif isconst(x) && isconst(y)
            return x.value - y.value
        else
            return x - y
        end
    elseif g == *
        if iszero(x)
            return x
        elseif iszero(y)
            return y
        elseif isone(x)
            return y
        elseif isone(y)
            return x
        elseif isminusone(x)
            return -y
        elseif isminusone(y)
            return -x
        elseif isconst(x) && isconst(y)
            return x.value * y.value
        else
            return x * y
        end
    elseif g == /
        if iszero(x)
            return x
        elseif iszero(y)
            error("divide by zero")
        elseif isone(y)
            return x
        elseif isminusone(y)
            return -x
        elseif isconst(x) && isconst(y)
            return x.value / y.value
        else
            return x / y
        end
    elseif g == ^
        if iszero(x)
            return x
        elseif iszero(y)
            return 1
        elseif isone(x)
            return x
        elseif isone(y)
            return x
        elseif isconst(x) && isconst(y)
            return x.value ^ y.value
        else
            return x ^ y
        end
    else
        Operation(g, [x, y])
    end
end

function simplify_nary(op::Operation)
    g = op.op
    x = simplify(op.args[1])
    y = simplify(Operation(op.op, op.args[2:end]))

    if g == +
        if iszero(x)
            return y
        else
            return x + y
        end
    elseif g == *
        if iszero(x)
            return x
        elseif isone(x)
            return y
        elseif isminusone(x)
            return -y
        else
            return x * y
        end
    else
        return Operation(op.op, [x,y])
    end
end
