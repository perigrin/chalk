my @a=(1,2); OUT: for my $i (1..2) { for (@a) { $_ .= "x"; next OUT if $i == 1 } } print "@a\n";
