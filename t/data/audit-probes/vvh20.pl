sub f { eval { die "z\n" }; return "c$@" if $@; 7 } print f();
