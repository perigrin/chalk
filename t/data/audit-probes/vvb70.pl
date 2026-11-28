my @r; for my $i (1..3) { my $x = $i; my $c = sub { $x += 10 }; $c->(); push @r, $x } print "@r\n";
