my @a=(1,2); sub z { $a[0]=7 } my $s=""; $s .= do { z(); $_ } for @a; print "$s\n";
