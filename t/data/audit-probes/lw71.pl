my @a=(1,2); eval { for (@a) { $_ .= "x"; die "d\n" if $_ eq "1x" } }; print "@a\n";
