our @a=(1,2,3); sub z { @a=() } my $n=0; for (@a) { $n++; } z(); print "$n ".scalar(@a)."\n";
