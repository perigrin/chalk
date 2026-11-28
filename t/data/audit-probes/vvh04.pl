my $x = 1; eval { eval { $x = 2; die "a\n" }; $x .= $@; die "b\n" }; print "$x$@";
