my @a=(1,2); sub inc { $_[0]++ } for my $x (@a) { inc($x) } print "@a\n";
