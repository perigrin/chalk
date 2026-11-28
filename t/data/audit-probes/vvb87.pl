my @r; for my $i (1..3) { my $x = $i; my $r = \$x; $$r += 10; push @r, $x } print "@r\n";
