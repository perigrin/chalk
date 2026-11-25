my @a=(1,2); sub z { $a[1]=7; 5 } for my $x (@a) { my $n = $x + z(); print $n } print "\n";
