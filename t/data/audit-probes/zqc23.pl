my @a=(1,2); my @b=(3,4); sub z { $b[0]=7 } for my $x (@a,@b) { z(); print $x } print "\n";
