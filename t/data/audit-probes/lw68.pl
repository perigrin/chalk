my @a=(1,2); for (@a) { $_ .= "x"; next if $_ eq "1x"; $_ .= "y" } print "@a\n";
