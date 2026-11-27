sub f { my $c = \@_; sub { $c->[0]++ } } my $x=1; my $c = f($x); $c->(); $c->(); print "$x\n";
