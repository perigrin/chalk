my @a=(1,2); for my $e (@a) { $e .= "x"; last if $e eq "1x" } print "@a\n";
