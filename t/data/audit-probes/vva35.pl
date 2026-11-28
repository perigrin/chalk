our $x = 1; eval { local $x = 2; eval { local $x = 3; die "z\n" }; print $x; die "y\n" }; print "$x$@";
