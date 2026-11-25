my @a=(1,2); my $r=\@a; sub z { $r->[0]=7 } for my $x (@a) { z(); print $x } print "\n";
