our $x=1; for my $k (1..3) { no strict "refs"; ${"x"}+=$k } print "$x\n";
