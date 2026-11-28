our $x = 1; sub f { local $x = 2; eval { die "q\n" }; $x } print f(), "$x$@";
