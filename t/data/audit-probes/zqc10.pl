my @a=(1,2); sub z { $a[1]=7 } sub y1 { z() } for my $x (@a) { y1(); print $x } print "\n";
