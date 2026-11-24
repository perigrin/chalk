my $e1; my $e2; eval { die "1\n" }; $e1=$@; eval { die "2\n" }; $e2=$@; print $e1,$e2;
