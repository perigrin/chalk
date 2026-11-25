sub inc { $_[0]++ } my @a=(1,2); inc(@a); inc(@a[1]); inc($a[-1]); print "@a\n";
