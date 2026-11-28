my ($p, @r); for my $i (1..3) { my $x = $i; $p = \$x if $i == 1; $$p += 10; push @r, $x } print "@r $$p\n";
