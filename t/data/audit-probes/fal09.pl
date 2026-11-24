my $s=""; my @a=(1,2); for my $x (@a) { for my $y (@a) { $y.="a"; $s.=$x } } print "$s @a\n";
