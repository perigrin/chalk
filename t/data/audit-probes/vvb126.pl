my ($c, @r); for my $i (1..3) { my $x = $i; $c //= sub { $x }; push @r, $c->() } print "@r\n";
