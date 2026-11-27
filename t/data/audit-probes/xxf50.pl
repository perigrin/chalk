our $_x = 1; sub rd { $_x } my $v = do { local $_x = 2; rd() } + rd(); print "$v\n";
