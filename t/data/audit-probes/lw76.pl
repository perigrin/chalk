sub b { $_ .= "x" } my @a=(1,2); for (@a) { b(); last if $_ eq "1x" } print "@a\n";
