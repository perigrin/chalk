eval { die "a\n" }; my $e=$@; eval { 1 }; print $e, "[$@]\n";
