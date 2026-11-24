our @s=(1); sub f { local @s=(@s,2); die "n".scalar(@s)."\n" } eval { f() }; print scalar(@s), $@;
