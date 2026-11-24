my $x=0; my $inc=sub { $x++ }; my $t=0; for (1..3) { $t+=$x; $inc->() } print "$t $x\n";
