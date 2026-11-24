sub f { local $@="keep"; eval { die "x\n" }; } eval { die "outer\n" }; f(); print $@;
