my $k = "a"; my %h = (a=>1, b=>2); my @l = @h{$k, $k++}; print "@l\n";
