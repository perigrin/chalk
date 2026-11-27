my $x = 0; my $c = sub { $x++ }; my $i = 0; while ($x < 3) { $c->(); $i++ } print "$i\n";
