my %h = (k=>1); my @l = do { ($h{k}, $h{k}++) }; print "@l\n";
