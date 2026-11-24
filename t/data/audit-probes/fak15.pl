my @log; sub lg { push @log, @_ } lg("a"); my $n=@log; lg("b","c"); print "$n ", scalar(@log), " @log\n";
