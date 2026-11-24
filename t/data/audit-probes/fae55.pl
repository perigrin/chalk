my $t=""; for my $i (1..3) { eval { $t.="a"; die "x\n" if $i==2; $t.="b"; 1 } or do { $t.="E" }; } print "$t\n";
