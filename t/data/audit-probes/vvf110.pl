my $k = "a"; my %h = (a=>1, b=>2); my @l = ($h{$k}, $h{$k++}, $h{$k}); print "@l\n";
