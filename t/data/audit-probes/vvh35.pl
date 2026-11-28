eval { die "x\n" }; sub cl { local $@; eval { 1 } } cl(); print $@;
