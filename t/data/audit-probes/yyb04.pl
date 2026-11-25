my @a=(1,2); my $r=\@a; for my $x (@a) { $r->[0]=7; print $x } print "\n";
