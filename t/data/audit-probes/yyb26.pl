my @a=(1,2); sub z { $a[1]=7 } for my $x (@a) { z() if $x==1; print $x } print "\n";
