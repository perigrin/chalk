my $x = 1; my $c = sub { my $d = sub { $x++ }; $d->(); $d->() }; $c->(); print "$x\n";
