my $p; for my $i (1..3) { $p ||= \$i; $$p += 10 } print "$$p\n";
