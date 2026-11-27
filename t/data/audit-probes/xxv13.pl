my $s = "ab"; my $n = ($s =~ s/a/x/); my $r = \$s; print "$$r$n\n";
