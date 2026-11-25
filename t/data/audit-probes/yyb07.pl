my @a=(1,2); my $r=\@a; sub z { $a[0]=7 } for my $x (@$r) { z(); print $x } print "\n";
