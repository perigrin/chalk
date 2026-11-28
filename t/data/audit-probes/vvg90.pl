my $x = 1; my $c = sub { sub { $x++ } }; my $d = $c->(); $d->(); $d->(); print "$x\n";
