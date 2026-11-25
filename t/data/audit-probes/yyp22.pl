my @a=(1,2); sub z { $a[1]=7 } my $s=""; $s .= $_, z() for @a; print "$s\n";
