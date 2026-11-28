sub f { $_[0]++ } my $t = 0; for my $i (1..3) { my $y = $i; my $r = \$y; f($y); $t += $$r } print "$t\n";
