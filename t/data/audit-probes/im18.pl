my $x; { local $@; eval { die "in\n" }; $x = $@ } print "$x";
