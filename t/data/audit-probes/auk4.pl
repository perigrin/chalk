eval { my $i = 0; while ($i < 3) { $i++; die "w$i\n" } }; print "[$@]\n";
