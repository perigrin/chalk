my @a=(1,2); sub inc { $_[0]++ } sub z { $a[0]=7 } for my $x (@a) { z(); inc($x) } print "@a\n";
