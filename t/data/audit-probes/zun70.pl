our @s=(1); sub f { local @s=(@s,2); die "x\n" if @s>1; } eval { f() }; print "@s\n";
