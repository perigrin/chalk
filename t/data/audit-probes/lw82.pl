my @a=(1,2); OUT: for my $i (1..1) { for my $e (@a) { $e .= "x"; next OUT } } print "@a\n";
