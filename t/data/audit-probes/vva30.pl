our $x = 1; my $i = 0; while ($i++ < 3) { local $x = $x + $i; print $x } print "$x\n";
