my @a=(1,2); OUT: for my $i (1..1) { for (@a) { $_ .= "x"; last OUT } } print "@a\n";
