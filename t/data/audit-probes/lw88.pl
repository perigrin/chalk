my @a=(1,2); for my $e (@a) { if ($e == 1) { $e = 10 } else { $e = 20 } last if $e == 10 } print "@a\n";
