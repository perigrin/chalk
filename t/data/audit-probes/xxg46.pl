my %h = (a=>1); my @l = (scalar(keys %h), ($h{b} = 2), scalar(keys %h)); print "@l\n";
