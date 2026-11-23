sub t { my $x = eval { die "q\n" } || 3; $x } print t(), " $@";
