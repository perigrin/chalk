my $x = 1; sub t { $x = 2; die "z\n" } eval { t() }; print "$x$@";
