my @r; for my $i (1..3) { my $x = $i; my $c = sub { $x }; push @r, $c->() } print "@r\n";
