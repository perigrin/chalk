my @log; for my $i (1..3) { eval { die "e$i\n" if $i % 2; push @log, "ok$i"; 1 } or push @log, "err:$@" =~ s/\n//r } print "@log\n";
