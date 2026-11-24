my @errs; for my $i (1..3) { eval { die "e$i\n" }; push @errs, $@ } print @errs;
