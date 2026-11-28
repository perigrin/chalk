my $x = 1; my $c = sub { my $y = $x; sub { $y++ . $x } }; my $d = $c->(); $x = 5; $d->(); print $d->(), "\n";
