my $x = 0; eval { $x = 1; eval { $x = 2; die "in\n" }; $x += 10; die "out\n"; $x = 99 }; print "$x $@";
