my $x = 1; my $c = sub { eval { $x = 2; die "z\n" }; $x = 3 if $@ }; $c->(); print "$x\n";
