my @a=(1,2); my $r=\@a; for my $x (@a) { $r->[1]=7; print $x } print "\n";
