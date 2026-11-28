my %h = (k=>1); my @l = ($h{k}, delete $h{k}); print scalar(@l), "\n";
