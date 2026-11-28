our $x = 1; eval { $x = 2; die "z\n" }; print "$x$@";
