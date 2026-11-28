our $x = 1; for my $i (1..3) { local $x = $i; next if $i == 2; print $x } print "$x\n";
