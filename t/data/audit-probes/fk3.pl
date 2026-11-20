my $s = "ab"; my @a = (1); if (@a) { $s =~ tr/a/b/ } print "[$s]\n"; if (!@a) { $s =~ tr/b/c/ } print "[$s]\n";
