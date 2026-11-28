our $x = 1; for my $i (1..3) { local $x = $x + $i; print $x } print "$x\n";
