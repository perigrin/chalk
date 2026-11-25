my @a=(1,2); my $r=\$a[1]; for my $x (@a) { $$r=7; print $x } print "\n";
