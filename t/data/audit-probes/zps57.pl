my @a=(1,2); my $t=0; for my $x (@a) { for my $y (@a) { $t+=$x*$y } $x=0 } print "$t @a\n";
