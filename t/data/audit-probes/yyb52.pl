my @a=(1,2); for my $x (@a) { my $r=\@a; $$r[1]=7; print $x } print "\n";
