my ($p, @r); for my $i (1..3) { my $x = $i; $p //= \$x; push @r, $$p } print "@r\n";
