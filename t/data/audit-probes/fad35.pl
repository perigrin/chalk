my $n=0; for my $i (1..3) { eval { for my $j (1..3) { $n++; die "x\n" if $j==$i } }; } print "$n\n";
