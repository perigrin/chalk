eval { die "a\n" }; my $e=$@; eval { die "b\n" }; print "$e$@";
