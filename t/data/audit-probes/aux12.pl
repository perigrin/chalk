our $g=1; eval { local $g=2; my $u; my $l = $u->{a}{b}; my @k = keys %$u; print "in\n"; die "x\n" }; print "$g\n";
