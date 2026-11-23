my @a=(1,2,3); my $t=""; for my $x (@a) { $t.=$x; shift @a if $x==1 } print "$t|@a\n";
