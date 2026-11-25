my @a=(1,2); sub w { z() } sub z { $a[1]=7 } for my $x (@a) { w(); print $x } print "\n";
