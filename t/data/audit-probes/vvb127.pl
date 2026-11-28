my ($c, @r); for my $i (1..3) { my $x = $i; $c ||= sub { $x++ }; $c->(); push @r, $x } print "@r\n";
