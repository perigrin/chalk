my @a=(1,2); OUT: for my $i (1..1) { for (@a) { $_ .= "x"; next OUT } } print "@a\n";
