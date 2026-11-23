my @a=(1,2); for my $i (1..1) { for (@a) { $_ .= "x"; last if $_ eq "1x" } } print "@a\n";
