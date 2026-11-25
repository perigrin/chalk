my $x=5; for my $i (1..3) { $x = $i == 2 ? undef : $i } print defined $x ? $x : "u", "\n";
