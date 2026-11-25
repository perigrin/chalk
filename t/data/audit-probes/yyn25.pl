$@ = "stale"; my $r = eval { 1 }; print "[$@]"; eval { die "x\n" }; { local $@; eval { 1 }; } print $@;
