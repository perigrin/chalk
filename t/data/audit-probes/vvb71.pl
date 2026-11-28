my @r; for my $i (1..3) { my $x; my $c = sub { $x .= "a" }; $c->(); $c->(); push @r, $x } print "@r\n";
