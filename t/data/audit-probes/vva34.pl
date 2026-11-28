our $x = 1; eval { local $x = 2; die "z\n" }; print "$x$@";
