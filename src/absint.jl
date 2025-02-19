# Abstractly interpret julia from LLVM

# Return (bool if could interpret, julia object interpreted to)
function absint(arg::LLVM.Value, partial::Bool=false)
    if isa(arg, LLVM.CallInst)
        fn = LLVM.called_operand(arg)
        nm = ""
        if isa(fn, LLVM.Function)
            nm = LLVM.name(fn)
        end
        for (fname, ty) in (
                             ("jl_box_int64", Int64), ("ijl_box_int64", Int64),
                             ("jl_box_uint64", UInt64), ("ijl_box_uint64", UInt64),
                             ("jl_box_int32", Int32), ("ijl_box_int32", Int32),
                             ("jl_box_uint32", UInt32), ("ijl_box_uint32", UInt32),
                            )
            if nm == fname
                v = first(operands(arg))
                if isa(v, ConstantInt)
                    return (true, convert(ty, v))
                end
            end
        end
        if nm == "julia.pointer_from_objref"
            return absint(operands(arg)[1], partial)
        end
        if nm == "jl_typeof" || nm == "ijl_typeof"
    		return abs_typeof(operands(arg)[1], partial)
        end
        if LLVM.callconv(arg) == 37 || nm == "julia.call"
            index = 1
            if LLVM.callconv(arg) != 37
                fn = first(operands(arg))
                nm = LLVM.name(fn)
                index += 1
            end
            if nm == "jl_f_apply_type" || nm == "ijl_f_apply_type"
                index += 1
                found = []
                legal, Ty = absint(operands(arg)[index], partial)
                unionalls = []
                for sarg in operands(arg)[index+1:end-1]
                    slegal , foundv = absint(sarg, partial)
                    if slegal
                        push!(found, foundv)
                    elseif partial
                        foundv = TypeVar(Symbol("sarg"*string(sarg)))
                        push!(found, foundv)
                        push!(unionalls, foundv)
                    else
                        legal = false
                        break
                    end
                end

                if legal
                    res = Ty{found...}
                    for u in unionalls
                        res = UnionAll(u, res)
                    end
                    return (true, res)
                end
            end
            if nm == "jl_f_tuple" || nm == "ijl_f_tuple"
                index += 1
                found = []
                legal = true
                for sarg in operands(arg)[index:end-1]
                    slegal , foundv = absint(sarg, partial)
                    if slegal
                        push!(found, foundv)
                    else
                        legal = false
                        break
                    end
                end
                if legal
                    res = (found...,)
                    return (true, res)
                end
            end
        end
    end
    if isa(arg, ConstantExpr)
        ce = arg
        while isa(ce, ConstantExpr)
            if opcode(ce) == LLVM.API.LLVMAddrSpaceCast || opcode(ce) == LLVM.API.LLVMBitCast ||  opcode(ce) == LLVM.API.LLVMIntToPtr
                ce = operands(ce)[1]
            else
                break
            end
        end
        if !isa(ce, LLVM.ConstantInt)
            return (false, nothing)
        end
        ptr = reinterpret(Ptr{Cvoid}, convert(UInt, ce))
        typ = Base.unsafe_pointer_to_objref(ptr)
        return (true, typ)
    end

    if isa(arg, LLVM.LoadInst) && value_type(arg) == LLVM.PointerType(LLVM.StructType(LLVMType[]), Tracked)
        ptr = operands(arg)[1]
        ce = ptr
        while isa(ce, ConstantExpr)
            if opcode(ce) == LLVM.API.LLVMAddrSpaceCast || opcode(ce) == LLVM.API.LLVMBitCast ||  opcode(ce) == LLVM.API.LLVMIntToPtr
                ce = operands(ce)[1]
            else
                break
            end
        end
        if !isa(ce, LLVM.ConstantInt)
            return (false, nothing)
        end
        ptr = unsafe_load(reinterpret(Ptr{Ptr{Cvoid}}, convert(UInt, ce)))
        typ = Base.unsafe_pointer_to_objref(ptr)
        return (true, typ)
    end
    return (false, nothing)
end

function abs_typeof(arg::LLVM.Value, partial::Bool=false)::Union{Tuple{Bool, Type},Tuple{Bool, Nothing}}
	if isa(arg, LLVM.CallInst)
        fn = LLVM.called_operand(arg)
        nm = ""
        if isa(fn, LLVM.Function)
            nm = LLVM.name(fn)
        end

        if nm == "julia.pointer_from_objref"
            return abs_typeof(operands(arg)[1], partial)
        end
        
        for (fname, ty) in (
                             ("jl_box_int64", Int64), ("ijl_box_int64", Int64),
                             ("jl_box_uint64", UInt64), ("ijl_box_uint64", UInt64),
                             ("jl_box_int32", Int32), ("ijl_box_int32", Int32),
                             ("jl_box_uint32", UInt32), ("ijl_box_uint32", UInt32),
                            )
            if nm == fname
                return (true, ty)
            end
        end
        
    	# Type tag is arg 3
        if nm == "julia.gc_alloc_obj" || nm == "jl_gc_alloc_typed" || nm == "ijl_gc_alloc_typed"
        	return absint(operands(arg)[3], partial)
        end
    	# Type tag is arg 1
        if nm == "jl_alloc_array_1d" ||
           nm == "ijl_alloc_array_1d" ||
           nm == "jl_alloc_array_2d" ||
           nm == "ijl_alloc_array_2d" ||
           nm == "jl_alloc_array_3d" ||
           nm == "ijl_alloc_array_3d" ||
           nm == "jl_new_array" ||
           nm == "ijl_new_array"
        	return absint(operands(arg)[1], partial)
        end

        if nm == "jl_new_structt" || nm == "ijl_new_structt"
            return absint(operands(arg)[1], partial)
        end

        if LLVM.callconv(arg) == 37 || nm == "julia.call"
            index = 1
            if LLVM.callconv(arg) != 37
                fn = first(operands(arg))
                nm = LLVM.name(fn)
                index += 1
            end

            if nm == "jl_new_structv" || nm == "ijl_new_structv"
                @assert index == 2
                return absint(operands(arg)[index], partial)
            end

            if nm == "jl_f_tuple" || nm == "ijl_f_tuple"
                index += 1
                found = []
                unionalls = []
                legal = true
                for sarg in operands(arg)[index:end-1]
                    slegal , foundv = abs_typeof(sarg, partial)
                    if slegal
                        push!(found, foundv)
                    elseif partial
                        foundv = TypeVar(Symbol("sarg"*string(sarg)))
                        push!(found, foundv)
                        push!(unionalls, foundv)
                    else
                        legal = false
                        break
                    end
                end
                if legal
                    res = Tuple{found...}
                    for u in unionalls
                        res = UnionAll(u, res)
                    end
                    return (true, res)
                end
            end
        end

        if nm == "julia.call"
            fn = operands(arg)[1]
            nm = ""
            if isa(fn, LLVM.Function)
                nm = LLVM.name(fn)
            end

        end

        if nm == "jl_array_copy" || nm == "ijl_array_copy"
        	return abs_typeof(operands(arg)[1], partial)
        end

        _, RT = enzyme_custom_extract_mi(arg, false)
        if RT !== nothing
            return (true, RT)
        end
    end

    if isa(arg, LLVM.LoadInst)
        larg = operands(arg)[1]
        offset = nothing
        error = false
        while true
            if isa(larg, LLVM.BitCastInst) ||
               isa(larg, LLVM.AddrSpaceCastInst)
               larg = operands(larg)[1]
               continue
            end
            if offset === nothing && isa(larg, LLVM.GetElementPtrInst) && all(x->isa(x, LLVM.ConstantInt), operands(larg)[2:end])
                b = LLVM.IRBuilder() 
                position!(b, larg)
                offty = LLVM.IntType(8*sizeof(Int))
                offset = API.EnzymeComputeByteOffsetOfGEP(b, larg, offty)
                @assert isa(offset, LLVM.ConstantInt)
                offset = convert(Int, offset)
                larg = operands(larg)[1]
                continue
            end
            if isa(larg, LLVM.Argument)
                break
            end
            error = true
            break
        end

        if !error
            if isa(larg, LLVM.Argument)
                f = LLVM.Function(LLVM.API.LLVMGetParamParent(larg))
                idx = only([i for (i, v) in enumerate(LLVM.parameters(f)) if v == larg])
                typ, byref = enzyme_extract_parm_type(f, idx, #=error=#false)
                if typ !== nothing && byref == GPUCompiler.BITS_REF
                    if offset === nothing
                        return (true, typ)
                    else
                        function llsz(ty)
                            if isa(ty, LLVM.PointerType)
                                return sizeof(Ptr{Cvoid})
                            elseif isa(ty, LLVM.IntegerType)
                                return LLVM.width(ty) / 8
                            end
                            error("Unknown llvm type to size: "*string(ty))
                        end
                        @assert Base.isconcretetype(typ)
                        for i in 1:fieldcount(typ)
                            if fieldoffset(typ, i) == offset
                                subT  = fieldtype(typ, i)
                                fsize = if i == fieldcount(typ)
                                    sizeof(typ)
                                else
                                    fieldoffset(typ, i+1)
                                end - offset
                                if fsize == llsz(value_type(larg))
                                    return (true, subT)
                                end
                            end
                        end
                        # @show "not found", typ, offset, [fieldoffset(typ, i) for i in 1:fieldcount(typ)]
                    end
                end
            end
        end
        
    end

    if isa(arg, LLVM.Argument)
        f = LLVM.Function(LLVM.API.LLVMGetParamParent(arg))
        idx = only([i for (i, v) in enumerate(LLVM.parameters(f)) if v == arg])
        typ, byref = enzyme_extract_parm_type(f, idx, #=error=#false)
        if typ !== nothing
            if byref == GPUCompiler.BITS_REF
                typ = Ptr{typ}
            end
            return (true, typ)
        end
    end

    legal, val = absint(arg, partial)
	if legal
		return (true, Core.Typeof(val))
	end
	return (false, nothing)
end

function abs_cstring(arg::LLVM.Value)::Tuple{Bool,String}

    if isa(arg, ConstantExpr)
        ce = arg
	    while isa(ce, ConstantExpr)
	        if opcode(ce) == LLVM.API.LLVMAddrSpaceCast || opcode(ce) == LLVM.API.LLVMBitCast ||  opcode(ce) == LLVM.API.LLVMIntToPtr
	            ce = operands(ce)[1]
	        else
	            break
	        end
	    end
	    if isa(ce, LLVM.GlobalVariable)
	        ce = LLVM.initializer(ce)
	        if (isa(ce, LLVM.ConstantArray) || isa(ce, LLVM.ConstantDataArray)) && eltype(value_type(ce)) == LLVM.IntType(8)
	        	return (true, String(map((x)->convert(UInt8, x), collect(flib)[1:(end-1)])))
		    end

	    end
	end
	return (false, "")
end
