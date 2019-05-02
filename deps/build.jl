using CUDAapi


## auxiliary routines

status = 0
function build_warning(reason)
    println("$reason.")
    global status
    status = 1
    # NOTE: it's annoying that we have to `exit(1)`, but otherwise messages are hidden
end

function build_error(reason)
    println(reason)
    exit(1)
end


## main

config_path = joinpath(@__DIR__, "ext.jl")
const previous_config_path = config_path * ".bak"

function write_ext(config)
    open(config_path, "w") do io
        println(io, "# autogenerated file, do not edit")
        for (key,val) in config
            println(io, "const $key = $(repr(val))")
        end
    end
end

function main()
    ispath(config_path) && mv(config_path, previous_config_path; force=true)
    config = Dict{Symbol,Any}(:configured => false)
    write_ext(config)


    ## discover stuff

    toolkit = find_toolkit()

    # required libraries that are part of the CUDA toolkit
    for name in ("cublas", "cusparse", "cusolver", "cufft", "curand")
        lib = Symbol("lib$name")
        config[lib] = find_cuda_library(name, toolkit)
        if config[lib] == nothing
            build_error("Could not find library '$name' (it should be part of the CUDA toolkit)")
        end
    end

    # optional libraries
    for name in ("cudnn", )
        lib = Symbol("lib$name")
        config[lib] = find_cuda_library(name, toolkit)
        if config[lib] == nothing
            build_warning("Could not find optional library '$name'")
        end
    end


    ## (re)generate ext.jl

    function globals(mod)
        all_names = names(mod, all=true)
        filter(name-> !any(name .== [nameof(mod), Symbol("#eval"), :eval]), all_names)
    end

    if isfile(previous_config_path)
        @eval module Previous; include($previous_config_path); end
        previous_config = Dict{Symbol,Any}(name => getfield(Previous, name)
                                           for name in globals(Previous))

        if config == previous_config
            mv(previous_config_path, config_path; force=true)
            return
        end
    end

    config[:configured] = true
    write_ext(config)

    if status != 0
        # we got here, so the status is non-fatal
        build_error("""

            CuArrays.jl has been built successfully, but there were warnings.
            Some functionality may be unavailable.""")
    end
end

main()
