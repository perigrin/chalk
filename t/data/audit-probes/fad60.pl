our %c=(a=>1); sub f { local %c=(); die "x\n" } eval { f() }; print join("",%c),"\n";
