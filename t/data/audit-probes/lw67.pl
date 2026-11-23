my @a=(1,2); my $s=""; OUT: for my $i (1..2) { for (@a) { $_ .= "x"; next OUT if $i == 1 } $s .= "@a;" } print "$s @a\n";
