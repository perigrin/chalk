my @a=(1,2); sub z { $_[0]=7 } for my $x (@a) { z($a[1]); print $x } print "\n";
