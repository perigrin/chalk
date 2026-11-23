my @a=(1,2); for (@a) { $_ .= "x"; redo if $_ eq "1x" } print "@a\n";
